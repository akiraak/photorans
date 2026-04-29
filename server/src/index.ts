import { serve } from '@hono/node-server';
import { Hono } from 'hono';
import Anthropic from '@anthropic-ai/sdk';
import { saveHistory } from './history.js';

const app = new Hono();

app.get('/', (c) => c.text('photorans server: hello'));

const MAX_IMAGE_BYTES = 10 * 1024 * 1024;
const MODEL_ID = 'claude-sonnet-4-6';
const SUPPORTED_IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'] as const;
type SupportedImageType = (typeof SUPPORTED_IMAGE_TYPES)[number];

const anthropic = new Anthropic();

if (!process.env.ANTHROPIC_API_KEY) {
  console.warn('warning: ANTHROPIC_API_KEY is not set; /translate calls will fail');
}

app.post('/translate', async (c) => {
  let body: Record<string, string | File>;
  try {
    body = await c.req.parseBody();
  } catch {
    return c.json({ error: 'invalid multipart/form-data body' }, 400);
  }

  const image = body['image'];
  if (!(image instanceof File)) {
    return c.json({ error: 'image field is required (multipart/form-data)' }, 400);
  }
  if (!SUPPORTED_IMAGE_TYPES.includes(image.type as SupportedImageType)) {
    return c.json(
      { error: `unsupported content-type: ${image.type || 'unknown'} (supported: ${SUPPORTED_IMAGE_TYPES.join(', ')})` },
      400,
    );
  }
  if (image.size === 0) {
    return c.json({ error: 'image is empty' }, 400);
  }
  if (image.size > MAX_IMAGE_BYTES) {
    return c.json({ error: `image too large (max ${MAX_IMAGE_BYTES} bytes)` }, 413);
  }

  const imageBytes = Buffer.from(await image.arrayBuffer());
  const base64 = imageBytes.toString('base64');
  const imageMimeType = image.type as SupportedImageType;

  let response;
  try {
    response = await anthropic.messages.create({
      model: MODEL_ID,
      max_tokens: 4096,
      output_config: {
        format: {
          type: 'json_schema',
          schema: {
            type: 'object',
            properties: {
              originalText: {
                type: 'string',
                description:
                  '画像内の英語テキストを忠実に書き起こしたもの。改行・段落構造は可能な限り保持する。',
              },
              translatedText: {
                type: 'string',
                description: 'originalText を自然な日本語に翻訳したもの。',
              },
            },
            required: ['originalText', 'translatedText'],
            additionalProperties: false,
          },
        },
      },
      messages: [
        {
          role: 'user',
          content: [
            {
              type: 'image',
              source: {
                type: 'base64',
                media_type: imageMimeType,
                data: base64,
              },
            },
            {
              type: 'text',
              text: [
                '画像に写っている英語の文字を OCR で抽出し、自然な日本語に翻訳してください。',
                '抽出時は改行・段落構造を保持してください。',
                '読み取り不能な部分があれば、読み取れた範囲のみ返してください。',
                '英語以外のテキストが混在する場合は、英語部分のみ翻訳対象とし、その他は原文のまま originalText に含めてください。',
              ].join('\n'),
            },
          ],
        },
      ],
    });
  } catch (err) {
    if (err instanceof Anthropic.APIError) {
      console.error(`anthropic api error: status=${err.status} message=${err.message}`);
      return c.json({ error: 'translation failed (upstream api error)' }, 502);
    }
    console.error('unexpected error during translate:', err);
    return c.json({ error: 'translation failed' }, 500);
  }

  const textBlock = response.content.find((b) => b.type === 'text');
  if (!textBlock || textBlock.type !== 'text') {
    console.error('unexpected response shape:', JSON.stringify(response));
    return c.json({ error: 'unexpected response from model' }, 502);
  }

  let parsed: { originalText: unknown; translatedText: unknown };
  try {
    parsed = JSON.parse(textBlock.text);
  } catch {
    console.error('failed to parse model output as JSON:', textBlock.text);
    return c.json({ error: 'unexpected response from model' }, 502);
  }

  if (typeof parsed.originalText !== 'string' || typeof parsed.translatedText !== 'string') {
    console.error('model output missing required fields:', parsed);
    return c.json({ error: 'unexpected response from model' }, 502);
  }

  try {
    saveHistory({
      imageBytes,
      imageMimeType,
      originalText: parsed.originalText,
      translatedText: parsed.translatedText,
      model: MODEL_ID,
    });
  } catch (err) {
    console.error('failed to save translation history:', err);
  }

  return c.json({
    originalText: parsed.originalText,
    translatedText: parsed.translatedText,
    model: MODEL_ID,
  });
});

const port = Number(process.env.PORT ?? 3000);

serve({ fetch: app.fetch, port }, (info) => {
  console.log(`photorans server listening on http://localhost:${info.port}`);
});

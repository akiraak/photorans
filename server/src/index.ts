import { serve } from '@hono/node-server';
import { Hono } from 'hono';
import Anthropic from '@anthropic-ai/sdk';
import { readFileSync } from 'node:fs';
import {
  getHistoryById,
  listHistory,
  resolveImageAbsolutePath,
  saveHistory,
  type HistoryRecord,
} from './history.js';

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

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function truncate(s: string, max: number): string {
  return s.length > max ? `${s.slice(0, max)}…` : s;
}

const ADMIN_STYLE = `
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 24px; color: #1a1a1a; }
  h1 { font-size: 20px; margin: 0 0 16px; }
  a { color: #0366d6; text-decoration: none; }
  a:hover { text-decoration: underline; }
  table { border-collapse: collapse; width: 100%; }
  th, td { border-bottom: 1px solid #e1e4e8; padding: 8px 12px; text-align: left; vertical-align: top; font-size: 14px; }
  th { background: #f6f8fa; font-weight: 600; }
  .preview { color: #586069; max-width: 480px; }
  .empty { color: #586069; padding: 24px 0; }
  .detail { display: grid; grid-template-columns: minmax(280px, 1fr) 2fr; gap: 24px; align-items: start; }
  .detail img { max-width: 100%; border: 1px solid #e1e4e8; border-radius: 4px; }
  .meta { color: #586069; font-size: 13px; margin-bottom: 16px; }
  pre { background: #f6f8fa; border: 1px solid #e1e4e8; border-radius: 4px; padding: 12px; white-space: pre-wrap; word-break: break-word; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 13px; }
  h2 { font-size: 15px; margin: 16px 0 8px; }
  .back { margin-bottom: 16px; display: inline-block; }
  @media (max-width: 720px) { .detail { grid-template-columns: 1fr; } }
`;

function renderListPage(records: HistoryRecord[]): string {
  const rows = records
    .map((r) => {
      const created = escapeHtml(r.createdAt);
      const original = escapeHtml(truncate(r.originalText.replace(/\s+/g, ' '), 80));
      const translated = escapeHtml(truncate(r.translatedText.replace(/\s+/g, ' '), 80));
      return `
        <tr>
          <td><a href="/admin/${encodeURIComponent(r.id)}">${created}</a></td>
          <td class="preview">${original || '<span class="empty">(空)</span>'}</td>
          <td class="preview">${translated || '<span class="empty">(空)</span>'}</td>
          <td>${escapeHtml(r.model)}</td>
        </tr>`;
    })
    .join('');
  const body = records.length
    ? `<table>
        <thead>
          <tr><th>作成日時</th><th>原文 (抜粋)</th><th>訳文 (抜粋)</th><th>モデル</th></tr>
        </thead>
        <tbody>${rows}</tbody>
      </table>`
    : '<p class="empty">履歴はまだありません。</p>';
  return `<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <title>photorans 管理画面</title>
  <style>${ADMIN_STYLE}</style>
</head>
<body>
  <h1>photorans 履歴 (${records.length}件)</h1>
  ${body}
</body>
</html>`;
}

function renderDetailPage(r: HistoryRecord): string {
  return `<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <title>photorans 詳細 ${escapeHtml(r.id)}</title>
  <style>${ADMIN_STYLE}</style>
</head>
<body>
  <a class="back" href="/admin">← 一覧に戻る</a>
  <h1>履歴詳細</h1>
  <div class="meta">
    ID: ${escapeHtml(r.id)} ／ 作成日時: ${escapeHtml(r.createdAt)} ／ モデル: ${escapeHtml(r.model)}
  </div>
  <div class="detail">
    <div>
      <img src="/admin/${encodeURIComponent(r.id)}/image" alt="撮影画像">
    </div>
    <div>
      <h2>原文 (英語)</h2>
      <pre>${escapeHtml(r.originalText)}</pre>
      <h2>訳文 (日本語)</h2>
      <pre>${escapeHtml(r.translatedText)}</pre>
    </div>
  </div>
</body>
</html>`;
}

app.get('/admin', (c) => {
  const records = listHistory();
  return c.html(renderListPage(records));
});

app.get('/admin/:id', (c) => {
  const id = c.req.param('id');
  if (!UUID_RE.test(id)) {
    return c.text('not found', 404);
  }
  const record = getHistoryById(id);
  if (!record) {
    return c.text('not found', 404);
  }
  return c.html(renderDetailPage(record));
});

app.get('/admin/:id/image', (c) => {
  const id = c.req.param('id');
  if (!UUID_RE.test(id)) {
    return c.text('not found', 404);
  }
  const record = getHistoryById(id);
  if (!record) {
    return c.text('not found', 404);
  }
  let bytes: Buffer;
  try {
    bytes = readFileSync(resolveImageAbsolutePath(record.imagePath));
  } catch (err) {
    console.error(`failed to read image for id=${id}:`, err);
    return c.text('image not found', 404);
  }
  c.header('Content-Type', record.imageMimeType);
  c.header('Cache-Control', 'private, max-age=3600');
  return c.body(new Uint8Array(bytes));
});

const port = Number(process.env.PORT ?? 3000);

serve({ fetch: app.fetch, port }, (info) => {
  console.log(`photorans server listening on http://localhost:${info.port}`);
});

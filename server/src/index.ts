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
import { calculateCost } from './pricing.js';

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

  console.log(
    `[translate] received: type=${imageMimeType} size=${imageBytes.length} bytes (base64=${base64.length} bytes)`,
  );

  const startedAt = Date.now();
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
                  '画像内の中心となる言語のテキストを忠実に書き起こしたもの。改行・段落構造は可能な限り保持する。',
              },
              translatedText: {
                type: 'string',
                description:
                  'originalText を targetLanguage に翻訳したもの (sourceLanguage が "en" なら自然な日本語、"ja" なら自然な英語)。',
              },
              sourceLanguage: {
                type: 'string',
                enum: ['en', 'ja'],
                description: 'originalText の言語 (ISO 639-1)。',
              },
              targetLanguage: {
                type: 'string',
                enum: ['en', 'ja'],
                description: 'translatedText の言語 (ISO 639-1)。sourceLanguage と必ず異なる。',
              },
            },
            required: ['originalText', 'translatedText', 'sourceLanguage', 'targetLanguage'],
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
                '画像内のテキストの主要言語を判定してください (英語 or 日本語)。',
                '英語が中心なら自然な日本語に翻訳し、日本語が中心なら自然な英語に翻訳してください。',
                'OCR は改行・段落構造を保持し、英語と日本語が混在する場合は中心となる言語を翻訳対象とし、その他言語のテキストは原文のまま originalText に含めてください。',
                '読み取り不能な部分があれば、読み取れた範囲のみ返してください。',
                'sourceLanguage には originalText の言語、targetLanguage には translatedText の言語を ISO 639-1 ("en" or "ja") で必ず返してください。',
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
  const elapsedMs = Date.now() - startedAt;
  console.log(
    `[translate] anthropic ok: duration=${elapsedMs}ms input_tokens=${response.usage.input_tokens} output_tokens=${response.usage.output_tokens}`,
  );

  const textBlock = response.content.find((b) => b.type === 'text');
  if (!textBlock || textBlock.type !== 'text') {
    console.error('unexpected response shape:', JSON.stringify(response));
    return c.json({ error: 'unexpected response from model' }, 502);
  }

  let parsed: {
    originalText: unknown;
    translatedText: unknown;
    sourceLanguage: unknown;
    targetLanguage: unknown;
  };
  try {
    parsed = JSON.parse(textBlock.text);
  } catch {
    console.error('failed to parse model output as JSON:', textBlock.text);
    return c.json({ error: 'unexpected response from model' }, 502);
  }

  if (
    typeof parsed.originalText !== 'string' ||
    typeof parsed.translatedText !== 'string' ||
    !isSupportedLanguage(parsed.sourceLanguage) ||
    !isSupportedLanguage(parsed.targetLanguage)
  ) {
    console.error('model output missing required fields:', parsed);
    return c.json({ error: 'unexpected response from model' }, 502);
  }

  const sourceLanguage = parsed.sourceLanguage;
  const targetLanguage = parsed.targetLanguage;

  console.log(
    `[translate] result: ${sourceLanguage}->${targetLanguage} original="${previewText(parsed.originalText)}" translated="${previewText(parsed.translatedText)}"`,
  );

  try {
    const saved = saveHistory({
      imageBytes,
      imageMimeType,
      originalText: parsed.originalText,
      translatedText: parsed.translatedText,
      sourceLanguage,
      targetLanguage,
      model: MODEL_ID,
      inputTokens: response.usage.input_tokens,
      outputTokens: response.usage.output_tokens,
      cacheCreationInputTokens: response.usage.cache_creation_input_tokens ?? null,
      cacheReadInputTokens: response.usage.cache_read_input_tokens ?? null,
    });
    console.log(`[translate] history saved: id=${saved.id}`);
  } catch (err) {
    console.error('failed to save translation history:', err);
  }

  return c.json({
    originalText: parsed.originalText,
    translatedText: parsed.translatedText,
    sourceLanguage,
    targetLanguage,
    model: MODEL_ID,
  });
});

const SUPPORTED_LANGUAGES = ['en', 'ja'] as const;
type SupportedLanguage = (typeof SUPPORTED_LANGUAGES)[number];

function isSupportedLanguage(value: unknown): value is SupportedLanguage {
  return typeof value === 'string' && (SUPPORTED_LANGUAGES as readonly string[]).includes(value);
}

function previewText(s: string, max = 60): string {
  const normalized = s.replace(/\s+/g, ' ').trim();
  return normalized.length > max ? `${normalized.slice(0, max)}…` : normalized;
}

const LANGUAGE_DISPLAY_NAMES: Record<string, string> = {
  en: '英語',
  ja: '日本語',
};

function languageDisplayName(code: string | null | undefined, fallback: string): string {
  if (!code) return LANGUAGE_DISPLAY_NAMES[fallback] ?? fallback;
  return LANGUAGE_DISPLAY_NAMES[code] ?? code;
}

function languageBadge(source: string | null, target: string | null): string {
  return `${(source ?? 'en').toUpperCase()}→${(target ?? 'ja').toUpperCase()}`;
}

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
  td.num { text-align: right; font-variant-numeric: tabular-nums; }
  th.num { text-align: right; }
  .preview { color: #586069; max-width: 480px; }
  .empty { color: #586069; padding: 24px 0; }
  .detail { display: grid; grid-template-columns: minmax(280px, 1fr) 2fr; gap: 24px; align-items: start; }
  .detail img { max-width: 100%; border: 1px solid #e1e4e8; border-radius: 4px; }
  .meta { color: #586069; font-size: 13px; margin-bottom: 16px; }
  pre { background: #f6f8fa; border: 1px solid #e1e4e8; border-radius: 4px; padding: 12px; white-space: pre-wrap; word-break: break-word; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 13px; }
  h2 { font-size: 15px; margin: 16px 0 8px; }
  .back { margin-bottom: 16px; display: inline-block; }
  .summary { background: #f6f8fa; border: 1px solid #e1e4e8; border-radius: 4px; padding: 12px 16px; margin-bottom: 16px; font-size: 13px; color: #1a1a1a; }
  .summary .row { display: flex; flex-wrap: wrap; gap: 16px; }
  .summary .row + .row { margin-top: 6px; }
  .summary .label { color: #586069; min-width: 8em; }
  @media (max-width: 720px) { .detail { grid-template-columns: 1fr; } }
`;

interface UsageSummary {
  count: number;
  inputTokens: number;
  outputTokens: number;
  costUsd: number;
}

function summarize(records: HistoryRecord[]): UsageSummary {
  let inputTokens = 0;
  let outputTokens = 0;
  let costUsd = 0;
  for (const r of records) {
    inputTokens += r.inputTokens ?? 0;
    outputTokens += r.outputTokens ?? 0;
    const cost = calculateCost(r.model, {
      inputTokens: r.inputTokens,
      outputTokens: r.outputTokens,
      cacheCreationInputTokens: r.cacheCreationInputTokens,
      cacheReadInputTokens: r.cacheReadInputTokens,
    });
    if (cost !== null) costUsd += cost;
  }
  return { count: records.length, inputTokens, outputTokens, costUsd };
}

function renderSummaryRow(label: string, s: UsageSummary): string {
  return `
    <div class="row">
      <span class="label">${escapeHtml(label)}</span>
      <span>件数: ${s.count.toLocaleString('en-US')}</span>
      <span>input: ${s.inputTokens.toLocaleString('en-US')}</span>
      <span>output: ${s.outputTokens.toLocaleString('en-US')}</span>
      <span>料金: $${s.costUsd.toFixed(4)}</span>
    </div>`;
}

function renderListPage(records: HistoryRecord[]): string {
  const monthPrefix = new Date().toISOString().slice(0, 7);
  const monthRecords = records.filter((r) => r.createdAt.startsWith(monthPrefix));
  const allSummary = summarize(records);
  const monthSummary = summarize(monthRecords);

  const rows = records
    .map((r) => {
      const created = escapeHtml(r.createdAt);
      const original = escapeHtml(truncate(r.originalText.replace(/\s+/g, ' '), 80));
      const translated = escapeHtml(truncate(r.translatedText.replace(/\s+/g, ' '), 80));
      const cost = calculateCost(r.model, {
        inputTokens: r.inputTokens,
        outputTokens: r.outputTokens,
        cacheCreationInputTokens: r.cacheCreationInputTokens,
        cacheReadInputTokens: r.cacheReadInputTokens,
      });
      const direction = escapeHtml(languageBadge(r.sourceLanguage, r.targetLanguage));
      return `
        <tr>
          <td><a href="/admin/${encodeURIComponent(r.id)}">${created}</a></td>
          <td class="preview">${original || '<span class="empty">(空)</span>'}</td>
          <td class="preview">${translated || '<span class="empty">(空)</span>'}</td>
          <td>${direction}</td>
          <td>${escapeHtml(r.model)}</td>
          <td class="num">${escapeHtml(formatUsd(cost))}</td>
        </tr>`;
    })
    .join('');
  const summary = `
    <div class="summary">
      ${renderSummaryRow('全期間', allSummary)}
      ${renderSummaryRow(`当月 (${monthPrefix})`, monthSummary)}
    </div>`;
  const body = records.length
    ? `${summary}<table>
        <thead>
          <tr><th>作成日時</th><th>原文 (抜粋)</th><th>訳文 (抜粋)</th><th>方向</th><th>モデル</th><th class="num">料金</th></tr>
        </thead>
        <tbody>${rows}</tbody>
      </table>`
    : `${summary}<p class="empty">履歴はまだありません。</p>`;
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

function formatTokens(n: number | null): string {
  return n === null ? '-' : n.toLocaleString('en-US');
}

function formatUsd(n: number | null): string {
  if (n === null) return '-';
  return `$${n.toFixed(4)}`;
}

function renderDetailPage(r: HistoryRecord): string {
  const tokensLine = `使用トークン: input ${formatTokens(r.inputTokens)} / output ${formatTokens(r.outputTokens)}`;
  const cacheWrite = r.cacheCreationInputTokens ?? 0;
  const cacheRead = r.cacheReadInputTokens ?? 0;
  const cacheLine =
    cacheWrite > 0 || cacheRead > 0
      ? ` ／ cache write ${formatTokens(r.cacheCreationInputTokens)} / cache read ${formatTokens(r.cacheReadInputTokens)}`
      : '';
  const cost = calculateCost(r.model, {
    inputTokens: r.inputTokens,
    outputTokens: r.outputTokens,
    cacheCreationInputTokens: r.cacheCreationInputTokens,
    cacheReadInputTokens: r.cacheReadInputTokens,
  });
  const costLine = `料金: ${formatUsd(cost)}`;

  const sourceLabel = languageDisplayName(r.sourceLanguage, 'en');
  const targetLabel = languageDisplayName(r.targetLanguage, 'ja');
  const directionLabel = languageBadge(r.sourceLanguage, r.targetLanguage);

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
    ID: ${escapeHtml(r.id)} ／ 作成日時: ${escapeHtml(r.createdAt)} ／ モデル: ${escapeHtml(r.model)} ／ 方向: ${escapeHtml(directionLabel)}
  </div>
  <div class="meta">
    ${escapeHtml(tokensLine)}${escapeHtml(cacheLine)}<br>
    ${escapeHtml(costLine)}
  </div>
  <div class="detail">
    <div>
      <img src="/admin/${encodeURIComponent(r.id)}/image" alt="撮影画像">
    </div>
    <div>
      <h2>原文 (${escapeHtml(sourceLabel)})</h2>
      <pre>${escapeHtml(r.originalText)}</pre>
      <h2>訳文 (${escapeHtml(targetLabel)})</h2>
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

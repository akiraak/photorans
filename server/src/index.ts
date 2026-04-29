import { serve } from '@hono/node-server';
import { Hono } from 'hono';

const app = new Hono();

app.get('/', (c) => c.text('photorans server: hello'));

const MAX_IMAGE_BYTES = 10 * 1024 * 1024;

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
  if (!image.type.startsWith('image/')) {
    return c.json({ error: `unsupported content-type: ${image.type || 'unknown'}` }, 400);
  }
  if (image.size === 0) {
    return c.json({ error: 'image is empty' }, 400);
  }
  if (image.size > MAX_IMAGE_BYTES) {
    return c.json({ error: `image too large (max ${MAX_IMAGE_BYTES} bytes)` }, 413);
  }

  // Phase1-3 で Claude Sonnet 4.6 呼び出しに置き換える
  return c.json({
    originalText: '',
    translatedText: '',
    model: 'stub',
  });
});

const port = Number(process.env.PORT ?? 3000);

serve({ fetch: app.fetch, port }, (info) => {
  console.log(`photorans server listening on http://localhost:${info.port}`);
});

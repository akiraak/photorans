export type TranslateResponse = {
  originalText: string;
  translatedText: string;
  model: string;
};

const REQUEST_TIMEOUT_MS = 60_000;

function getApiBaseUrl(): string {
  const url = process.env.EXPO_PUBLIC_API_URL;
  if (!url || url.length === 0) {
    throw new Error(
      'EXPO_PUBLIC_API_URL が未設定です。client/.env に LAN IP を指定して Metro を再起動してください。',
    );
  }
  return url.replace(/\/+$/, '');
}

export async function translatePhoto(params: {
  uri: string;
  mimeType: string;
  fileName: string;
}): Promise<TranslateResponse> {
  const formData = new FormData();
  formData.append('image', {
    uri: params.uri,
    name: params.fileName,
    type: params.mimeType,
  } as unknown as Blob);

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

  let res: Response;
  try {
    res = await fetch(`${getApiBaseUrl()}/translate`, {
      method: 'POST',
      body: formData,
      signal: controller.signal,
    });
  } catch (err) {
    if (err instanceof Error && err.name === 'AbortError') {
      throw new Error(`タイムアウト (${REQUEST_TIMEOUT_MS / 1000}s)`);
    }
    throw err;
  } finally {
    clearTimeout(timeoutId);
  }

  if (!res.ok) {
    let detail = '';
    try {
      const data = (await res.json()) as { error?: string };
      detail = data.error ?? '';
    } catch {
      // ignore
    }
    throw new Error(detail ? `${res.status}: ${detail}` : `request failed (${res.status})`);
  }

  const data = (await res.json()) as TranslateResponse;
  if (
    typeof data.originalText !== 'string' ||
    typeof data.translatedText !== 'string' ||
    typeof data.model !== 'string'
  ) {
    throw new Error('unexpected response shape');
  }
  return data;
}

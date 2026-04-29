export type TranslateResponse = {
  originalText: string;
  translatedText: string;
  model: string;
};

const DEFAULT_API_URL = 'http://localhost:3000';

function getApiUrl(): string {
  const url = process.env.EXPO_PUBLIC_API_URL;
  return url && url.length > 0 ? url : DEFAULT_API_URL;
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

  const res = await fetch(`${getApiUrl()}/translate`, {
    method: 'POST',
    body: formData,
  });

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

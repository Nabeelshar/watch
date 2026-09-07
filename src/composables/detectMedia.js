import { formatFromType, formatFromBytes } from '../../shared/formats.js';

// Detection stays on the viewer's device: no server proxy, credentials, or full downloads.
export async function detectMedia(url, signal) {
  const abort = new AbortController();
  const cancel = () => abort.abort();
  signal?.addEventListener('abort', cancel, { once: true });
  if (signal?.aborted) abort.abort();
  const timeout = setTimeout(cancel, 5000);
  let reader;
  try {
    const response = await fetch(url, {
      headers: { Range: 'bytes=0-4095' }, signal: abort.signal,
      credentials: 'omit', referrerPolicy: 'no-referrer',
    });
    if (!response.ok) return 'Video';
    const format = formatFromType(response.headers.get('content-type') || '');
    if (format !== 'Auto') { await response.body?.cancel(); return format; }
    reader = response.body?.getReader();
    const sample = await reader?.read();
    return sample?.value ? formatFromBytes(sample.value.subarray(0, 4096)) : 'Video';
  } catch {
    // Native video can often play cross-origin media even if fetch is not permitted.
    return 'Video';
  } finally {
    await reader?.cancel().catch(() => {});
    clearTimeout(timeout);
    signal?.removeEventListener('abort', cancel);
    abort.abort();
  }
}

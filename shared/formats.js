export const formats = ['Auto', 'Video', 'HLS', 'TS', 'DASH', 'FLV', 'Embed'];

const nativeExtensions = new Set('3gp 3g2 aac aif aiff asf avi m4a m4v mkv mov mp3 mp4 mpa mpe mpeg mpg ogg ogv qt ra rm rmvb wav wma wmv webm flac opus'.split(' '));
const archiveExtensions = /^(7z|ace|arj|bz2|gz|gzip|lzh|r\d\d|rar|sea|sit|sitx|tar|z|zip)$/;
const otherExtensions = /^(apk|bin|exe|img|iso|msi|msu|pdf|plj|pps|ppt|pptx|tif|tiff)$/;
export function fileKind(url) {
  const u = new URL(url);
  for (const part of [u.searchParams.get('filename'),u.searchParams.get('file'),u.pathname]) {
    if (!part) continue;
    const ext = part.toLowerCase().match(/\.([a-z0-9]+)$/)?.[1];
    if (archiveExtensions.test(ext || '')) return 'archive';
    if (otherExtensions.test(ext || '')) return 'non-media';
    if (nativeExtensions.has(ext)) return 'media';
  }
  return 'unknown';
}

export function unsupportedFileMessage(url) {
  const kind = fileKind(url);
  if (kind === 'archive') return 'This is an archive, not a video. Extract it on your device, then share a link to the video inside.';
  if (kind === 'non-media') return 'This file is a document, image, disk image, or installer—not playable audio or video. Choose a media file.';
  return '';
}

export function formatFromType(type = '') {
  type = type.toLowerCase().split(';')[0].trim();
  if (['application/vnd.apple.mpegurl', 'application/x-mpegurl', 'audio/mpegurl', 'audio/x-mpegurl'].includes(type)) return 'HLS';
  if (type === 'application/dash+xml') return 'DASH';
  if (['video/mp2t', 'video/mpegts'].includes(type)) return 'TS';
  if (['video/x-flv', 'video/flv'].includes(type)) return 'FLV';
  if (['text/html', 'application/xhtml+xml'].includes(type)) return 'Page';
  if (type.startsWith('video/') || type.startsWith('audio/')) return 'Video';
  return 'Auto';
}

export function formatFromUrl(url) {
  const u = new URL(url);
  // Only inspect format-related query parameters, never rewrite signed URLs.
  const values = [u.pathname, ...['format', 'type', 'ext', 'filename', 'file'].map(key => u.searchParams.get(key) || '')];
  for (const raw of values) {
    const value = raw.toLowerCase();
    const mime = formatFromType(value);
    if (mime !== 'Auto' && mime !== 'Page') return mime;
    if (/(?:^|\.)m3u8$/.test(value) || value === 'hls') return 'HLS';
    if (/(?:^|\.)mpd$/.test(value) || value === 'dash') return 'DASH';
    if (/(?:^|\.)(ts|m2ts|mts)$/.test(value) || value === 'mpegts') return 'TS';
    if (/(?:^|\.)flv$/.test(value)) return 'FLV';
    if (nativeExtensions.has(value.split('.').pop())) return 'Video';
  }
  return 'Auto';
}

export function formatFromBytes(bytes) {
  const text = new TextDecoder().decode(bytes).trimStart();
  if (text.startsWith('#EXTM3U')) return 'HLS';
  if (/<MPD(?:\s|>)/i.test(text)) return 'DASH';
  if (/^(?:<!doctype\s+html|<html)/i.test(text)) return 'Page';
  if (bytes[0] === 0x46 && bytes[1] === 0x4c && bytes[2] === 0x56) return 'FLV';
  for (const stride of [188,192,204]) for (let offset = 0; offset < Math.min(stride, bytes.length); offset++) {
    if (bytes[offset] === 0x47 && bytes[offset + stride] === 0x47 && bytes[offset + stride * 2] === 0x47) return 'TS';
  }
  return 'Video';
}

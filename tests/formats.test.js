import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { formatFromUrl, formatFromType, formatFromBytes } from '../shared/formats.js';
import { detectMedia } from '../src/composables/detectMedia.js';
import { parseMedia } from '../server/media.js';

test('direct links, extensionless streams and format overrides preserve signed query strings',()=>{
  for(const [path,format] of [['/VIDEO.TS?token=a%2Bb','TS'],['/video.m2ts','TS'],['/master.m3u8?expires=123','HLS'],['/manifest.mpd','DASH'],['/watch?format=flv','FLV'],['/watch?type=application%2Fvnd.apple.mpegurl','HLS'],['/clip.mov','Video'],['/opaque?id=video','Auto']]){
    const url='https://cdn.example.com'+path;
    assert.equal(formatFromUrl(url),format);
    assert.equal(parseMedia(url).url,url);
  }
  assert.equal(parseMedia('https://cdn.example.com/opaque','TS').provider,'TS');
  assert.equal(parseMedia('https://youtu.be/aqz-KE-bpKQ','TS').provider,'YouTube');
});
test('MIME and byte signatures distinguish streams from HTML pages',async()=>{
  assert.equal(formatFromType('video/mp2t'),'TS');
  assert.equal(formatFromType('application/dash+xml; charset=utf-8'),'DASH');
  assert.equal(formatFromType('text/html'),'Page');
  const encode=s=>new TextEncoder().encode(s);
  assert.equal(formatFromBytes(encode('#EXTM3U\n#EXT-X-VERSION:3')),'HLS');
  assert.equal(formatFromBytes(encode('<?xml version="1.0"?><MPD profiles="live">')),'DASH');
  assert.equal(formatFromBytes(encode('<!DOCTYPE html><html>')),'Page');
  assert.equal(formatFromBytes(await readFile(new URL('../public/hls-check/segment-00.ts',import.meta.url))),'TS');
});
test('automatic detection cancels response bodies and allows native fallback on CORS failure',async t=>{
  const original=globalThis.fetch;t.after(()=>globalThis.fetch=original);
  let cancelled=false;
  globalThis.fetch=async()=>new Response(new ReadableStream({cancel(){cancelled=true;}}),{headers:{'Content-Type':'video/mp2t'}});
  assert.equal(await detectMedia('https://example.com/opaque'),'TS');assert.equal(cancelled,true);
  globalThis.fetch=async()=>new Response('#EXTM3U\n#EXTINF:6,\nclip.ts',{headers:{'Content-Type':'application/octet-stream'}});
  assert.equal(await detectMedia('https://example.com/opaque'),'HLS');
  globalThis.fetch=async()=>{throw new TypeError('Failed to fetch');};
  assert.equal(await detectMedia('https://example.com/opaque'),'Video');
});

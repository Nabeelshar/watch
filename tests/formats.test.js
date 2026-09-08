import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { formatFromUrl, formatFromType, formatFromBytes } from '../shared/formats.js';
import { detectMedia } from '../src/composables/detectMedia.js';
import { parseMedia, resolveMedia } from '../server/media.js';

test('requested media extensions use device decoding without claiming universal codecs',()=>{
  for(const ext of '3GP AAC AIF ASF AVI M4A M4V MKV MOV MP3 MP4 MPA MPE MPEG MPG OGG OGV QT RA RM RMVB WAV WMA WMV'.split(' ')){
    assert.equal(parseMedia(`https://cdn.example.com/movie.${ext}`).provider,'Video',ext);
  }
});

test('archives, installers, disk images and documents fail before creating a player',()=>{
  for(const ext of '7Z ACE APK ARJ BIN BZ2 EXE GZ GZIP IMG ISO LZH MSI MSU PDF PLJ PPS PPT R00 R19 RAR SEA SIT SITX TAR TIF TIFF Z ZIP'.split(' ')){
    assert.throws(()=>parseMedia(`https://cdn.example.com/file.${ext}`),/archive|document|installer/,ext);
  }
  assert.throws(()=>parseMedia('https://cdn.example.com/download?filename=movie.zip'),/archive/);
});

test('iframe input extracts only the URL, preserving dedicated player APIs',async()=>{
  const input='<iframe src="https://player.example.org/embed/123?a=1&amp;b=2" allow="autoplay" onload="evil()"></iframe>';
  assert.deepEqual(parseMedia(input),{url:'https://player.example.org/embed/123?a=1&b=2',id:'https://player.example.org/embed/123?a=1&b=2',provider:'Embed'});
  assert.equal((await resolveMedia(input)).provider,'Embed');
  assert.equal(parseMedia('<iframe src="https://www.youtube.com/embed/eRsGyueVLvQ"></iframe>').provider,'YouTube');
  assert.equal(parseMedia('https://player.example.org/watch','Embed').provider,'Embed');
  assert.throws(()=>parseMedia('<iframe src="javascript:alert(1)"></iframe>'),/HTTP/);
  assert.throws(()=>parseMedia('<iframe src="https://example.org"></iframe><script>evil()</script>'),/complete iframe/);
  assert.throws(()=>parseMedia('<iframe src="https://example.org/archive.zip"></iframe>'),/archive/);
});

test('Drive file variants preserve resource keys and reject non-video share targets',()=>{
  const id='shared-video_123';
  for(const url of [`https://drive.google.com/file/d/${id}/view?usp=sharing&resourcekey=0-key`, `https://drive.google.com/open?id=${id}&resourcekey=0-key`, `https://docs.google.com/uc?export=download&id=${id}&resourcekey=0-key`]){
    const media=parseMedia(url);
    assert.equal(media.provider,'Drive');
    assert.equal(media.url,`https://drive.google.com/file/d/${id}/preview?resourcekey=0-key`);
    assert.deepEqual(parseMedia(media.url),media);
  }
  for(const path of ['/drive/folders/folder123','/document/d/doc123/edit','/file/d/bad%22id/view','/open?id=bad%2Fid','/file/d/'])assert.throws(()=>parseMedia('https://drive.google.com'+path),/video file link/);
});

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

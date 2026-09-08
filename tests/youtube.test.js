import test from 'node:test';
import assert from 'node:assert/strict';
import { createYouTubeLoader, youtubeError } from '../src/composables/youtubeApi.js';

function environment() {
  const scripts=[];
  return {win:{},scripts,doc:{head:{append(script){scripts.push(script);}},createElement(){return {remove(){this.removed=true;}};}}};
}

test('YouTube timeout clears the failed promise so retry can succeed',async t=>{
  t.mock.timers.enable({apis:['setTimeout','setInterval']});
  const env=environment(),load=createYouTubeLoader(env.win,env.doc);
  const first=load();assert.equal(load(),first);
  const failed=assert.rejects(first,/timed out/);
  t.mock.timers.tick(20000);await failed;
  assert.equal(env.scripts[0].removed,true);
  const retry=load();assert.notEqual(retry,first);assert.equal(env.scripts.length,2);
  env.win.YT={Player(){}};env.win.onYouTubeIframeAPIReady();
  assert.equal(await retry,env.win.YT);
});

test('YouTube detects readiness even if another widget replaces the callback',async t=>{
  t.mock.timers.enable({apis:['setTimeout','setInterval']});
  const env=environment(),load=createYouTubeLoader(env.win,env.doc);
  const pending=load();const replacement=()=>{};env.win.onYouTubeIframeAPIReady=replacement;
  env.win.YT={Player(){}};t.mock.timers.tick(100);
  assert.equal(await pending,env.win.YT);
  assert.equal(env.win.onYouTubeIframeAPIReady,replacement);
});

test('YouTube script errors are retryable and player errors are actionable',async()=>{
  const env=environment(),load=createYouTubeLoader(env.win,env.doc);
  const failed=load();env.scripts[0].onerror();await assert.rejects(failed,/script could not load/);
  const retry=load();env.win.YT={Player(){}};env.win.onYouTubeIframeAPIReady();await retry;
  assert.match(youtubeError(153),/referrer/);
  assert.match(youtubeError(150),/disabled embedded playback/);
  assert.match(youtubeError(100),/private, removed/);
});

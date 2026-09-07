<script setup>
import { ref,watch,onBeforeUnmount,nextTick } from 'vue';
import { Play,Pause,Volume2,VolumeX,Maximize,RefreshCw,RotateCcw,RotateCw,PictureInPicture2 } from 'lucide-vue-next';
import { detectMedia } from '../composables/detectMedia';
import {room,expected,playback,reactions,connected} from '../composables/useRoom';
const emit=defineEmits(['pick','invite']);
const native=ref(null),embed=ref(null),surface=ref(null),time=ref(0),duration=ref(0),volume=ref(.8),isMuted=ref(false),blocked=ref(false),failure=ref(''),loading=ref(false),resolvedFormat=ref('Video'),isLive=ref(false);
let adapter=null,hls=null,transport=null,dash=null,detector=null,suppressUntil=0,loadGeneration=0,interval=null,applying=false,loadingTimeout=null;
const fmt=n=>`${Math.floor((n||0)/60)}:${String(Math.floor((n||0)%60)).padStart(2,'0')}`;
let ytPromise;
function youtube(){if(window.YT?.Player)return Promise.resolve(window.YT);if(!ytPromise)ytPromise=new Promise((resolve,reject)=>{const script=document.createElement('script');script.src='https://www.youtube.com/iframe_api';script.onerror=()=>reject(new Error('YouTube could not load. Check your connection.'));window.onYouTubeIframeAPIReady=()=>resolve(window.YT);document.head.append(script);setTimeout(()=>{if(!window.YT?.Player)reject(new Error('YouTube is unavailable on this connection. Try a direct video.'));},15000);});return ytPromise;}
function cleanup(){clearInterval(interval);clearTimeout(loadingTimeout);detector?.abort();hls?.destroy();hls=null;transport?.destroy();transport=null;dash?.destroy().catch(()=>{});dash=null;adapter?.destroy?.();adapter=null;applying=false;}
function mediaError(){if(!room.value)return;failure.value='This link could not play. It may be a webpage, an expired link, a blocked stream, or a codec this device cannot decode. Try the format selector or a direct video link.';loading.value=false;clearTimeout(loadingTimeout);}
function mediaReady(){loading.value=false;clearTimeout(loadingTimeout);reconcile(true);}
async function load(){const gen=++loadGeneration;cleanup();time.value=0;duration.value=0;failure.value='';blocked.value=false;isLive.value=false;const media=room.value?.video;if(!media)return;loading.value=true;resolvedFormat.value=media.provider;detector=new AbortController();loadingTimeout=setTimeout(()=>{if(gen===loadGeneration&&loading.value){failure.value='This video is taking too long to load. Check the link, choose its format, or try again.';loading.value=false;}},25000);await nextTick();
 try{
 if(media.provider==='YouTube'){
  const YT=await youtube();if(gen!==loadGeneration)return;
  const host=document.createElement('div');embed.value.replaceChildren(host);
  await new Promise((resolve,reject)=>{let player=new YT.Player(host,{videoId:media.id,playerVars:{playsinline:1,rel:0,controls:0,disablekb:1,origin:location.origin},events:{onReady:()=>{if(gen!==loadGeneration){player.destroy();return resolve();}adapter={getTime:()=>player.getCurrentTime(),getDuration:()=>player.getDuration(),seek:t=>player.seekTo(t,true),play:()=>player.playVideo(),pause:()=>player.pauseVideo(),rate:r=>player.setPlaybackRate(r),volume:v=>player.setVolume(v*100),destroy:()=>player.destroy()};resolve();},onStateChange:e=>{if(e.data===0&&Date.now()>suppressUntil)playback('pause',player.getCurrentTime());},onAutoplayBlocked:()=>blocked.value=true,onError:()=>{failure.value='This video cannot be embedded. Try another video or open it on YouTube.';reject(new Error(failure.value));}}});});
 }else if(media.provider==='Vimeo'){
  const {default:Vimeo}=await import('@vimeo/player');if(gen!==loadGeneration)return;
  const player=new Vimeo(embed.value,{url:media.url,controls:false,responsive:true,autoplay:false});await player.ready();if(gen!==loadGeneration){player.destroy();return;}adapter={getTime:()=>player.getCurrentTime(),getDuration:()=>player.getDuration(),seek:t=>player.setCurrentTime(t),play:()=>player.play(),pause:()=>player.pause(),rate:r=>player.setPlaybackRate(r),volume:v=>player.setVolume(v),destroy:()=>player.destroy().catch(()=>{})};player.on('ended',()=>{if(Date.now()>suppressUntil)playback('pause',time.value);});player.on('error',()=>failure.value='Vimeo could not play this video. It may be private or unavailable.');
 }else{
  const el=native.value;
  const format=media.provider==='Auto'?await detectMedia(media.url,detector.signal):media.provider;
  if(gen!==loadGeneration)return;
  resolvedFormat.value=format;
  if(format==='Page')throw new Error('This is a webpage, not a video stream. Open it to find a supported share/embed link, or paste the direct MP4, HLS, TS, or DASH URL.');
  if(location.protocol==='https:'&&new URL(media.url).protocol==='http:')throw new Error('This HTTP video is blocked on an HTTPS app. Use the HTTPS version of the video link.');
  if(format==='HLS'&&!el.canPlayType('application/vnd.apple.mpegurl')){
   const {default:Hls}=await import('hls.js');if(gen!==loadGeneration)return;
   if(!Hls.isSupported())throw new Error('HLS playback is not supported by this browser.');
   hls=new Hls();hls.loadSource(media.url);hls.attachMedia(el);hls.on(Hls.Events.ERROR,(_,d)=>{if(d.fatal)mediaError();});
  }else if(format==='TS'||format==='FLV'){
   const {default:mpegts}=await import('mpegts.js');if(gen!==loadGeneration)return;
   if(!mpegts.isSupported())throw new Error('This device cannot play raw TS/FLV. Try an HLS (.m3u8) version. On iPhone, raw TS requires iOS 17.1 or newer and compatible codecs.');
   transport=mpegts.createPlayer({type:format==='TS'?'mpegts':'flv',url:media.url,isLive:false},{enableWorker:true,lazyLoad:true,seekType:'range'});
   transport.on(mpegts.Events.ERROR,()=>mediaError());transport.attachMediaElement(el);transport.load();
  }else if(format==='DASH'){
   const {default:shaka}=await import('shaka-player/dist/shaka-player.compiled.js');if(gen!==loadGeneration)return;
   shaka.polyfill.installAll();if(!shaka.Player.isBrowserSupported())throw new Error('DASH is not supported on this device. Try HLS or MP4.');
   dash=new shaka.Player();await dash.attach(el);if(gen!==loadGeneration)return;
   dash.addEventListener('error',mediaError);await dash.load(media.url);if(gen!==loadGeneration)return;
  }else el.src=media.url;
  adapter={getTime:()=>el.currentTime,getDuration:()=>el.duration,seek:t=>{el.currentTime=t;},play:()=>el.play(),pause:()=>el.pause(),rate:r=>{el.playbackRate=r;},volume:v=>{el.volume=v;},destroy:()=>{el.pause();el.removeAttribute('src');el.load();}};
 }
 if(gen!==loadGeneration)return;adapter?.volume(isMuted.value?0:volume.value);if(['YouTube','Vimeo'].includes(media.provider)||native.value?.readyState>=2)mediaReady();await reconcile(true);interval=setInterval(()=>reconcile(),400);
 }catch(e){if(gen===loadGeneration){failure.value=e.message||'This video is unavailable.';loading.value=false;clearTimeout(loadingTimeout);}}
}
async function reconcile(force=false){if(!adapter||applying||!room.value||failure.value)return;applying=true;const gen=loadGeneration,player=adapter;try{const actual=Number(await player.getTime())||0;const total=Number(await player.getDuration());if(gen!==loadGeneration)return;isLive.value=total===Infinity;duration.value=Number.isFinite(total)?total:0;time.value=actual;if(!connected.value){suppressUntil=Date.now()+1000;await player.pause();return;}let target=Math.min(expected(),duration.value>0?Math.max(0,duration.value-.05):Infinity);const seekable=native.value?.seekable;if(isLive.value&&seekable?.length)target=Math.max(seekable.start(0),Math.min(target,seekable.end(seekable.length-1)-.1));if(force||Math.abs(actual-target)>1){suppressUntil=Date.now()+900;await player.seek(target);time.value=target;}await player.rate(room.value.playbackRate);if(room.value.playbackState==='playing'&&!blocked.value){try{await player.play();}catch{if(gen===loadGeneration)blocked.value=true;}}else if(room.value.playbackState==='paused')await player.pause();}catch{/* A loading player may not be seekable yet; the next pulse retries. */}finally{if(gen===loadGeneration)applying=false;}}
async function toggle(){if(!adapter)return;if(room.value.playbackState==='playing'){await adapter.pause();playback('pause',Number(await adapter.getTime())||time.value);}else{blocked.value=false;try{await adapter.play();playback('play',Number(await adapter.getTime())||time.value);}catch{blocked.value=true;}}}
async function enable(){blocked.value=false;try{await adapter?.play();if(room.value.playbackState!=='playing')playback('play',time.value);else reconcile(true);}catch{blocked.value=true;}}
function seek(e){const target=Number(e.target.value);time.value=target;suppressUntil=Date.now()+900;adapter?.seek(target);playback('seek',target);}
function changeVolume(){isMuted.value=volume.value===0;adapter?.volume(volume.value);}
function mute(){isMuted.value=!isMuted.value;adapter?.volume(isMuted.value?0:volume.value);}
function fullscreen(){if(surface.value?.requestFullscreen)surface.value.requestFullscreen().catch(()=>native.value?.webkitEnterFullscreen?.());else native.value?.webkitEnterFullscreen?.();}
async function pip(){try{if(document.pictureInPictureElement)await document.exitPictureInPicture();else if(native.value?.requestPictureInPicture)await native.value.requestPictureInPicture();else native.value?.webkitSetPresentationMode?.('picture-in-picture');}catch{/* Some devices disallow PiP for this media. */}}
function skip(delta){if(!duration.value)return;seek({target:{value:Math.max(0,Math.min(time.value+delta,duration.value-.05))}});}
function rate(e){playback('rate',time.value,Number(e.target.value));}
watch(()=>room.value?`${room.value.video.url}|${room.value.video.provider}`:null,load,{immediate:true});watch(()=>room.value?.revision,()=>reconcile());onBeforeUnmount(()=>{loadGeneration++;cleanup();});
</script>
<template>
 <div ref="surface" class="player" :class="{'has-media':room}">
  <template v-if="room">
   <video v-if="!['YouTube','Vimeo'].includes(room.video.provider)" ref="native" playsinline disableRemotePlayback preload="metadata" @error="mediaError" @ended="playback('pause',time)" @loadeddata="mediaReady" @loadedmetadata="reconcile(true)" @click="toggle" />
   <div v-else ref="embed" class="embed"></div>
   <div v-if="loading" class="player-message"><RefreshCw class="spin"/><span>Getting your video ready…</span></div>
   <div v-if="failure" class="player-message"><span>{{ failure }}</span><a :href="room.video.url" target="_blank" rel="noopener noreferrer">Open original link ↗</a><div class="player-recovery"><button class="button secondary" @click="load">Try again</button><button class="button" @click="emit('pick')">Change link / format</button></div></div>
   <button v-else-if="blocked" class="autoplay-button button" @click="enable"><Play :size="18"/> Click to enable playback</button>
   <div class="video-top"><span class="video-pill"><i/> {{ failure?'Unavailable':loading?'Loading':connected?'Connected':'Reconnecting' }}</span><span class="video-pill">{{resolvedFormat==='Auto'?'Detecting…':resolvedFormat}}</span></div>
   <div v-if="!failure" class="player-controls"><input class="timeline" type="range" min="0" :max="duration||Math.max(time,1)" step="0.1" :value="time" aria-label="Seek video" :disabled="!duration" @change="seek"/><div class="control-row"><button class="icon-button" :disabled="loading" :aria-label="room.playbackState==='playing'?'Pause video':'Play video'" @click="toggle"><Pause v-if="room.playbackState==='playing'" :size="22"/><Play v-else :size="22"/></button><button class="icon-button skip-control" aria-label="Back 10 seconds" :disabled="!duration" @click="skip(-10)"><RotateCcw :size="19"/></button><button class="icon-button skip-control" aria-label="Forward 10 seconds" :disabled="!duration" @click="skip(10)"><RotateCw :size="19"/></button><button class="icon-button" aria-label="Toggle video sound" @click="mute"><VolumeX v-if="isMuted" :size="19"/><Volume2 v-else :size="19"/></button><input class="volume" type="range" min="0" max="1" step="0.05" v-model.number="volume" aria-label="Video volume" @input="changeVolume"/><span class="time-label">{{isLive?'LIVE':fmt(time)}} <span v-if="!isLive">/ {{fmt(duration)}}</span></span><div class="control-spacer"/><select :value="room.playbackRate" aria-label="Playback speed" @change="rate"><option v-for="r in [.5,.75,1,1.25,1.5,2]" :value="r">{{r}}×</option></select><button class="icon-button sync-control" aria-label="Sync now" @click="reconcile(true)"><RefreshCw :size="17"/></button><button v-if="native" class="icon-button pip-control" aria-label="Picture in picture" @click="pip"><PictureInPicture2 :size="19"/></button><button class="icon-button" aria-label="Fullscreen" @click="fullscreen"><Maximize :size="19"/></button></div></div>
  </template>
  <div v-else class="player-welcome"><div class="orbit-mark"><Play :size="34" fill="currentColor"/></div><span class="eyebrow">THE BEST SEAT IS NEXT TO YOUR PEOPLE</span><h2>Different places.<br/>Same <em>moment.</em></h2><p>A movie night, a rabbit hole, or just one more video.<br/>It’s better when you’re here together.</p><button class="button" @click="emit('pick')"><Play :size="17" fill="currentColor"/> Pick something to watch</button><span class="welcome-footnote">No sign-ups. Just a link and your people.</span></div>
  <div class="reaction-layer"><span v-for="r in reactions" :key="r.id" class="floating-reaction" :style="{left:r.left+'%'}">{{r.emoji}}</span></div>
 </div>
</template>

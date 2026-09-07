import { ref, computed } from 'vue';
import { io } from 'socket.io-client';
function read(key,fallback){try{return JSON.parse(localStorage.getItem(key))||fallback;}catch{return fallback;}}
const avatars=['🌙','🪐','🍿','🦊','🐸','👾','🐻','🌻'];
const names=['Cosmic Fox','Midnight Owl','Peach Comet','Moon Bear','Cozy Koala','Little Saturn'];
const stored=read('afterglow.profile',{});
export const profile=ref({name:stored.name||names[Math.floor(Math.random()*names.length)],avatar:stored.avatar||avatars[Math.floor(Math.random()*avatars.length)],id:stored.id||null});
let token=stored.token;
function persist(key,value){try{localStorage.setItem(key,JSON.stringify(value));}catch{/* Guest sessions still work when browser storage is disabled. */}}
export const friends=ref(read('afterglow.friends',[]));
export const online=ref([]),room=ref(null),members=ref([]),messages=ref([]),connected=ref(false),ready=ref(false),error=ref(''),reactions=ref([]),iceServers=ref([]),clockOffset=ref(0);
export const socket=io({autoConnect:false,transports:['websocket','polling'],reconnection:true,reconnectionDelay:700,reconnectionDelayMax:5000});
export const roomId=computed(()=>room.value?.roomId||null);
export const partners=computed(()=>friends.value.map(f=>({...f,...online.value.find(p=>p.id===f.id)})));
let currentPathId=location.pathname.match(/^\/watch\/([\w-]+)\/?$/)?.[1]||null;
let generation=0;
export function request(event,payload={}){return new Promise((resolve,reject)=>{if(!socket.connected)return reject(new Error('Reconnecting. Try again in a moment.'));socket.timeout(7000).emit(event,payload,(err,result)=>{if(err)reject(new Error('The server took too long to respond. Please try again.'));else if(!result?.ok)reject(new Error(result?.error||'Something went wrong.'));else resolve(result);});});}
function saveProfile(){persist('afterglow.profile',{...profile.value,token});}
function accept(data){room.value=data.state;members.value=data.members;messages.value=data.messages;currentPathId=data.state.roomId;history.replaceState({},'',`/watch/${currentPathId}`);error.value='';}
async function measureClock(){let best=Infinity;for(let i=0;i<4;i++){const start=Date.now();const {now}=await request('clock:ping');const elapsed=Date.now()-start;if(elapsed<best){best=elapsed;clockOffset.value=now-(start+elapsed/2);}}}
socket.on('connect',async()=>{connected.value=true;ready.value=false;const attempt=++generation;try{const d=await request('identity:hello',{...profile.value,token,friends:friends.value.map(f=>f.id)});if(attempt!==generation)return;profile.value=d.profile;token=d.token;iceServers.value=d.iceServers;saveProfile();await measureClock();ready.value=true;if(currentPathId)accept(await request('room:join',{roomId:currentPathId}));}catch(e){error.value=e.message;ready.value=true;}});
socket.on('disconnect',()=>{connected.value=false;ready.value=false;generation++;});
socket.on('connect_error',()=>{connected.value=false;error.value='Connection lost. We’re reconnecting automatically…';});
socket.on('room:state',s=>{if(room.value?.roomId===s.roomId&&s.revision>=room.value.revision)room.value=s;});
socket.on('room:members',m=>members.value=m);
socket.on('chat:message',m=>{if(!messages.value.some(x=>x.id===m.id))messages.value=[...messages.value,m].slice(-100);});
socket.on('friends:add',f=>{const idx=friends.value.findIndex(p=>p.id===f.id);if(idx===-1)friends.value.unshift(f);else friends.value[idx]={...friends.value[idx],...f};friends.value=friends.value.slice(0,100);persist('afterglow.friends',friends.value);});
socket.on('friends:presence',p=>online.value=p);
socket.on('reaction',r=>{reactions.value.push({...r,left:15+Math.random()*70});setTimeout(()=>reactions.value=reactions.value.filter(x=>x.id!==r.id),2800);});
socket.on('app:error',msg=>error.value=msg);
export async function pickVideo(url,title,format='Auto'){if(!ready.value)throw new Error('Connecting to the lounge. Please try again in a moment.');if(room.value)await request('room:video',{url,title,format});else accept(await request('room:create',{url,title,format}));}
export async function joinRoom(id){accept(await request('room:join',{roomId:id}));}
export async function leaveRoom(){await request('room:leave');room.value=null;members.value=[];messages.value=[];currentPathId=null;history.pushState({},'','/');}
export async function updateProfile(name,avatar){const d=await request('identity:update',{name,avatar});profile.value=d.profile;saveProfile();}
export async function switchGuest(){if(room.value)await leaveRoom();token=null;profile.value={name:names[Math.floor(Math.random()*names.length)],avatar:avatars[Math.floor(Math.random()*avatars.length)]};friends.value=[];persist('afterglow.friends',[]);socket.disconnect();socket.connect();}
export function playback(action,time,rate){if(!room.value||!ready.value)return;request('player:update',{action,time,rate,videoUrl:room.value.video.url}).catch(e=>error.value=e.message);}
export function expected(){const r=room.value;if(!r)return 0;return Math.max(0,r.lastTimestamp+(r.playbackState==='playing'?Math.max(0,Date.now()+clockOffset.value-r.lastTimestampUpdated)/1000*r.playbackRate:0));}
window.addEventListener('popstate',async()=>{const id=location.pathname.match(/^\/watch\/([\w-]+)/)?.[1];try{if(id)await joinRoom(id);else if(room.value)await leaveRoom();}catch(e){error.value=e.message;}});
socket.connect();

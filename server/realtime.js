import { Server } from 'socket.io';
import { randomBytes, createHmac, timingSafeEqual } from 'node:crypto';
import { parseMedia, expectedTime } from './media.js';
const MAX_MEMBERS=8, TTL=30*60*1000;
export function attachRealtime(httpServer,options={}){
 const secret=options.secret||process.env.IDENTITY_SECRET||randomBytes(32).toString('hex');
 const origins=(process.env.ALLOWED_ORIGINS||'').split(',').filter(Boolean);
 const io=new Server(httpServer,{maxHttpBufferSize:64000,pingInterval:20000,pingTimeout:15000,allowRequest:(req,cb)=>{const origin=req.headers.origin;if(!origin)return cb(null,true);try{const u=new URL(origin);cb(null,origins.length?origins.includes(origin):u.host===req.headers.host);}catch{cb(null,false);}}});
 const rooms=new Map(), profiles=new Map(), tokens=new Map();
 const sign=id=>createHmac('sha256',secret).update(id).digest('hex');
 const validToken=t=>{if(typeof t!=='string')return null;const [id,sig]=t.split('.');if(!/^[a-f0-9]{24}$/.test(id||'')||! /^[a-f0-9]{64}$/.test(sig||''))return null;return timingSafeEqual(Buffer.from(sig),Buffer.from(sign(id)))?id:null;};
 const state=r=>({roomId:r.roomId,video:r.video,playbackState:r.playbackState,lastTimestamp:expectedTime(r),lastTimestampUpdated:Date.now(),playbackRate:r.playbackRate,revision:r.revision,controller:r.controller});
 const members=r=>[...r.socketIds].map(id=>{const s=io.sockets.sockets.get(id);return s?{...s.data.profile,socketId:id,voice:!!s.data.voice}:null;}).filter(Boolean);
 const roomFor=s=>rooms.get(s.data.roomId);
 function presence(s){
  const list=[...(s.data.friends||new Set())].slice(0,100).map(id=>{
   const p=profiles.get(id), sockets=[...io.sockets.sockets.values()].filter(x=>x.data.profile?.id===id);const joined=sockets.find(x=>roomFor(x));const r=joined&&roomFor(joined);
   return{id,...p,online:sockets.length>0,roomId:r?.roomId||null,video:r?.video||null,time:r?expectedTime(r):0};
  });s.emit('friends:presence',list);
 }
 function broadcastPresence(){for(const s of io.sockets.sockets.values())if(s.data.profile)presence(s);}
 function notice(r,text){const msg={id:randomBytes(8).toString('hex'),kind:'system',text,at:Date.now()};r.messages.push(msg);r.messages=r.messages.slice(-100);io.to(r.roomId).emit('chat:message',msg);}
 function leave(s){const r=roomFor(s);if(!r)return;s.leave(r.roomId);r.socketIds.delete(s.id);s.data.roomId=null;s.data.voice=false;r.emptySince=r.socketIds.size?null:Date.now();notice(r,`${s.data.profile.name} left the room`);io.to(r.roomId).emit('room:members',members(r));broadcastPresence();}
 function join(s,r){
  if(r.socketIds.size>=MAX_MEMBERS&&!r.socketIds.has(s.id))throw new Error('This room is full (8 people maximum).');
  if(s.data.roomId===r.roomId)return;
  leave(s);s.join(r.roomId);s.data.roomId=r.roomId;r.socketIds.add(s.id);r.emptySince=null;
  const others=members(r).filter(p=>p.id!==s.data.profile.id);
  for(const p of others){s.data.friends.add(p.id);for(const peer of io.sockets.sockets.values())if(peer.data.profile?.id===p.id){peer.data.friends.add(s.data.profile.id);peer.emit('friends:add',s.data.profile);}}
  for(const p of others)s.emit('friends:add',{id:p.id,name:p.name,avatar:p.avatar});
  io.to(r.roomId).emit('room:members',members(r));notice(r,`${s.data.profile.name} joined the room`);broadcastPresence();
 }
 io.on('connection',s=>{
  let budget=120,refill=Date.now();
  s.use(([event],next)=>{const now=Date.now();budget=Math.min(120,budget+(now-refill)*0.04);refill=now;if(budget<1)return next(new Error('Too many events. Please slow down.'));budget--;next();});
  const handle=(event,fn)=>s.on(event,(payload,ack)=>{try{if(event!=='identity:hello'&&!s.data.profile)throw new Error('Connect your guest profile first.');const result=fn(payload||{});if(typeof ack==='function')ack({ok:true,...result});}catch(e){if(typeof ack==='function')ack({ok:false,error:e.message});else s.emit('app:error',e.message);}});
  handle('identity:hello',p=>{
   if(s.data.profile)throw new Error('Guest profile is already connected.');
   const id=validToken(p.token)||randomBytes(12).toString('hex');
   const profile={id,name:String(p.name||'Guest').trim().slice(0,24)||'Guest',avatar:['🌙','🪐','🍿','🦊','🐸','👾','🐻','🌻'].includes(p.avatar)?p.avatar:'🌙'};
   s.data.profile=profile;s.data.friends=new Set(Array.isArray(p.friends)?p.friends.filter(x=>typeof x==='string'&&x!==id).slice(0,100):[]);profiles.set(id,profile);tokens.set(id,Date.now());broadcastPresence();
   return{profile,token:`${id}.${sign(id)}`,iceServers:options.iceServers||[{urls:'stun:stun.l.google.com:19302'},...(process.env.TURN_URL?[{urls:process.env.TURN_URL,username:process.env.TURN_USERNAME,credential:process.env.TURN_CREDENTIAL}]:[])]};
  });
  handle('identity:update',p=>{s.data.profile.name=String(p.name||'Guest').trim().slice(0,24)||'Guest';if(['🌙','🪐','🍿','🦊','🐸','👾','🐻','🌻'].includes(p.avatar))s.data.profile.avatar=p.avatar;profiles.set(s.data.profile.id,s.data.profile);for(const peer of io.sockets.sockets.values())if(peer.data.profile?.id===s.data.profile.id)peer.data.profile=s.data.profile;const r=roomFor(s);if(r)io.to(r.roomId).emit('room:members',members(r));broadcastPresence();return{profile:s.data.profile};});
  handle('clock:ping',()=>({now:Date.now()}));
  handle('room:create',p=>{if(rooms.size>=5000)throw new Error('The server is busy. Try again shortly.');const video=parseMedia(p.url,p.format);let roomId;do{roomId=randomBytes(5).toString('base64url');}while(rooms.has(roomId));const r={roomId,currentVideoUrl:video.url,video:{...video,title:String(p.title||`${video.provider} watch party`).slice(0,120)},playbackState:'paused',lastTimestamp:0,lastTimestampUpdated:Date.now(),playbackRate:1,socketIds:new Set(),revision:0,messages:[],emptySince:null};rooms.set(roomId,r);join(s,r);return{state:state(r),members:members(r),messages:r.messages};});
  handle('room:join',p=>{const r=rooms.get(p.roomId);if(!r)throw new Error('This room has expired or does not exist. Pick a video to start a new one.');join(s,r);return{state:state(r),members:members(r),messages:r.messages};});
  handle('room:leave',()=>{leave(s);return{};});
  handle('room:video',p=>{const r=roomFor(s);if(!r)throw new Error('Join a room first.');const video=parseMedia(p.url,p.format);Object.assign(r,{video:{...video,title:String(p.title||`${video.provider} watch party`).slice(0,120)},currentVideoUrl:video.url,lastTimestamp:0,lastTimestampUpdated:Date.now(),playbackState:'paused',playbackRate:1,revision:r.revision+1});io.to(r.roomId).emit('room:state',state(r));notice(r,`${s.data.profile.name} picked a new video`);broadcastPresence();return{};});
  handle('player:update',p=>{
   const r=roomFor(s);if(!r)throw new Error('Join a room first.');if(!['play','pause','seek','rate'].includes(p.action))throw new Error('Invalid playback action.');
   if(!Number.isFinite(p.time)||p.time<0||p.time>604800)throw new Error('Invalid playback time.');
   if(p.action==='rate'&&![0.5,0.75,1,1.25,1.5,2].includes(p.rate))throw new Error('Invalid playback speed.');
   // Reject stale actions from a previous video or outdated state.
   if(p.videoUrl!==r.video.url)return{state:state(r)};
   r.lastTimestamp=p.time;r.lastTimestampUpdated=Date.now();if(p.action==='play'||p.action==='pause')r.playbackState=p.action==='play'?'playing':'paused';if(p.action==='rate')r.playbackRate=p.rate;r.controller=s.data.profile.name;r.revision++;
   io.to(r.roomId).emit('room:state',state(r));return{state:state(r)};
  });
  handle('chat:send',p=>{const r=roomFor(s);if(!r)throw new Error('Join a room first.');const text=String(p.text||'').trim().slice(0,1000);if(!text)throw new Error('Write a message first.');const msg={id:randomBytes(8).toString('hex'),kind:'chat',profile:s.data.profile,text,at:Date.now()};r.messages.push(msg);r.messages=r.messages.slice(-100);io.to(r.roomId).emit('chat:message',msg);return{};});
  handle('reaction:send',p=>{const r=roomFor(s);if(!r)return{};if(['❤️','😂','🔥','👏','😮','🎉'].includes(p.emoji))io.to(r.roomId).emit('reaction',{emoji:p.emoji,id:randomBytes(6).toString('hex'),name:s.data.profile.name});return{};});
  handle('friends:subscribe',p=>{s.data.friends=new Set(Array.isArray(p.ids)?p.ids.filter(x=>typeof x==='string').slice(0,100):[]);presence(s);return{};});
  handle('voice:state',p=>{const r=roomFor(s);if(!r)throw new Error('Join a room first.');s.data.voice=p.enabled===true;io.to(r.roomId).emit('room:members',members(r));return{};});
  handle('voice:signal',p=>{const peer=io.sockets.sockets.get(p.to);if(!s.data.roomId||!peer||peer.data.roomId!==s.data.roomId||!s.data.voice||!peer.data.voice)throw new Error('Voice peer is not available in this room.');if(!['offer','answer','ice-candidate'].includes(p.type))throw new Error('Invalid signal.');if(JSON.stringify(p.payload).length>48000)throw new Error('Signal too large.');peer.emit('voice:signal',{from:s.id,type:p.type,payload:p.payload});return{};});
  s.on('disconnect',()=>{leave(s);broadcastPresence();});
 });
 const pulse=setInterval(()=>{for(const r of rooms.values()){if(r.socketIds.size)io.to(r.roomId).emit('room:state',state(r));else if(Date.now()-r.emptySince>TTL)rooms.delete(r.roomId);}broadcastPresence();for(const [id,at]of tokens)if(Date.now()-at>86400000&&![...io.sockets.sockets.values()].some(s=>s.data.profile?.id===id)){profiles.delete(id);tokens.delete(id);}},2000);pulse.unref();
 return{io,rooms,close(){clearInterval(pulse);io.close();}};
}

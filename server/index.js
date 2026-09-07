import express from 'express';
import helmet from 'helmet';
import { createServer } from 'node:http';
import { resolve } from 'node:path';
import { attachRealtime } from './realtime.js';
if(process.env.NODE_ENV==='production'&&(!process.env.IDENTITY_SECRET||!process.env.ALLOWED_ORIGINS)){throw new Error('Set IDENTITY_SECRET and ALLOWED_ORIGINS in production.');}
const app=express();
app.disable('x-powered-by');
app.use(helmet({contentSecurityPolicy:{directives:{defaultSrc:["'self'"],scriptSrc:["'self'",'https://www.youtube.com','https://s.ytimg.com'],styleSrc:["'self'","'unsafe-inline'"],imgSrc:["'self'",'data:','https:'],connectSrc:["'self'",'https:','wss:','ws:'],mediaSrc:["'self'",'https:','http:','blob:'],frameSrc:['https://www.youtube.com','https://www.youtube-nocookie.com','https://player.vimeo.com'],workerSrc:["'self'",'blob:']}},crossOriginEmbedderPolicy:false}));
app.get('/api/health',(_,res)=>res.json({ok:true}));
app.use(express.static(resolve('dist'),{maxAge:'1h'}));
app.get('/{*path}',(_,res)=>res.sendFile(resolve('dist/index.html')));
const http=createServer(app);const runtime=attachRealtime(http);
http.listen(Number(process.env.PORT||3000),'0.0.0.0',()=>console.log('Afterglow server ready on port '+(process.env.PORT||3000)));
for(const signal of ['SIGTERM','SIGINT'])process.on(signal,()=>{runtime.close();http.close(()=>process.exit(0));setTimeout(()=>process.exit(0),5000).unref();});

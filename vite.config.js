import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import tailwindcss from '@tailwindcss/vite';
import { attachRealtime } from './server/realtime.js';
export default defineConfig({plugins:[vue(),tailwindcss(),{name:'watch-realtime',configureServer(server){const runtime=attachRealtime(server.httpServer);server.httpServer.once('close',()=>runtime.close());}}],server:{host:'0.0.0.0',port:4173,strictPort:true,allowedHosts:['terminal.local']},build:{target:'es2022'}});

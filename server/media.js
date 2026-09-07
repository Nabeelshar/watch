import { formats, formatFromUrl } from '../shared/formats.js';
export function parseMedia(input, format = 'Auto') {
  if(!formats.includes(format)) throw new Error('Choose a supported video format.');
  if(typeof input!=='string'||input.length>2048) throw new Error('Enter a valid video link.');
  let u;try{u=new URL(input.trim());}catch{throw new Error('Enter a complete https:// video link.');}
  if(!['https:','http:'].includes(u.protocol)||u.username||u.password)throw new Error('Use an HTTP or HTTPS video link.');
  const host=u.hostname.toLowerCase().replace(/^www\./,'');
  if(['youtube.com','m.youtube.com','youtu.be','youtube-nocookie.com'].includes(host)){
    const id=host==='youtu.be'?u.pathname.slice(1):u.searchParams.get('v')||u.pathname.match(/^\/(?:embed|shorts|live)\/([^/]+)/)?.[1];
    if(!/^[a-zA-Z0-9_-]{11}$/.test(id||''))throw new Error('This YouTube link does not contain a valid video.');
    return {url:`https://www.youtube.com/watch?v=${id}`,provider:'YouTube',id};
  }
  if(['vimeo.com','player.vimeo.com'].includes(host)){
    const id=u.pathname.match(/(?:\/video)?\/(\d+)/)?.[1];
    if(!id)throw new Error('This Vimeo link does not contain a valid video.');
    const hash=u.searchParams.get('h')||u.pathname.match(/^\/\d+\/([a-zA-Z0-9]+)/)?.[1];
    return{url:`https://player.vimeo.com/video/${id}${hash?'?h='+hash:''}`,provider:'Vimeo',id};
  }
  return{url:u.href,provider:format === 'Auto' ? formatFromUrl(u.href) : format,id:u.href};
}
export function expectedTime(room,now=Date.now()){
 return Math.max(0,room.lastTimestamp+(room.playbackState==='playing'?(Math.max(0,now-room.lastTimestampUpdated)/1000)*room.playbackRate:0));
}

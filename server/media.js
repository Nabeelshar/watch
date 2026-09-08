import { formats, formatFromUrl, unsupportedFileMessage } from '../shared/formats.js';
export function mediaInput(input) {
  if(typeof input !== 'string' || input.length > 2048) throw new Error('Enter a video link or a short iframe embed code.');
  const value=input.trim();
  if(!value.startsWith('<'))return {url:value,iframe:false};
  // Read a single iframe source only. Never render submitted HTML or its attributes.
  const frame=value.match(/^<iframe\b([^>]*)>\s*<\/iframe>$/i);
  const src=frame?.[1].match(/(?:^|\s)src\s*=\s*(["'])(.*?)\1/i)?.[2];
  if(!src)throw new Error('Paste a complete iframe embed code with a quoted src, or its HTTPS URL.');
  return {url:src.replace(/&amp;/gi,'&'),iframe:true};
}
export function parseMedia(input, format = 'Auto') {
  if(!formats.includes(format)) throw new Error('Choose a supported video format.');
  const normalized=mediaInput(input);input=normalized.url;if(normalized.iframe)format='Embed';
  let u;try{u=new URL(input.trim());}catch{throw new Error('Enter a complete https:// video link.');}
  if(!['https:','http:'].includes(u.protocol)||u.username||u.password)throw new Error('Use an HTTP or HTTPS video link.');
  const unsupported=unsupportedFileMessage(u.href);
  if(unsupported)throw new Error(unsupported);
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
  if(['drive.google.com','docs.google.com'].includes(host)){
    const id=u.pathname.match(/^\/file\/d\/([a-zA-Z0-9_-]+)(?:\/(?:view|preview|edit))?\/?$/)?.[1]||(['/', '/open', '/uc', '/download'].includes(u.pathname)?u.searchParams.get('id'):null);
    if(!/^[a-zA-Z0-9_-]+$/.test(id||''))throw new Error('Paste a Google Drive video file link, not a folder or document link.');
    const preview=new URL(`https://drive.google.com/file/d/${id}/preview`);
    const resourceKey=u.searchParams.get('resourcekey');
    if(resourceKey)preview.searchParams.set('resourcekey',resourceKey);
    return{url:preview.href,provider:'Drive',id};
  }
  return{url:u.href,provider:format === 'Auto' ? formatFromUrl(u.href) : format,id:u.href};
}

// --- Embed-page scraping -------------------------------------------------
// Some watch sites expose a playable stream only inside a page: the server
// fetches that single page, finds the embedded stream, and hands the direct
// media URL back to the room. Only known, allow-listed hosts are fetched.
const SCRAPE_HOSTS = new Set(['piratexplay.cc']);

export function extractIframeSrc(html, baseUrl) {
  const frames = [];
  for (const m of html.matchAll(/<iframe\b[^>]*>/gi)) {
    const src = m[0].match(/\bsrc=["']([^"']+)["']/i)?.[1];
    if (src) frames.push(src);
  }
  if (!frames.length) return null;
  const preferred = frames.find((s) => /proxy\/play\.php/i.test(s)) || frames[0];
  return new URL(preferred, baseUrl).href;
}

export function extractEpisodeKey(pathname) {
  const m = pathname.match(/(\d+)x(\d+)\/?$/);
  return m ? { season: Number(m[1]), episode: Number(m[2]) } : null;
}

export function extractNextEpisode(html, baseUrl) {
  const cur = extractEpisodeKey(new URL(baseUrl).pathname);
  if (!cur) return null;
  const want = `${cur.season}x${cur.episode + 1}`;
  for (const m of html.matchAll(/href=["']([^"']*\/episode\/[^"']*-\d+x\d+\/?)["']/gi)) {
    const key = extractEpisodeKey(new URL(m[1], baseUrl).pathname);
    if (key && `${key.season}x${key.episode}` === want) return new URL(m[1], baseUrl).href;
  }
  return null;
}

export function extractPageTitle(html) {
  const og = html.match(/<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']/i)
    || html.match(/<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:title["']/i);
  if (og?.[1]) return og[1].trim();
  const h1 = html.match(/<h1\b[^>]*>([\s\S]*?)<\/h1>/i)?.[1]
    ?.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
  return h1 || null;
}

async function scrapePage(u) {
  let html;
  try {
    const res = await fetch(u.href, {
      headers: { 'User-Agent': 'Mozilla/5.0 (compatible; Afterglow/1.0)', 'Accept': 'text/html,application/xhtml+xml' },
      redirect: 'follow',
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) throw new Error('That page could not be reached.');
    html = await res.text();
  } catch {
    throw new Error('This episode page could not be read. It may be offline or blocking automated requests.');
  }
  const embedUrl = extractIframeSrc(html, u.href);
  if (!embedUrl) throw new Error('No playable video was found on that page.');
  return { url: embedUrl, provider: 'Embed', id: embedUrl, title: extractPageTitle(html), next: extractNextEpisode(html, u.href) };
}

export async function resolveMedia(input, format = 'Auto') {
  if (!formats.includes(format)) throw new Error('Choose a supported video format.');
  const normalized=mediaInput(input);input=normalized.url;if(normalized.iframe)format='Embed';
  let u; try { u = new URL(input.trim()); } catch { throw new Error('Enter a complete https:// video link.'); }
  if (!['https:', 'http:'].includes(u.protocol) || u.username || u.password) throw new Error('Use an HTTP or HTTPS video link.');
  const host = u.hostname.toLowerCase().replace(/^www\./, '');
  if (SCRAPE_HOSTS.has(host) && format !== 'Embed') return scrapePage(u);
  return { ...parseMedia(input, format), next: null };
}

export function expectedTime(room,now=Date.now()){
 return Math.max(0,room.lastTimestamp+(room.playbackState==='playing'?(Math.max(0,now-room.lastTimestampUpdated)/1000)*room.playbackRate:0));
}

// Coturn REST credentials, scoped to a signed-in room member and valid for 10 minutes.
// TURN_SHARED_SECRET stays on the server. Configure matching coturn use-auth-secret.
const headers = { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Cache-Control': 'no-store' };
const reply = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers });
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers });
  if (req.method !== 'POST') return reply(405, { error: 'Use POST.' });
  const authorization = req.headers.get('Authorization');
  if (!authorization?.startsWith('Bearer ')) return reply(401, { error: 'Sign in first.' });
  try {
    const raw = await req.text();
    if (raw.length > 4096) return reply(413, { error: 'Request too large.' });
    const { room_id } = JSON.parse(raw);
    if (typeof room_id !== 'string' || !/^[a-f0-9-]{36}$/i.test(room_id)) return reply(400, { error: 'Invalid room.' });
    const base = Deno.env.get('SUPABASE_URL')!;
    const apikey = Deno.env.get('SUPABASE_ANON_KEY')!;
    const authHeaders = { apikey, Authorization: authorization };
    const auth = await fetch(`${base}/auth/v1/user`, { headers: authHeaders });
    if (!auth.ok) return reply(401, { error: 'Sign in again.' });
    const user = await auth.json();
    const membership = await fetch(`${base}/rest/v1/ag_members?select=user_id&room_id=eq.${room_id}&user_id=eq.${user.id}`, { headers: authHeaders });
    if (!membership.ok || !(await membership.json()).length) return reply(403, { error: 'Join this room first.' });
    const secret = Deno.env.get('TURN_SHARED_SECRET');
    const urls: unknown = JSON.parse(Deno.env.get('TURN_URLS') || '[]');
    if (!secret || !Array.isArray(urls) || !urls.length || !urls.every(url => typeof url === 'string' && /^turns?:/.test(url))) return reply(503, { error: 'The call relay is not configured yet.' });
    const expires = Math.floor(Date.now() / 1000) + 600;
    const username = `${expires}:${user.id}`;
    const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']);
    const signature = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(username));
    const credential = btoa(String.fromCharCode(...new Uint8Array(signature)));
    return reply(200, { iceServers: [{ urls: 'stun:stun.l.google.com:19302' }, { urls, username, credential }], expiresAt: expires });
  } catch (_) {
    return reply(400, { error: 'Unable to prepare the call. Try again.' });
  }
});

# Afterglow — Watch Together

## Mobile and playback update — September 2026

The phone layout has two tabs: **Watch** and **Chat**. The same player stays mounted above either screen. Watch contains recent people, watch history and video sources; avatars open people/settings. Fullscreen requests landscape orientation when supported and uses a rotated layout fallback on portrait phones. Custom controls hide automatically; tap the video to reveal them.

The app includes a web app manifest, Apple touch icon, standalone Home Screen mode, and a service worker that caches only the interface. Open the profile menu and choose **Add to Home Screen**. Watching and chatting still require an internet connection. This is an installable web app, not an App Store binary.

### Expanded video links

- Direct **TS / M2TS / MTS** and **FLV** use a lazy-loaded MPEG-TS adapter.
- **DASH (.mpd)** uses a lazy-loaded Shaka adapter.
- **HLS (.m3u8)** uses native Apple playback where available, otherwise hls.js.
- **MP4, M4V, MOV, WebM, Ogg** and other native media are passed to the browser decoder.
- **Signed and extensionless URLs** are accepted. Detection checks format-related query parameters, response MIME type and a bounded sample of the stream. Signed query strings are preserved. If browser fetch is blocked, native playback is attempted instead.
- The video picker has an explicit format override for opaque URLs. Retry and change-format actions appear for playback failures. YouTube and Vimeo retain their dedicated adapters.

Accepting a URL does not guarantee playback. A webpage is not a media stream. Embedding restrictions, DRM, authentication, expired signatures, source CORS settings, unavailable codecs and mixed HTTP/HTTPS content still apply. No protection is stripped and no arbitrary URL is fetched by the server. Media detection occurs on the viewer's device without credentials.

Raw TS support depends on MediaSource / ManagedMediaSource and compatible video/audio codecs; mpegts.js documents iPhone support from iOS 17.1 onward. Older iPhones should use HLS or MP4. Raw TS does not provide general indexed file seeking in this adapter; buffered seeking can work, while full seekable watch parties should use an HLS VOD playlist or MP4. MPEG-2 video is not supported by mpegts.js. Codec support varies by browser. See the [mpegts.js documentation](https://github.com/xqq/mpegts.js).

Player controls also include ten-second skipping, an iPhone fullscreen fallback and Picture in Picture where the browser supports it. iOS may continue to use its hardware controls for volume.

Validation for this update: production compilation and five automated suites covering format detection, signed URLs, TS byte recognition using the included fixture, native fallback, room synchronization, chat and presence. Physical iPhone/Android testing and new end-to-end TS/DASH playback checks have not been completed; earlier preview browser access was blocked by its URL policy. The two-tab results below describe the original MP4 implementation, not new device-level validation.

A complete Vue 3 Composition API + Vite + Tailwind CSS frontend and Express + Socket.io server. No account setup, room-code entry, screen sharing, or video rebroadcasting. Pick a video; the app creates `/watch/:roomId`. People opening the link join automatically.

## YouTube, web players and file compatibility

YouTube loading now clears failed requests before retrying, polls for API readiness if another widget replaces its callback, and reports provider error codes (including missing referrer error 153). The server sends a strict-origin-when-cross-origin referrer policy. A blocked YouTube domain, disabled embedding, or WebView policy still needs a browser/network change; retry cannot bypass those restrictions.

Paste an HTTPS web-player URL with **Web page / iframe** selected, or paste a complete quoted iframe embed code into the picker. Only the source URL is kept; submitted HTML and event handlers are never rendered. YouTube and Vimeo embeds still use their dedicated synchronized APIs. Other pages use a sandboxed iframe with an Open source link. The page must allow embedding; CSP frame-ancestors and X-Frame-Options are respected. No desktop browser or native WebView is installed by this feature.

Direct video/audio links include 3GP, AAC, AIF/AIFF, ASF, AVI, M4A, M4V, MKV, MOV, MP3, MP4, MPA/MPE/MPEG/MPG, OGG/OGV, QT, RA/RM/RMVB, WAV, WMA/WMV, WebM, FLAC and Opus. Recognition is not codec conversion: legacy containers and codecs commonly require conversion to MP4 with H.264/AAC or MP3 before browsers can decode them. HLS, DASH, TS and FLV retain their existing adapters. There is no transcoding service bundled here.

7Z, ACE, ARJ, BZ2, GZ/GZIP, LZH, R00–R99, RAR, SEA, SIT/SITX, TAR, Z and ZIP are archives; extract the media first. APK, EXE, MSI/MSU, BIN, IMG/ISO, PDF, PLJ, PPS/PPT, and TIF/TIFF are not playable video/audio. They produce an actionable error instead of an endless loading player.

Synchronization sends explicit play/pause state and timestamps through Socket.io. Player-originated YouTube, Vimeo and native play/pause events also update the room; remote commands are suppressed to avoid echo loops. Google Drive and arbitrary cross-origin embeds remain manual: the browser cannot access their internal controls or synthesize trusted user taps. A provider playback API or a separately developed browser extension/native integration would be required for those sources.

## Run locally

Requires Node.js 22 or newer.

```sh
npm ci
npm run dev
```

Open `http://localhost:4173`. The Vite development plugin attaches the real Socket.io backend to the same HTTP server: one origin, one port, no separate CORS configuration. The standalone Express server is used for production. This arrangement uses the same room implementation in both modes.

For a self-contained test, paste `http://localhost:4173/sync-check.mp4`. This bundled, original 90-second color-pattern video includes an audio test tone. Turn your volume down before playing it. A short HLS test is at `http://localhost:4173/hls-check/master.m3u8`.

Use a second browser/private window for another guest. To simulate two guests in regular tabs sharing localStorage, open the profile menu in the second tab and choose **Use a new guest identity**, then open the first tab’s watch link. Existing tabs retain their in-memory identity until reloaded. Switching identities clears the stored watch partners on that browser, so use a private window for ongoing multi-user testing.

## Production

```sh
npm ci
npm run build
```

Copy `.env.example` to `.env`. Set `IDENTITY_SECRET` to a random, stable secret (at least 32 random bytes), set `ALLOWED_ORIGINS` to the exact public HTTPS origin (comma-separated for multiple origins), and configure a TURN service for reliable voice across restricted networks. Then:

```sh
npm run start:env
```

If your host injects environment variables, use `npm start` instead. The server listens on `PORT` (3000 by default), serves the built SPA, handles deep links, and exposes `GET /api/health`. A Node host with long-lived WebSockets is required; static-only hosting does not run the room server.

Docker:

```sh
docker build -t afterglow .
docker run --env-file .env -p 3000:3000 afterglow
```

Put HTTPS in front of Express, preserve the host/origin headers, and forward WebSocket upgrades. For example, in an existing Nginx TLS server:

```nginx
location / {
    proxy_pass http://127.0.0.1:3000;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 75s;
}
```

`TURN_URL`, `TURN_USERNAME`, and `TURN_CREDENTIAL` are optional configuration variables. Use a dedicated, restricted TURN credential; configured credentials are delivered to guests because browsers need them. A production TURN service should issue short-lived credentials; integrate its credential endpoint if needed. The default STUN service alone cannot traverse every firewall.

## Included behavior

- Immediate room creation after valid video selection, automatic URL updates and deep-link joining.
- HTML5 MP4/WebM/Ogg, HLS via native support or lazy-loaded hls.js, YouTube IFrame API, and Vimeo Player API.
- Shared play, pause, seek, and playback speed. Everyone in a room may control playback; last accepted action wins.
- Server-authoritative timestamps, rate-aware clock projection, four clock probes on connection, two-second state broadcasts, and local drift checks every 400 ms. Drift over one second triggers a seek. Local volume and mute do not affect other people.
- Custom playback controls publish explicit actions. Programmatic sync does not republish player events. Revision numbers reject stale incoming snapshots, and media URL checks prevent delayed actions from modifying a replacement video.
- Guest names and emoji avatars persisted locally; HMAC-signed guest credentials prevent trivial ID impersonation. This is a guest identity, not a full user account.
- Automatic mutual recent-partner registration, online media/time presence and one-click room rejoining.
- Timestamped chat, join/leave notices, floating reactions, and reconnect recovery. Chat is escaped by Vue, never inserted as HTML.
- WebRTC microphone mesh for up to eight sockets in a room. Deterministic offer initiation prevents offer collisions; candidates queue until remote descriptions are ready. Peer connections, remote audio, and microphone tracks are cleaned up on departure/disconnection.
- Origin checks, payload/event limits, input validation, room capacity, security headers, bounded chat history, cleanup, and graceful shutdown.
- Responsive layout, dialog focus handling, keyboard playback controls, form labels, and reduced-motion support.

## Data and operating limits

Room state and the last 100 messages are deliberately **in memory**, as requested. Empty rooms expire after 30 minutes; all rooms disappear on server restart. Guest identity tokens survive production restarts when the signing secret is stable. Saved friend names remain on each browser; their current online status is rebuilt from connections.

Run **one server instance** for this implementation. Multiple replicas need a shared room/presence store, a Socket.io adapter, and appropriate routing; adding only sticky sessions does not make room state shared. An in-memory design is not a durable service or a high-availability deployment.

Rooms are unlisted bearer links, not authenticated private rooms. A link holder may join, control playback and see chat. There is no claim of end-to-end encrypted chat. Voice travels over WebRTC; the application server forwards signaling only.

Browsers can require a user click before audible playback. The player shows an enable-playback button when blocked. Microphone access needs HTTPS (localhost is also allowed), user permission and working ICE connectivity. YouTube/Vimeo restrictions, ads, deleted videos, account restrictions, regional availability, and provider outages can affect playback. There is no DRM bypass or support for arbitrary subscription streaming pages. HLS media must permit cross-origin fetches, and all guests need access to the same media. Shared VOD timelines are supported; unrelated live/DVR timestamp discontinuities need provider-specific timeline mapping.

The included film choices point to external sample videos. Artwork is mood imagery, not official film stills. Network availability and embed rights belong to those providers. The bundled test videos allow playback testing without an external media service.

## Verification

```sh
npm test
npm run build
```

Integration tests create real independent Socket.io clients against an ephemeral server. They check URL validation, server clock math, room creation/joining, mutual friendship, play/pause/seek/rate, invalid actions, chat, reactions, in-room voice signaling, cross-room signaling denial, identity forgery rejection, reconnect/late-join state and history, missing rooms, and stale-video event rejection.

Browser QA performed in two Chrome tabs:

- Picking a video updated the route to a generated watch link.
- A second guest opening that link joined with two-member presence and reciprocal saved partners.
- The bundled MP4 played on both devices; sampled positions were 11.522 s and 11.541 s (sequential observations, not a latency benchmark).
- Shared pause and seek aligned both clients at 9.1 s, paused, at 1.5x playback rate.
- A text chat sent in one tab appeared in the other.
- Leaving and using **Join room** in the partner sidebar restored the paused time and speed.
- All three thumbnail images loaded.
- Voice correctly reported the secure-context requirement in the HTTP preview. Actual microphone capture and end-to-end voice audio were not verified.

The standalone production Express server also passed health, deep-link fallback, security-header and video byte-range smoke checks.

An additional HLS browser check was blocked by the browser URL policy. The HLS adapter is implemented and a local HLS fixture is included, but HLS playback was not browser-verified. The browser tooling provided two tabs, but did not expose arranging them side by side. External sample-video fetching was unavailable in the test network. YouTube/Vimeo playback therefore needs a final check on your deployment, as does real microphone/voice connectivity. Treat this as a deployable implementation with the stated validation limits, not an independently audited production service.

## Source map

The Flutter Android/iOS app is in [mobile](mobile/README.md), backed by the watchparty Supabase project. It includes native playback, room chat, audio/video calling, and AdMob integration. See its README for the Android APK, configuration, and validation limits.

| File | Responsibility |
| --- | --- |
| `src/App.vue` | Watch lounge, picker, chat, profile, invite and partners UI |
| `src/components/SyncPlayer.vue` | Player adapters and drift correction |
| `src/composables/useRoom.js` | Guest persistence, socket state, clock estimation and room actions |
| `src/composables/useVoice.js` | Audio mesh, signaling and resource cleanup |
| `server/realtime.js` | Room authority, presence, chat, validation and signaling |
| `server/media.js` | Provider URL parsing and expected playback time |
| `server/index.js` | Express production host and headers |
| `tests/realtime.test.js` | Real client/server integration checks |

## Artwork

The three illustrative photographs use Unsplash image assets:
- `photo-1441974231531-c6227db76b6e` — forest
- `photo-1464822759023-fed622ff2c3b` — mountain landscape
- `photo-1519608487953-e999c86e7455` — night scene

The sample films are Big Buck Bunny, Sintel, and Tears of Steel, Blender open movie projects. The original generated sync-check clip is included for testing; it is not a movie sample.

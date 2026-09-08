# Afterglow mobile

Flutter recreation of the watch-together app for Android and iOS. The existing Vue/Express website stays in the parent folder. Mobile rooms use Supabase and are independent of the website's Socket.io rooms.

## Included

- Email signup, confirmation, sign-in, password recovery, persistent sessions, and display names.
- Private rooms with 16-character invitation codes, up to eight members, host removal, shared playback controls, and recent videos.
- Watch and Chat navigation on phones; video and chat beside each other at 900 logical pixels and wider.
- Native video/audio playback and YouTube with custom play/pause, seek, mute, and fullscreen controls. Playback uses database revisions and server timestamps rather than simulated screen taps.
- Google Drive previews and HTTPS web players in a WebView. These are explicitly marked as manual playback because arbitrary embedded players do not expose a shared control interface.
- Room audio/video calls for up to four participants: mute, camera toggle, camera switch, speaker/earpiece, and leave. Camera and microphone open only after Join. Calls end when the app enters the background.
- Google AdMob adaptive banners outside the player/call controls, Google UMP consent handling, and privacy choices. Google test IDs are the defaults.
- Supabase tables protected with RLS and explicit grants. Mutating RPCs validate room membership and host permissions. Call offers, answers, and ICE messages are visible only to their recipient.

## Run on Android

This workspace has Flutter 3.44.6 / Dart 3.12.2. Packages are pinned in `pubspec.yaml` and `pubspec.lock`.

`config.local.json` already points to the supplied **watchparty** project and contains only its publishable key. It is excluded from version control. For another checkout, copy `config.example.json` to `config.local.json` and enter the project URL and publishable key.

```powershell
cd mobile
flutter pub get
flutter run --dart-define-from-file=config.local.json
flutter build apk --debug --dart-define-from-file=config.local.json
```

APK: `build/app/outputs/flutter-apk/app-debug.apk`. This is a development build for Android 7.0 / API 24 and newer. Install it on two Android devices, create separate accounts, create a room on one, and join with the invitation code on the other.

No secret/service-role key belongs in Dart defines, the client, or source control. The secret key supplied in the conversation was not used or saved; revoke it in Supabase because it was shared.

## Supabase deployment

Project: `seyhmrdouryfvhfmvwkj` (watchparty, Tokyo).

Applied migration: `supabase/migrations/20260908134029_afterglow_mobile.sql`.

Deployed Edge Function: `call-ice`, with JWT verification enabled.

The redirect allow list includes `afterglow://auth-callback/`. Android and iOS register this callback. Email confirmation remains enabled; anonymous sign-in remains disabled. Configure your own SMTP service for production email delivery.

Tables: `ag_profiles`, `ag_rooms`, `ag_members`, `ag_messages`, `ag_signals`, and `ag_history`. Every table has RLS. Private command logic lives in the non-exposed `afterglow_private` schema; `ag_command` is a security-invoker wrapper. Playback is ordered by a revision and stamped on the server. Message history is bounded to 500 messages per room, watch history to 20 sources, and expired signaling is pruned by room heartbeats.

The migration is already applied to watchparty. Do not paste it again. Use a new CLI-generated migration for future schema changes.

## Call relay

The app currently falls back to STUN/direct peer connections. **TURN is not configured yet**, so some carrier, corporate, or restrictive NAT networks will prevent calls from connecting.

The deployed function supports a coturn-compatible REST credential service. Set these Edge Function secrets in Supabase:

```text
TURN_URLS=["turn:YOUR_RELAY_HOST:3478?transport=udp","turns:YOUR_RELAY_HOST:5349?transport=tcp"]
TURN_SHARED_SECRET=YOUR_COTURN_SHARED_SECRET
```

Configure the same shared secret on your relay with coturn's `use-auth-secret`. Do not copy this secret into the mobile configuration. The function verifies the signed-in user and room membership and issues credentials lasting ten minutes. Relay hosting and bandwidth are not provisioned by this repository.

## AdMob production configuration

Use your own AdMob application and banner-unit IDs before publishing:

- Android application ID: set `ADMOB_APP_ID` in `android/gradle.properties` or supply the Gradle property. The default is Google's sample app ID.
- iOS application ID: replace `GADApplicationIdentifier` in `ios/Runner/Info.plist`.
- Banner units: set `ADMOB_ANDROID_BANNER_ID` and `ADMOB_IOS_BANNER_ID` in the local Dart configuration.
- Configure consent messages in AdMob Privacy & messaging. If consent or the ad service is unavailable, the room stays usable and does not request ads without permission.
- Complete Play/App Store privacy disclosures and supply your app privacy-policy URL before store submission.

Integration follows the [Google Flutter setup](https://developers.google.com/admob/flutter/quick-start) and [UMP guidance](https://developers.google.com/admob/flutter/privacy). Current SDKs can require updated advertising-network entries for iOS; maintain these when enabling additional ad networks.

## Release signing and iOS

For Android store builds, copy `android/key.properties.example` to `android/key.properties` and configure your own upload keystore. Release builds do not silently use the debug key. Then build an app bundle:

```powershell
flutter build appbundle --release --dart-define-from-file=config.local.json
```

iOS source and camera/microphone/AdMob/deep-link settings are included. Building/signing an IPA requires macOS, Xcode, and your Apple developer team; it cannot be performed on this Windows machine. Review bundle identifiers and app icons before store submission.

## Validation

```powershell
flutter analyze
flutter test
```

Tests cover media-link parsing, unsafe/non-media files, server-clock playback, shared pause commands, offline recovery, two-tab navigation, and phone portrait/landscape/tablet layouts. Widget screenshots are written to `build/qa/` using test room data; these are layout previews, not evidence of a live call.

`supabase/tests/room_security.sql` was executed against watchparty and passed. It creates temporary test identities in a transaction, checks outsider isolation, profile ownership, host-only controls, stale playback revisions, shared pause, and recipient-only signaling, then rolls everything back. The deployed credential function also rejects unsigned requests with HTTP 401. Supabase's security advisor reported no findings after the migration.

No physical phone or Android emulator was connected for this build. Verify YouTube/direct playback, permissions, audio routing, full-screen rotation, ads, email callbacks, and calls on two real devices before release. Google Drive access depends on file sharing, video codecs depend on the device, and archive/document/installer files are not video formats. Generic WebViews do not bypass DRM, login, or provider restrictions.

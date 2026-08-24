# Changelog

All notable changes to Count Me In are recorded here, newest first.

The current shipped version is `1.1.1+2` (see `pubspec.yaml` for what's
building locally, which may be ahead of it). Anything under
**Unreleased** hasn't gone out in a build yet, since App Store/Play
Store releases are cut manually, not on every commit.

## Unreleased

### Added
- Debug-only "Send test notification" button (Settings > Notifications,
  only visible in `kDebugMode` builds) that sends a real push through the
  full pipeline - Firestore write -> `sendPushNotification` -> FCM -
  without needing a second account/device to trigger one. Needed a
  narrow Firestore rules carve-out: `pushNotifications` writes normally
  can't target yourself (`recipientUid != request.auth.uid`, to prevent
  self-spam), except for `type == 'debug_test'`.

### Fixed
- The real reason push notifications never worked, in any build,
  regardless of the 1.1.2+3 retry fix below: two separate things were
  missing, found by working through this debug button end-to-end and
  watching both the client logs and the Cloud Function logs.
  1. `ios/Runner/Runner.entitlements` never had an `aps-environment` key
     - the Push Notifications capability was never actually added in
     Xcode, so `firebase_messaging`'s APNs device token registration
     silently never completed (`apns-token-not-set`, forever, not just
     slow). `PushNotificationService._getTokenWithRetry` also now
     explicitly waits on `getAPNSToken()` before ever calling
     `getToken()`, per Firebase's own error message, instead of just
     blindly retrying `getToken()` and hoping APNs won the race.
  2. Firebase Console had no APNs Authentication Key uploaded at all for
     the iOS app (Project Settings > Cloud Messaging > Apple app
     configuration) - so even with a valid FCM token, sending failed
     server-side with `messaging/third-party-auth-error: Invalid APNs
     credential`. Fixed by generating a Sandbox & Production auth key in
     Apple Developer (Certificates, Identifiers & Profiles > Keys) and
     uploading it there.
  Confirmed end-to-end via the debug test button: Cloud Function logs
  now show `"message":"Sent push"` instead of skipping or erroring.

## 1.1.2+3

### Added
- Two new notification types, each with its own toggle in Settings >
  Notifications, on top of (not replacing) the existing "Someone joins"
  group toggle:
  - "Someone joins your group" - only for groups you created, separately
    toggleable from the existing "notify me for any group I'm in" one.
  - "Someone joins your challenge" - challenges had no join notification
    at all before this.
  Cloud Functions side deployed and live.

### Fixed
- Removed the auto-redirect to the App Store from the deep link landing
  page (`cf-pages/404.html`, added in 1.1.1+2 below). Landing on that
  page doesn't reliably mean the app isn't installed - Universal Links
  can flash the app open then still fall back to Safari (an iOS-level
  race), and the forced redirect fought the Smart App Banner's correct
  "Open" behavior in exactly that case, turning a working-ish link tap
  into a confusing App Store detour. "Get the app" is now a manual
  button again; the Smart Banner still offers native "Open" when the
  app's present. Cloudflare-only change, no app rebuild needed.
- FCM push token could silently never get saved on iOS - `getToken()`
  can throw if called before APNs finishes registering the device, and
  the call had no error handling (fire-and-forget from `auth_gate.dart`),
  so the failure was invisible. Added `PushNotificationService
  ._getTokenWithRetry`. **Turned out to be necessary but not
  sufficient** - see Unreleased above for the two actual missing pieces
  (a missing entitlement, and no APNs key in Firebase Console) found
  after this alone didn't fix it.

## 1.1.1+2

### Added
- Deep link landing page (`cf-pages/404.html`) now redirects straight to
  the [App Store listing](https://apps.apple.com/us/app/count-me-in-group-challenges/id6801997166)
  when someone taps a `count-me-in-links.pages.dev/join/...` link without
  the app installed, instead of showing a "check back soon" placeholder.
- Committed the `cf-pages/` source (Universal Links / App Links
  association files and the fallback landing page) into the repo - it
  previously only existed in a scratch folder and had to be recreated by
  hand for each redeploy.
- "Free for all" group mode - a third option in the "Who controls
  tallies?" picker when creating a group, alongside Member and Admin.
  Lets any member update any other member's tally. Firestore rules
  deployed and live.
- Notification when someone joins a group you're in, with a "Someone
  joins" toggle in Settings > Notifications alongside the other group
  notification types.

### Fixed
- Joining a group or challenge could occasionally fail with a permission
  error even though the join had actually already gone through - caused
  by a race between the membership check and the write, most likely to
  show up when a deep link got processed twice (a known quirk of the
  `app_links` package). Joins are now atomic (wrapped in a Firestore
  transaction), and the deep link handler ignores an exact repeat of the
  last link it handled.
- Universal Links never actually worked on a real device, even with the
  app installed - this machine had no Apple Distribution certificate, so
  every archive (including whatever got submitted as `1.0.0+1`) was
  silently signed with a Development certificate instead. Not a code
  change: fixed by generating a Distribution certificate in Xcode
  (Settings > Accounts > Manage Certificates) and re-archiving.

## 1.0.0+1

Baseline - first version tracked here.

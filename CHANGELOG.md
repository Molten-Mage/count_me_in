# Changelog

All notable changes to Count Me In are recorded here, newest first.

The current shipped version is `1.0.0+1` (see `pubspec.yaml` for what's
building locally, which may be ahead of it). Anything under
**Unreleased** hasn't gone out in a build yet, since App Store/Play
Store releases are cut manually, not on every commit.

## Unreleased

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

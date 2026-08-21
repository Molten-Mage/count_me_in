# Changelog

All notable changes to Count Me In are recorded here, newest first.

The current shipped version is `1.0.0+1` (see `pubspec.yaml`). Anything
under **Unreleased** hasn't gone out in a build yet, since App Store/Play
Store releases are cut manually, not on every commit.

## Unreleased

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

## 1.0.0+1

Baseline - first version tracked here.

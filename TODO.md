# Count Me In — TODO

**Once you have a real App ID (Apple Developer + AdMob)**
- [ ] Change the bundle ID from the placeholder (`com.example.countMeIn` iOS / `com.example.count_me_in` Android) to a real identifier tied to your Apple Developer account
- [ ] Enroll in the Apple Developer Program ($99/yr) when ready to share beyond your own device
- [ ] Set up App Store Connect record
- [x] App icon — custom tally-mark icon already in place (`ios/Runner/Assets.xcassets/AppIcon.appiconset`)
- [ ] Finish Apple Sign In setup — Dart side is implemented (`login_page.dart`, gated to iOS/macOS) and won't affect Android/current testing, but it can't actually work until you: enroll in the Apple Developer Program (needed even to add the Xcode capability, not just to ship), add the "Sign in with Apple" capability in Xcode's Signing & Capabilities tab, and enable the Apple provider in the Firebase Console (Authentication → Sign-in method)
- [ ] Run a TestFlight beta with a few real users (friends/family group is a natural first test)
- [ ] Submit for App Store review
- [x] Swap the AdMob test App ID/ad unit IDs for real ones on both platforms — done (`ios/Runner/Info.plist`, `android/app/src/main/AndroidManifest.xml`, `lib/widgets/ad_banner.dart`)
- [x] Add a GDPR/ATT consent flow and update the privacy policy — `ConsentService` (`lib/services/consent_service.dart`) gathers Google UMP consent + iOS App Tracking Transparency before the Mobile Ads SDK ever initializes; a "Ad privacy options" tile in Settings lets EEA/UK users revisit their choice later. `PRIVACY.md` and the in-app `privacy_policy_page.dart` (which was a hardcoded duplicate, not a live read of the `.md` — now both updated in lockstep) both disclose AdMob, Firebase Analytics, and the consent flow, including that these apply even in guest mode
- [ ] Implement in-app purchase or subscription via StoreKit — needs the Apple Developer Program enrollment and App Store Connect record above before IAP products can even be created

**Worth fixing before real users touch it**
- [ ] Monitor Crashlytics once live and check whether iOS dSYM upload is actually needed — reporting itself works (Dart-level errors and native crashes both show up), but iOS native crashes won't be symbolicated without the dSYM upload build phase, which we backed out after it repeatedly broke the Xcode build (see git history around the Crashlytics setup). Revisit only if real native crashes show up unsymbolicated in practice
- [x] Add telemetry/analytics (Firebase Analytics) — `AnalyticsService` (`lib/services/analytics_service.dart`) covers: goal-reached Continue vs New goal (counter + group), counter/group/challenge create/join/delete/leave, theme mode changes, the premium prompt's Upgrade vs Not now (tagged by source: settings vs free-limit popup), and login provider on sign-in. Could still expand to screen views / drop-off funnels beyond these discrete events
- [x] Expand automated test coverage beyond the default counter smoke test — 133 tests across models, `GroupService`/`ChallengeService`/`PremiumService` (via `fake_cloud_firestore` + `firebase_auth_mocks`), `HomePage`, and the shared dialogs. Needed a couple of testability changes to production code: optional DI constructor params on `GroupService`/`ChallengeService`/`FirestoreCounterStorage`/`PremiumService` (default to the real Firebase singletons, so behavior is unchanged), `analyticsService`'s type widened to an `AnalyticsLogger` interface so tests can swap in a no-op, and a hand-rolled `FirebasePlatform` fake (`test/support/firebase_core_mocks.dart`) since real `Firebase.initializeApp()` can't run in `flutter test`. Not covered yet: Groups/Challenges list & detail pages, Settings, LoginPage, MainShell's nested-navigator behavior, drag-to-reorder — all still only reachable via manual testing
- [ ] Fix auth email deliverability to iCloud — confirmed an iCloud recipient never got a password-reset email (not spam-foldered, account/email confirmed correct in Firebase Console) while Gmail worked fine. Firebase Auth's default sender (`noreply@<project>.firebaseapp.com`, shared Google IPs) has a known reputation problem with iCloud Mail's filtering. Real fix needs a custom sending domain configured in Firebase Console (Authentication → Templates) with proper SPF/DKIM/DMARC — requires owning a domain first

**Launch / marketing**
- [ ] Post launch announcement in relevant subreddits (e.g. r/getdisciplined, r/productivity, r/loseit — pick communities matching the group-challenge use case)

**Personal goals (polish current MVP)**
- [ ] Be able to mark personal goals as completed

**Backend & auth**
- [ ] Configure Firebase for the web platform — `firebase_options.dart` only has android/ios/macos (never ran `flutterfire configure` for web), so `flutter run -d chrome` throws immediately on `Firebase.initializeApp()` and can't be used for browser-based testing/dev right now

**Group tasks**
- [x] Deep-link group invites — tapping `countmein://join/group/{code}` auto-joins and opens the group's detail page, via `DeepLinkService` (`lib/services/deep_link_service.dart`) + `AppNavigation` (`lib/services/app_navigation.dart`, lets code outside the widget tree switch `MainShell`'s tab and push onto a specific tab's Navigator). Share text in `group_detail_page.dart` includes the link alongside the manual code
- [ ] Upgrade the above to real Universal Links (iOS) / App Links (Android) once there's a domain and (for iOS) Apple Developer Program enrollment — needed for a tap to skip the browser entirely and for an App/Play Store fallback when the app isn't installed. The routing logic doesn't need to change: it only ever reads `Uri.pathSegments`, never the scheme/host. Just needs: hosting `apple-app-site-association` / `assetlinks.json` over HTTPS at the domain, the Associated Domains capability in Xcode, `android:autoVerify="true"` on the existing intent filter, and switching the shared link text from `countmein://` to `https://`
- [x] Make group edits save optimistically with instant UI feedback, and show a popup/snackbar only on failure (instead of waiting on the write before reflecting the change)

**Accounts & profile**
- [ ] Improve the login flow further (revisit UX, consider additional sign-in options)

**Friends & social**
- [ ] Look into a friends system — add/accept friends
- [ ] Let friends view each other's counters on a profile page
- [ ] Invite friends directly to a group counter (instead of only sharing a code)

**Notifications**
- [ ] In-app notification/activity log — a per-user feed of group/friend activity (goal reached, badge earned, member joined, etc.), shown via a bell icon + unread count and a list screen. Still not built; the push infra below could feed it later, but it's a separate UI piece
- [x] Push notifications (FCM) — `PushNotificationService` (`lib/services/push_notification_service.dart`) requests permission and keeps each signed-in user's token on `users/{uid}.fcmToken`. `NotificationPreferencesService` + a "Notification settings" page in Settings let each user toggle seven types independently, grouped by Groups/Challenges/Personal counters (`users/{uid}.notificationPrefs`). `functions/index.js` (Node, Blaze plan) has `sendPushNotification`, a generic Firestore-triggered sender — reads the recipient's token + per-type pref (via `PREF_KEY_BY_TYPE`), sends, cleans up. iOS delivery additionally needs the Apple Developer Program enrollment above, an APNs key uploaded in the Firebase console, and the Push Notifications capability in Xcode; Android needs none of that
- [x] Group 80%-of-target reached — client-side, `GroupService._maybeNotifyThreshold`
- [x] Group goal fully reached (100%) — client-side, `GroupService._maybeAwardGroupBadge`, fans out alongside the existing badge-award transaction
- [x] Group gone quiet — `notifyGroupQuiet` (`functions/index.js`), scheduled daily, reminds every member once a group's had no tally activity for 7+ days. Activity is tracked via `lastActivityAt` on the group doc, bumped (and `quietNotifiedAt` cleared) by `GroupService._touchGroupActivity` on every increment/decrement; 7-day cooldown between repeat reminders, same shape as the counter-inactivity one below
- [x] Challenge halfway-point reminder — `notifyChallengeHalfway` (`functions/index.js`), scheduled hourly, notifies every member once "now" crosses the midpoint between a challenge's `createdAt` and `endsAt`, deduped via `halfwayNotifiedAt` on the challenge doc
- [x] Challenge deadline approaching — `notifyChallengeDeadlineApproaching` (`functions/index.js`), scheduled hourly, lead time scales with the challenge's own total duration (10% of createdAt-to-endsAt, clamped 12h–3 days) rather than a fixed window, deduped via `deadlineNotifiedAt`
- [x] Challenge leaderboard "X just passed you" — `ChallengeService._maybeNotifyLeaderboardPass`, client-side after every objective increment (never fires on decrements). Compares the acting participant's overall percent-complete (same metric shown in `challenge_participants_page.dart`) before vs. after against every other participant, and notifies anyone who was just overtaken
- [x] Personal counter inactivity reminder — `notifyCounterInactivity` (`functions/index.js`), scheduled daily, reminds a user about a counter untouched for 7+ days (`Counter.updatedAt`, bumped only on actual count changes — see `lib/models/counter.dart`), with a 7-day cooldown between repeat reminders for the same counter via `lastInactivityReminderAt`. Guest-mode counters are invisible to this (device-local only, nothing in Firestore to scan)
- [ ] **Redeploy needed** — the initial push notification + auto-replenish functions are already live, but two new scheduled functions (`notifyGroupQuiet`, `notifyChallengeDeadlineApproaching`), the expanded `PREF_KEY_BY_TYPE` mapping, the higher official-challenge floor, the expanded template pool, and a Firestore rules change (group `lastActivityAt`/`quietNotifiedAt`) have all been added since the last deploy. Run `firebase deploy --only functions,firestore:rules` from the repo root to push it all live

**Leaderboards**
- [ ] Decide tie-breaking and time-window rules (all-time vs. reset periodically)
- Challenges (time-boxed competitions paired with leaderboards):
  - [x] Full auto-replenishing — `replenishOfficialChallenges` (`functions/index.js`), scheduled daily (Blaze plan), tops up the pool of active official public challenges to a floor of 10 using the same random category/objective/duration logic as the old debug button (ported to `functions/challengeTemplates.js`, kept in sync with `lib/data/challenge_templates.dart`, and expanded to 8 categories with multiple description variants each so repeats don't read identically). The debug "Generate official challenge" button in Settings still exists for manual/immediate top-up but is no longer required. See the deploy note in the Notifications section above
  - [x] "Count Me In" as official challenges' creator — solved as a side effect of the above: the Cloud Function writes via the Admin SDK, which bypasses Firestore security rules entirely, so `createdBy` is set to a fixed sentinel (`"official-generator"`) with no real account behind it. No one's `request.auth.uid` can ever match it, so as a bonus no real account can accidentally edit or delete generated challenges either

**Achievements / badges**
- [ ] Look into time-targeted goals and streaks (e.g. daily/weekly goals, consecutive-day streak tracking)

**Visuals & platform features**
- [ ] Look into localization (support languages beyond English)
- [ ] Investigate an iOS home screen widget (WidgetKit) for incrementing/decrementing a counter without opening the app
- [x] Haptics — `HapticFeedback.lightImpact()` on every increment/decrement tap, added once in `TallyStepper` (`lib/widgets/tally_stepper.dart`) so it covers personal counters, group member tallies, and challenge objectives in one place. `HapticFeedback.heavyImpact()` on the celebration moments: goal/badge reached (`goal_reached_dialog.dart`, covers both personal counters and groups) and challenge completed (`challenge_completed_dialog.dart`)

**Monetization (later, once group features exist)**
- [x] Free tier: cap the *combined* total of personal counters + challenges + groups at 8 — gating + paywall popup implemented (`PremiumService`, `paywall_dialog.dart`); `isPremium` is currently a hardcoded placeholder (always `false`) until real purchases are wired up (see the App ID header above)
- [x] Paid tier also removes ads entirely (on top of unlocking unlimited counters/challenges/groups above) — `ad_banner.dart` now skips loading/rendering the banner when `PremiumService.isPremium` is true
- [ ] Investigate making the ad banner temporary/conditional rather than always showing — e.g. hidden for brand-new users during their first session or first few opens, so the app doesn't feel ad-cluttered before someone's had a chance to get value from it. Could also tie into the free-tier/paid-tier decision above (e.g. no ads until X counters/groups, or ads only after a grace period)

# Count Me In — TODO

**Shippable checklist (App Store readiness)**

*Hard blockers*
- [ ] Change the bundle ID from the placeholder (`com.example.countMeIn` iOS / `com.example.count_me_in` Android) to a real identifier tied to your Apple Developer account
- [x] Add in-app account deletion — Apple guideline 5.1.1(v) requires it since the app supports account creation; Settings currently only has Sign out
- [ ] Finish Apple Sign In setup — Dart side is implemented (`login_page.dart`, gated to iOS/macOS) and won't affect Android/current testing, but it can't actually work until you: enroll in the Apple Developer Program (needed even to add the Xcode capability, not just to ship), add the "Sign in with Apple" capability in Xcode's Signing & Capabilities tab, and enable the Apple provider in the Firebase Console (Authentication → Sign-in method)
- [ ] Enroll in the Apple Developer Program ($99/yr) when ready to share beyond your own device
- [ ] Set up App Store Connect record and app icon
- [ ] Write a privacy policy (required even for simple apps, more so once accounts/backend exist)
- [ ] Run a TestFlight beta with a few real users (friends/family group is a natural first test)
- [ ] Submit for App Store review

*Worth fixing before real users touch it*
- [ ] Tighten Firestore rules — a member can currently write any value (including negative) directly to their own `tally` field with no server-side bound, bypassing the app's client-side clamping
- [ ] Add crash/error reporting (e.g. Firebase Crashlytics) — no visibility into real-user crashes right now
- [x] Add "Forgot password" — send a password reset email link
- [x] Make invite codes actually unique — `_generateCode()` picks 6 random chars with no collision check against Firestore
- [ ] Expand automated test coverage beyond the default counter smoke test in `test/widget_test.dart`
- [ ] Fix auth email deliverability to iCloud — confirmed an iCloud recipient never got a password-reset email (not spam-foldered, account/email confirmed correct in Firebase Console) while Gmail worked fine. Firebase Auth's default sender (`noreply@<project>.firebaseapp.com`, shared Google IPs) has a known reputation problem with iCloud Mail's filtering. Real fix needs a custom sending domain configured in Firebase Console (Authentication → Templates) with proper SPF/DKIM/DMARC — requires owning a domain first

*Cosmetic*
- [x] Update `pubspec.yaml` description from the default `"A new Flutter project."`

**Personal goals (polish current MVP)**
- [x] Fix keyboard not dismissing when tapping outside the step field
- [x] Fix delete confirmation dialog text overflow
- [x] Handle edge cases (empty title, zero/negative targets, very large counts)
- [x] Be able to reorder groups and personal goals in the list
- [ ] Be able to mark personal goals as completed

**Backend & auth**
- [x] Pick a backend — Firebase
- [x] Set up the Firebase project and configure it in the app
- [x] Add sign-up/login (email+password and Google Sign-In)
- [x] Migrate counter storage from local-only to Firestore
- [ ] Configure Firebase for the web platform — `firebase_options.dart` only has android/ios/macos (never ran `flutterfire configure` for web), so `flutter run -d chrome` throws immediately on `Firebase.initializeApp()` and can't be used for browser-based testing/dev right now

**Group tasks**
- [x] Design the data model (group, members, each member's personal tally, group total)
- [x] Build "create group task" flow
- [x] Build "join group task" flow (invite code)
- [x] Build group detail screen showing group total + per-member breakdown
- [x] Wire up realtime updates so group totals update live across members
- [x] Let the group creator edit name/goal, including converting to/from having a goal
- [x] Let the group creator remove a member, with a confirm popup (Firestore rules enforce creator-only, not just the UI)
- [x] Move member removal into the "Edit group" menu instead of a remove icon sitting on every member row — cleaner member list, removal action grouped with the other admin-only actions
- [x] Add copy-to-clipboard on the invite code popup, with visual feedback that it was copied
- [x] Add a "Share" button on the invite code popup using the native share sheet (`share_plus`), sharing the code as plain text
- [ ] Upgrade invite sharing to a tappable deep link that opens the app straight to "join this group" (skips manually typing the code). Needs Universal Links (iOS) / App Links (Android): a domain to host `apple-app-site-association` / `assetlinks.json` over HTTPS, Associated Domains + intent filter config in the native projects, and an `app_links`-based listener in Flutter to catch the incoming URL and route to the join flow. Bigger lift than the plain-text share — worth doing once there's real distribution (ties into the Shippable checklist above)
- [x] Let a user leave a group counter themselves — any member can leave via an app bar icon; if the admin leaves, ownership transfers to the longest-standing remaining member, or the group is deleted if they were the only one left
- [x] Let the group creator decide at creation time whether the group is fully admin-controlled (only the admin can increase members' tallies, members can't edit their own) or member-controlled (each member controls their own tally, current/default behavior)
- [ ] Make group edits save optimistically with instant UI feedback, and show a popup/snackbar only on failure (instead of waiting on the write before reflecting the change)

**Accounts & profile**
- [x] Add a guest/offline mode — "Continue without an account" on the login page, personal counters stored on-device only (SharedPreferences), no cloud sync; Groups tab shows a sign-in prompt since group tasks are inherently multi-user
- [x] Let users set an optional username at sign-up (stored as the Firebase Auth display name), shown to other group members instead of their full name/email-derived name
- [x] Confirm password (twice) when creating an account
- [x] Let users change their password from Settings (current password, then new password twice) — only shown for email/password accounts, not Google sign-in
- [ ] Improve the login flow further (revisit UX, consider additional sign-in options)

**Friends & social**
- [ ] Look into a friends system — add/accept friends
- [ ] Let friends view each other's counters on a profile page
- [ ] Invite friends directly to a group counter (instead of only sharing a code)

**Notifications**
- [ ] In-app notification/activity log — a per-user feed of group/friend activity (goal reached, badge earned, member joined, etc.), shown via a bell icon + unread count and a list screen. No new infra needed: fan out a doc to each relevant user's `notifications` subcollection when the event happens (same pattern already used for badge-awarding), pure Firestore + Flutter, no Cloud Functions or push permissions required. Natural first step since it works the moment someone opens the app, even without push
- [ ] Support push notifications (FCM) — real device pings for group/friend activity. Needs `firebase_messaging`, storing each device's push token in Firestore, a Cloud Function (requires upgrading the Firebase project to the Blaze pay-as-you-go plan) that fans out sends via the Admin SDK when the relevant event fires, plus native setup: APNs push certs/keys in the Firebase console + Push Notifications capability in Xcode for iOS, less friction on Android. Bigger lift than the in-app log above — worth doing once there are enough real users for immediate pings to matter

**Leaderboards**
- [x] Build a leaderboard view ranking members within a group task by tally
- [ ] Decide tie-breaking and time-window rules (all-time vs. reset periodically)

**Achievements / badges**
- [x] Award a badge when a personal counter's goal is reached (target hit), shown as a horizontal scrollable viewer under Notes, capped at the latest 15
- [x] Save the date a goal was reached
- [x] Award badges for group goals too, shown under the members list, attributed to whichever member's increment crossed the goal (initials shown on the badge)
- [ ] Look into time-targeted goals and streaks (e.g. daily/weekly goals, consecutive-day streak tracking)
- [x] Show a celebratory popup when a goal is reached (personal counters and group goals)
- [x] From that popup, offer an option to raise/update the goal right there instead of needing to go find the edit button
- [x] Show a number on each badge icon for the value it was reached at, formatted compactly for large numbers (999 as-is, then 1k, 1.4k, 1M, etc.)
- [x] Different colors of badge icons (5-color cycle by chronological order the goal was reached)

**Visuals & platform features**
- [x] Add a light/dark mode switch in Settings (app currently follows system theme only — `ThemeMode.system` in `main.dart`)
- [ ] Investigate icon language/style options — look at swapping from Material Icons to a different consistent icon set (or a specific style variant, e.g. outlined vs. filled) to better match the app's look
- [ ] Look into localization (support languages beyond English)
- [ ] Investigate an iOS home screen widget (WidgetKit) for incrementing/decrementing a counter without opening the app
- [ ] Try moving the top-right AppBar action icons (share/delete/edit, etc.) down to the bottom of the screen to streamline navigation
- [ ] Replace the row of separate AppBar action icons on inner pages with a single 3-line (overflow) menu button showing text-labeled dropdown options instead

**Monetization (later, once group features exist)**
- [ ] Decide free-tier limits (e.g. capped number of personal counters)
- [ ] Scope what a paid tier unlocks (unlimited counters and/or group features)
- [ ] Implement in-app purchase or subscription via StoreKit

# Count Me In — TODO

**Shippable checklist (App Store readiness)**

*Hard blockers*
- [ ] Change the bundle ID from the placeholder (`com.example.countMeIn` iOS / `com.example.count_me_in` Android) to a real identifier tied to your Apple Developer account
- [x] Add in-app account deletion — Apple guideline 5.1.1(v) requires it since the app supports account creation; Settings currently only has Sign out
- [ ] Finish Apple Sign In setup — Dart side is implemented (`login_page.dart`, gated to iOS/macOS) and won't affect Android/current testing, but it can't actually work until you: enroll in the Apple Developer Program (needed even to add the Xcode capability, not just to ship), add the "Sign in with Apple" capability in Xcode's Signing & Capabilities tab, and enable the Apple provider in the Firebase Console (Authentication → Sign-in method)
- [ ] Enroll in the Apple Developer Program ($99/yr) when ready to share beyond your own device
- [ ] Set up App Store Connect record and app icon
- [x] Write a privacy policy (required even for simple apps, more so once accounts/backend exist)
- [ ] Run a TestFlight beta with a few real users (friends/family group is a natural first test)
- [ ] Submit for App Store review
- [ ] Swap the AdMob test App ID/ad unit IDs for real ones from an actual AdMob account before release, add a GDPR/ATT consent flow (Google's UMP SDK) if serving personalized ads, and update `PRIVACY.md` — it currently states "no ads and no third-party trackers," which stops being true once this ships for real

*Worth fixing before real users touch it*
- [x] Tighten Firestore rules — a member can currently write any value (including negative) directly to their own `tally` field with no server-side bound, bypassing the app's client-side clamping
- [x] Add crash/error reporting (e.g. Firebase Crashlytics) — no visibility into real-user crashes right now
- [ ] Monitor Crashlytics once live and check whether iOS dSYM upload is actually needed — reporting itself works (Dart-level errors and native crashes both show up), but iOS native crashes won't be symbolicated without the dSYM upload build phase, which we backed out after it repeatedly broke the Xcode build (see git history around the Crashlytics setup). Revisit only if real native crashes show up unsymbolicated in practice
- [ ] Add telemetry/analytics (e.g. Firebase Analytics) so we can see how people actually use the app — which features get touched, drop-off points, etc. Currently flying blind on usage, only have crash data
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
- [x] Investigate "Challenges" — time-boxed competitions (e.g. a week-long tally race) paired with leaderboards, distinct from the always-on group tally/leaderboard that exists today. Could be picked/regenerated from a preset list (like real-life side quests) and/or user-created
  - [x] Built as its own tab (leftmost, before Groups): a challenge is 1-10 named "objectives" (each a Counter-shaped goal) bundled with an optional deadline, joinable either by invite code (private) or directly from an "Explore" list (public/community — including official ones marked `isOfficial`, currently only settable by hand in Firestore since there's no admin UI). Solo vs. group isn't a separate mode — every challenge starts as just you, and becomes "with friends" the moment you share the code
  - [x] `firestore.rules`: per-objective tally bounds (0-999999) and a hard deny on tally writes once the challenge's deadline has passed, enforced server-side not just client-side
  - [x] Added a third "Completed" tab — a challenge moves there once either its deadline passes, or (independently, per-viewer) once *your own* tallies hit every objective that has a target. Personal completion is computed live from your own tallies, not a one-way flag, so decrementing a tally below target after completing moves it back to My Challenges. A challenge with no targeted objectives at all can only ever complete via its deadline
  - [x] Explore no longer shows challenges whose deadline has already passed (previously they'd still appear as "Join"-able even though nobody could add progress to them)
  - [x] The one-off "Seed official challenges" debug button was replaced by a permanent admin ops tool — "Generate official challenge" in Settings (still `kDebugMode`-gated) creates one random public/official challenge per tap, drawn from a template library (`lib/data/challenge_templates.dart`: Fitness/Health/Mind/Productivity categories, each with a reusable description, a few flavor names, and objectives with target ranges), 1-4 objectives picked at random, random 7/14/30-day duration. `ChallengeService.createOfficialChallenge` makes sure the generating account never ends up a member of what it creates (creates normally, then removes itself — `leaveChallenge` can't be reused here since it'd delete a brand-new solo-member challenge instead)
  - [ ] Full auto-replenishing (no human tapping a button) is still deferred — current tool is manual/on-demand, not a "keep N always active" background process. Would still need Cloud Functions (not on the Blaze plan) or a client-side "check count on Explore open" trigger to go further
  - [ ] "Count Me In" as official challenges' creator is currently cosmetic only — `createdBy` is still whichever real account tapped "Generate", masked in the UI by `isOfficial`. Firestore rules require `request.auth.uid == createdBy`, so a *real* separate identity would need a dedicated Firebase account signed into specifically for generation runs — not done, since the display-level fix already covers the visible problem
  - [x] Every challenge gets a random cosmetic emblem (icon + color, from `lib/widgets/challenge_emblem.dart`) assigned once at creation, shown in every list row and the detail page header — purely decorative, not an earned achievement like the personal/group badges
  - [x] Participant count shown in every list row and the detail page header
  - [x] Detail page header shows *your own* average % completion across objectives that have a target (not a leaderboard — objectives without a target are excluded from the average; if none have a target, nothing is shown)
  - [x] Per-objective leaderboard added on the "Challenge Info" page (renamed from "Participants") — each objective is a collapsed row by default (tap or chevron to expand, no extra "tap to see standings" hint needed), showing top 3 by tally plus a small window of ranks around the viewer if they're outside the top 3, with a "···" gap divider and the viewer's own row highlighted. A combined cross-objective leaderboard is still skipped (unclear how to rank someone ahead on one objective but behind on another)
  - [x] Objective cards in the detail page now show only your own progress (no name label, it's implied) plus a checkmark inline next to the "15/16" progress text once you've hit that objective's target — full participant comparison lives on the separate Challenge Info page instead
  - [x] `ChallengeParticipant` now persists `completedAt` (set/cleared transactionally by `ChallengeService._applyTallyDelta` on the false↔true crossing of "every targeted objective reached"), instead of every screen recomputing completion from raw tallies each time
  - [x] Challenge Info page's top card now repeats the main detail page's header (emblem, participants, time remaining, your own progress %) plus who created it (shows "Count Me In" with a verified tick for `isOfficial` challenges, since those were technically created under the seeding account), "First to complete: name", and "Participant completion rate: Z%" (reworded from "X of Y participants completed")
  - [x] Tapping the top info card or any objective card on the main detail page jumps straight to Challenge Info — objective cards land with that specific objective's standings already expanded (`ExpansionTile.initiallyExpanded`), the header card just opens the page
  - [x] My Challenges and Explore now sort by time remaining (soonest deadline first, no-deadline challenges last); Completed sorts by completion date, most recent first (own `completedAt` if personally completed, else the challenge's deadline)
  - [x] Challenge cards in every list now show a second subtitle line with your own progress % (plus time remaining/status) — needed combining each challenge with its own participant doc via a new `rxdart`-based `ChallengeService.streamMyChallengesWithParticipation()`, since sorting/displaying that data isn't possible from per-tile nested streams alone
  - [x] Create and edit now share one `ChallengeFormPage` (`existingChallenge` null vs. non-null) instead of two diverging pages — edit mode shows name/description/visibility/deadline as read-only (matches what `firestore.rules` actually lets the creator change) with only objective targets editable
  - [x] Fixed a likely focus-restoration bug: dismissing the challenge-completed celebration popup could reopen a step field's keyboard (same class of bug as the earlier Counters-page fix) — now unfocuses before showing the popup and again after it closes
  - [x] Celebration popup (confetti, same style as the personal/group goal-reached one) fires the moment your own tallies complete every targeted objective — tracked as a false→true transition so it doesn't refire on every visit, and doesn't fire retroactively for a challenge you'd already finished before opening the page
  - [x] Creator can now edit objective targets after creation (edit icon, top right, creator-only) — `firestore.rules` updated to allow the creator to update the `objectives` field. Name, description, visibility, deadline, and objective count/names are still immutable — only target numbers can change
  - [x] Fixed: the step field's keyboard couldn't be dismissed by tapping elsewhere on the challenge detail page (same class of bug already fixed on the Counters page) — now wrapped in the same tap-to-unfocus `GestureDetector`
  - [x] Fixed a real bug while restructuring: a non-member browsing a public challenge's detail page before joining (from Explore) would see live increment/decrement buttons that would fail silently (no participant doc yet) — the stepper now only shows once you've actually joined
  - [x] Fixed: browsing a public challenge's detail page before joining now has a "Join Challenge" button — previously the only way in was the "Join" button back on the Explore list
  - [x] Deployed the updated `firestore.rules` (creator objective-target edits, `completedAt` field) to the live Firebase project
  - [x] Deploy the new `firestore.rules` (challenges collection) to the live Firebase project

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
- [x] Investigate icon language/style options — look at swapping from Material Icons to a different consistent icon set (or a specific style variant, e.g. outlined vs. filled) to better match the app's look
- [ ] Look into localization (support languages beyond English)
- [ ] Investigate an iOS home screen widget (WidgetKit) for incrementing/decrementing a counter without opening the app
- [x] Try moving the top-right AppBar action icons (share/delete/edit, etc.) down to the bottom of the screen to streamline navigation
- [x] Replace the row of separate AppBar action icons on inner pages with a single 3-line (overflow) menu button showing text-labeled dropdown options instead
- [x] Update Counters visuals to match Group counters more closely — same background panel styling, and move the reset button out to sit on its own underneath (rather than wherever it currently lives) so it reads more cohesively with the rest of the app
- [x] Audit every popup/dialog in the app for consistent positive/negative (and neutral, where a third option exists) button placement — decide on one convention and make sure `AppDialog`/`AppDialogActions` and any one-off dialogs all actually follow it

**Monetization (later, once group features exist)**
- [ ] Free tier: cap the *combined* total of personal counters + challenges + groups at some number X — paid tier removes the cap
- [ ] Paid tier also removes ads entirely (on top of unlocking unlimited counters/challenges/groups above)
- [ ] Implement in-app purchase or subscription via StoreKit
- [x] Investigate ads (network, placement, and whether they're worth it alongside/instead of a paid tier) — went with a top banner via AdMob (`google_mobile_ads`), currently wired up with Google's public test IDs in `AndroidManifest.xml`, `Info.plist`, and `lib/widgets/ad_banner.dart`
- [ ] Investigate making the ad banner temporary/conditional rather than always showing — e.g. hidden for brand-new users during their first session or first few opens, so the app doesn't feel ad-cluttered before someone's had a chance to get value from it. Could also tie into the free-tier/paid-tier decision below (e.g. no ads until X counters/groups, or ads only after a grace period)
- [x] Reduce the ad banner's size at the top — switched from `AdSize.getLargeAnchoredAdaptiveBannerAdSize` to the shorter (deprecated but still functional) `getCurrentOrientationAnchoredAdaptiveBannerAdSize`

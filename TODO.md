# Count Me In — TODO

**Once you have a real App ID (Apple Developer + AdMob)**
- [ ] Change the bundle ID from the placeholder (`com.example.countMeIn` iOS / `com.example.count_me_in` Android) to a real identifier tied to your Apple Developer account
- [ ] Enroll in the Apple Developer Program ($99/yr) when ready to share beyond your own device
- [ ] Set up App Store Connect record and app icon
- [ ] Finish Apple Sign In setup — Dart side is implemented (`login_page.dart`, gated to iOS/macOS) and won't affect Android/current testing, but it can't actually work until you: enroll in the Apple Developer Program (needed even to add the Xcode capability, not just to ship), add the "Sign in with Apple" capability in Xcode's Signing & Capabilities tab, and enable the Apple provider in the Firebase Console (Authentication → Sign-in method)
- [ ] Run a TestFlight beta with a few real users (friends/family group is a natural first test)
- [ ] Submit for App Store review
- [ ] Swap the AdMob test App ID/ad unit IDs for real ones from an actual AdMob account before release, add a GDPR/ATT consent flow (Google's UMP SDK) if serving personalized ads, and update `PRIVACY.md` — it currently states "no ads and no third-party trackers," which stops being true once this ships for real
- [ ] Implement in-app purchase or subscription via StoreKit — needs the Apple Developer Program enrollment and App Store Connect record above before IAP products can even be created

**Worth fixing before real users touch it**
- [ ] Monitor Crashlytics once live and check whether iOS dSYM upload is actually needed — reporting itself works (Dart-level errors and native crashes both show up), but iOS native crashes won't be symbolicated without the dSYM upload build phase, which we backed out after it repeatedly broke the Xcode build (see git history around the Crashlytics setup). Revisit only if real native crashes show up unsymbolicated in practice
- [ ] Add telemetry/analytics (e.g. Firebase Analytics) so we can see how people actually use the app — which features get touched, drop-off points, etc. Currently flying blind on usage, only have crash data
- [ ] Expand automated test coverage beyond the default counter smoke test in `test/widget_test.dart`
- [ ] Fix auth email deliverability to iCloud — confirmed an iCloud recipient never got a password-reset email (not spam-foldered, account/email confirmed correct in Firebase Console) while Gmail worked fine. Firebase Auth's default sender (`noreply@<project>.firebaseapp.com`, shared Google IPs) has a known reputation problem with iCloud Mail's filtering. Real fix needs a custom sending domain configured in Firebase Console (Authentication → Templates) with proper SPF/DKIM/DMARC — requires owning a domain first

**Personal goals (polish current MVP)**
- [ ] Be able to mark personal goals as completed

**Backend & auth**
- [ ] Configure Firebase for the web platform — `firebase_options.dart` only has android/ios/macos (never ran `flutterfire configure` for web), so `flutter run -d chrome` throws immediately on `Firebase.initializeApp()` and can't be used for browser-based testing/dev right now

**Group tasks**
- [ ] Upgrade invite sharing to a tappable deep link that opens the app straight to "join this group" (skips manually typing the code). Needs Universal Links (iOS) / App Links (Android): a domain to host `apple-app-site-association` / `assetlinks.json` over HTTPS, Associated Domains + intent filter config in the native projects, and an `app_links`-based listener in Flutter to catch the incoming URL and route to the join flow. Bigger lift than the plain-text share — worth doing once there's real distribution
- [x] Make group edits save optimistically with instant UI feedback, and show a popup/snackbar only on failure (instead of waiting on the write before reflecting the change)

**Accounts & profile**
- [ ] Improve the login flow further (revisit UX, consider additional sign-in options)

**Friends & social**
- [ ] Look into a friends system — add/accept friends
- [ ] Let friends view each other's counters on a profile page
- [ ] Invite friends directly to a group counter (instead of only sharing a code)

**Notifications**
- [ ] In-app notification/activity log — a per-user feed of group/friend activity (goal reached, badge earned, member joined, etc.), shown via a bell icon + unread count and a list screen. No new infra needed: fan out a doc to each relevant user's `notifications` subcollection when the event happens (same pattern already used for badge-awarding), pure Firestore + Flutter, no Cloud Functions or push permissions required. Natural first step since it works the moment someone opens the app, even without push
- [ ] Support push notifications (FCM) — real device pings for group/friend activity. Needs `firebase_messaging`, storing each device's push token in Firestore, a Cloud Function (requires upgrading the Firebase project to the Blaze pay-as-you-go plan) that fans out sends via the Admin SDK when the relevant event fires, plus native setup: APNs push certs/keys in the Firebase console + Push Notifications capability in Xcode for iOS, less friction on Android. Bigger lift than the in-app log above — worth doing once there are enough real users for immediate pings to matter

**Leaderboards**
- [ ] Decide tie-breaking and time-window rules (all-time vs. reset periodically)
- Challenges (time-boxed competitions paired with leaderboards):
  - [ ] Full auto-replenishing (no human tapping a button) is still deferred — current tool is manual/on-demand, not a "keep N always active" background process. Would still need Cloud Functions (not on the Blaze plan) or a client-side "check count on Explore open" trigger to go further
  - [ ] "Count Me In" as official challenges' creator is currently cosmetic only — `createdBy` is still whichever real account tapped "Generate", masked in the UI by `isOfficial`. Firestore rules require `request.auth.uid == createdBy`, so a *real* separate identity would need a dedicated Firebase account signed into specifically for generation runs — not done, since the display-level fix already covers the visible problem

**Achievements / badges**
- [ ] Look into time-targeted goals and streaks (e.g. daily/weekly goals, consecutive-day streak tracking)

**Visuals & platform features**
- [ ] Look into localization (support languages beyond English)
- [ ] Investigate an iOS home screen widget (WidgetKit) for incrementing/decrementing a counter without opening the app

**Monetization (later, once group features exist)**
- [x] Free tier: cap the *combined* total of personal counters + challenges + groups at 8 — gating + paywall popup implemented (`PremiumService`, `paywall_dialog.dart`); `isPremium` is currently a hardcoded placeholder (always `false`) until real purchases are wired up (see the App ID header above)
- [x] Paid tier also removes ads entirely (on top of unlocking unlimited counters/challenges/groups above) — `ad_banner.dart` now skips loading/rendering the banner when `PremiumService.isPremium` is true
- [ ] Investigate making the ad banner temporary/conditional rather than always showing — e.g. hidden for brand-new users during their first session or first few opens, so the app doesn't feel ad-cluttered before someone's had a chance to get value from it. Could also tie into the free-tier/paid-tier decision above (e.g. no ads until X counters/groups, or ads only after a grace period)

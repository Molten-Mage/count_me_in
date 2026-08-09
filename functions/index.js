const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {logger} = require("firebase-functions");
const {challengeCategories, challengeDurationDaysOptions} =
  require("./challengeTemplates");

initializeApp();
const db = getFirestore();
const messaging = getMessaging();

// Maps a pushNotifications doc's `type` to the notificationPrefs key that
// gates it — kept in sync with
// lib/services/notification_preferences_service.dart.
const PREF_KEY_BY_TYPE = {
  group_threshold: "groupThreshold",
  group_goal_reached: "groupGoalReached",
  group_quiet: "groupQuiet",
  challenge_halfway: "challengeHalfway",
  challenge_deadline: "challengeDeadline",
  challenge_passed: "challengePassed",
  counter_inactivity: "counterInactivity",
};

/**
 * Every notification type (group 80% threshold from the Flutter client,
 * challenge-halfway and counter-inactivity from the scheduled functions in
 * this file) writes one doc per recipient into `pushNotifications`. This
 * is the single place that actually calls FCM: it checks the recipient's
 * per-type preference and stored token, sends if eligible, and always
 * deletes the doc afterward so the collection never accumulates old jobs.
 */
exports.sendPushNotification = onDocumentCreated(
    "pushNotifications/{id}",
    async (event) => {
      const snap = event.data;
      if (!snap) return;
      const data = snap.data();
      const {recipientUid, type, title, body} = data;

      try {
        if (!recipientUid || !title || !body) {
          logger.warn("pushNotifications doc missing required fields", {
            id: event.params.id,
          });
          return;
        }

        const userSnap = await db.collection("users").doc(recipientUid).get();
        const userData = userSnap.data() || {};
        const token = userData.fcmToken;
        const prefKey = PREF_KEY_BY_TYPE[type];
        const enabled = prefKey ?
          (userData.notificationPrefs || {})[prefKey] ?? true :
          true;

        if (!token || !enabled) return;

        await messaging.send({
          token,
          notification: {title, body},
        });
      } catch (err) {
        logger.error("Failed to send push notification", err);
      } finally {
        await snap.ref.delete();
      }
    },
);

/**
 * Every hour, notifies each challenge's members once "now" has crossed the
 * halfway point between the challenge's `createdAt` and `endsAt`.
 * Challenges with no `endsAt` (open-ended) are skipped — there's no
 * halfway point to compute. Dedup via `halfwayNotifiedAt` on the challenge
 * doc itself, same one-shot-per-value idea as the client's badge/threshold
 * dedupe fields, just stored as "already sent" rather than "sent for which
 * value" since a challenge's `endsAt` doesn't change after creation.
 *
 * Scans the whole `challenges` collection rather than a filtered query —
 * simplest option, and fine at this app's scale; revisit with a composite
 * index (`endsAt` range + `halfwayNotifiedAt` equality) if the collection
 * grows large enough for a full scan every hour to matter.
 */
exports.notifyChallengeHalfway = onSchedule("every 60 minutes", async () => {
  const now = Date.now();
  const snapshot = await db.collection("challenges").get();

  for (const doc of snapshot.docs) {
    const data = doc.data();
    if (!data.endsAt || data.halfwayNotifiedAt) continue;

    const createdAtMs = data.createdAt.toMillis();
    const endsAtMs = data.endsAt.toMillis();
    const halfwayMs = createdAtMs + (endsAtMs - createdAtMs) / 2;
    if (now < halfwayMs || now >= endsAtMs) continue;

    const memberIds = data.memberIds || [];
    const batch = db.batch();
    batch.update(doc.ref, {halfwayNotifiedAt: FieldValue.serverTimestamp()});
    for (const uid of memberIds) {
      batch.set(db.collection("pushNotifications").doc(), {
        recipientUid: uid,
        type: "challenge_halfway",
        title: data.name,
        body: `"${data.name}" is halfway through its time — keep it up!`,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
});

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;
// Reminder fires this fraction of the challenge's total duration before
// endsAt, clamped to a sane range — a 7-day challenge gets ~17h notice, a
// 30-day one gets the 3-day cap rather than a barely-useful ~1h notice.
const DEADLINE_LEAD_FRACTION = 0.1;
const DEADLINE_LEAD_MIN_MS = 12 * HOUR_MS;
const DEADLINE_LEAD_MAX_MS = 3 * DAY_MS;

/**
 * Every hour, notifies each challenge's members once its deadline is
 * close — how close scales with the challenge's own total duration
 * (`DEADLINE_LEAD_FRACTION` of createdAt-to-endsAt, clamped between
 * `DEADLINE_LEAD_MIN_MS` and `DEADLINE_LEAD_MAX_MS`) rather than a fixed
 * lead time, so a week-long sprint and a month-long challenge each get a
 * proportionate heads-up. Dedup via `deadlineNotifiedAt` on the challenge
 * doc, same one-shot idea as `halfwayNotifiedAt` above.
 */
exports.notifyChallengeDeadlineApproaching = onSchedule(
    "every 60 minutes",
    async () => {
      const now = Date.now();
      const snapshot = await db.collection("challenges").get();

      for (const doc of snapshot.docs) {
        const data = doc.data();
        if (!data.endsAt || data.deadlineNotifiedAt) continue;

        const createdAtMs = data.createdAt.toMillis();
        const endsAtMs = data.endsAt.toMillis();
        const totalDurationMs = endsAtMs - createdAtMs;
        if (totalDurationMs <= 0) continue;

        const leadTimeMs = Math.min(
            Math.max(totalDurationMs * DEADLINE_LEAD_FRACTION, DEADLINE_LEAD_MIN_MS),
            DEADLINE_LEAD_MAX_MS,
        );
        const reminderAtMs = endsAtMs - leadTimeMs;
        if (now < reminderAtMs || now >= endsAtMs) continue;

        const daysLeft = Math.max(1, Math.round((endsAtMs - now) / DAY_MS));
        const memberIds = data.memberIds || [];
        const batch = db.batch();
        batch.update(doc.ref, {
          deadlineNotifiedAt: FieldValue.serverTimestamp(),
        });
        for (const uid of memberIds) {
          batch.set(db.collection("pushNotifications").doc(), {
            recipientUid: uid,
            type: "challenge_deadline",
            title: data.name,
            body: `"${data.name}" ends in ${daysLeft} ` +
              `day${daysLeft === 1 ? "" : "s"} — finish strong!`,
            createdAt: FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
    },
);

// Used both as the inactivity threshold and, once a reminder's gone out,
// as the cooldown before the same counter can trigger another one — so a
// counter left untouched gets nudged about once a week, not every day.
const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000;

/**
 * Once a day, reminds each user about personal counters they haven't
 * touched in 7+ days. Counters live as a JSON array embedded in the
 * `counters` field of each `users/{uid}` doc (see
 * lib/services/firestore_counter_storage.dart) rather than as their own
 * documents, so there's no per-counter doc to query — this scans every
 * user doc that has a `counters` array, checks each entry's `updatedAt`,
 * and writes back an updated `lastInactivityReminderAt` per counter
 * (inside that same array field) so the same stale counter doesn't
 * trigger a push every single day.
 *
 * Guest-mode counters (device-local only, never synced to Firestore) are
 * invisible to this — and unreachable by any server-side check, since
 * there's nothing in Firestore to scan for them.
 */
exports.notifyCounterInactivity = onSchedule("every 24 hours", async () => {
  const now = Date.now();
  // Firestore's `!=` doesn't support comparing against `null`, so this
  // can't be filtered server-side — scan every user doc and skip the ones
  // without a `counters` array. Fine at this app's scale; revisit if the
  // user collection grows large enough for a daily full scan to matter.
  const snapshot = await db.collection("users").get();

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const counters = data.counters;
    if (!Array.isArray(counters) || counters.length === 0) continue;

    const enabled = (data.notificationPrefs || {}).counterInactivity ?? true;
    const token = data.fcmToken;
    if (!enabled || !token) continue;

    let changed = false;
    const updatedCounters = [];
    for (const counter of counters) {
      const updatedAtMs = Date.parse(counter.updatedAt || counter.createdAt);
      const lastReminderMs = counter.lastInactivityReminderAt ?
        Date.parse(counter.lastInactivityReminderAt) :
        null;
      const staleEnough = now - updatedAtMs >= SEVEN_DAYS_MS;
      const dueForReminder = staleEnough &&
        (!lastReminderMs || now - lastReminderMs >= SEVEN_DAYS_MS);

      if (!dueForReminder) {
        updatedCounters.push(counter);
        continue;
      }

      changed = true;
      await db.collection("pushNotifications").add({
        recipientUid: doc.id,
        type: "counter_inactivity",
        title: counter.title,
        body: `You haven't updated "${counter.title}" in a week — ` +
          "still going?",
        createdAt: FieldValue.serverTimestamp(),
      });
      updatedCounters.push({
        ...counter,
        lastInactivityReminderAt: new Date(now).toISOString(),
      });
    }

    if (changed) {
      await doc.ref.update({counters: updatedCounters});
    }
  }
});

/**
 * Once a day, reminds every member of a group that's had no tally
 * activity in 7+ days. "Activity" is tracked via `lastActivityAt`, bumped
 * by GroupService._touchGroupActivity on every increment/decrement —
 * falls back to the group's `createdAt` for groups that predate that
 * field or have never had a single tally change. Cooldown mirrors the
 * counter-inactivity reminder above: once reminded, waits another 7 days
 * before reminding again for the same quiet stretch (and
 * `_touchGroupActivity` clears `quietNotifiedAt` the moment real activity
 * resumes, so a later quiet stretch isn't blocked by a stale timestamp).
 */
exports.notifyGroupQuiet = onSchedule("every 24 hours", async () => {
  const now = Date.now();
  const snapshot = await db.collection("groups").get();

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const lastActivity = data.lastActivityAt || data.createdAt;
    if (!lastActivity) continue;

    const lastActivityMs = lastActivity.toMillis();
    const lastReminderMs = data.quietNotifiedAt ?
      data.quietNotifiedAt.toMillis() :
      null;
    const staleEnough = now - lastActivityMs >= SEVEN_DAYS_MS;
    const dueForReminder = staleEnough &&
      (!lastReminderMs || now - lastReminderMs >= SEVEN_DAYS_MS);
    if (!dueForReminder) continue;

    const memberIds = data.memberIds || [];
    const batch = db.batch();
    batch.update(doc.ref, {quietNotifiedAt: FieldValue.serverTimestamp()});
    for (const uid of memberIds) {
      batch.set(db.collection("pushNotifications").doc(), {
        recipientUid: uid,
        type: "group_quiet",
        title: data.name,
        body: `"${data.name}" has been quiet for a week — check in?`,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
});

// Not a real account — a fixed sentinel `createdBy` for generated official
// challenges. The old debug "Generate official challenge" button in
// Settings (settings_page.dart's _GenerateChallengeTile) had to create the
// challenge under a *real* signed-in account and then immediately remove
// them as a member, purely to satisfy the client-side rule that
// `createdBy` must match the creating account (see the note in TODO.md).
// Cloud Functions write via the Admin SDK, which bypasses security rules
// entirely, so no such workaround is needed here — and as a side effect,
// no real account can accidentally edit or delete what this generates,
// since no one's `request.auth.uid` will ever equal this string.
const OFFICIAL_GENERATOR_UID = "official-generator";

// Floor on how many active (not yet ended) official public challenges
// should exist at once — topped up daily, not tied to a fixed catalog.
const MIN_ACTIVE_OFFICIAL_CHALLENGES = 10;

const INVITE_CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

function randomInt(maxExclusive) {
  return Math.floor(Math.random() * maxExclusive);
}

function pick(list) {
  return list[randomInt(list.length)];
}

async function generateUniqueChallengeCode() {
  for (let attempt = 0; attempt < 10; attempt++) {
    let code = "";
    for (let i = 0; i < 6; i++) code += pick(INVITE_CODE_CHARS.split(""));
    const existing = await db.collection("challenges")
        .where("code", "==", code).limit(1).get();
    if (existing.empty) return code;
  }
  throw new Error("Could not generate a unique challenge invite code.");
}

// Ports the random-selection logic from settings_page.dart's
// _GenerateChallengeTile — same category/flavor-name/objective-count/
// duration randomization, just run server-side. Keep the two in sync if
// the generation "feel" changes on either side.
async function generateOfficialChallenge() {
  const category = pick(challengeCategories);
  const name = pick(category.flavorNames);
  const description = pick(category.descriptions);
  const objectiveCount = Math.min(
      1 + randomInt(4), category.objectives.length,
  );
  const shuffled = [...category.objectives].sort(() => Math.random() - 0.5);
  const chosen = shuffled.slice(0, objectiveCount);
  const durationDays = pick(challengeDurationDaysOptions);
  const code = await generateUniqueChallengeCode();
  const endsAt = new Date(
      Date.now() + durationDays * 24 * 60 * 60 * 1000,
  );

  await db.collection("challenges").add({
    name,
    description,
    visibility: "public",
    isOfficial: true,
    code,
    createdBy: OFFICIAL_GENERATOR_UID,
    createdAt: FieldValue.serverTimestamp(),
    endsAt,
    memberIds: [],
    objectives: chosen.map((o, i) => ({
      id: `obj_${i}`,
      name: o.name,
      target: o.minTarget + randomInt(o.maxTarget - o.minTarget + 1),
    })),
    emblemIconIndex: randomInt(10),
    emblemColorIndex: randomInt(5),
  });
}

/**
 * Once a day, tops up the pool of active official public challenges so
 * Explore always has fresh content available, without anyone needing to
 * tap the debug "Generate official challenge" button in Settings.
 */
exports.replenishOfficialChallenges = onSchedule(
    "every 24 hours",
    async () => {
      const now = Date.now();
      const snapshot = await db.collection("challenges")
          .where("isOfficial", "==", true)
          .where("visibility", "==", "public")
          .get();

      const activeCount = snapshot.docs.filter((doc) => {
        const endsAt = doc.data().endsAt;
        return !endsAt || endsAt.toMillis() > now;
      }).length;

      const deficit = MIN_ACTIVE_OFFICIAL_CHALLENGES - activeCount;
      for (let i = 0; i < deficit; i++) {
        await generateOfficialChallenge();
      }
    },
);

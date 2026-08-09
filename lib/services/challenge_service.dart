import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rxdart/rxdart.dart';

import '../models/challenge.dart';
import '../models/challenge_participant.dart';
import 'analytics_service.dart';

typedef ChallengeWithParticipation = ({Challenge challenge, ChallengeParticipant? me});

class ChallengeService {
  ChallengeService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('No signed-in user.');
    return uid;
  }

  String get _displayName {
    final user = _auth.currentUser;
    final name = user?.displayName;
    if (name != null && name.trim().isNotEmpty) return name;
    final email = user?.email;
    if (email != null && email.contains('@')) return email.split('@').first;
    return 'Anonymous';
  }

  CollectionReference<Map<String, dynamic>> get _challenges =>
      _firestore.collection('challenges');

  Stream<List<Challenge>> streamMyChallenges() {
    return _challenges
        .where('memberIds', arrayContains: _uid)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Challenge.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }

  /// Public challenges, including ones the caller has already joined — the
  /// UI is responsible for filtering those out of "Explore".
  Stream<List<Challenge>> streamPublicChallenges() {
    return _challenges
        .where('visibility', isEqualTo: 'public')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Challenge.fromFirestore(doc.id, doc.data()))
              .toList(),
        );
  }

  Stream<Challenge> streamChallenge(String challengeId) {
    return _challenges
        .doc(challengeId)
        .snapshots()
        .map((doc) => Challenge.fromFirestore(doc.id, doc.data()!));
  }

  Stream<List<ChallengeParticipant>> streamParticipants(String challengeId) {
    return _challenges
        .doc(challengeId)
        .collection('participants')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (doc) => ChallengeParticipant.fromFirestore(doc.id, doc.data()),
              )
              .toList(),
        );
  }

  /// The signed-in user's own participation in a challenge — null if they
  /// haven't joined. Used to detect personal completion (every objective
  /// with a target reached) independent of the challenge's deadline.
  Stream<ChallengeParticipant?> streamMyParticipant(String challengeId) {
    return _challenges
        .doc(challengeId)
        .collection('participants')
        .doc(_uid)
        .snapshots()
        .map(
          (doc) => doc.exists
              ? ChallengeParticipant.fromFirestore(doc.id, doc.data()!)
              : null,
        );
  }

  /// Each of the caller's challenges paired with their own participation
  /// record. Needed wherever the UI has to sort or filter using data that
  /// only lives on the participant doc (e.g. personal `completedAt`) —
  /// [streamMyChallenges] alone can't provide that since it only reads
  /// challenge-level documents.
  Stream<List<ChallengeWithParticipation>> streamMyChallengesWithParticipation() {
    return streamMyChallenges().switchMap((challenges) {
      if (challenges.isEmpty) {
        return Stream.value(const <ChallengeWithParticipation>[]);
      }
      final perChallenge = challenges.map(
        (challenge) => streamMyParticipant(
          challenge.id,
        ).map((me) => (challenge: challenge, me: me)),
      );
      return CombineLatestStream.list(perChallenge);
    });
  }

  Future<String> _generateUniqueCode() async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random();
    for (var attempt = 0; attempt < 10; attempt++) {
      final code = List.generate(
        6,
        (_) => chars[random.nextInt(chars.length)],
      ).join();
      final existing = await _challenges
          .where('code', isEqualTo: code)
          .limit(1)
          .get();
      if (existing.docs.isEmpty) return code;
    }
    throw StateError(
      'Could not generate a unique invite code. Please try again.',
    );
  }

  Future<Challenge> createChallenge({
    required String name,
    String description = '',
    required ChallengeVisibility visibility,
    DateTime? endsAt,
    required List<({String name, int? target})> objectives,
    // Not exposed in the normal create-challenge UI — only used for
    // curated challenges we seed ourselves.
    bool isOfficial = false,
  }) async {
    if (objectives.isEmpty || objectives.length > maxChallengeObjectives) {
      throw ArgumentError(
        'A challenge needs between 1 and $maxChallengeObjectives objectives.',
      );
    }

    final code = await _generateUniqueCode();
    final now = DateTime.now();
    final docRef = _challenges.doc();
    final random = Random();
    final challenge = Challenge(
      id: docRef.id,
      name: name,
      description: description,
      visibility: visibility,
      isOfficial: isOfficial,
      code: code,
      createdBy: _uid,
      createdAt: now,
      endsAt: endsAt,
      memberIds: [_uid],
      objectives: [
        for (var i = 0; i < objectives.length; i++)
          ChallengeObjective(
            id: 'obj_$i',
            name: objectives[i].name,
            target: objectives[i].target,
          ),
      ],
      // Cosmetic emblem, random and fixed for the challenge's lifetime.
      // Counts must match challengeEmblemIcons.length (10) and
      // badgeColors.length (5) in lib/widgets/.
      emblemIconIndex: random.nextInt(10),
      emblemColorIndex: random.nextInt(5),
    );
    final batch = _firestore.batch();
    batch.set(docRef, challenge.toFirestore());
    batch.set(
      docRef.collection('participants').doc(_uid),
      ChallengeParticipant(
        uid: _uid,
        displayName: _displayName,
        joinedAt: now,
        tallies: const {},
      ).toFirestore(),
    );
    await batch.commit();
    await analyticsService.logChallengeCreated();
    return challenge;
  }

  /// Creates a public, official challenge without the creating account
  /// ending up a member of it — these are meant to be pure content for
  /// other people to join, not something the generating (admin) account
  /// is actually part of. Firestore rules require `memberIds` to be
  /// exactly `[creator]` at creation time, so this creates normally via
  /// [createChallenge] and then removes the creator in a follow-up write,
  /// rather than [leaveChallenge] — which would instead delete the whole
  /// challenge, since it treats "creator, last member" as "nobody wants
  /// this anymore" rather than "this was never meant to have them in it".
  Future<Challenge> createOfficialChallenge({
    required String name,
    String description = '',
    required List<({String name, int? target})> objectives,
    DateTime? endsAt,
  }) async {
    final challenge = await createChallenge(
      name: name,
      description: description,
      visibility: ChallengeVisibility.public,
      isOfficial: true,
      endsAt: endsAt,
      objectives: objectives,
    );
    final ref = _challenges.doc(challenge.id);
    final batch = _firestore.batch();
    batch.update(ref, {
      'memberIds': FieldValue.arrayRemove([_uid]),
    });
    batch.delete(ref.collection('participants').doc(_uid));
    await batch.commit();
    return challenge;
  }

  /// Updates objective targets (names and ids stay fixed). Firestore rules
  /// restrict this to the challenge's creator.
  Future<void> updateObjectiveTargets(
    String challengeId,
    List<ChallengeObjective> objectives,
  ) async {
    await _challenges.doc(challengeId).update({
      'objectives': objectives.map((o) => o.toFirestore()).toList(),
    });
  }

  Future<void> _joinChallenge(DocumentReference<Map<String, dynamic>> ref) async {
    final snapshot = await ref.get();
    final data = snapshot.data();
    if (data == null) throw StateError('Challenge not found.');
    final challenge = Challenge.fromFirestore(snapshot.id, data);
    if (challenge.memberIds.contains(_uid)) return;

    final batch = _firestore.batch();
    batch.update(ref, {
      'memberIds': FieldValue.arrayUnion([_uid]),
    });
    batch.set(
      ref.collection('participants').doc(_uid),
      ChallengeParticipant(
        uid: _uid,
        displayName: _displayName,
        joinedAt: DateTime.now(),
        tallies: const {},
      ).toFirestore(),
    );
    await batch.commit();
    await analyticsService.logChallengeJoined();
  }

  Future<Challenge> joinChallengeByCode(String code) async {
    final query = await _challenges
        .where('code', isEqualTo: code.trim().toUpperCase())
        .limit(1)
        .get();
    if (query.docs.isEmpty) {
      throw StateError('No challenge found with that code.');
    }
    final doc = query.docs.first;
    await _joinChallenge(doc.reference);
    return Challenge.fromFirestore(doc.id, doc.data());
  }

  Future<void> joinPublicChallenge(String challengeId) =>
      _joinChallenge(_challenges.doc(challengeId));

  Future<void> incrementObjectiveTally(
    String challengeId,
    String objectiveId,
    int amount,
  ) async {
    await _applyTallyDelta(challengeId, objectiveId, amount);
    await _maybeNotifyLeaderboardPass(challengeId, objectiveId, amount);
  }

  Future<void> decrementObjectiveTally(
    String challengeId,
    String objectiveId,
    int amount,
  ) async {
    await _applyTallyDelta(challengeId, objectiveId, -amount);
    await _maybeNotifyLeaderboardPass(challengeId, objectiveId, -amount);
  }

  /// The same overall-percent metric shown as each participant's progress
  /// in challenge_detail_page.dart / challenge_participants_page.dart —
  /// the average, across every objective that has a target, of that
  /// objective's tally-over-target (clamped to 100%).
  double _percentComplete(List<ChallengeObjective> targeted, Map<String, int> tallies) {
    final total = targeted.fold<double>(
      0,
      (acc, o) => acc + ((tallies[o.id] ?? 0) / o.target!).clamp(0.0, 1.0),
    );
    return total / targeted.length;
  }

  /// After an objective tally increases (never fires on decrements — a
  /// drop can't be described as "passing" anyone), checks whether the
  /// acting participant's overall percent-complete now exceeds another
  /// participant's when it didn't just before this change, and notifies
  /// whoever got passed. "Before" is derived arithmetically by undoing
  /// [delta] on [objectiveId] rather than re-reading — cheaper, and this
  /// only ever gets called right after that exact delta was applied.
  /// Runs as plain reads/writes rather than a transaction: a missed or
  /// duplicate "just passed you" push under rare concurrent updates isn't
  /// worth the extra round trips for a notification (unlike the badge and
  /// threshold checks elsewhere, which guard against real duplication).
  Future<void> _maybeNotifyLeaderboardPass(
    String challengeId,
    String objectiveId,
    int delta,
  ) async {
    if (delta <= 0) return;

    final challengeRef = _challenges.doc(challengeId);
    final challengeSnapshot = await challengeRef.get();
    final challengeData = challengeSnapshot.data();
    if (challengeData == null) return;
    final challenge = Challenge.fromFirestore(challengeSnapshot.id, challengeData);

    final targeted = challenge.objectives.where((o) => (o.target ?? 0) > 0).toList();
    if (targeted.isEmpty) return;

    final participantsSnapshot = await challengeRef.collection('participants').get();
    final participants = participantsSnapshot.docs
        .map((doc) => ChallengeParticipant.fromFirestore(doc.id, doc.data()))
        .toList();

    ChallengeParticipant? me;
    for (final p in participants) {
      if (p.uid == _uid) me = p;
    }
    if (me == null) return;

    final afterPercent = _percentComplete(targeted, me.tallies);
    final beforeTallies = Map<String, int>.from(me.tallies);
    beforeTallies[objectiveId] = max((beforeTallies[objectiveId] ?? 0) - delta, 0);
    final beforePercent = _percentComplete(targeted, beforeTallies);
    if (afterPercent <= beforePercent) return;

    final notifications = _firestore.collection('pushNotifications');
    final batch = _firestore.batch();
    var wroteAny = false;
    for (final other in participants) {
      if (other.uid == _uid) continue;
      final otherPercent = _percentComplete(targeted, other.tallies);
      if (beforePercent <= otherPercent && afterPercent > otherPercent) {
        batch.set(notifications.doc(), {
          'recipientUid': other.uid,
          'type': 'challenge_passed',
          'title': challenge.name,
          'body': '$_displayName just passed you in "${challenge.name}"!',
          'createdAt': FieldValue.serverTimestamp(),
        });
        wroteAny = true;
      }
    }
    if (wroteAny) await batch.commit();
  }

  /// Applies a signed delta to one objective's tally (clamped at zero), and
  /// sets or clears `completedAt` on the false<->true transition of "every
  /// targeted objective reached" — the single source of truth other code
  /// reads instead of recomputing completion from raw tallies each time.
  Future<void> _applyTallyDelta(
    String challengeId,
    String objectiveId,
    int delta,
  ) async {
    final challengeRef = _challenges.doc(challengeId);
    final participantRef = challengeRef.collection('participants').doc(_uid);
    await _firestore.runTransaction((transaction) async {
      final challengeSnapshot = await transaction.get(challengeRef);
      final participantSnapshot = await transaction.get(participantRef);
      final challengeData = challengeSnapshot.data();
      final participantData = participantSnapshot.data();
      if (challengeData == null || participantData == null) return;
      final challenge = Challenge.fromFirestore(challengeSnapshot.id, challengeData);

      final tallies = Map<String, int>.from(
        (participantData['tallies'] as Map<String, dynamic>?) ?? {},
      );
      final current = tallies[objectiveId] ?? 0;
      tallies[objectiveId] = max(current + delta, 0);

      final targeted = challenge.objectives.where((o) => (o.target ?? 0) > 0);
      final nowComplete =
          targeted.isNotEmpty &&
          targeted.every((o) => (tallies[o.id] ?? 0) >= o.target!);
      final wasComplete = participantData['completedAt'] != null;

      final update = <String, dynamic>{'tallies': tallies};
      if (nowComplete != wasComplete) {
        update['completedAt'] = nowComplete
            ? Timestamp.fromDate(DateTime.now())
            : null;
      }
      transaction.update(participantRef, update);
    });
  }

  /// Removes the current user from the challenge. If they're the creator,
  /// ownership transfers to the longest-standing remaining member, or the
  /// whole challenge is deleted if no other members remain — same pattern
  /// as leaving a group.
  Future<void> leaveChallenge(String challengeId) async {
    await analyticsService.logChallengeLeft();
    final ref = _challenges.doc(challengeId);
    final snapshot = await ref.get();
    final data = snapshot.data();
    if (data == null) return;
    final challenge = Challenge.fromFirestore(snapshot.id, data);

    if (challenge.createdBy != _uid) {
      final batch = _firestore.batch();
      batch.update(ref, {
        'memberIds': FieldValue.arrayRemove([_uid]),
      });
      batch.delete(ref.collection('participants').doc(_uid));
      await batch.commit();
      return;
    }

    if (challenge.memberIds.length <= 1) {
      await deleteChallenge(challengeId);
      return;
    }

    final participantsSnapshot = await ref.collection('participants').get();
    final remaining =
        participantsSnapshot.docs
            .map((doc) => ChallengeParticipant.fromFirestore(doc.id, doc.data()))
            .where((p) => p.uid != _uid)
            .toList()
          ..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
    final newOwnerUid = remaining.first.uid;

    final batch = _firestore.batch();
    batch.update(ref, {
      'memberIds': FieldValue.arrayRemove([_uid]),
      'createdBy': newOwnerUid,
    });
    batch.delete(ref.collection('participants').doc(_uid));
    await batch.commit();
  }

  Future<void> deleteChallenge(String challengeId) async {
    final ref = _challenges.doc(challengeId);
    final participantsSnapshot = await ref.collection('participants').get();
    final batch = _firestore.batch();
    for (final doc in participantsSnapshot.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(ref);
    await batch.commit();
    await analyticsService.logChallengeDeleted();
  }
}

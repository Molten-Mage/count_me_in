import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationPreferences {
  // Master switch - checked server-side too (functions/index.js), so
  // turning it off is a real kill switch, not just a UI shortcut for
  // flipping the seven type toggles below.
  final bool allEnabled;
  final bool groupThreshold;
  final bool groupGoalReached;
  final bool groupQuiet;
  final bool groupMemberJoined;
  final bool myGroupMemberJoined;
  final bool challengeHalfway;
  final bool challengeDeadline;
  final bool challengePassed;
  final bool myChallengeMemberJoined;
  final bool counterInactivity;

  const NotificationPreferences({
    this.allEnabled = true,
    this.groupThreshold = true,
    this.groupGoalReached = true,
    this.groupQuiet = true,
    this.groupMemberJoined = true,
    this.myGroupMemberJoined = true,
    this.challengeHalfway = true,
    this.challengeDeadline = true,
    this.challengePassed = true,
    this.myChallengeMemberJoined = true,
    this.counterInactivity = true,
  });

  factory NotificationPreferences.fromFirestore(Map<String, dynamic>? data) =>
      NotificationPreferences(
        allEnabled: data?['allEnabled'] as bool? ?? true,
        groupThreshold: data?['groupThreshold'] as bool? ?? true,
        groupGoalReached: data?['groupGoalReached'] as bool? ?? true,
        groupQuiet: data?['groupQuiet'] as bool? ?? true,
        groupMemberJoined: data?['groupMemberJoined'] as bool? ?? true,
        myGroupMemberJoined: data?['myGroupMemberJoined'] as bool? ?? true,
        challengeHalfway: data?['challengeHalfway'] as bool? ?? true,
        challengeDeadline: data?['challengeDeadline'] as bool? ?? true,
        challengePassed: data?['challengePassed'] as bool? ?? true,
        myChallengeMemberJoined:
            data?['myChallengeMemberJoined'] as bool? ?? true,
        counterInactivity: data?['counterInactivity'] as bool? ?? true,
      );
}

/// Per-user toggles for each push notification type, stored in a
/// `notificationPrefs` map on the user's `users/{uid}` doc. The Cloud
/// Functions side (functions/index.js's `PREF_KEY_BY_TYPE`) reads this
/// same field directly before sending a push - this service only manages
/// the client's read/write of it.
class NotificationPreferencesService {
  NotificationPreferencesService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('No signed-in user.');
    return uid;
  }

  DocumentReference<Map<String, dynamic>> get _doc =>
      _firestore.collection('users').doc(_uid);

  Stream<NotificationPreferences> stream() {
    return _doc.snapshots().map(
      (doc) => NotificationPreferences.fromFirestore(
        doc.data()?['notificationPrefs'] as Map<String, dynamic>?,
      ),
    );
  }

  Future<void> setAllEnabled(bool value) => _setPref('allEnabled', value);

  Future<void> setGroupThreshold(bool value) => _setPref('groupThreshold', value);

  Future<void> setGroupGoalReached(bool value) =>
      _setPref('groupGoalReached', value);

  Future<void> setGroupQuiet(bool value) => _setPref('groupQuiet', value);

  Future<void> setGroupMemberJoined(bool value) =>
      _setPref('groupMemberJoined', value);

  Future<void> setMyGroupMemberJoined(bool value) =>
      _setPref('myGroupMemberJoined', value);

  Future<void> setChallengeHalfway(bool value) =>
      _setPref('challengeHalfway', value);

  Future<void> setChallengeDeadline(bool value) =>
      _setPref('challengeDeadline', value);

  Future<void> setChallengePassed(bool value) =>
      _setPref('challengePassed', value);

  Future<void> setMyChallengeMemberJoined(bool value) =>
      _setPref('myChallengeMemberJoined', value);

  Future<void> setCounterInactivity(bool value) =>
      _setPref('counterInactivity', value);

  // Nested-map merge: SetOptions(merge: true) merges `notificationPrefs`
  // key-by-key rather than replacing the whole map, so toggling one
  // preference never clobbers the others.
  Future<void> _setPref(String key, bool value) async {
    await _doc.set({
      'notificationPrefs': {key: value},
    }, SetOptions(merge: true));
  }
}

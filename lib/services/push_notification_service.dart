import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

void _log(String message) {
  if (kDebugMode) debugPrint('[PushNotificationService] $message');
}

/// Must be a top-level function (not a method) so it can run in a separate
/// isolate when a push arrives while the app is backgrounded or terminated.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  _log('background message: ${message.messageId}');
}

/// Requests notification permission and keeps the signed-in user's FCM
/// token saved on their `users/{uid}` doc - the Cloud Functions side reads
/// it from there to actually send pushes.
class PushNotificationService {
  PushNotificationService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  bool _listeningForRefresh = false;

  /// Call once auth state resolves to a signed-in user. Safe to call more
  /// than once - a no-op past the first successful setup for a given
  /// sign-in, and does nothing for guests.
  Future<void> init() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final settings = await FirebaseMessaging.instance.requestPermission();
    _log('permission: ${settings.authorizationStatus}');
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    // Lets iOS show a system banner for pushes that arrive while the app is
    // foregrounded. Android has no equivalent without a local-notifications
    // plugin, so foreground pushes on Android are silent for now -
    // acceptable since goal-progress/reminder pushes aren't time-critical.
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

    final token = await _getTokenWithRetry();
    if (token != null) await _saveToken(uid, token);

    if (!_listeningForRefresh) {
      _listeningForRefresh = true;
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        final currentUid = _auth.currentUser?.uid;
        if (currentUid != null) _saveToken(currentUid, newToken);
      });
    }
  }

  /// On iOS, getToken() can throw if called before APNs has finished
  /// registering the device - most likely right after a fresh install,
  /// which is exactly when init() first runs. Retries with a short delay
  /// instead of letting the token silently never get saved.
  Future<String?> _getTokenWithRetry() async {
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        return await FirebaseMessaging.instance.getToken();
      } catch (e) {
        _log('getToken attempt $attempt failed: $e');
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    return null;
  }

  Future<void> _saveToken(String uid, String token) async {
    await _firestore.collection('users').doc(uid).set({
      'fcmToken': token,
    }, SetOptions(merge: true));
  }
}

final pushNotificationService = PushNotificationService();

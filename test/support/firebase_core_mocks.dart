import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

const _fakeOptions = FirebaseOptions(
  apiKey: 'test-api-key',
  appId: 'test-app-id',
  messagingSenderId: 'test-sender-id',
  projectId: 'test-project-id',
);

class _FakeFirebaseAppPlatform extends FirebaseAppPlatform {
  _FakeFirebaseAppPlatform() : super(defaultFirebaseAppName, _fakeOptions);
}

/// Swaps the platform-interface singleton directly instead of mocking a
/// method channel — recent firebase_core versions moved app registration
/// onto a Pigeon-generated channel with its own binary codec, which is
/// impractical to hand-mock. [FirebasePlatform.instance] is the documented
/// seam for exactly this: platform implementations (and, here, tests)
/// swap it in wholesale rather than answering its channel calls.
///
/// This only fakes the *app registration* handshake, so
/// `FirebaseAuth.instance` / `FirebaseFirestore.instance` /
/// `FirebaseAnalytics.instance` field initializers stop throwing — it does
/// not fake Auth, Firestore, or Analytics' own platform channels. Widgets
/// under test still shouldn't call real methods on those instances; inject
/// `fake_cloud_firestore` / `firebase_auth_mocks` / [FakeAnalyticsLogger]
/// for that, or rely on a code path that never reaches them (e.g. reading
/// an unauthenticated `currentUser` is safely `null` locally, no channel
/// round-trip involved).
Future<void> setupFirebaseCoreMocks() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fakeApp = _FakeFirebaseAppPlatform();
  FirebasePlatform.instance = _FakeFirebasePlatform(fakeApp);

  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
}

class _FakeFirebasePlatform extends FirebasePlatform {
  _FakeFirebasePlatform(this._app);

  final _FakeFirebaseAppPlatform _app;

  @override
  List<FirebaseAppPlatform> get apps => [_app];

  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _app;

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async => _app;
}

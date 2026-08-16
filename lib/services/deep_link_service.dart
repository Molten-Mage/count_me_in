import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/challenge.dart';
import '../models/group.dart';
import '../pages/challenge_detail_page.dart';
import '../pages/group_detail_page.dart';
import '../widgets/error_dialog.dart';
import 'app_navigation.dart';
import 'challenge_service.dart';
import 'group_service.dart';

void _log(String message) {
  if (kDebugMode) debugPrint('[DeepLinkService] $message');
}

enum _JoinKind { group, challenge }

/// Handles both `https://count-me-in-links.pages.dev/join/{kind}/{code}`
/// (Universal Links on iOS, App Links on Android) and the
/// `countmein://join/{kind}/{code}` custom-scheme fallback: auto-joins the
/// group/challenge and opens its detail page inside the relevant tab.
///
/// The routing logic below only ever reads [Uri.pathSegments], never the
/// scheme or host, so it handles both link forms identically. The
/// association files that make the real links work are hosted on Cloudflare
/// Pages (apple-app-site-association, .well-known/assetlinks.json) rather
/// than the app's own molten-mage.github.io site - GitHub Pages can't serve
/// a custom Content-Type for that extension-less file, and iOS's Universal
/// Links verification needs it served as application/json. The
/// entitlement/manifest wiring is in ios/Runner/Runner.entitlements and
/// AndroidManifest.xml.
class DeepLinkService {
  ({_JoinKind kind, String code})? _pendingJoin;

  Future<void> init() async {
    final appLinks = AppLinks();

    try {
      final initial = await appLinks.getInitialLink();
      if (initial != null) _handleUri(initial);
    } catch (e) {
      _log('getInitialLink failed: $e');
    }

    appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (Object e) => _log('uriLinkStream error: $e'),
    );
  }

  /// Call whenever auth state resolves to a signed-in user - completes a
  /// join that arrived (or was tapped) before the user was signed in. Safe
  /// to call anytime; a no-op unless a join is actually pending.
  void retryPendingJoin() {
    final pending = _pendingJoin;
    if (pending != null && FirebaseAuth.instance.currentUser != null) {
      _pendingJoin = null;
      _completeJoin(pending.kind, pending.code);
    }
  }

  void _handleUri(Uri uri) {
    _log('received: $uri');
    final segments = uri.pathSegments;
    if (segments.length != 3 || segments[0] != 'join') return;
    switch (segments[1]) {
      case 'group':
        _startJoin(_JoinKind.group, segments[2]);
      case 'challenge':
        _startJoin(_JoinKind.challenge, segments[2]);
    }
  }

  void _startJoin(_JoinKind kind, String code) {
    if (FirebaseAuth.instance.currentUser == null) {
      _log('not signed in yet - deferring join for code $code');
      _pendingJoin = (kind: kind, code: code);
      return;
    }
    _completeJoin(kind, code);
  }

  Future<void> _completeJoin(_JoinKind kind, String code) {
    return switch (kind) {
      _JoinKind.group => _completeGroupJoin(code),
      _JoinKind.challenge => _completeChallengeJoin(code),
    };
  }

  Future<void> _completeGroupJoin(String code) async {
    Group group;
    try {
      group = await GroupService().joinGroupByCode(code);
    } catch (e) {
      _log('group join failed for code $code: $e');
      await _showJoinError(
        AppNavigation.groupsTabIndex,
        appNavigation.groupsNavigatorKey,
        title: "Couldn't join group",
      );
      return;
    }

    final navigator = await _awaitNavigator(
      AppNavigation.groupsTabIndex,
      appNavigation.groupsNavigatorKey,
    );
    navigator?.push(
      MaterialPageRoute(builder: (_) => GroupDetailPage(group: group)),
    );
  }

  Future<void> _completeChallengeJoin(String code) async {
    Challenge challenge;
    try {
      challenge = await ChallengeService().joinChallengeByCode(code);
    } catch (e) {
      _log('challenge join failed for code $code: $e');
      await _showJoinError(
        AppNavigation.challengesTabIndex,
        appNavigation.challengesNavigatorKey,
        title: "Couldn't join challenge",
      );
      return;
    }

    final navigator = await _awaitNavigator(
      AppNavigation.challengesTabIndex,
      appNavigation.challengesNavigatorKey,
    );
    navigator?.push(
      MaterialPageRoute(
        builder: (_) => ChallengeDetailPage(challenge: challenge),
      ),
    );
  }

  Future<void> _showJoinError(
    int tabIndex,
    GlobalKey<NavigatorState> navigatorKey, {
    required String title,
  }) async {
    final navigator = await _awaitNavigator(tabIndex, navigatorKey);
    if (navigator == null || !navigator.mounted) return;
    await showErrorDialog(
      navigator.context,
      title: title,
      message: "That invite link is invalid or has expired.",
    );
  }

  /// Switches to the given tab and waits for its Navigator to actually be
  /// attached - needed on cold start, where the link can arrive before
  /// `MainShell` has built at all.
  Future<NavigatorState?> _awaitNavigator(
    int tabIndex,
    GlobalKey<NavigatorState> navigatorKey,
  ) async {
    appNavigation.selectedTab.value = tabIndex;
    for (var attempt = 0; attempt < 20; attempt++) {
      final state = navigatorKey.currentState;
      if (state != null) return state;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _log('Tab $tabIndex navigator never became available');
    return null;
  }
}

final deepLinkService = DeepLinkService();

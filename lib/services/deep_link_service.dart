import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/group.dart';
import '../pages/group_detail_page.dart';
import '../widgets/error_dialog.dart';
import 'app_navigation.dart';
import 'group_service.dart';

void _log(String message) {
  if (kDebugMode) debugPrint('[DeepLinkService] $message');
}

/// Handles `countmein://join/group/{code}` links: auto-joins the group and
/// opens its detail page inside the Groups tab.
///
/// Uses a custom URL scheme for now rather than Universal/App Links, since
/// those need a domain plus — on iOS — the Apple Developer Program, neither
/// of which exist yet. The path structure (`/join/group/{code}`) and all
/// the routing logic below only ever reads [Uri.pathSegments], never the
/// scheme or host, specifically so it doesn't need to change later: moving
/// to real `https://` links is purely a matter of hosting the association
/// files and registering Associated Domains / App Links.
class DeepLinkService {
  String? _pendingGroupCode;

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

  /// Call whenever auth state resolves to a signed-in user — completes a
  /// join that arrived (or was tapped) before the user was signed in. Safe
  /// to call anytime; a no-op unless a join is actually pending.
  void retryPendingJoin() {
    final code = _pendingGroupCode;
    if (code != null && FirebaseAuth.instance.currentUser != null) {
      _pendingGroupCode = null;
      _completeJoin(code);
    }
  }

  void _handleUri(Uri uri) {
    _log('received: $uri');
    final segments = uri.pathSegments;
    if (segments.length == 3 &&
        segments[0] == 'join' &&
        segments[1] == 'group') {
      _joinGroup(segments[2]);
    }
  }

  void _joinGroup(String code) {
    if (FirebaseAuth.instance.currentUser == null) {
      _log('not signed in yet — deferring join for code $code');
      _pendingGroupCode = code;
      return;
    }
    _completeJoin(code);
  }

  Future<void> _completeJoin(String code) async {
    Group group;
    try {
      group = await GroupService().joinGroupByCode(code);
    } catch (e) {
      _log('join failed for code $code: $e');
      await _showJoinError();
      return;
    }

    final navigator = await _awaitGroupsNavigator();
    navigator?.push(
      MaterialPageRoute(builder: (_) => GroupDetailPage(group: group)),
    );
  }

  Future<void> _showJoinError() async {
    final navigator = await _awaitGroupsNavigator();
    if (navigator == null || !navigator.mounted) return;
    await showErrorDialog(
      navigator.context,
      title: "Couldn't join group",
      message: "That invite link is invalid or has expired.",
    );
  }

  /// Switches to the Groups tab and waits for its Navigator to actually be
  /// attached — needed on cold start, where the link can arrive before
  /// `MainShell` has built at all.
  Future<NavigatorState?> _awaitGroupsNavigator() async {
    appNavigation.selectedTab.value = AppNavigation.groupsTabIndex;
    for (var attempt = 0; attempt < 20; attempt++) {
      final state = appNavigation.groupsNavigatorKey.currentState;
      if (state != null) return state;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _log('Groups tab navigator never became available');
    return null;
  }
}

final deepLinkService = DeepLinkService();

import 'package:flutter/material.dart';

/// Lets code outside the widget tree - currently just [DeepLinkService] -
/// switch `MainShell`'s visible tab and push onto a specific tab's own
/// Navigator, e.g. landing on a group's detail page inside the Groups
/// tab's stack after auto-joining via an invite link.
class AppNavigation {
  /// One key per MainShell tab, in the same order as its destinations:
  /// Challenges, Groups, Counters, Settings.
  final List<GlobalKey<NavigatorState>> tabNavigatorKeys = List.generate(
    4,
    (_) => GlobalKey<NavigatorState>(),
  );

  static const challengesTabIndex = 0;
  static const groupsTabIndex = 1;

  /// Which tab MainShell should show. MainShell listens to this and also
  /// updates it when the user taps a tab directly, so it stays in sync
  /// either way.
  final ValueNotifier<int> selectedTab = ValueNotifier<int>(2);

  GlobalKey<NavigatorState> get challengesNavigatorKey =>
      tabNavigatorKeys[challengesTabIndex];

  GlobalKey<NavigatorState> get groupsNavigatorKey =>
      tabNavigatorKeys[groupsTabIndex];
}

final appNavigation = AppNavigation();

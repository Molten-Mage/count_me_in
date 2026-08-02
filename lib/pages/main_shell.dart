import 'package:flutter/material.dart';

import '../services/counter_storage.dart';
import '../services/firestore_counter_storage.dart';
import '../services/local_counter_storage.dart';
import '../widgets/ad_banner.dart';
import '../widgets/tally_icon.dart';
import 'groups_list_page.dart';
import 'home_page.dart';
import 'settings_page.dart';

class MainShell extends StatefulWidget {
  final bool isGuest;
  final VoidCallback? onSignIn;

  const MainShell({super.key, this.isGuest = false, this.onSignIn});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 1;

  late final CounterStorage _storage = widget.isGuest
      ? LocalCounterStorage()
      : FirestoreCounterStorage();

  @override
  Widget build(BuildContext context) {
    final pages = [
      widget.isGuest
          ? _GuestGroupsPlaceholder(onSignIn: widget.onSignIn)
          : GroupsListPage(active: _selectedIndex == 0),
      HomePage(storage: _storage, active: _selectedIndex == 1),
      SettingsPage(isGuest: widget.isGuest, onSignIn: widget.onSignIn),
    ];
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const AdBanner(),
            Expanded(
              child: IndexedStack(index: _selectedIndex, children: pages),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.groups), label: 'Groups'),
          NavigationDestination(icon: TallyIcon(), label: 'Counters'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

class _GuestGroupsPlaceholder extends StatelessWidget {
  final VoidCallback? onSignIn;

  const _GuestGroupsPlaceholder({required this.onSignIn});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Groups')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.groups_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'Sign in to use groups',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Group tasks are shared with other people and need an '
                'account to sync.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: onSignIn,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                ),
                child: const Text('Log in or create an account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

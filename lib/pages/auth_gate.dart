import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/deep_link_service.dart';
import 'login_page.dart';
import 'main_shell.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isGuest = false;

  @override
  Widget build(BuildContext context) {
    if (_isGuest) {
      return MainShell(
        isGuest: true,
        onSignIn: () => setState(() => _isGuest = false),
      );
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => deepLinkService.retryPendingJoin(),
          );
          return const MainShell();
        }
        return LoginPage(
          onContinueAsGuest: () => setState(() => _isGuest = true),
        );
      },
    );
  }
}

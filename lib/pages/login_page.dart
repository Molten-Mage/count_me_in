import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../services/analytics_service.dart';
import '../widgets/tally_icon.dart';
import 'privacy_policy_page.dart';

/// Whether to offer "Sign in with Apple" — only relevant on Apple platforms
/// (and the entitlement is only configured for iOS/macOS builds).
bool get _supportsAppleSignIn =>
    !kIsWeb && (Platform.isIOS || Platform.isMacOS);

/// A cryptographically random string used as the Apple sign-in nonce, per
/// Firebase's recommended flow to prevent replay attacks.
String _generateNonce([int length = 32]) {
  const charset =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
  final random = Random.secure();
  return List.generate(
    length,
    (_) => charset[random.nextInt(charset.length)],
  ).join();
}

class LoginPage extends StatefulWidget {
  final VoidCallback onContinueAsGuest;

  const LoginPage({super.key, required this.onContinueAsGuest});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _usernameController = TextEditingController();
  bool _showEmailForm = false;
  bool _isRegistering = false;
  bool _isSubmitting = false;
  String? _errorMessage;
  String? _infoMessage;
  late final _privacyPolicyRecognizer = TapGestureRecognizer()
    ..onTap = _openPrivacyPolicy;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _usernameController.dispose();
    _privacyPolicyRecognizer.dispose();
    super.dispose();
  }

  void _openPrivacyPolicy() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const PrivacyPolicyPage()),
    );
  }

  void _backToMethodPicker() {
    setState(() {
      _showEmailForm = false;
      _errorMessage = null;
      _infoMessage = null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      if (_isRegistering) {
        final credential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
              email: _emailController.text.trim(),
              password: _passwordController.text,
            );
        final username = _usernameController.text.trim();
        if (username.isNotEmpty) {
          await credential.user?.updateDisplayName(username);
          await credential.user?.reload();
        }
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
      await analyticsService.logLogin('password');
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message ?? 'Something went wrong.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _infoMessage = null;
        _errorMessage = 'Enter your email above, then tap "Forgot password?"';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      setState(() => _infoMessage = 'Password reset email sent to $email.');
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message ?? 'Something went wrong.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      await FirebaseAuth.instance.signInWithCredential(credential);
      await analyticsService.logLogin('google.com');
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) {
        setState(() => _errorMessage = 'Google sign-in failed. Try again.');
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message ?? 'Something went wrong.');
    } catch (_) {
      setState(
        () => _errorMessage = 'Google sign-in isn\'t available on this device.',
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _signInWithApple() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      final rawNonce = _generateNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
      );
      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        oauthCredential,
      );

      // Apple only returns the user's name on the very first sign-in; save
      // it as the display name since Firebase won't have captured it.
      final givenName = appleCredential.givenName;
      final familyName = appleCredential.familyName;
      if (userCredential.user?.displayName == null &&
          (givenName != null || familyName != null)) {
        final name = [
          givenName,
          familyName,
        ].where((part) => part != null && part.isNotEmpty).join(' ');
        if (name.isNotEmpty) {
          await userCredential.user?.updateDisplayName(name);
        }
      }
      await analyticsService.logLogin('apple.com');
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code != AuthorizationErrorCode.canceled) {
        setState(() => _errorMessage = 'Apple sign-in failed. Try again.');
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message ?? 'Something went wrong.');
    } catch (_) {
      setState(
        () => _errorMessage = 'Apple sign-in isn\'t available on this device.',
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_showEmailForm,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backToMethodPicker();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _showEmailForm
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _backToMethodPicker,
                )
              : null,
          title: _showEmailForm
              ? Text(_isRegistering ? 'Create account' : 'Log in')
              : null,
        ),
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.opaque,
          child: _showEmailForm
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: _buildEmailForm(),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: _buildMethodPicker(),
                ),
        ),
      ),
    );
  }

  Widget _buildMethodPicker() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Column(
            children: [
              Text(
                'Count Me In',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              TallyIcon(
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 48),
              Text(
                'Log in',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        OutlinedButton.icon(
          onPressed: _isSubmitting
              ? null
              : () => setState(() => _showEmailForm = true),
          icon: const Icon(Icons.email_outlined),
          label: const Text('Continue with Email'),
        ),
        if (_supportsAppleSignIn) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _isSubmitting ? null : _signInWithApple,
            icon: const Icon(Icons.apple),
            label: const Text('Continue with Apple'),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _isSubmitting ? null : _signInWithGoogle,
          icon: const Icon(Icons.g_mobiledata),
          label: const Text('Continue with Google'),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            _errorMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 24),
        const Row(
          children: [
            Expanded(child: Divider()),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('or'),
            ),
            Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: _isSubmitting ? null : widget.onContinueAsGuest,
          child: const Text('Continue without an account'),
        ),
        const SizedBox(height: 8),
        Text(
          "Your counters will be stored only on this device — they "
          "won't sync, back up, or support group goals.",
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            children: [
              const TextSpan(text: 'By continuing, you agree to our '),
              TextSpan(
                text: 'Privacy Policy',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
                recognizer: _privacyPolicyRecognizer,
              ),
              const TextSpan(text: '.'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmailForm() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _emailController,
            decoration: const InputDecoration(labelText: 'Email'),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            validator: (value) {
              if (value == null || !value.contains('@')) {
                return 'Enter a valid email';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordController,
            decoration: const InputDecoration(labelText: 'Password'),
            obscureText: true,
            validator: (value) {
              if (value == null || value.length < 6) {
                return 'Password must be at least 6 characters';
              }
              return null;
            },
          ),
          if (_isRegistering) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmPasswordController,
              decoration: const InputDecoration(
                labelText: 'Confirm password',
              ),
              obscureText: true,
              validator: (value) {
                if (value != _passwordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username (optional)',
                helperText:
                    "Shown to others instead of the name associated with you email account",
              ),
            ),
          ],
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_infoMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _infoMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isRegistering ? 'Create account' : 'Log in'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _isSubmitting
                ? null
                : () => setState(() {
                    _isRegistering = !_isRegistering;
                    _errorMessage = null;
                    _infoMessage = null;
                  }),
            child: Text(
              _isRegistering
                  ? 'Already have an account? Log in'
                  : 'Need an account? Create one',
            ),
          ),
          if (!_isRegistering)
            TextButton(
              onPressed: _isSubmitting ? null : _sendPasswordReset,
              child: const Text('Forgot password?'),
            ),
        ],
      ),
    );
  }
}

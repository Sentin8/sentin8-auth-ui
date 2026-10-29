// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:AuthUI
// SPDX-License-Identifier: Apache-2.0

// Sentin8 Auth UI - Sign Up page.
//
// Full registration form with:
//   - First name, last name, email, password, confirm password
//   - Password strength indicator
//   - Terms acceptance checkbox
//   - API call to POST /v1/sign-up
//   - Error states (duplicate email, weak password, network error)
//   - Success → redirect
import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';
import '../theme.dart';
import '../branding_provider.dart';
import '../api.dart';
import '../test_bridge.dart';

class SignUpPage extends StatefulWidget {
  final String? redirectUri;
  final String? clientId;
  final String? state;
  final String? codeChallenge;
  final String? scope;
  final bool consentRequired;

  const SignUpPage({super.key, this.redirectUri, this.clientId, this.state, this.codeChallenge, this.scope, this.consentRequired = true});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _acceptTerms = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Register a test bridge handler so e2e tests can trigger sign-up
    // by calling window.sentin8TestSignUp() from JavaScript. This fills
    // the form controllers and calls _signUp() - the same code path
    // as clicking the submit button.
    setSignUpHandler((email, firstName, lastName, password) {
      _emailCtrl.text = email;
      _firstNameCtrl.text = firstName;
      _lastNameCtrl.text = lastName;
      _passwordCtrl.text = password;
      _confirmCtrl.text = password;
      _acceptTerms = true;
      _signUp();
    });
  }

  @override
  void dispose() {
    setSignUpHandler(null);
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    // Validation
    if (_emailCtrl.text.isEmpty || _passwordCtrl.text.isEmpty) {
      setState(() => _error = 'Email and password are required');
      return;
    }
    if (_passwordCtrl.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }
    if (_passwordCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    if (!_acceptTerms) {
      setState(() => _error = 'Please accept the terms to continue');
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      final api = AuthApi(baseUrl: web.window.location.origin);
      final res = await api.signUp(
        _emailCtrl.text,
        _passwordCtrl.text,
        firstName: _firstNameCtrl.text.isNotEmpty ? _firstNameCtrl.text : null,
        lastName: _lastNameCtrl.text.isNotEmpty ? _lastNameCtrl.text : null,
      );

      // After successful sign-up, do NOT auto-complete the OAuth flow.
      // The user should sign in manually with their new credentials.
      // Redirect to the sign-in page, preserving the OAuth context
      // (client_id, redirect_uri, state, code_challenge) so that after
      // sign-in the flow continues to the BFF callback.
      _redirectAfterAuth();
    } on AuthApiException catch (e) {
      setState(() => _error = _friendlyError(e));
    } catch (e) {
      setState(() => _error = 'Network error. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Mirror of SignInPage._redirectAfterAuth: after a successful sign-up
  /// (which sets the __session cookie via /v1/sign-up), redirect to
  /// the sign-in page, preserving the OAuth context (client_id,
  /// redirect_uri, state, code_challenge) so that after sign-in the
  /// flow continues to the BFF callback. We do NOT call /oauth/authorize
  /// directly because Auth requires PAR (Pushed Authorization Request)
  /// and inline authorize parameters would be rejected.
  void _redirectAfterAuth() {
    if (widget.clientId != null && widget.clientId!.isNotEmpty) {
      // Redirect to /sign-in with the OAuth context so the user can
      // sign in with their new credentials and the OAuth flow continues.
      final scope = widget.scope ?? 'openid profile email';
      final signInUrl =
          '/sign-in'
          '?response_type=code'
          '&client_id=${widget.clientId}'
          '${widget.redirectUri != null ? '&redirect_uri=${Uri.encodeComponent(widget.redirectUri!)}' : ''}'
          '${widget.state != null ? '&state=${widget.state}' : ''}'
          '&scope=${Uri.encodeQueryComponent(scope)}'
          '${widget.codeChallenge != null ? '&code_challenge=${widget.codeChallenge}' : ''}'
          '&code_challenge_method=S256'
          '&consent_required=${widget.consentRequired}';
      web.window.location.href = signInUrl;
    } else if (widget.redirectUri != null && widget.redirectUri!.isNotEmpty) {
      web.window.location.href = widget.redirectUri!;
    } else {
      web.window.location.href = '/sign-in';
    }
  }

  String _friendlyError(AuthApiException e) {
    if (e.statusCode == 409) return 'An account with this email already exists';
    if (e.statusCode == 422) return 'Invalid email or password format';
    return e.message;
  }

  String _passwordStrength() {
    final pw = _passwordCtrl.text;
    if (pw.isEmpty) return '';
    int score = 0;
    if (pw.length >= 8) score++;
    if (pw.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(pw)) score++;
    if (RegExp(r'[0-9]').hasMatch(pw)) score++;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(pw)) score++;
    if (score <= 1) return 'Weak';
    if (score <= 3) return 'Fair';
    if (score <= 4) return 'Good';
    return 'Strong';
  }

  Color _strengthColor(String strength) => switch (strength) {
    'Weak' => Sentin8Colors.errorCrimson,
    'Fair' => Sentin8Colors.warningAmber,
    'Good' => Sentin8Colors.successGold,
    'Strong' => Sentin8Colors.successGold,
    _ => Sentin8Colors.textMuted,
  };

  @override
  Widget build(BuildContext context) {
    final strength = _passwordStrength();
    final branding = BrandingProvider.of(context);
    final heading = branding.hasOrganizationName
        ? 'Create account for ${branding.organizationName}'
        : 'Create Account';
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GlassPanel(
            maxWidth: 440,
            padding: const EdgeInsets.all(Sentin8Spacing.xl),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Sentin8Logo(size: 36, logoUrl: branding.logoUrl, logoIconUrl: branding.logoIconUrl),
                  const SizedBox(height: Sentin8Spacing.lg),
                  Text(heading, style: h2For(context), textAlign: TextAlign.center),
                  const SizedBox(height: Sentin8Spacing.xl),
                  if (_error != null) ...[
                    ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
                    const SizedBox(height: Sentin8Spacing.md),
                  ],
                  // First name + Last name
                  Row(
                    children: [
                      Expanded(child: TextField(controller: _firstNameCtrl, decoration: const InputDecoration(labelText: 'First name (optional)'), style: TextStyle(color: textPrimaryFor(context)))),
                      const SizedBox(width: Sentin8Spacing.sm),
                      Expanded(child: TextField(controller: _lastNameCtrl, decoration: const InputDecoration(labelText: 'Last name (optional)'), style: TextStyle(color: textPrimaryFor(context)))),
                    ],
                  ),
                  const SizedBox(height: Sentin8Spacing.md),
                  // Email
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined, color: iconMutedFor(context))),
                    style: TextStyle(color: textPrimaryFor(context)),
                  ),
                  const SizedBox(height: Sentin8Spacing.md),
                  // Password
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: _obscurePassword,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline, color: iconMutedFor(context)),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: iconMutedFor(context)),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    style: TextStyle(color: textPrimaryFor(context)),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (strength.isNotEmpty) ...[
                    const SizedBox(height: Sentin8Spacing.xs),
                    Row(
                      children: [
                        Text('Password strength: ', style: Theme.of(context).brightness == Brightness.light ? Sentin8Text.captionLight : Sentin8Text.caption),
                        Text(strength, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _strengthColor(strength))),
                      ],
                    ),
                  ],
                  const SizedBox(height: Sentin8Spacing.md),
                  // Confirm password
                  TextField(
                    controller: _confirmCtrl,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(labelText: 'Confirm password', prefixIcon: Icon(Icons.lock_outline, color: iconMutedFor(context))),
                    style: TextStyle(color: textPrimaryFor(context)),
                  ),
                  const SizedBox(height: Sentin8Spacing.md),
                  // Terms checkbox
                  Row(
                    children: [
                      Checkbox(value: _acceptTerms, onChanged: (v) => setState(() => _acceptTerms = v ?? false)),
                      Expanded(child: Text('I accept the Terms of Service and Privacy Policy', style: Theme.of(context).brightness == Brightness.light ? Sentin8Text.captionLight : Sentin8Text.caption)),
                    ],
                  ),
                  const SizedBox(height: Sentin8Spacing.lg),
                  // Sign up button
                  FilledButton(
                    onPressed: _isLoading ? null : _signUp,
                    child: _isLoading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Sentin8Colors.obsidianBlack))
                        : const Text('Create account'),
                  ),
                  const SizedBox(height: Sentin8Spacing.lg),
                  // Sign in link - preserve OAuth context so the flow continues
                  // after the user signs in with their existing credentials.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Already have an account? ', style: Theme.of(context).brightness == Brightness.light ? Sentin8Text.bodySecondaryLight : Sentin8Text.bodySecondary),
                      TextButton(
                        onPressed: () {
                          // Navigate to /sign-in preserving ALL OAuth params.
                          final scope = widget.scope ?? 'openid profile email';
                          final signInUrl =
                              '/sign-in'
                              '?response_type=code'
                              '&client_id=${widget.clientId ?? ''}'
                              '${widget.redirectUri != null ? '&redirect_uri=${Uri.encodeComponent(widget.redirectUri!)}' : ''}'
                              '${widget.state != null ? '&state=${widget.state}' : ''}'
                              '&scope=${Uri.encodeQueryComponent(scope)}'
                              '${widget.codeChallenge != null ? '&code_challenge=${widget.codeChallenge}' : ''}'
                              '&code_challenge_method=S256';
                          web.window.location.href = signInUrl;
                        },
                        child: const Text('Sign in'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Sentin8Spacing.xs),
          // Powered by Sentin8 - outside the form panel
          const PoweredBySentin8(),
        ],
      ),
    );
  }
}
// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:AuthUI
// SPDX-License-Identifier: Apache-2.0

// Sentin8 Auth UI — Device approval page (RFC 8628 §3.3).
//
// Story DEVUI-1.1 — hosted device-verification page for `sentin8-cli signin`.
//
// The CLI's device flow directs the operator to
// `/device?user_code=XXXX-XXXX` (`verification_uri_complete`). This page:
//   1. Checks for an existing session (GET /v1/session) — a signed-in user
//      approves immediately with one click.
//   2. Otherwise renders the email/password form; on success the session
//      token from the sign-in response authorizes the verify call
//      (`Authorization: Bearer`, CSRF-exempt per SEC-2.4.4).
//   3. Calls POST /device/verify with only the `user_code` — the approving
//      user/env are stamped server-side from the session (SEC-2.1.4).
//   4. Shows the terminal state; the CLI polls `/oauth/token` independently
//      and completes on its own — nothing is navigated away.
//
// Design: design/sentin8-sentin8-auth-technical-design.md §13.5 §5.1a.
import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';
import '../theme.dart';
import '../branding_provider.dart';
import '../api.dart';

class DevicePage extends StatefulWidget {
  /// The user_code from `?user_code=` — empty means the URL was malformed.
  final String userCode;

  const DevicePage({super.key, required this.userCode});

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isLoading = true;
  bool _isApproving = false;
  bool _obscurePassword = true;
  String? _error;
  String? _status; // null = pending, 'approved', 'denied', 'expired'
  bool _hasSession = false;
  String? _sessionEmail;
  String? _sessionToken; // Bearer for the verify call when freshly signed in.
  AuthApi? _api;

  @override
  void initState() {
    super.initState();
    _api = AuthApi(baseUrl: web.window.location.origin);
    // Defer past the first frame — calling the HTTP client synchronously
    // from initState on Flutter web leaves the future unresolvable (the
    // request completes at the network layer but the Dart future never
    // resumes), wedging the page on its loading state forever.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 50), _checkSession);
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  /// Check for an existing session — a signed-in operator approves directly.
  Future<void> _checkSession() async {
    if (widget.userCode.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'This device-approval link is malformed — no code was provided.';
      });
      return;
    }
    try {
      final session = await _api!.getSession();
      if (session != null) {
        setState(() {
          _hasSession = true;
          _sessionEmail = session.email;
        });
      }
    } catch (_) {
      // No session — the operator signs in below.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Approve with the existing session (cookie authenticates the request).
  Future<void> _approveWithSession() async {
    await _approve(null);
  }

  /// Sign in, then approve with the fresh session token (Bearer).
  Future<void> _signInAndApprove() async {
    if (_emailCtrl.text.isEmpty || _passwordCtrl.text.isEmpty) {
      setState(() => _error = 'Email and password are required');
      return;
    }
    setState(() { _isApproving = true; _error = null; });
    try {
      final res = await _api!.signIn(_emailCtrl.text, _passwordCtrl.text);
      await _approve(res.token);
    } on AuthApiException catch (e) {
      setState(() => _error = _friendlyError(e));
    } catch (e) {
      setState(() => _error = 'Network error. Please try again.');
    } finally {
      if (mounted) setState(() => _isApproving = false);
    }
  }

  /// Shared approval path — `sessionToken` is the freshly-minted session
  /// token after sign-in (Bearer path) or null (cookie path).
  Future<void> _approve(String? sessionToken) async {
    setState(() { _isApproving = true; _error = null; });
    try {
      await _api!.verifyDevice(widget.userCode, sessionToken: sessionToken);
      setState(() => _status = 'approved');
    } on AuthApiException catch (e) {
      if (e.statusCode == 404) {
        setState(() {
          _status = 'expired';
          _error = 'This code has expired or was already used. Run the command again.';
        });
      } else {
        setState(() => _error = e.message);
      }
    } catch (e) {
      setState(() => _error = 'Network error. Please try again.');
    } finally {
      if (mounted) setState(() => _isApproving = false);
    }
  }

  String _friendlyError(AuthApiException e) {
    if (e.statusCode == 401) return 'Invalid email or password';
    if (e.statusCode == 403) return 'Account is locked or disabled';
    return e.message;
  }

  @override
  Widget build(BuildContext context) {
    final branding = BrandingProvider.of(context);
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GlassPanel(
            maxWidth: 440,
            padding: const EdgeInsets.all(Sentin8Spacing.xl),
            child: _buildContent(branding),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(Branding branding) {
    if (_isLoading) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: Sentin8Spacing.md),
          Text('Checking session…'),
        ],
      );
    }

    // Approved — the CLI picks it up on its next poll.
    if (_status == 'approved') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.check_circle_outline, size: 48, color: Sentin8Colors.successGold),
          const SizedBox(height: Sentin8Spacing.md),
          Text('Device approved', textAlign: TextAlign.center, style: Sentin8Text.h2),
          const SizedBox(height: Sentin8Spacing.sm),
          Text(
            'The CLI is now signed in. You can close this tab.',
            textAlign: TextAlign.center,
            style: Sentin8Text.body,
          ),
        ],
      );
    }

    // Malformed URL / expired code — terminal error, nothing to do.
    if (_status == 'expired' || (widget.userCode.isEmpty && _error != null)) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Sentin8Colors.errorCrimson),
          const SizedBox(height: Sentin8Spacing.md),
          Text('Code not accepted', textAlign: TextAlign.center, style: Sentin8Text.h2),
          const SizedBox(height: Sentin8Spacing.sm),
          Text(
            _error ?? 'This code has expired or was already used. Run the command again.',
            textAlign: TextAlign.center,
            style: Sentin8Text.body,
          ),
        ],
      );
    }

    // Pending — code display + approve (session) or sign-in-then-approve.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Sentin8Logo(size: 36, logoUrl: branding.logoUrl, logoIconUrl: branding.logoIconUrl),
        const SizedBox(height: Sentin8Spacing.lg),
        Text('Device Sign-In Request', textAlign: TextAlign.center, style: Sentin8Text.h2),
        const SizedBox(height: Sentin8Spacing.md),
        Text(
          'A command-line client is requesting access to your Sentin8 account.',
          textAlign: TextAlign.center,
          style: Sentin8Text.body,
        ),
        const SizedBox(height: Sentin8Spacing.md),
        // The code being approved — cross-check against the CLI output.
        Container(
          padding: const EdgeInsets.all(Sentin8Spacing.md),
          decoration: BoxDecoration(
            color: Sentin8Colors.glassFill,
            borderRadius: BorderRadius.circular(Sentin8Spacing.sm),
          ),
          child: Text(
            widget.userCode,
            textAlign: TextAlign.center,
            style: Sentin8Text.h2.copyWith(letterSpacing: 2),
          ),
        ),
        const SizedBox(height: Sentin8Spacing.sm),
        Text(
          'Verify this code matches the one shown in your terminal.',
          textAlign: TextAlign.center,
          style: Sentin8Text.caption,
        ),
        const SizedBox(height: Sentin8Spacing.lg),
        if (_error != null) ...[
          Text(
            _error!,
            style: Sentin8Text.body.copyWith(color: Sentin8Colors.errorCrimson),
          ),
          const SizedBox(height: Sentin8Spacing.md),
        ],
        if (_hasSession) ...[
          if (_sessionEmail != null)
            Text(
              'Signed in as $_sessionEmail',
              textAlign: TextAlign.center,
              style: Sentin8Text.caption,
            ),
          const SizedBox(height: Sentin8Spacing.md),
          FilledButton(
            onPressed: _isApproving ? null : _approveWithSession,
            child: _isApproving
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Approve'),
          ),
        ] else ...[
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
          ),
          const SizedBox(height: Sentin8Spacing.sm),
          TextField(
            controller: _passwordCtrl,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            onSubmitted: (_) => _signInAndApprove(),
          ),
          const SizedBox(height: Sentin8Spacing.lg),
          FilledButton(
            onPressed: _isApproving ? null : _signInAndApprove,
            child: _isApproving
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Sign In & Approve'),
          ),
        ],
      ],
    );
  }
}
// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:AuthUI
// SPDX-License-Identifier: Apache-2.0

// Sentin8 Auth UI — Assisted Login page.
//
// Story 1.1.70 — CIBA Assisted Login front-channel page.
//
// The customer opens the link forwarded by the staff member (SMS / email /
// QR). This page:
//   1. Fetches the CIBA request metadata (binding_message, short_code,
//      scope, client_id) from GET /ciba/assisted/{auth_req_id}.
//   2. Checks if the customer has a session cookie (GET /v1/session).
//      - If yes: shows a "Confirm" button → POST /v1/ciba/assisted/{id}/complete.
//      - If no: shows the sign-in form → on success → POST complete.
//   3. On success: shows "You are authenticated — eTeller can proceed".
//   4. On expired/denied: shows an error.
//
// Design: design/sentin8-auth-technical-design.md §5.2d
import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';
import '../theme.dart';
import '../branding_provider.dart';
import '../api.dart';

class AssistedLoginPage extends StatefulWidget {
  final String authReqId;

  const AssistedLoginPage({super.key, required this.authReqId});

  @override
  State<AssistedLoginPage> createState() => _AssistedLoginPageState();
}

class _AssistedLoginPageState extends State<AssistedLoginPage> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isLoading = true;
  bool _isCompleting = false;
  bool _obscurePassword = true;
  String? _error;
  String? _bindingMessage;
  String? _shortCode;
  String? _scope;
  String? _status;
  bool _hasSession = false;
  String? _customerEmail;
  AuthApi? _api;

  @override
  void initState() {
    super.initState();
    _api = AuthApi(baseUrl: web.window.location.origin);
    _loadCibaRequest();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  /// Fetch the CIBA request metadata and check for an existing session.
  Future<void> _loadCibaRequest() async {
    try {
      // 1. Fetch CIBA request metadata.
      final meta = await _api!.getRaw('/v1/ciba/assisted/${widget.authReqId}');
      setState(() {
        _bindingMessage = meta['binding_message'] as String?;
        _shortCode = meta['short_code'] as String?;
        _scope = meta['scope'] as String?;
        _status = meta['status'] as String?;
      });

      // If already approved/denied, don't check session.
      if (_status == 'approved' || _status == 'denied') {
        setState(() => _isLoading = false);
        return;
      }

      // 2. Check for existing session.
      try {
        final session = await _api!.getSession();
        if (session != null) {
          setState(() {
            _hasSession = true;
            _customerEmail = session.email;
          });
        }
      } catch (_) {
        // No session — customer needs to sign in.
      }
    } on AuthApiException catch (e) {
      setState(() {
        _error = e.statusCode == 404
            ? 'This link has expired or is invalid. Please ask the teller to send a new link.'
            : 'Unable to load the request: ${e.message}';
      });
    } catch (e) {
      setState(() => _error = 'Network error. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Sign in (email/password) then complete the CIBA request.
  Future<void> _signInAndComplete() async {
    if (_emailCtrl.text.isEmpty || _passwordCtrl.text.isEmpty) {
      setState(() => _error = 'Email and password are required');
      return;
    }
    setState(() { _isCompleting = true; _error = null; });
    try {
      // Sign in.
      await _api!.signIn(_emailCtrl.text, _passwordCtrl.text);
      // Complete the CIBA request.
      await _api!.postRaw('/v1/ciba/assisted/${widget.authReqId}/complete', {});
      setState(() => _status = 'approved');
    } on AuthApiException catch (e) {
      setState(() => _error = _friendlyError(e));
    } catch (e) {
      setState(() => _error = 'Network error. Please try again.');
    } finally {
      if (mounted) setState(() => _isCompleting = false);
    }
  }

  /// Complete the CIBA request using the existing session (no sign-in needed).
  Future<void> _confirmWithSession() async {
    setState(() { _isCompleting = true; _error = null; });
    try {
      await _api!.postRaw('/v1/ciba/assisted/${widget.authReqId}/complete', {});
      setState(() => _status = 'approved');
    } on AuthApiException catch (e) {
      setState(() => _error = 'Failed to confirm: ${e.message}');
    } catch (e) {
      setState(() => _error = 'Network error. Please try again.');
    } finally {
      if (mounted) setState(() => _isCompleting = false);
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
          Text('Loading request…'),
        ],
      );
    }

    if (_error != null && _status == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.error_outline, size: 48, color: Sentin8Colors.errorCrimson),
          const SizedBox(height: Sentin8Spacing.md),
          Text(_error!, textAlign: TextAlign.center, style: Sentin8Text.body),
        ],
      );
    }

    // Success state.
    if (_status == 'approved') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.check_circle_outline, size: 48, color: Sentin8Colors.successGold),
          const SizedBox(height: Sentin8Spacing.md),
          Text(
            'You are authenticated',
            textAlign: TextAlign.center,
            style: Sentin8Text.h2,
          ),
          const SizedBox(height: Sentin8Spacing.sm),
          Text(
            'The teller can now proceed with your request. You can close this tab.',
            textAlign: TextAlign.center,
            style: Sentin8Text.body,
          ),
        ],
      );
    }

    // Denied state.
    if (_status == 'denied') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.cancel_outlined, size: 48, color: Sentin8Colors.errorCrimson),
          const SizedBox(height: Sentin8Spacing.md),
          Text('Request denied', textAlign: TextAlign.center, style: Sentin8Text.h2),
        ],
      );
    }

    // Pending — show the request details + sign-in or confirm.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Sentin8Logo(size: 36, logoUrl: branding.logoUrl, logoIconUrl: branding.logoIconUrl),
        const SizedBox(height: Sentin8Spacing.lg),
        Text('Assisted Login Request', textAlign: TextAlign.center, style: Sentin8Text.h2),
        const SizedBox(height: Sentin8Spacing.md),
        // Binding message.
        if (_bindingMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(Sentin8Spacing.md),
            decoration: BoxDecoration(
              color: Sentin8Colors.glassFill,
              borderRadius: BorderRadius.circular(Sentin8Spacing.sm),
            ),
            child: Text(_bindingMessage!, textAlign: TextAlign.center, style: Sentin8Text.body),
          ),
          const SizedBox(height: Sentin8Spacing.sm),
        ],
        // Short code for cross-verification.
        if (_shortCode != null) ...[
          Text(
            'Reference code: $_shortCode',
            textAlign: TextAlign.center,
            style: Sentin8Text.caption.copyWith(color: Sentin8Colors.textSecondary),
          ),
          const SizedBox(height: Sentin8Spacing.sm),
          Text(
            'Verify this code matches what the teller showed you.',
            textAlign: TextAlign.center,
            style: Sentin8Text.caption,
          ),
          const SizedBox(height: Sentin8Spacing.lg),
        ],
        // Requested scopes.
        if (_scope != null && _scope!.isNotEmpty) ...[
          Text('Requested access:', style: Sentin8Text.label),
          const SizedBox(height: Sentin8Spacing.xs),
          Text(_scope!, style: Sentin8Text.caption),
          const SizedBox(height: Sentin8Spacing.lg),
        ],
        if (_error != null) ...[
          Text(_error!, style: Sentin8Text.body.copyWith(color: Sentin8Colors.errorCrimson)),
          const SizedBox(height: Sentin8Spacing.md),
        ],
        // If the customer has a session, show "Confirm" button.
        if (_hasSession) ...[
          if (_customerEmail != null)
            Text('Signed in as $_customerEmail', textAlign: TextAlign.center, style: Sentin8Text.caption),
          const SizedBox(height: Sentin8Spacing.md),
          FilledButton(
            onPressed: _isCompleting ? null : _confirmWithSession,
            child: _isCompleting
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Confirm'),
          ),
        ] else ...[
          // Sign-in form.
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
            onSubmitted: (_) => _signInAndComplete(),
          ),
          const SizedBox(height: Sentin8Spacing.lg),
          FilledButton(
            onPressed: _isCompleting ? null : _signInAndComplete,
            child: _isCompleting
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Sign In & Authorize'),
          ),
        ],
      ],
    );
  }
}
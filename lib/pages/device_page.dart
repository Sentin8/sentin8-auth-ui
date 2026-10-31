// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:AuthUI
// SPDX-License-Identifier: Apache-2.0

// Sentin8 Auth UI - Device approval page (RFC 8628 §3.3).
//
// The CLI's device flow directs the operator to the verification URI:
// either the bare `/device` (the RFC's canonical typed-code entry - the
// CLI displays the code, the user types it here) or the
// `verification_uri_complete` link (`/device?user_code=XXXX-XXXX`).
//
// The page is a state machine (auth-ui DESIGN §2.4):
//   1. Resolve the code: typed at the page (uppercase-normalized) or
//      carried by the URL.
//   2. Check for an existing session (GET /v1/session) - a signed-in
//      user decides immediately.
//   3. Otherwise render the email/password form. A TOTP-enrolled
//      account answers `needs_mfa` - the TOTP step is embedded in this
//      page (a password alone can never decide a device, MFA-SYNC).
//   4. POST /device/verify with `{user_code, action}` - the approving
//      user/env are stamped server-side from the session (SEC-2.1.4).
//   5. Terminal states: approved, denied, expired/invalid. The CLI
//      polls /oauth/token independently and completes on its own -
//      nothing is navigated away.
//
// Design: auth DESIGN §2 (device lifecycle) §3 (MFA-SYNC); auth-ui
// DESIGN §2.4.
import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../branding_provider.dart';
import '../api.dart';

class DevicePage extends StatefulWidget {
  /// The user_code from `?user_code=` - empty means the user opened the
  /// bare verification URI and must type the code shown by the device.
  final String userCode;

  const DevicePage({super.key, required this.userCode});

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final List<TextEditingController> _totpCtrls =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _totpFocus = List.generate(6, (_) => FocusNode());
  bool _isLoading = true;
  bool _isDeciding = false;
  bool _obscurePassword = true;
  String? _error;
  String? _status; // null = in flow, 'approved', 'denied', 'expired'
  bool _hasSession = false;
  String? _sessionEmail;
  String? _pendingTokenId; // needs_mfa challenge capability.
  AuthApi? _api;

  String get _totp => _totpCtrls.map((c) => c.text).join();

  @override
  void initState() {
    super.initState();
    _api = AuthApi(baseUrl: web.window.location.origin);
    // Defer past the first frame - calling the HTTP client synchronously
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
    _codeCtrl.dispose();
    for (final c in _totpCtrls) {
      c.dispose();
    }
    for (final f in _totpFocus) {
      f.dispose();
    }
    super.dispose();
  }

  /// The code being decided on - either the URL-carried code or the value
  /// typed into the entry field (uppercased; codes are case-insensitive
  /// on entry, canonical on display).
  String _resolvedCode() =>
      widget.userCode.isNotEmpty ? widget.userCode : _codeCtrl.text.trim().toUpperCase();

  /// Check for an existing session - a signed-in operator decides
  /// directly. A pending-MFA session reads as "no session" server-side
  /// (a pending row is not a session, MFA-SYNC) - the sign-in path below
  /// handles the TOTP step. The session probe runs even for the typed-
  /// code entry path so a signed-in user reaches the decision right
  /// after typing the code.
  Future<void> _checkSession() async {
    try {
      final session = await _api!.getSession();
      if (session != null) {
        setState(() {
          _hasSession = true;
          _sessionEmail = session.email;
        });
      }
    } catch (_) {
      // No session - the operator signs in below.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Decide with the existing session (cookie authenticates the request).
  Future<void> _decideWithSession(String action) async {
    await _decide(action, null);
  }

  /// Sign in, then approve with the fresh session token (Bearer). A
  /// TOTP-enrolled account needs the embedded MFA step first - the
  /// decision is sent only after the session is ACTIVE.
  Future<void> _signInAndApprove() async {
    if (_emailCtrl.text.isEmpty || _passwordCtrl.text.isEmpty) {
      setState(() => _error = 'Email and password are required');
      return;
    }
    setState(() { _isDeciding = true; _error = null; });
    try {
      final res = await _api!.signIn(_emailCtrl.text, _passwordCtrl.text);
      if (res.mfaRequired) {
        // The needs_mfa contract (MFA-SYNC): NO active session exists yet.
        // Hold the challenge capability and render the TOTP step;
        // completing it activates the session (the verify response's
        // set-cookie then authenticates the decision request).
        setState(() {
          _pendingTokenId = res.pendingTokenId;
        });
      } else {
        await _decide('approve', res.token);
      }
    } on AuthApiException catch (e) {
      setState(() => _error = _friendlyError(e));
    } catch (e) {
      setState(() => _error = 'Network error. Please try again.');
    } finally {
      if (mounted) setState(() => _isDeciding = false);
    }
  }

  /// Complete the embedded TOTP step: /v1/mfa/verify consumes the
  /// challenge and ACTIVATES the session, then the decision is sent
  /// cookie-authenticated.
  Future<void> _verifyTotpAndDecide(String action) async {
    if (_totp.length != 6) {
      setState(() => _error = 'Please enter all 6 digits');
      return;
    }
    setState(() { _isDeciding = true; _error = null; });
    try {
      await _api!.verifyMfa(_totp, pendingTokenId: _pendingTokenId);
      setState(() { _pendingTokenId = null; });
      await _decide(action, null);
    } on AuthApiException catch (e) {
      setState(() => _error =
          e.statusCode == 401 ? 'Invalid code. Please try again.' : e.message);
      for (final c in _totpCtrls) {
        c.clear();
      }
      _totpFocus[0].requestFocus();
    } catch (e) {
      setState(() => _error = 'Network error. Please try again.');
    } finally {
      if (mounted) setState(() => _isDeciding = false);
    }
  }

  /// Shared decision path - `sessionToken` is the freshly-minted session
  /// token after sign-in (Bearer path) or null (cookie path, including
  /// the post-MFA activation where the verify response set the cookie).
  Future<void> _decide(String action, String? sessionToken) async {
    final code = _resolvedCode();
    if (code.isEmpty) {
      setState(() => _error = 'Enter the code shown on your device.');
      return;
    }
    setState(() { _isDeciding = true; _error = null; });
    try {
      await _api!.verifyDevice(code, sessionToken: sessionToken, action: action);
      setState(() => _status = action == 'deny' ? 'denied' : 'approved');
    } on AuthApiException catch (e) {
      if (e.statusCode == 404 || e.statusCode == 410) {
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
      if (mounted) setState(() => _isDeciding = false);
    }
  }

  String _friendlyError(AuthApiException e) {
    if (e.statusCode == 401) return 'Invalid email or password';
    if (e.statusCode == 403) return 'Account is locked or disabled';
    return e.message;
  }

  void _onTotpChanged(int index, String value) {
    if (value.length == 1 && index < 5) {
      _totpFocus[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _totpFocus[index - 1].requestFocus();
    }
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

    // Approved - the CLI picks it up on its next poll.
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

    // Denied - the CLI is told on its next poll and stops.
    if (_status == 'denied') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.block_outlined, size: 48, color: Sentin8Colors.errorCrimson),
          const SizedBox(height: Sentin8Spacing.md),
          Text('Device denied', textAlign: TextAlign.center, style: Sentin8Text.h2),
          const SizedBox(height: Sentin8Spacing.sm),
          Text(
            'The request was denied. The CLI will stop asking. You can close this tab.',
            textAlign: TextAlign.center,
            style: Sentin8Text.body,
          ),
        ],
      );
    }

    // Expired/invalid code - terminal error, nothing to do.
    if (_status == 'expired') {
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

    // Code entry step - bare verification_uri (RFC 8628's canonical
    // typed-code interaction): the CLI displays the code, the user types
    // it here. A session is still resolved first so a signed-in user
    // proceeds straight to the decision after entry.
    if (_resolvedCode().isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Sentin8Logo(size: 36, logoUrl: branding.logoUrl, logoIconUrl: branding.logoIconUrl),
          const SizedBox(height: Sentin8Spacing.lg),
          Text('Device Sign-In Request', textAlign: TextAlign.center, style: Sentin8Text.h2),
          const SizedBox(height: Sentin8Spacing.md),
          Text(
            'Enter the code displayed on your device.',
            textAlign: TextAlign.center,
            style: Sentin8Text.body,
          ),
          const SizedBox(height: Sentin8Spacing.lg),
          TextField(
            controller: _codeCtrl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
              LengthLimitingTextInputFormatter(9),
            ],
            decoration: const InputDecoration(
              labelText: 'Device code',
              hintText: 'XXXX-XXXX',
              prefixIcon: Icon(Icons.devices_other),
            ),
            onChanged: (v) => setState(() {
              _error = null;
            }),
            onSubmitted: (_) => _decideWithSession('approve'),
          ),
          if (_error != null) ...[
            const SizedBox(height: Sentin8Spacing.md),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: Sentin8Text.body.copyWith(color: Sentin8Colors.errorCrimson),
            ),
          ],
          const SizedBox(height: Sentin8Spacing.lg),
          FilledButton(
            onPressed: _codeCtrl.text.trim().isEmpty
                ? null
                : () => _decideWithSession('approve'),
            child: const Text('Continue'),
          ),
        ],
      );
    }

    // Pending - code display + approve (session) or sign-in-then-approve.
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
        // The code being approved - cross-check against the CLI output.
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
        if (_pendingTokenId != null && _pendingTokenId!.isNotEmpty) ...[
          // Embedded TOTP step (MFA-SYNC): the account requires the
          // second factor before any device decision - a password alone
          // can never approve or deny a device.
          Text(
            'This account requires multi-factor authentication. Enter the 6-digit code from your authenticator app.',
            textAlign: TextAlign.center,
            style: Sentin8Text.bodySecondary,
          ),
          const SizedBox(height: Sentin8Spacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(6, (i) {
              return SizedBox(
                width: 48,
                child: TextField(
                  controller: _totpCtrls[i],
                  focusNode: _totpFocus[i],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(counterText: ''),
                  onChanged: (v) {
                    setState(() => _error = null);
                    _onTotpChanged(i, v);
                    // Auto-decide (approve path) when all 6 digits land.
                    if (_totp.length == 6 && !_isDeciding) {
                      _verifyTotpAndDecide('approve');
                    }
                  },
                ),
              );
            }),
          ),
          const SizedBox(height: Sentin8Spacing.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isDeciding || _totp.length != 6
                      ? null
                      : () => _verifyTotpAndDecide('deny'),
                  child: const Text('Deny'),
                ),
              ),
              const SizedBox(width: Sentin8Spacing.md),
              Expanded(
                child: FilledButton(
                  onPressed: _isDeciding || _totp.length != 6
                      ? null
                      : () => _verifyTotpAndDecide('approve'),
                  child: _isDeciding
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Approve'),
                ),
              ),
            ],
          ),
        ] else if (_hasSession) ...[
          if (_sessionEmail != null)
            Text(
              'Signed in as $_sessionEmail',
              textAlign: TextAlign.center,
              style: Sentin8Text.caption,
            ),
          const SizedBox(height: Sentin8Spacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isDeciding ? null : () => _decideWithSession('deny'),
                  child: _isDeciding
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Deny'),
                ),
              ),
              const SizedBox(width: Sentin8Spacing.md),
              Expanded(
                child: FilledButton(
                  onPressed: _isDeciding ? null : () => _decideWithSession('approve'),
                  child: _isDeciding
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Approve'),
                ),
              ),
            ],
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
            onPressed: _isDeciding ? null : _signInAndApprove,
            child: _isDeciding
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Sign In'),
          ),
        ],
      ],
    );
  }
}
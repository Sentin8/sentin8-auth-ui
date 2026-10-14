// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:AuthUI
// SPDX-License-Identifier: Apache-2.0

// Sentin8 Auth UI — MFA verification page (TOTP input).
//
// Presents a 6-digit code input for TOTP-based MFA verification.
// Calls POST /v1/mfa/verify with the code and session ID.
import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../api.dart';

class MfaPage extends StatefulWidget {
  final String? sessionId;
  final String? redirectUri;

  const MfaPage({super.key, this.sessionId, this.redirectUri});

  @override
  State<MfaPage> createState() => _MfaPageState();
}

class _MfaPageState extends State<MfaPage> {
  final List<TextEditingController> _controllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _code => _controllers.map((c) => c.text).join();

  Future<void> _verify() async {
    if (_code.length != 6) {
      setState(() => _error = 'Please enter all 6 digits');
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      final api = AuthApi(baseUrl: web.window.location.origin);
      await api.verifyMfa(_code, sessionId: widget.sessionId);

      // Success — redirect
      if (widget.redirectUri != null && widget.redirectUri!.isNotEmpty) {
        web.window.location.href = widget.redirectUri!;
      } else {
        web.window.location.href = '/';
      }
    } on AuthApiException catch (e) {
      setState(() => _error = e.statusCode == 401 ? 'Invalid code. Please try again.' : e.message);
      // Clear inputs
      for (final c in _controllers) {
        c.clear();
      }
      _focusNodes[0].requestFocus();
    } catch (e) {
      setState(() => _error = 'Network error. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onChanged(int index, String value) {
    if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    // Auto-submit when all 6 digits are entered
    if (_code.length == 6 && !_isLoading) {
      _verify();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassPanel(
        maxWidth: 440,
        padding: const EdgeInsets.all(Sentin8Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.shield_outlined, color: Sentin8Colors.royalGold, size: 48),
            const SizedBox(height: Sentin8Spacing.lg),
            Text('Two-Factor Authentication', style: Sentin8Text.h2, textAlign: TextAlign.center),
            const SizedBox(height: Sentin8Spacing.sm),
            Text('Enter the 6-digit code from your authenticator app.', style: Sentin8Text.bodySecondary, textAlign: TextAlign.center),
            const SizedBox(height: Sentin8Spacing.xl),
            if (_error != null) ...[
              ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
              const SizedBox(height: Sentin8Spacing.md),
            ],
            // 6-digit code input
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(6, (i) {
                return SizedBox(
                  width: 48,
                  child: RawKeyboardListener(
                    focusNode: _focusNodes[i],
                    child: TextField(
                      controller: _controllers[i],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 1,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: textPrimaryFor(context)),
                      decoration: const InputDecoration(counterText: '', contentPadding: EdgeInsets.symmetric(vertical: 16)),
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (v) => _onChanged(i, v),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: Sentin8Spacing.xl),
            FilledButton(
              onPressed: _isLoading ? null : _verify,
              child: _isLoading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Sentin8Colors.obsidianBlack))
                  : const Text('Verify'),
            ),
            const SizedBox(height: Sentin8Spacing.lg),
            TextButton(onPressed: () => web.window.location.href = '/sign-in', child: const Text('Back to sign in')),
          ],
        ),
      ),
    );
  }
}
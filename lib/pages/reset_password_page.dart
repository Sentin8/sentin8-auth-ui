// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:AuthUI
// SPDX-License-Identifier: Apache-2.0

// Sentin8 Auth UI — Password reset confirmation page.
//
// User enters a new password using a reset token from the email link.
// Calls POST /v1/password/reset-confirm.
import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';
import '../theme.dart';
import '../api.dart';

class ResetPasswordPage extends StatefulWidget {
  final String? token;

  const ResetPasswordPage({super.key, this.token});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (widget.token == null || widget.token!.isEmpty) {
      setState(() => _error = 'Invalid reset link. Please request a new one.');
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

    setState(() { _isLoading = true; _error = null; });

    try {
      final api = AuthApi(baseUrl: web.window.location.origin);
      await api.confirmPasswordReset(widget.token!, _passwordCtrl.text);
      setState(() => _done = true);
    } on AuthApiException catch (e) {
      setState(() => _error = e.statusCode == 401 ? 'Reset link expired or invalid. Please request a new one.' : e.message);
    } catch (e) {
      setState(() => _error = 'Network error. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
            const Icon(Icons.lock_reset, color: Sentin8Colors.royalGold, size: 48),
            const SizedBox(height: Sentin8Spacing.lg),
            Text('Set New Password', style: Sentin8Text.h2, textAlign: TextAlign.center),
            const SizedBox(height: Sentin8Spacing.xl),
            if (_done) ...[
              const SuccessBanner(message: 'Your password has been reset successfully.'),
              const SizedBox(height: Sentin8Spacing.xl),
              FilledButton(onPressed: () => web.window.location.href = '/sign-in', child: const Text('Continue to sign in')),
            ] else ...[
              if (_error != null) ...[
                ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
                const SizedBox(height: Sentin8Spacing.md),
              ],
              TextField(
                controller: _passwordCtrl,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'New password',
                  prefixIcon: Icon(Icons.lock_outline, color: iconMutedFor(context)),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: iconMutedFor(context)),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                style: TextStyle(color: textPrimaryFor(context)),
              ),
              const SizedBox(height: Sentin8Spacing.md),
              TextField(
                controller: _confirmCtrl,
                obscureText: _obscurePassword,
                decoration: InputDecoration(labelText: 'Confirm new password', prefixIcon: Icon(Icons.lock_outline, color: iconMutedFor(context))),
                style: TextStyle(color: textPrimaryFor(context)),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: Sentin8Spacing.lg),
              FilledButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Sentin8Colors.obsidianBlack))
                    : const Text('Reset password'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
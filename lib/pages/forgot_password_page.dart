// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:AuthUI
// SPDX-License-Identifier: Apache-2.0

// Sentin8 Auth UI - Password reset request page.
//
// User enters their email and a reset link is sent.
// Calls POST /v1/password/reset-request.
import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';
import '../theme.dart';
import '../api.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailCtrl = TextEditingController();
  bool _isLoading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_emailCtrl.text.isEmpty) {
      setState(() => _error = 'Email is required');
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      final api = AuthApi(baseUrl: web.window.location.origin);
      await api.requestPasswordReset(_emailCtrl.text);
      setState(() => _sent = true);
    } catch (e) {
      // Don't reveal whether the email exists - show success anyway
      setState(() => _sent = true);
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
            Text('Reset Password', style: Sentin8Text.h2, textAlign: TextAlign.center),
            const SizedBox(height: Sentin8Spacing.xl),
            if (_sent) ...[
              const SuccessBanner(message: 'If an account exists for that email, a reset link has been sent.'),
              const SizedBox(height: Sentin8Spacing.xl),
              FilledButton(onPressed: () => web.window.location.href = '/sign-in', child: const Text('Back to sign in')),
            ] else ...[
              if (_error != null) ...[
                ErrorBanner(message: _error!, onDismiss: () => setState(() => _error = null)),
                const SizedBox(height: Sentin8Spacing.md),
              ],
              Text('Enter your email address and we\'ll send you a link to reset your password.', style: Sentin8Text.bodySecondary, textAlign: TextAlign.center),
              const SizedBox(height: Sentin8Spacing.lg),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined, color: iconMutedFor(context))),
                style: TextStyle(color: textPrimaryFor(context)),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: Sentin8Spacing.lg),
              FilledButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Sentin8Colors.obsidianBlack))
                    : const Text('Send reset link'),
              ),
              const SizedBox(height: Sentin8Spacing.lg),
              TextButton(onPressed: () => web.window.location.href = '/sign-in', child: const Text('Back to sign in')),
            ],
          ],
        ),
      ),
    );
  }
}
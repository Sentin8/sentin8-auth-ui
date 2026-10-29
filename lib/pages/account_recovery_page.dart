// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:AuthUI
// SPDX-License-Identifier: Apache-2.0

// Sentin8 Auth UI - Account recovery page.
//
// Allows users who have lost access to their authenticator device to
// initiate an account recovery flow. This is a P2 feature - the page
// is a placeholder that explains the recovery process.
import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';
import '../theme.dart';

class AccountRecoveryPage extends StatefulWidget {
  const AccountRecoveryPage({super.key});

  @override
  State<AccountRecoveryPage> createState() => _AccountRecoveryPageState();
}

class _AccountRecoveryPageState extends State<AccountRecoveryPage> {
  final _emailCtrl = TextEditingController();
  bool _isLoading = false;
  bool _submitted = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _isLoading = true);
    // TODO: Call POST /v1/account/recover when the endpoint is implemented
    await Future.delayed(const Duration(seconds: 1));
    setState(() { _isLoading = false; _submitted = true; });
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
            const Icon(Icons.help_outline, color: Sentin8Colors.warningAmber, size: 48),
            const SizedBox(height: Sentin8Spacing.lg),
            Text('Account Recovery', style: Sentin8Text.h2, textAlign: TextAlign.center),
            const SizedBox(height: Sentin8Spacing.xl),
            if (_submitted) ...[
              const SuccessBanner(message: 'If an account exists, recovery instructions have been sent to your email.'),
              const SizedBox(height: Sentin8Spacing.xl),
              FilledButton(onPressed: () => web.window.location.href = '/sign-in', child: const Text('Back to sign in')),
            ] else ...[
              Text(
                'Lost access to your authenticator? Enter your email and we\'ll guide you through the account recovery process.',
                style: Sentin8Text.bodySecondary,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Sentin8Spacing.lg),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined, color: iconMutedFor(context))),
                style: TextStyle(color: textPrimaryFor(context)),
              ),
              const SizedBox(height: Sentin8Spacing.lg),
              FilledButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Sentin8Colors.obsidianBlack))
                    : const Text('Start recovery'),
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
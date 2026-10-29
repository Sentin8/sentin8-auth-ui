// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:AuthUI
// SPDX-License-Identifier: Apache-2.0

// Sentin8 Auth UI - Email verification page.
//
// Verifies an email address using a token from the verification email link.
// Calls POST /v1/email/verify.
import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';
import '../theme.dart';
import '../api.dart';

class EmailVerifyPage extends StatefulWidget {
  final String? token;

  const EmailVerifyPage({super.key, this.token});

  @override
  State<EmailVerifyPage> createState() => _EmailVerifyPageState();
}

class _EmailVerifyPageState extends State<EmailVerifyPage> {
  bool _isLoading = true;
  bool _verified = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _verify();
  }

  Future<void> _verify() async {
    if (widget.token == null || widget.token!.isEmpty) {
      setState(() { _isLoading = false; _error = 'Invalid verification link.'; });
      return;
    }

    try {
      final api = AuthApi(baseUrl: web.window.location.origin);
      await api.verifyEmail(widget.token!);
      setState(() { _verified = true; _isLoading = false; });
    } on AuthApiException catch (e) {
      setState(() { _error = e.statusCode == 401 ? 'Verification link expired or invalid.' : e.message; _isLoading = false; });
    } catch (e) {
      setState(() { _error = 'Network error. Please try again.'; _isLoading = false; });
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
            if (_isLoading) ...[
              const LoadingSpinner(label: 'Verifying your email…'),
            ] else if (_verified) ...[
              const Icon(Icons.mark_email_read_outlined, color: Sentin8Colors.successGold, size: 48),
              const SizedBox(height: Sentin8Spacing.lg),
              Text('Email Verified', style: Sentin8Text.h2, textAlign: TextAlign.center),
              const SizedBox(height: Sentin8Spacing.sm),
              Text('Your email has been verified successfully.', style: Sentin8Text.bodySecondary, textAlign: TextAlign.center),
              const SizedBox(height: Sentin8Spacing.xl),
              FilledButton(onPressed: () => web.window.location.href = '/sign-in', child: const Text('Continue to sign in')),
            ] else ...[
              const Icon(Icons.error_outline, color: Sentin8Colors.errorCrimson, size: 48),
              const SizedBox(height: Sentin8Spacing.lg),
              Text('Verification Failed', style: Sentin8Text.h2, textAlign: TextAlign.center),
              const SizedBox(height: Sentin8Spacing.sm),
              Text(_error ?? 'Could not verify your email.', style: const TextStyle(color: Sentin8Colors.errorCrimson), textAlign: TextAlign.center),
              const SizedBox(height: Sentin8Spacing.xl),
              FilledButton(onPressed: () => web.window.location.href = '/sign-in', child: const Text('Back to sign in')),
            ],
          ],
        ),
      ),
    );
  }
}
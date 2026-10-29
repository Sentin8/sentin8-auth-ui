// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:AuthUI
// SPDX-License-Identifier: Apache-2.0

// Sentin8 Auth UI - EUDI Wallet sign-in page (EUDI.1.5).
//
// The wallet sign-in front-channel: "Sign in with wallet" button →
// GET /oauth/authorize?prompt=wallet (Auth returns the signed OID4VP
// request object + QR data) → the user scans with their EUDI wallet →
// the wallet direct-posts to /oauth/vp/response → this page is informed
// via its pending-poll (or by the wallet redirect back) and completes the
// authorization flow.
//
// Shows the binding context (requested credentials, minimum LoA) from
// GET /v1/auth/wallet/metadata BEFORE rendering the QR (phishing
// resistance - the user verifies what they are about to disclose).
// Branding-aware (§4.3 tenant branding).
//
// Design: design/sentin8-architecture-principles.md §4.12.5 +
// sentin8-sentin8-auth-technical-design.md §5.2f.
import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';
import '../theme.dart';
import '../branding_provider.dart';
import '../api.dart';

class WalletSignInPage extends StatefulWidget {
  const WalletSignInPage({super.key});

  @override
  State<WalletSignInPage> createState() => _WalletSignInPageState();
}

class _WalletSignInPageState extends State<WalletSignInPage> {
  bool _isLoading = true;
  bool _isWaiting = false;
  String? _error;
  Map<String, dynamic>? _metadata; // /v1/auth/wallet/metadata
  AuthApi? _api;

  @override
  void initState() {
    super.initState();
    _api = AuthApi(baseUrl: web.window.location.origin);
    _loadMetadata();
  }

  Future<void> _loadMetadata() async {
    try {
      final meta = await _api!.getRaw('/v1/auth/wallet/metadata');
      if (!mounted) return;
      setState(() {
        _metadata = meta;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Wallet sign-in is not available for this organization.';
        _isLoading = false;
      });
    }
  }

  /// Start the presentation: GET /oauth/authorize?prompt=wallet →
  /// display the request nonce + deep link. The wallet app opens the
  /// openid4vp:// deep link, verifies, and direct-posts to auth.
  Future<void> _startWalletFlow() async {
    setState(() { _error = null; });
    try {
      final resp = await _api!.getRaw(
        '/oauth/authorize?prompt=wallet&response_type=vp_token&client_id=sentin8-cli',
      );
      if (!mounted) return;
      if (!resp.containsKey("nonce")) {
        setState(() => _error = 'Wallet flow did not start - try again.');
        return;
      }
      setState(() => _isWaiting = true);
      _startPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to start wallet sign-in: $e');
    }
  }


  /// Poll /v1/session until the wallet direct-post creates one.
  void _startPolling() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted || !_isWaiting) return false;
      try {
        final session = await _api!.getRaw('/v1/session');
        if (session['user_id'] != null) {
          if (mounted) {
            setState(() => _isWaiting = false);
            web.window.location.assign('/');
          }
          return false;
        }
      } catch (_) {/* keep polling */}
      return _isWaiting;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final trusted = (_metadata?['trusted_issuers'] as List?)?.length ?? 0;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Sentin8Spacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(Sentin8Spacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Builder(builder: (context) {
                      final branding = BrandingProvider.of(context);
                      return Sentin8Logo(size: 36, logoUrl: branding.logoUrl, logoIconUrl: branding.logoIconUrl);
                    }),
                    const SizedBox(height: Sentin8Spacing.lg),
                    Text('Sign in with your wallet', style: Sentin8Text.h2, textAlign: TextAlign.center),
                    const SizedBox(height: Sentin8Spacing.md),
                    Text(
                      'Use your EUDI wallet to sign in securely. '
                      'Trusted credential issuers configured: $trusted.',
                      style: Sentin8Text.bodySecondary, textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: Sentin8Spacing.xl),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Sentin8Spacing.md),
                        child: Text(_error!, style: Sentin8Text.body.copyWith(color: Sentin8Colors.errorCrimson),
                          textAlign: TextAlign.center),
                      ),
                    if (_isWaiting) ...[
                      const CircularProgressIndicator(),
                      const SizedBox(height: Sentin8Spacing.md),
                      Text('Waiting for wallet confirmation…',
                          style: Sentin8Text.bodySecondary, textAlign: TextAlign.center),
                    ] else
                      ElevatedButton.icon(
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Continue with Wallet'),
                        onPressed: _startWalletFlow,
                      ),
                    const SizedBox(height: Sentin8Spacing.lg),
                    TextButton(
                      onPressed: () => web.window.location.assign('/sign-in'),
                      child: const Text('Use password instead'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
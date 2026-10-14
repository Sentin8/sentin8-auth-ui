// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:AuthUI
// SPDX-License-Identifier: Apache-2.0

// Sentin8 Auth UI — Sign In page.
//
// Full implementation with:
//   - Email + password form
//   - API call to POST /v1/sign-in
//   - Error states (invalid credentials, account locked, network error)
//   - Loading state
//   - "Forgot password?" link
//   - "Sign up" link
//   - SSO button placeholder (for enterprise connections)
//   - MFA redirect if MFA is required
import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';
import '../theme.dart';
import '../branding_provider.dart';
import '../api.dart';
import '../test_bridge.dart';

class SignInPage extends StatefulWidget {
  final String? redirectUri;
  final String? clientId;
  final String? state;
  final String? codeChallenge;
  final String? scope;
  final bool consentRequired;

  const SignInPage(
      {super.key,
      this.redirectUri,
      this.clientId,
      this.state,
      this.codeChallenge,
      this.scope,
      this.consentRequired = true});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _error;
  AuthApi? _api;

  @override
  void initState() {
    super.initState();
    _api = AuthApi(baseUrl: _baseUrl());
    // Register a test bridge handler so e2e tests can trigger sign-in
    // by calling window.sentin8TestSignIn() from JavaScript. This fills
    // the form controllers and calls _signIn() — the same code path
    // as clicking the submit button.
    setSignInHandler((email, password) {
      _emailCtrl.text = email;
      _passwordCtrl.text = password;
      _signIn();
    });
  }

  String _baseUrl() {
    final origin = web.window.location.origin;
    return origin; // Auth UI is served from the same origin as the API
  }

  @override
  void dispose() {
    setSignInHandler(null);
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_emailCtrl.text.isEmpty || _passwordCtrl.text.isEmpty) {
      setState(() => _error = 'Email and password are required');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await _api!.signIn(_emailCtrl.text, _passwordCtrl.text);

      if (res.mfaRequired) {
        // Redirect to MFA verification
        _navigateTo('/mfa?sessionId=${res.sessionId}'
            '${widget.redirectUri != null ? '&redirect_uri=${Uri.encodeComponent(widget.redirectUri!)}' : ''}'
            '${widget.state != null ? '&state=${widget.state}' : ''}');
        return;
      }

      // Success — if this is an OAuth flow (client_id present), check
      // whether consent is required. The consent flow detection is
      // handled by Sentin8:Auth's /oauth/authorize endpoint — when a
      // consent flow matches the requested scopes, the authorize
      // redirect includes a `consent_flow` param. The sign-in page
      // passes it through to the consent page. If no consent_flow is
      // present, the consent page renders the platform-default simple
      // approve/deny (OIDC standard scopes only).
      // First-party consent bypass (§4.16, §5.2e): when the OAuth client has
      // consent_required = false (e.g. dash), skip the consent page entirely
      // and call authorize/continue directly.
      if (widget.clientId != null &&
          widget.clientId!.isNotEmpty &&
          widget.scope != null &&
          widget.scope!.isNotEmpty &&
          widget.consentRequired) {
        _navigateToConsent(res.userId, res.token);
      } else {
        await _completeOAuthFlow(res.userId, res.token);
      }
    } on AuthApiException catch (e) {
      setState(() => _error = _friendlyError(e));
    } catch (e) {
      setState(() => _error = 'Network error. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Complete the OAuth flow by calling /oauth/authorize/continue.
  /// This issues an authorization code and redirects the browser to
  /// the BFF callback URL.
  Future<void> _completeOAuthFlow(String userId, String sessionToken) async {
    if (widget.clientId == null || widget.clientId!.isEmpty) {
      // No OAuth context — redirect home
      _redirectAfterAuth(widget.redirectUri);
      return;
    }
    try {
      final redirectUrl = await _api!.authorizeContinue(
        clientId: widget.clientId!,
        redirectUri: widget.redirectUri ?? '',
        scope: widget.scope ?? 'openid profile email',
        state: widget.state ?? '',
        codeChallenge: widget.codeChallenge,
        userId: userId,
        sessionToken: sessionToken,
      );
      // Redirect the browser to the BFF callback URL
      web.window.location.href = redirectUrl;
    } on AuthApiException catch (e) {
      setState(() => _error = 'Authorization failed: ${e.message}');
    } catch (e) {
      // Fallback: redirect to /oauth/authorize (may fail if PAR required)
      _redirectAfterAuth(widget.redirectUri);
    }
  }

  /// Check whether the requested OAuth scopes require a consent screen.
  /// Navigate to the consent page with the OAuth params + session token.
  /// The consent page shows the requested data clusters, lets the customer
  /// approve/deny, and then calls authorize/continue to issue the code.
  void _navigateToConsent(String userId, String sessionToken) {
    final params = <String, String>{
      'client_id': widget.clientId ?? '',
      'redirect_uri': widget.redirectUri ?? '',
      'scope': widget.scope ?? '',
      'state': widget.state ?? '',
      'user_id': userId,
      'session_token': sessionToken,
      if (widget.codeChallenge != null) 'code_challenge': widget.codeChallenge!,
    };
    final qs = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    _navigateTo('/consent?$qs');
  }

  String _friendlyError(AuthApiException e) {
    if (e.statusCode == 401) return 'Invalid email or password';
    if (e.statusCode == 403) return 'Account is locked or disabled';
    if (e.statusCode == 429)
      return 'Too many attempts. Please try again later.';
    return e.message;
  }

  void _navigateTo(String path) {
    web.window.location.href = path;
  }

  void _redirectAfterAuth(String? redirectUri) {
    if (widget.clientId != null && widget.clientId!.isNotEmpty) {
      // OAuth flow: redirect back to /oauth/authorize which will now
      // see the session cookie and issue an authorization code,
      // which then redirects to the callback URL.
      final scope = widget.scope ?? 'openid+profile+email';
      final authUrl = '/oauth/authorize'
          '?client_id=${widget.clientId}'
          '${widget.redirectUri != null ? '&redirect_uri=${Uri.encodeComponent(widget.redirectUri!)}' : ''}'
          '&response_type=code'
          '${widget.state != null ? '&state=${widget.state}' : ''}'
          '&scope=${Uri.encodeQueryComponent(scope)}'
          '${widget.codeChallenge != null ? '&code_challenge=${widget.codeChallenge}' : ''}'
          '&code_challenge_method=S256';
      web.window.location.href = authUrl;
    } else if (redirectUri != null && redirectUri.isNotEmpty) {
      web.window.location.href = redirectUri;
    } else {
      web.window.location.href = '/';
    }
  }

  @override
  Widget build(BuildContext context) {
    final branding = BrandingProvider.of(context);
    final heading = branding.hasSignInText
        ? branding.signInText
        : branding.hasOrganizationName
            ? 'Sign in to ${branding.organizationName}'
            : 'Sign In';
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GlassPanel(
              maxWidth: 440,
              padding: const EdgeInsets.all(Sentin8Spacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Sentin8Logo(
                      size: 36,
                      logoUrl: branding.logoUrl,
                      logoIconUrl: branding.logoIconUrl),
                  const SizedBox(height: Sentin8Spacing.lg),
                  Text(
                    heading,
                    style: h2For(context),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Sentin8Spacing.xl),
                  if (_error != null) ...[
                    ErrorBanner(
                        message: _error!,
                        onDismiss: () => setState(() => _error = null)),
                    const SizedBox(height: Sentin8Spacing.md),
                  ],
                  // Email field
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined,
                            color: iconMutedFor(context))),
                    style: TextStyle(color: textPrimaryFor(context)),
                    onSubmitted: (_) => _passwordFocus.requestFocus(),
                  ),
                  const SizedBox(height: Sentin8Spacing.md),
                  // Password field
                  TextField(
                    controller: _passwordCtrl,
                    focusNode: _passwordFocus,
                    obscureText: _obscurePassword,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline,
                          color: iconMutedFor(context)),
                      suffixIcon: IconButton(
                        icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: iconMutedFor(context)),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    style: TextStyle(color: textPrimaryFor(context)),
                    onSubmitted: (_) => _signIn(),
                  ),
                  const SizedBox(height: Sentin8Spacing.sm),
                  // Forgot password link
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => _navigateTo('/forgot-password'),
                      child: const Text('Forgot password?',
                          style: TextStyle(fontSize: 13)),
                    ),
                  ),
                  const SizedBox(height: Sentin8Spacing.md),
                  // Sign in button
                  FilledButton(
                    onPressed: _isLoading ? null : _signIn,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Sentin8Colors.obsidianBlack))
                        : const Text('Continue'),
                  ),
                  const SizedBox(height: Sentin8Spacing.lg),
                  // Divider
                  Row(
                    children: [
                      Expanded(
                          child:
                              Divider(color: Theme.of(context).dividerColor)),
                      Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: Sentin8Spacing.md),
                          child: Text('or',
                              style: Theme.of(context).brightness ==
                                      Brightness.light
                                  ? Sentin8Text.captionLight
                                  : Sentin8Text.caption)),
                      Expanded(
                          child:
                              Divider(color: Theme.of(context).dividerColor)),
                    ],
                  ),
                  const SizedBox(height: Sentin8Spacing.lg),
                  // SSO button placeholder
                  OutlinedButton.icon(
                    onPressed: () {}, // TODO: Enterprise SSO (SAML/OIDC)
                    icon: const Icon(Icons.business,
                        color: Sentin8Colors.softGold),
                    label: const Text('Continue with SSO'),
                  ),
                  const SizedBox(height: Sentin8Spacing.xl),
                  // Sign up link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text("Don't have an account? ",
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).brightness == Brightness.light
                                    ? Sentin8Text.bodySecondaryLight
                                    : Sentin8Text.bodySecondary),
                      ),
                      TextButton(
                        onPressed: () => _navigateTo('/sign-up'
                            '${widget.redirectUri != null ? '?redirect_uri=${Uri.encodeComponent(widget.redirectUri!)}' : ''}'
                            '${widget.clientId != null ? '&client_id=${widget.clientId}' : ''}'
                            '${widget.state != null ? '&state=${widget.state}' : ''}'
                            '${widget.codeChallenge != null ? '&code_challenge=${widget.codeChallenge}' : ''}'
                            '&code_challenge_method=S256'
                            '${widget.scope != null ? '&scope=${Uri.encodeQueryComponent(widget.scope!)}' : ''}'),
                        child: const Text('Sign up'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: Sentin8Spacing.xs),
            // Powered by Sentin8 — outside the form panel
            const PoweredBySentin8(),
          ],
        ),
      ),
    );
  }
}

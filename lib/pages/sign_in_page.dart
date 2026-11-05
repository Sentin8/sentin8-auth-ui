// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:AuthUI
// SPDX-License-Identifier: Apache-2.0

// Sentin8 Auth UI - Sign In page.
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
import '../webauthn.dart' as webauthn;
import '../test_bridge.dart';

class SignInPage extends StatefulWidget {
  final String? redirectUri;
  final String? clientId;
  final String? state;
  final String? codeChallenge;
  final String? scope;
  final bool consentRequired;
  // OIDC Core §3.1.2.1 protocol params the certification suite sends on
  // every authorize request (auth DESIGN §9a.11): nonce is REQUIRED for
  // the suite's ID-token binding checks; response_mode/claims/acr ride
  // the same intake so the SPA's authorizeContinue emits the exact
  // request the caller made.
  final String? nonce;
  final String? responseMode;
  // DESIGN 9a.13 - the CELL's response_type (the fragment cells
  // deliver the id_token/token members in the callback fragment).
  final String? responseType;
  final String? claims;
  final String? acrValues;
  final String? resource;
  // RFC 9449 dpop_jkt - the pre-bound DPoP key thumbprint (rides the
  // code record so the mint sender-constrains the token).
  final String? dpopJkt;

  const SignInPage(
      {super.key,
      this.redirectUri,
      this.clientId,
      this.state,
      this.codeChallenge,
      this.scope,
      this.consentRequired = true,
      this.nonce,
      this.responseMode,
      this.responseType,
      this.claims,
      this.acrValues,
      this.resource,
      this.dpopJkt});

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

  // Identifier-first state machine (IDFIRST-1): step 1 collects the
  // email; the identify answer drives step 2 (password always,
  // passkey when the account has one, an MFA label when TOTP is
  // enrolled). The whole OAuth context stays in widget state across
  // the steps - a refresh lands back on step 1 (standard behavior).
  IdentifyResponse? _identify;
  bool _passkeyBusy = false;

  @override
  void initState() {
    super.initState();
    _api = AuthApi(baseUrl: _baseUrl());
    // Register a test bridge handler so e2e tests can trigger sign-in
    // by calling window.sentin8TestSignIn() from JavaScript. The bridge
    // keeps its ONE-SHOT contract: it fills the email, advances to the
    // credential step, fills the password, and submits - the same path
    // a user walks manually.
    setSignInHandler((email, password) {
      _emailCtrl.text = email;
      _identifyAndThen(password);
    });
    // The certification suite's user-rejects module drives the DENY
    // path: the bridge deny call completes the CURRENT session's
    // authorize continuation with deny=true (auth redirects back with
    // error=access_denied). The deny path doesn't need fresh
    // credentials - it uses the signed-in session (the suite reaches
    // the deny step AFTER the user signed in).
    setDenyHandler(() {
      _denyAuthorizeFlow();
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

  /// Bridge continuation: after the identify round-trip completes,
  // fill the password and submit - preserving the one-shot bridge
  // contract for the OIDF battery.
  Future<void> _identifyAndThen(String? password) async {
    await _submitIdentify();
    if (!mounted) return;
    if (password != null && _identify != null) {
      _passwordCtrl.text = password;
      await _signIn();
    }
  }

  /// Step 1 submit: identify the email and advance to the credential
  /// step. Unknown emails still advance (the server answers the same
  /// shape) - the credential step surfaces the real failure.
  Future<void> _submitIdentify() async {
    if (_emailCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Email is required');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await _api!.identify(_emailCtrl.text.trim());
      if (mounted) {
        setState(() {
          _identify = res;
          _isLoading = false;
        });
      }
    } on AuthApiException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.statusCode == 429
              ? 'Too many attempts. Please try again later.'
              : 'Network error. Please try again.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Network error. Please try again.';
        });
      }
    }
  }

  /// Back to step 1 (the email chip's edit affordance) - drops the
  /// identify answer; the OAuth context is untouched.
  void _backToEmail() {
    setState(() {
      _identify = null;
      _passwordCtrl.clear();
      _error = null;
    });
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
        // Redirect to MFA verification with the challenge capability
        // (the server's needs_mfa contract: pending_token_id - never a
        // session id; consuming the challenge activates the session).
        _navigateTo('/mfa?pending_token_id=${res.pendingTokenId}'
            '${widget.redirectUri != null ? '&redirect_uri=${Uri.encodeComponent(widget.redirectUri!)}' : ''}'
            '${widget.state != null ? '&state=${widget.state}' : ''}');
        return;
      }

      // Success - if this is an OAuth flow (client_id present), check
      // whether consent is required. The consent flow detection is
      // handled by Sentin8:Auth's /oauth/authorize endpoint - when a
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

  /// Step 2, passkey path: run the WebAuthn ceremony (typed package:web
  /// bindings) and complete the same post-auth routing as the password
  /// path. The server creates the session `active` and sets the cookie;
  /// the finish answer carries no body token, so the OAuth continuation
  /// rides the cookie via `/oauth/authorize` (which now sees the session).
  Future<void> _passkeySignIn() async {
    if (_identify == null) return;
    setState(() {
      _passkeyBusy = true;
      _error = null;
    });
    try {
      final beginJson = await _api!.passkeySignInBegin(_identify!.continuationToken);
      final begin = webauthn.PasskeySignInBegin.fromJson(beginJson);
      final assertion = await webauthn.getAssertion(begin);
      await _api!.passkeySignInFinish(assertion.toJson());
      // The session cookie is set - complete via /oauth/authorize, or
      // land home when no OAuth context rides this page.
      if (widget.clientId != null && widget.clientId!.isNotEmpty) {
        final scope = widget.scope ?? 'openid profile email';
        final authUrl = '/oauth/authorize'
            '?client_id=${widget.clientId}'
            '${widget.redirectUri != null ? '&redirect_uri=${Uri.encodeComponent(widget.redirectUri!)}' : ''}'
            '&response_type=code'
            '${widget.state != null ? '&state=${widget.state}' : ''}'
            '&scope=${Uri.encodeQueryComponent(scope)}'
            '${widget.codeChallenge != null ? '&code_challenge=${widget.codeChallenge}' : ''}'
            '&code_challenge_method=S256'
            '${widget.nonce != null ? '&nonce=${widget.nonce}' : ''}'
            '${widget.responseMode != null ? '&response_mode=${widget.responseMode}' : ''}'
            '${widget.acrValues != null ? '&acr_values=${widget.acrValues}' : ''}'
            '${widget.resource != null ? '&resource=${Uri.encodeComponent(widget.resource!)}' : ''}'
            '${widget.dpopJkt != null ? '&dpop_jkt=${widget.dpopJkt}' : ''}';
        web.window.location.href = authUrl;
      } else {
        _redirectAfterAuth(widget.redirectUri);
      }
    } on AuthApiException catch (e) {
      if (mounted) {
        setState(() {
          _passkeyBusy = false;
          _error = e.statusCode == 429
              ? 'Too many attempts. Please try again later.'
              : 'Passkey sign-in failed: ${e.message}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _passkeyBusy = false;
          _error = 'Passkey sign-in was cancelled or failed. Try again.';
        });
      }
    }
  }

  /// The suite's user-rejects path: forward to the consent screen with
  /// the deny instruction (the consent page holds the session context
  /// and completes the continuation with deny=true).
  void _denyAuthorizeFlow() {
    if (widget.clientId == null || widget.clientId!.isEmpty) return;
    final params = <String, String>{
      'client_id': widget.clientId ?? '',
      'redirect_uri': widget.redirectUri ?? '',
      'scope': widget.scope ?? '',
      'state': widget.state ?? '',
      'deny': '1',
      if (widget.codeChallenge != null) 'code_challenge': widget.codeChallenge!,
    };
    final qs = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    _navigateTo('/consent?$qs');
  }

  /// Complete the OAuth flow by calling /oauth/authorize/continue.
  /// This issues an authorization code and redirects the browser to
  /// the BFF callback URL.
  Future<void> _completeOAuthFlow(String userId, String sessionToken) async {
    if (widget.clientId == null || widget.clientId!.isEmpty) {
      // No OAuth context - redirect home
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
        // OIDC params forwarded (DESIGN §9a.11) - the code record binds
        // exactly the request the caller made.
        nonce: widget.nonce,
        responseMode: widget.responseMode,
        responseType: widget.responseType,
        claims: widget.claims,
        acrValues: widget.acrValues,
        resource: widget.resource,
        dpopJkt: widget.dpopJkt,
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
      if (widget.nonce != null) 'nonce': widget.nonce!,
      if (widget.responseMode != null) 'response_mode': widget.responseMode!,
      if (widget.claims != null) 'claims': widget.claims!,
      if (widget.acrValues != null) 'acr_values': widget.acrValues!,
      if (widget.resource != null) 'resource': widget.resource!,
      if (widget.dpopJkt != null) 'dpop_jkt': widget.dpopJkt!,
    };
    final qs = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    _navigateTo('/consent?$qs');
  }

  String _friendlyError(AuthApiException e) {
    if (e.statusCode == 401) return 'Invalid email or password';
    if (e.statusCode == 403) return 'Account is locked or disabled';
    if (e.statusCode == 429) {
      return 'Too many attempts. Please try again later.';
    }
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
                  if (_identify == null) ...[
                    // Step 1 - the identifier step.
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined,
                              color: iconMutedFor(context))),
                      style: TextStyle(color: textPrimaryFor(context)),
                      onSubmitted: (_) => _submitIdentify(),
                    ),
                    const SizedBox(height: Sentin8Spacing.lg),
                    FilledButton(
                      onPressed: _isLoading ? null : _submitIdentify,
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
                    // Sign up link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text("Don't have an account? ",
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).brightness ==
                                      Brightness.light
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
                  ] else ...[
                    // Step 2 - the credential step. The email chip shows
                    // the identified address with an edit affordance back
                    // to step 1 (the OAuth context is untouched).
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Sentin8Spacing.md,
                          vertical: Sentin8Spacing.sm),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.light
                            ? Colors.black.withValues(alpha: 0.04)
                            : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(Sentin8Radii.medium),
                        border: Border.all(
                            color: Theme.of(context).dividerColor),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.email_outlined,
                              size: 18, color: iconMutedFor(context)),
                          const SizedBox(width: Sentin8Spacing.sm),
                          Expanded(
                            child: Text(
                              _emailCtrl.text,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: textPrimaryFor(context), fontSize: 14),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Change email',
                            icon: Icon(Icons.edit_outlined,
                                size: 18, color: iconMutedFor(context)),
                            onPressed: _backToEmail,
                          ),
                        ],
                      ),
                    ),
                    if (_identify!.mfaRequired) ...[
                      const SizedBox(height: Sentin8Spacing.sm),
                      Text(
                        'This account requires a verification code after the password.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).brightness == Brightness.light
                            ? Sentin8Text.captionLight
                            : Sentin8Text.caption,
                      ),
                    ],
                    const SizedBox(height: Sentin8Spacing.md),
                    // Password field
                    TextField(
                      controller: _passwordCtrl,
                      focusNode: _passwordFocus,
                      obscureText: _obscurePassword,
                      autofocus: true,
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
                    // Sign in button (the password submit)
                    FilledButton(
                      onPressed: _isLoading ? null : _signIn,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Sentin8Colors.obsidianBlack))
                          : const Text('Sign in'),
                    ),
                    if (_identify!.hasPasskey) ...[
                      const SizedBox(height: Sentin8Spacing.lg),
                      // Divider + the passkey option the identify answer
                      // offered (the account has an active WebAuthn factor).
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
                      const SizedBox(height: Sentin8Spacing.md),
                      OutlinedButton.icon(
                        onPressed: _passkeyBusy ? null : _passkeySignIn,
                        icon: _passkeyBusy
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.fingerprint,
                                color: Sentin8Colors.softGold),
                        label: const Text('Sign in with passkey'),
                      ),
                    ],
                    const SizedBox(height: Sentin8Spacing.lg),
                    // Sign up link - step 2 keeps it visible too
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text("Don't have an account? ",
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).brightness ==
                                      Brightness.light
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
                ],
              ),
            ),
            const SizedBox(height: Sentin8Spacing.xs),
            // Legal links + Powered by Sentin8 - outside the form panel
            const AuthUiFooter(),
          ],
        ),
      ),
    );
  }
}

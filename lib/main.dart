// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:AuthUI
// SPDX-License-Identifier: Apache-2.0

// Sentin8 Auth Hosted UI - Flutter Web app.
//
// This Flutter Web app is embedded in the Auth Rust server and served
// from the same hostname as the OAuth/FAPI endpoints.
//
// Route map:
//   /sign-in          → Sign In page
//   /sign-up          → Sign Up page
//   /mfa              → MFA verification page
//   /forgot-password  → Password reset request page
//   /reset-password   → Password reset confirmation page
//   /verify-email     → Email verification page
//   /consent          → OAuth consent screen
//   /recover          → Account recovery page
//   /ciba/assisted/{id} → Assisted Login page (Story 1.1.70)
//   /device           → Device approval page (RFC 8628, DEVUI-1.1)
//   /                 → redirect to /sign-in
import 'package:web/web.dart' as web;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'theme.dart';
import 'observability.dart';
import 'pages/sign_in_page.dart';
import 'pages/sign_up_page.dart';
import 'pages/mfa_page.dart';
import 'pages/forgot_password_page.dart';
import 'pages/reset_password_page.dart';
import 'pages/email_verify_page.dart';
import 'pages/consent_page.dart';
import 'pages/account_recovery_page.dart';
import 'pages/assisted_login_page.dart';
import 'pages/device_page.dart';
import 'pages/wallet_sign_in_page.dart';
import 'test_bridge.dart';
import 'branding_provider.dart';

void main() {
  // Enable semantics so that Playwright/e2e tests can interact with
  // form fields via ARIA labels. Flutter CanvasKit renders to a canvas
  // by default; with semantics enabled, it creates real DOM elements
  // (flt-semantics containers with aria-label) that test automation
  // can find and fill.
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  // Register the test bridge on window so e2e tests can trigger
  // form submissions by calling window.sentin8TestSignUp/SignIn.
  // These functions call the same Flutter widget code as clicking
  // the submit button - no direct API calls.
  registerTestBridge();
  AuthUiLogger.info('auth-ui app starting', metadata: {'correlation_id': sessionCorrelationId});
  runApp(const AuthApp());
}

class AuthApp extends StatelessWidget {
  const AuthApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Wrap in BrandingScope to fetch tenant branding on startup.
    return BrandingScope(
      child: _AuthApp(),
    );
  }
}

class _AuthApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Read the initial route from the browser URL so Flutter renders
    // the correct page (sign-in, sign-up, mfa, etc.) on page load.
    final initialRoute = web.window.location.pathname;
    final branding = BrandingProvider.of(context);

    // Set the browser tab title from the org name (or default).
    final orgName = branding.hasOrganizationName
        ? branding.organizationName
        : 'Sentin8';
    web.document.title = '$orgName · Sign In';

    return MaterialApp(
      title: '$orgName Sign In',
      theme: sentin8ThemeForBranding(branding),
      debugShowCheckedModeBanner: false,
      initialRoute: initialRoute,
      onGenerateRoute: _generateRoute,
    );
  }

  Route<dynamic>? _generateRoute(RouteSettings settings) {
    final uri = Uri.parse(settings.name ?? '/');
    final segments = uri.pathSegments;
    final params = uri.queryParameters;

    // / → redirect to /sign-in
    if (segments.isEmpty) {
      return _page(const SignInPage(), settings);
    }

    // Read query params directly from window.location since Flutter's
    // initialRoute strips query parameters. Both /sign-in and /sign-up
    // (and the BFF /auth/sign-up → Auth /sign-up redirect) carry
    // OAuth parameters (client_id, state, code_challenge, scope,
    // redirect_uri) that the pages need to round-trip the user back
    // through /oauth/authorize after sign-in / sign-up.
    final path = web.window.location.pathname;
    final search = web.window.location.search;
    final winUri = Uri.parse(path + search);
    final q = winUri.queryParameters;

    switch (segments[0]) {
      case 'sign-in':
        return _page(SignInPage(
          redirectUri: q['redirect_uri'],
          clientId: q['client_id'],
          state: q['state'],
          codeChallenge: q['code_challenge'],
          scope: q['scope'],
          consentRequired: q['consent_required'] != 'false',
          // OIDC Core §3.1.2.1 protocol params (auth-ui §9a.11) -
          // forwarded to authorize/continue so the code record binds the
          // exact caller request (nonce → ID token, JARM response_mode,
          // the §5.5 claims selection, acr_values, RFC 8707 resource).
          nonce: q['nonce'],
          responseMode: q['response_mode'],
          responseType: q['response_type'],
          claims: q['claims'],
          acrValues: q['acr_values'],
          resource: q['resource'],
          dpopJkt: q['dpop_jkt'],
        ), settings);

      case 'sign-up':
        return _page(SignUpPage(
          redirectUri: q['redirect_uri'],
          clientId: q['client_id'],
          state: q['state'],
          codeChallenge: q['code_challenge'],
          scope: q['scope'],
          consentRequired: q['consent_required'] != 'false',
        ), settings);

      case 'mfa':
        // MFA step - carries the sign-in response's `pending_token_id`
        // (the needs_mfa challenge capability, MFA-SYNC): consuming the
        // challenge at /v1/mfa/verify is what activates the session.
        return _page(
            MfaPage(
              pendingTokenId: params['pending_token_id'],
              redirectUri: params['redirect_uri'],
            ),
            settings);

      case 'forgot-password':
        return _page(const ForgotPasswordPage(), settings);

      case 'reset-password':
        return _page(ResetPasswordPage(token: params['token']), settings);

      case 'verify-email':
        return _page(EmailVerifyPage(token: params['token']), settings);

      case 'consent':
        return _page(ConsentPage(
          clientId: q['client_id'],
          clientName: q['client_name'],
          redirectUri: q['redirect_uri'],
          state: q['state'],
          scope: q['scope'],
          userId: q['user_id'],
          sessionToken: q['session_token'],
          codeChallenge: q['code_challenge'],
          nonce: q['nonce'],
          responseMode: q['response_mode'],
          responseType: q['response_type'],
          claims: q['claims'],
          acrValues: q['acr_values'],
          resource: q['resource'],
          dpopJkt: q['dpop_jkt'],
        ), settings);

      case 'recover':
        return _page(const AccountRecoveryPage(), settings);

      case 'device':
        // Device-approval page (RFC 8628 §3.3, DEVUI-1.1) - the CLI device
        // flow sends the operator here with ?user_code=. Rendered even
        // without a code so a malformed link shows a terminal error state
        // instead of a context-less sign-in form.
        return _page(DevicePage(userCode: q['user_code'] ?? ''), settings);

      case 'ciba':
        // /ciba/assisted/{auth_req_id} - Assisted Login page (Story 1.1.70)
        if (segments.length >= 3 && segments[1] == 'assisted') {
          return _page(AssistedLoginPage(authReqId: segments[2]), settings);
        }
        return _page(const SignInPage(), settings);

      case 'wallet':
        // /wallet - EUDI wallet sign-in (EUDI.1.5, §5.2f).
        return _page(const WalletSignInPage(), settings);

      default:
        return _page(const SignInPage(), settings);
    }
  }

  MaterialPageRoute _page(Widget page, RouteSettings settings) =>
      MaterialPageRoute(builder: (_) => page, settings: settings);
}
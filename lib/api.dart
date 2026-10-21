// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:AuthUI
// SPDX-License-Identifier: Apache-2.0

// Sentin8 Auth UI — API client for Auth server endpoints.
//
// Calls the Auth Rust server's frontend API endpoints:
//   POST /v1/sign-in   — email/password authentication
//   POST /v1/sign-up   — customer registration
//   POST /v1/sign-out   — session termination
//   GET  /v1/session    — return current session from cookie
//   POST /v1/mfa/verify — MFA verification (TOTP)
//   POST /v1/password/reset-request — password reset request
//   POST /v1/password/reset-confirm — password reset confirmation
//   POST /v1/email/verify — email verification
//
// Every request carries an `x-sentin8-correlation-id` header so the
// downstream Rust `sentin8-middleware::correlation_id` middleware can
// correlate the request back to the originating Flutter action.
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'observability.dart';

/// Auth API client.
class AuthApi {
  final String baseUrl;
  final http.Client _client;

  /// Session token id of the RESTORED session (from `GET /v1/session`)
  /// or of the session established by the most recent `signIn` — both
  /// feed the `X-Sentin8-CSRF` header on cookie-authenticated mutations
  /// (SEC-2.4.4); Bearer paths ignore it. Set by `getSession()` and by
  /// `signIn` (AUTH-UI-4: a fresh sign-in must arm the CSRF header for
  /// the immediately-following cookie-authenticated mutation, e.g. the
  /// CIBA assisted-login `complete` call).
  String? _restoredSessionToken;

  AuthApi({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  /// Standard JSON headers for every request. Includes the session-level
  /// correlation ID so Auth can stamp it on every downstream log line, and
  /// the CSRF header when a restored session's token id is known.
  Map<String, String> get _jsonHeaders => {
        'content-type': 'application/json',
        'accept': 'application/json',
        'x-sentin8-correlation-id': sessionCorrelationId,
        if (_restoredSessionToken != null && _restoredSessionToken!.isNotEmpty)
          'x-sentin8-csrf': _restoredSessionToken!,
      };

  /// GET headers (no content-type, but still correlation_id).
  Map<String, String> get _getHeaders => {
        'accept': 'application/json',
        'x-sentin8-correlation-id': sessionCorrelationId,
      };

  /// Record a request's latency and outcome.
  void _record(String method, String path, int status, int millis) {
    AuthUiMetrics().recordApiLatency(path, millis);
    AuthUiLogger.info(
      'HTTP $method $path → $status (${millis}ms)',
      metadata: {'method': method, 'path': path, 'status': status, 'latency_ms': millis},
    );
  }

  /// Record an error response (4xx/5xx) for metrics and alerting.
  void _recordError(String method, String path, int status, int millis) {
    AuthUiMetrics().recordApiError(path);
    authUiAlerts.recordApiError(path);
    AuthUiLogger.warn(
      'HTTP $method $path → $status (${millis}ms)',
      metadata: {'method': method, 'path': path, 'status': status, 'latency_ms': millis},
    );
  }

  /// Sign in with email and password.
  Future<SignInResponse> signIn(String email, String password) async {
    AuthUiMetrics().recordSignInAttempt();
    final sw = Stopwatch()..start();
    final res = await _client.post(
      Uri.parse('$baseUrl/v1/sign-in'),
      headers: _jsonHeaders,
      body: jsonEncode({'email': email, 'password': password}),
    );
    sw.stop();
    if (res.statusCode >= 400) {
      _recordError('POST', '/v1/sign-in', res.statusCode, sw.elapsedMilliseconds);
      authUiAlerts.recordAuthFailure();
      final body = _decode(res);
      throw AuthApiException(res.statusCode, body['message'] as String? ?? 'Sign-in failed');
    }
    _record('POST', '/v1/sign-in', res.statusCode, sw.elapsedMilliseconds);
    final body = _decode(res);
    // AUTH-UI-4 — record the just-established session's token id so the
    // next cookie-authenticated mutation carries a valid `X-Sentin8-CSRF`
    // (SEC-2.4.4). Without this, the CIBA assisted-login `complete` call
    // made immediately after sign-in failed 403.
    final token = body['token'] as String?;
    if (token != null && token.isNotEmpty) {
      _restoredSessionToken = token;
    }
    AuthUiMetrics().recordSignInSuccess();
    return SignInResponse.fromJson(body);
  }

  /// Sign up a new customer.
  Future<SignUpResponse> signUp(String email, String password, {String? firstName, String? lastName}) async {
    AuthUiMetrics().recordSignUpAttempt();
    final sw = Stopwatch()..start();
    final res = await _client.post(
      Uri.parse('$baseUrl/v1/sign-up'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'email': email,
        'password': password,
        if (firstName != null) 'first_name': firstName,
        if (lastName != null) 'last_name': lastName,
      }),
    );
    sw.stop();
    if (res.statusCode >= 400) {
      _recordError('POST', '/v1/sign-up', res.statusCode, sw.elapsedMilliseconds);
      final body = _decode(res);
      throw AuthApiException(res.statusCode, body['message'] as String? ?? 'Sign-up failed');
    }
    _record('POST', '/v1/sign-up', res.statusCode, sw.elapsedMilliseconds);
    final body = _decode(res);
    AuthUiMetrics().recordSignUpSuccess();
    return SignUpResponse.fromJson(body);
  }

  /// Sign out — terminate the current session.
  Future<void> signOut() async {
    final sw = Stopwatch()..start();
    final res = await _client.post(
      Uri.parse('$baseUrl/v1/sign-out'),
      headers: _jsonHeaders,
    );
    sw.stop();
    _record('POST', '/v1/sign-out', res.statusCode, sw.elapsedMilliseconds);
  }

  /// Get the current session from the cookie. Remembers the session token
  /// id so later mutations can present the CSRF header (SEC-2.4.4).
  Future<SessionResponse?> getSession() async {
    final sw = Stopwatch()..start();
    final res = await _client.get(
      Uri.parse('$baseUrl/v1/session'),
      headers: _getHeaders,
    );
    sw.stop();
    _record('GET', '/v1/session', res.statusCode, sw.elapsedMilliseconds);
    if (res.statusCode == 401 || res.statusCode == 404) return null;
    final body = _decode(res);
    if (res.statusCode >= 400) return null;
    final session = SessionResponse.fromJson(body);
    if (session.sessionToken.isNotEmpty) {
      _restoredSessionToken = session.sessionToken;
    }
    return session;
  }

  /// Approve a device sign-in (RFC 8628 §3.3) — `POST /device/verify`.
  ///
  /// SEC-2.1.4: the approving user comes from the session server-side, so
  /// the body carries only the `user_code`. When `sessionToken` is passed
  /// the call uses `Authorization: Bearer <token>` (Bearer is CSRF-exempt,
  /// SEC-2.4.4); otherwise the `__session` cookie authenticates the request
  /// and `_jsonHeaders` supplies the `X-Sentin8-CSRF` header from the
  /// restored session token id.
  Future<void> verifyDevice(String userCode, {String? sessionToken}) async {
    final sw = Stopwatch()..start();
    final headers = Map<String, String>.from(_jsonHeaders);
    if (sessionToken != null && sessionToken.isNotEmpty) {
      headers['authorization'] = 'Bearer $sessionToken';
    }
    final res = await _client.post(
      Uri.parse('$baseUrl/device/verify'),
      headers: headers,
      body: jsonEncode({'user_code': userCode}),
    );
    sw.stop();
    _record('POST', '/device/verify', res.statusCode, sw.elapsedMilliseconds);
    if (res.statusCode >= 400) {
      _recordError('POST', '/device/verify', res.statusCode, sw.elapsedMilliseconds);
      final body = _decode(res);
      throw AuthApiException(
        res.statusCode,
        body['message'] as String? ??
            body['error'] as String? ??
            'Device verification failed',
      );
    }
  }

  /// Generic GET returning a decoded JSON map. Story 1.1.70.
  Future<Map<String, dynamic>> getRaw(String path) async {
    final sw = Stopwatch()..start();
    final res = await _client.get(
      Uri.parse('$baseUrl$path'),
      headers: _getHeaders,
    );
    sw.stop();
    if (res.statusCode >= 400) {
      _recordError('GET', path, res.statusCode, sw.elapsedMilliseconds);
      final body = _decode(res);
      throw AuthApiException(res.statusCode, body['message'] as String? ?? 'Request failed');
    }
    _record('GET', path, res.statusCode, sw.elapsedMilliseconds);
    return _decode(res);
  }

  /// Generic POST with an optional JSON body, returning a decoded JSON map.
  /// Story 1.1.70.
  Future<Map<String, dynamic>> postRaw(String path, Map<String, dynamic> body) async {
    final sw = Stopwatch()..start();
    final res = await _client.post(
      Uri.parse('$baseUrl$path'),
      headers: _jsonHeaders,
      body: jsonEncode(body),
    );
    sw.stop();
    if (res.statusCode >= 400) {
      _recordError('POST', path, res.statusCode, sw.elapsedMilliseconds);
      final decoded = _decode(res);
      throw AuthApiException(res.statusCode, decoded['message'] as String? ?? 'Request failed');
    }
    _record('POST', path, res.statusCode, sw.elapsedMilliseconds);
    return _decode(res);
  }

  /// Verify MFA (TOTP code).
  Future<void> verifyMfa(String code, {String? sessionId}) async {
    AuthUiMetrics().recordMfaAttempt();
    final sw = Stopwatch()..start();
    final res = await _client.post(
      Uri.parse('$baseUrl/v1/mfa/verify'),
      headers: _jsonHeaders,
      body: jsonEncode({'code': code, if (sessionId != null) 'session_id': sessionId}),
    );
    sw.stop();
    if (res.statusCode >= 400) {
      _recordError('POST', '/v1/mfa/verify', res.statusCode, sw.elapsedMilliseconds);
      authUiAlerts.recordAuthFailure();
      final body = _decode(res);
      throw AuthApiException(res.statusCode, body['message'] as String? ?? 'MFA verification failed');
    }
    _record('POST', '/v1/mfa/verify', res.statusCode, sw.elapsedMilliseconds);
    AuthUiMetrics().recordMfaSuccess();
  }

  /// Request a password reset.
  Future<void> requestPasswordReset(String email) async {
    AuthUiMetrics().recordPasswordResetRequest();
    final sw = Stopwatch()..start();
    final res = await _client.post(
      Uri.parse('$baseUrl/v1/password/reset-request'),
      headers: _jsonHeaders,
      body: jsonEncode({'email': email}),
    );
    sw.stop();
    _record('POST', '/v1/password/reset-request', res.statusCode, sw.elapsedMilliseconds);
  }

  /// Confirm a password reset with a token.
  Future<void> confirmPasswordReset(String token, String newPassword) async {
    final sw = Stopwatch()..start();
    final res = await _client.post(
      Uri.parse('$baseUrl/v1/password/reset-confirm'),
      headers: _jsonHeaders,
      body: jsonEncode({'token': token, 'password': newPassword}),
    );
    sw.stop();
    if (res.statusCode >= 400) {
      _recordError('POST', '/v1/password/reset-confirm', res.statusCode, sw.elapsedMilliseconds);
      final body = _decode(res);
      throw AuthApiException(res.statusCode, body['message'] as String? ?? 'Password reset failed');
    }
    _record('POST', '/v1/password/reset-confirm', res.statusCode, sw.elapsedMilliseconds);
  }

  /// Verify email with a token.
  Future<void> verifyEmail(String token) async {
    AuthUiMetrics().recordEmailVerifyAttempt();
    final sw = Stopwatch()..start();
    final res = await _client.post(
      Uri.parse('$baseUrl/v1/email/verify'),
      headers: _jsonHeaders,
      body: jsonEncode({'token': token}),
    );
    sw.stop();
    if (res.statusCode >= 400) {
      _recordError('POST', '/v1/email/verify', res.statusCode, sw.elapsedMilliseconds);
      final body = _decode(res);
      throw AuthApiException(res.statusCode, body['message'] as String? ?? 'Email verification failed');
    }
    _record('POST', '/v1/email/verify', res.statusCode, sw.elapsedMilliseconds);
  }

  /// Continue the OAuth authorize flow after sign-in / sign-up.
  ///
  /// Calls POST /oauth/authorize/continue with the session token and OAuth
  /// params. Auth validates the session, issues an authorization code, and
  /// returns JSON with the redirect URL (e.g.
  /// https://sentin8-bff.ops.sys.local.sentin8.dev/auth/callback?code=...&state=...).
  ///
  /// The Flutter UI then navigates the browser to the redirect URL so
  /// that BFF receives the authorization code and sets the session cookie.
  Future<String> authorizeContinue({
    required String clientId,
    required String redirectUri,
    required String scope,
    required String state,
    String? codeChallenge,
    required String userId,
    required String sessionToken,
    List<String> selectedAccountIds = const [],
  }) async {
    final sw = Stopwatch()..start();
    final res = await _client.post(
      Uri.parse('$baseUrl/oauth/authorize/continue'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'scope': scope,
        'state': state,
        if (codeChallenge != null) 'code_challenge': codeChallenge,
        'user_id': userId,
        'session_token': sessionToken,
        'selected_account_ids': selectedAccountIds,
      }),
    );
    sw.stop();
    final body = _decode(res);
    if (res.statusCode >= 400) {
      _recordError('POST', '/oauth/authorize/continue', res.statusCode, sw.elapsedMilliseconds);
      throw AuthApiException(
        res.statusCode,
        body['message'] as String? ?? body['error'] as String? ?? 'authorize/continue failed',
      );
    }
    _record('POST', '/oauth/authorize/continue', res.statusCode, sw.elapsedMilliseconds);
    final redirectUrl = body['redirect_url'] as String?;
    if (redirectUrl == null || redirectUrl.isEmpty) {
      throw AuthApiException(res.statusCode, 'No redirect_url in response');
    }
    return redirectUrl;
  }

  /// Fetch the customer's accounts at this Data Provider for the FDX consent
  /// screen's account selection step (FDX UX Guidelines §3.1.6 "Select
  /// Accounts"). Called from the consent page on the provider's auth domain.
  Future<List<Map<String, dynamic>>> fetchConsentAccounts({
    required String userId,
    required String sessionToken,
  }) async {
    final sw = Stopwatch()..start();
    final res = await _client.get(
      Uri.parse('$baseUrl/v1/auth/consent/accounts?user_id=$userId&session_token=${Uri.encodeComponent(sessionToken)}'),
      headers: _getHeaders,
    );
    sw.stop();
    if (res.statusCode >= 400) {
      _recordError('GET', '/v1/auth/consent/accounts', res.statusCode, sw.elapsedMilliseconds);
      return [];
    }
    _record('GET', '/v1/auth/consent/accounts', res.statusCode, sw.elapsedMilliseconds);
    final body = _decode(res);
    final accounts = body['accounts'];
    if (accounts is List) {
      return accounts.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Map<String, dynamic> _decode(http.Response res) {
    if (res.body.isEmpty) return {};
    try {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}

/// Sign-in response from POST /v1/sign-in.
class SignInResponse {
  final String userId;
  final String sessionId;
  final String token;
  final String email;
  final bool mfaRequired;

  const SignInResponse({
    required this.userId,
    required this.sessionId,
    required this.token,
    required this.email,
    this.mfaRequired = false,
  });

  factory SignInResponse.fromJson(Map<String, dynamic> json) => SignInResponse(
        userId: json['user_id'] as String? ?? '',
        sessionId: json['session_id'] as String? ?? '',
        token: json['token'] as String? ?? '',
        email: json['email'] as String? ?? '',
        mfaRequired: json['mfa_required'] as bool? ?? json['mfa_required'] as bool? ?? false,
      );
}

/// Sign-up response from POST /v1/sign-up.
class SignUpResponse {
  final String userId;
  final String sessionId;
  final String token;
  final String email;

  const SignUpResponse({
    required this.userId,
    required this.sessionId,
    required this.token,
    required this.email,
  });

  factory SignUpResponse.fromJson(Map<String, dynamic> json) => SignUpResponse(
        userId: json['user_id'] as String? ?? '',
        sessionId: json['session_id'] as String? ?? '',
        token: json['token'] as String? ?? '',
        email: json['email'] as String? ?? '',
      );
}

/// Session response from GET /v1/session.
class SessionResponse {
  final String userId;
  final String email;
  final String? firstName;
  final String? lastName;
  /// Session token id — the CSRF header value (SEC-2.4.4) for
  /// cookie-authenticated mutations after a page reload. Empty when the
  /// server did not include it (pre-1.2.2 responses).
  final String sessionToken;

  const SessionResponse({
    required this.userId,
    required this.email,
    this.firstName,
    this.lastName,
    this.sessionToken = '',
  });

  factory SessionResponse.fromJson(Map<String, dynamic> json) => SessionResponse(
        userId: json['user_id'] as String? ?? '',
        email: json['email'] as String? ?? '',
        firstName: json['first_name'] as String?,
        lastName: json['last_name'] as String?,
        sessionToken: json['session_token'] as String? ?? '',
      );
}

/// Exception thrown when an Auth API request fails.
class AuthApiException implements Exception {
  final int statusCode;
  final String message;
  AuthApiException(this.statusCode, this.message);
  @override
  String toString() => message;
}

// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:AuthUI
// SPDX-License-Identifier: Apache-2.0

// Auth UI observability - structured logging, metrics, traces, alerts.
//
// All logs carry correlation IDs for traceability across the Flutter →
// Auth Rust server boundary. Correlation IDs are generated on the
// Flutter side and sent as `x-sentin8-correlation-id` on every Auth request.
// The Rust `sentin8-middleware::correlation_id` middleware reads this header
// and stamps it on every log line in the request's downstream path.
//
// Stories: 4.1.1-4.1.5 (auth hosted UI observability)

import 'dart:math';

/// Session-scoped correlation ID. Generated once per app session and
/// stamped on every outgoing request as `x-sentin8-correlation-id`.
///
/// To track a sub-flow within a session (e.g. "sign in" → "verify MFA"),
/// callers can pass an explicit [correlationId] to API helpers - the
/// default behaviour reuses the session-level ID.
String _sessionCorrelationId = _newCorrelationId();

String get sessionCorrelationId => _sessionCorrelationId;

String generateCorrelationId() => _newCorrelationId();

String _newCorrelationId() {
  final now = DateTime.now().microsecondsSinceEpoch;
  final rng = Random();
  // Use nextDouble + multiply instead of nextInt(1 << 32) because the
  // latter gets miscompiled by dart2js (1 << 32 wraps to 1 in JS).
  // 53-bit mantissa of double gives us plenty of entropy for an ID.
  final tail = (rng.nextDouble() * 0xFFFFFFFF).toInt().toRadixString(36);
  return 'a8u-$now-$tail';
}

/// Reset the session correlation ID. Useful after sign-in/sign-out so
/// the new session's logs don't share an ID with the previous one.
void resetSessionCorrelationId() {
  _sessionCorrelationId = _newCorrelationId();
}

/// Structured log entry with correlation ID.
class LogEntry {
  final String level; // INFO, WARN, ERROR
  final String message;
  final String correlationId;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;
  final String? service;

  const LogEntry({
    required this.level,
    required this.message,
    required this.correlationId,
    required this.timestamp,
    this.metadata,
    this.service,
  });

  Map<String, dynamic> toJson() => {
        'level': level,
        'message': message,
        'correlation_id': correlationId,
        'timestamp': timestamp.toIso8601String(),
        'service': service ?? 'auth-ui',
        if (metadata != null) 'metadata': metadata,
      };
}

/// In-memory structured logger for the Auth hosted UI.
class AuthUiLogger {
  static final List<LogEntry> _entries = [];
  static const int _maxEntries = 500;

  static void info(String message,
      {String? correlationId,
      Map<String, dynamic>? metadata,
      String? service}) {
    _log('INFO', message, correlationId, metadata, service);
  }

  static void warn(String message,
      {String? correlationId,
      Map<String, dynamic>? metadata,
      String? service,
      Object? error,
      StackTrace? stackTrace}) {
    final meta = <String, dynamic>{
      if (metadata != null) ...metadata,
      if (error != null) 'error': error.toString(),
      if (stackTrace != null) 'stack': stackTrace.toString(),
    };
    _log('WARN', message, correlationId, meta.isEmpty ? null : meta, service);
  }

  static void error(String message,
      {String? correlationId,
      Map<String, dynamic>? metadata,
      String? service,
      Object? error,
      StackTrace? stackTrace}) {
    final meta = <String, dynamic>{
      if (metadata != null) ...metadata,
      if (error != null) 'error': error.toString(),
      if (stackTrace != null) 'stack': stackTrace.toString(),
    };
    _log('ERROR', message, correlationId, meta.isEmpty ? null : meta, service);
  }

  static void _log(String level, String message, String? correlationId,
      Map<String, dynamic>? metadata, String? service) {
    final entry = LogEntry(
      level: level,
      message: message,
      correlationId: correlationId ?? _sessionCorrelationId,
      timestamp: DateTime.now(),
      metadata: metadata,
      service: service,
    );
    _entries.add(entry);
    if (_entries.length > _maxEntries) _entries.removeAt(0);

    // Print to browser console (DevTools) with correlation_id so e2e tests
    // and operators can see what's happening from the frontend.
    // ignore: avoid_print
    print('[${entry.level}] ${entry.timestamp.toIso8601String()} '
        '[${entry.correlationId}] ${entry.service} '
        '$message'
        '${entry.metadata == null ? '' : ' ${entry.metadata}'}');
  }

  static List<LogEntry> get entries => List.unmodifiable(_entries);
}

/// Metrics counters for the Auth hosted UI.
class AuthUiMetrics {
  int _signInAttempts = 0;
  int _signInSuccesses = 0;
  int _signUpAttempts = 0;
  int _signUpSuccesses = 0;
  int _mfaAttempts = 0;
  int _mfaSuccesses = 0;
  int _passwordResetRequests = 0;
  int _emailVerifyAttempts = 0;
  int _apiErrors = 0;
  final Map<String, int> _errorsByEndpoint = {};

  // Latency tracking
  final Map<String, List<int>> _apiLatencies = {};

  void recordSignInAttempt() => _signInAttempts++;
  void recordSignInSuccess() => _signInSuccesses++;
  void recordSignUpAttempt() => _signUpAttempts++;
  void recordSignUpSuccess() => _signUpSuccesses++;
  void recordMfaAttempt() => _mfaAttempts++;
  void recordMfaSuccess() => _mfaSuccesses++;
  void recordPasswordResetRequest() => _passwordResetRequests++;
  void recordEmailVerifyAttempt() => _emailVerifyAttempts++;

  void recordApiError(String endpoint) {
    _apiErrors++;
    _errorsByEndpoint[endpoint] = (_errorsByEndpoint[endpoint] ?? 0) + 1;
  }

  void recordApiLatency(String endpoint, int milliseconds) {
    _apiLatencies.putIfAbsent(endpoint, () => []).add(milliseconds);
    if (_apiLatencies[endpoint]!.length > 100) {
      _apiLatencies[endpoint]!.removeAt(0);
    }
  }

  double get signInSuccessRate =>
      _signInAttempts > 0 ? _signInSuccesses / _signInAttempts : 0;
  double get signUpConversionRate =>
      _signUpAttempts > 0 ? _signUpSuccesses / _signUpAttempts : 0;
  double get mfaSuccessRate =>
      _mfaAttempts > 0 ? _mfaSuccesses / _mfaAttempts : 0;
  int get apiErrorCount => _apiErrors;

  Map<String, double> get averageLatencies {
    final result = <String, double>{};
    _apiLatencies.forEach((endpoint, latencies) {
      if (latencies.isNotEmpty) {
        result[endpoint] =
            latencies.reduce((a, b) => a + b) / latencies.length;
      }
    });
    return result;
  }

  Map<String, dynamic> toJson() => {
        'signInSuccessRate': signInSuccessRate,
        'signUpConversionRate': signUpConversionRate,
        'mfaSuccessRate': mfaSuccessRate,
        'apiErrorCount': _apiErrors,
        'errorsByEndpoint': Map.of(_errorsByEndpoint),
        'averageLatencies': averageLatencies,
      };
}

/// Alert configuration for the Auth hosted UI. Tracks recent failures
/// in a sliding window and emits warnings via [AuthUiLogger] when
/// thresholds are crossed.
class AuthUiAlerts {
  static const int authFailureThreshold = 5;
  static const int apiErrorThreshold = 10;
  static const Duration window = Duration(minutes: 5);

  final List<DateTime> _authFailures = [];
  final List<DateTime> _apiErrors = [];

  void recordAuthFailure() {
    _authFailures.add(DateTime.now());
    _prune(_authFailures);
    if (_authFailures.length >= authFailureThreshold) {
      AuthUiLogger.warn(
        'Auth failure spike detected: ${_authFailures.length} failures in $window',
      );
    }
  }

  void recordApiError(String endpoint) {
    _apiErrors.add(DateTime.now());
    _prune(_apiErrors);
    if (_apiErrors.length >= apiErrorThreshold) {
      AuthUiLogger.warn(
        'Auth API error spike: ${_apiErrors.length} errors in $window (latest endpoint=$endpoint)',
      );
    }
  }

  void _prune(List<DateTime> events) {
    final cutoff = DateTime.now().subtract(window);
    events.removeWhere((e) => e.isBefore(cutoff));
  }
}

/// Global alert tracker instance.
final authUiAlerts = AuthUiAlerts();

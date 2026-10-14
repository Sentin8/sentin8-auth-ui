// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:AuthUI
// SPDX-License-Identifier: Apache-2.0

// Passkey enrollment/verification page — Story 1.2.6
//
// Provides a UI for enrolling a new passkey (WebAuthn) and verifying with
// an existing passkey during sign-in. Uses the browser's WebAuthn API
// (navigator.credentials) via JS interop.

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Passkey enrollment page.
///
/// Calls `POST /v1/passkey/enroll/begin` to get the WebAuthn challenge,
/// then uses `navigator.credentials.create()` to enroll the passkey, and
/// `POST /v1/passkey/enroll/finish` to send the attestation back to the server.
class PasskeyEnrollPage extends StatefulWidget {
  final String? sessionToken;
  final VoidCallback? onSuccess;

  const PasskeyEnrollPage({super.key, this.sessionToken, this.onSuccess});

  @override
  State<PasskeyEnrollPage> createState() => _PasskeyEnrollPageState();
}

class _PasskeyEnrollPageState extends State<PasskeyEnrollPage> {
  bool _loading = false;
  String? _error;

  Future<void> _enroll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 1. Begin enrollment — fetch challenge from server.
      final beginResp = await web.window.fetch(
        '/v1/passkey/enroll/begin'.toJS,
        web.RequestInit(
          method: 'POST',
          credentials: 'include',
          headers: _jsonHeaders(),
          body: jsonEncode({'authenticator_attachment': 'platform'}).toJS,
        ),
      ).toDart;

      if (beginResp.status != 200) {
        throw Exception('Failed to begin passkey enrollment');
      }

      final beginData = jsonDecode((await beginResp.text().toDart).toDart)
          as Map<String, dynamic>;

      // 2. Build the WebAuthn PublicKeyCredentialCreationOptions.
      final challenge = _base64UrlDecode(beginData['challenge'] as String);
      final userId = _base64UrlDecode(beginData['user_id'] as String);

      final publicKeyOptions = {
        'challenge': challenge,
        'rp': {'name': beginData['rp_name']},
        'user': {
          'id': userId,
          'name': beginData['user_name'],
          'display_name': beginData['user_display_name'],
        },
        'pub_key_cred_params': beginData['pub_key_cred_params'] ?? [],
        'timeout': beginData['timeout'] ?? 60000,
        'authenticator_selection': {
          'authenticator_attachment': 'platform',
          'user_verification': 'required',
        },
      };

      // 3. Call navigator.credentials.create() via JS interop.
      final credential = await _webAuthnCreate(publicKeyOptions);

      // 4. Send the attestation to the server.
      final finishResp = await web.window.fetch(
        '/v1/passkey/enroll/finish'.toJS,
        web.RequestInit(
          method: 'POST',
          credentials: 'include',
          headers: _jsonHeaders(),
          body: jsonEncode({
            'challenge_id': beginData['challenge_id'],
            'credential': credential,
          }).toJS,
        ),
      ).toDart;

      if (finishResp.status != 200) {
        throw Exception('Failed to finish passkey enrollment');
      }

      if (mounted) {
        widget.onSuccess?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Passkey enrolled successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.key, size: 48),
            const SizedBox(height: 16),
            const Text('Enroll a Passkey',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text(
              'Add a passkey for faster, passwordless sign-in.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            if (_loading)
              const CircularProgressIndicator()
            else
              FilledButton(
                onPressed: _enroll,
                child: const Text('Enroll Passkey'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Passkey verification page (for sign-in with a passkey).
class PasskeyVerifyPage extends StatefulWidget {
  final String email;
  final VoidCallback? onSuccess;

  const PasskeyVerifyPage({super.key, required this.email, this.onSuccess});

  @override
  State<PasskeyVerifyPage> createState() => _PasskeyVerifyPageState();
}

class _PasskeyVerifyPageState extends State<PasskeyVerifyPage> {
  bool _loading = false;
  String? _error;

  Future<void> _verify() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 1. Begin verification.
      final beginResp = await web.window.fetch(
        '/v1/passkey/verify/begin'.toJS,
        web.RequestInit(
          method: 'POST',
          credentials: 'include',
          headers: _jsonHeaders(),
          body: jsonEncode({'email': widget.email}).toJS,
        ),
      ).toDart;

      if (beginResp.status != 200) {
        throw Exception('Failed to begin passkey verification');
      }

      final beginData = jsonDecode((await beginResp.text().toDart).toDart)
          as Map<String, dynamic>;

      // 2. Build WebAuthn PublicKeyCredentialRequestOptions.
      final challenge = _base64UrlDecode(beginData['challenge'] as String);
      final publicKeyOptions = {
        'challenge': challenge,
        'rp_id': beginData['rp_id'],
        'timeout': beginData['timeout'] ?? 60000,
        'user_verification': 'required',
      };

      // 3. Call navigator.credentials.get().
      final assertion = await _webAuthnGet(publicKeyOptions);

      // 4. Send assertion to server.
      final finishResp = await web.window.fetch(
        '/v1/passkey/verify/finish'.toJS,
        web.RequestInit(
          method: 'POST',
          credentials: 'include',
          headers: _jsonHeaders(),
          body: jsonEncode({
            'challenge_id': beginData['challenge_id'],
            'assertion': assertion,
          }).toJS,
        ),
      ).toDart;

      if (finishResp.status != 200) {
        throw Exception('Passkey verification failed');
      }

      if (mounted) {
        widget.onSuccess?.call();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.fingerprint, size: 48),
            const SizedBox(height: 16),
            const Text('Sign in with Passkey',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('Authenticating as ${widget.email}...',
                style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 24),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            if (_loading)
              const CircularProgressIndicator()
            else
              FilledButton(
                onPressed: _verify,
                child: const Text('Verify with Passkey'),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────

Map<String, String> _jsonHeaders() => {'content-type': 'application/json'};

/// Decode a base64url string to a Uint8List (for WebAuthn challenge).
Uint8List _base64UrlDecode(String b64url) {
  // Pad to multiple of 4.
  final padded = b64url.replaceAll('-', '+').replaceAll('_', '/');
  final pad = padded.length % 4;
  final finalStr = pad == 0 ? padded : '$padded${'=' * (4 - pad)}';
  return Uint8List.fromList(base64Decode(finalStr));
}

/// Call navigator.credentials.create() via JS interop.
Future<Map<String, dynamic>> _webAuthnCreate(Map<String, dynamic> options) async {
  // Use the browser's WebAuthn API via JS interop.
  // This is a simplified implementation — a full implementation would
  // use the `web` package's WebAuthn bindings or a JS interop wrapper.
  final jsOptions = jsonEncode(options).jsify();
  final credPromise = web.window
      .getProperty('navigator'.toJS)
      .getProperty('credentials'.toJS)
      .callMethod('create'.toJS, [jsOptions]);
  final credential = await credPromise.toDart as web.JSObject;
  // Extract credential fields for the server.
  return {
    'id': (credential.getProperty('id'.toJS) as web.JSString).toDart,
    'raw_id': _arrayBufferToBase64Url(credential.getProperty('rawId'.toJS)),
    'type': (credential.getProperty('type'.toJS) as web.JSString).toDart,
    'response': {
      'attestation_object': _arrayBufferToBase64Url(
          credential.getProperty('response'.toJS).getProperty('attestationObject'.toJS)),
      'client_data_json': _arrayBufferToBase64Url(
          credential.getProperty('response'.toJS).getProperty('clientDataJSON'.toJS)),
    },
  };
}

/// Call navigator.credentials.get() via JS interop.
Future<Map<String, dynamic>> _webAuthnGet(Map<String, dynamic> options) async {
  final jsOptions = jsonEncode(options).jsify();
  final credPromise = web.window
      .getProperty('navigator'.toJS)
      .getProperty('credentials'.toJS)
      .callMethod('get'.toJS, [jsOptions]);
  final credential = await credPromise.toDart as web.JSObject;
  return {
    'id': (credential.getProperty('id'.toJS) as web.JSString).toDart,
    'raw_id': _arrayBufferToBase64Url(credential.getProperty('rawId'.toJS)),
    'type': (credential.getProperty('type'.toJS) as web.JSString).toDart,
    'response': {
      'authenticator_data': _arrayBufferToBase64Url(
          credential.getProperty('response'.toJS).getProperty('authenticatorData'.toJS)),
      'client_data_json': _arrayBufferToBase64Url(
          credential.getProperty('response'.toJS).getProperty('clientDataJSON'.toJS)),
      'signature': _arrayBufferToBase64Url(
          credential.getProperty('response'.toJS).getProperty('signature'.toJS)),
      'user_handle': _arrayBufferToBase64Url(
          credential.getProperty('response'.toJS).getProperty('userHandle'.toJS)),
    },
  };
}

/// Convert an ArrayBuffer/JSArrayBuffer to base64url.
String _arrayBufferToBase64Url(web.JSValue buffer) {
  // Convert ArrayBuffer to Uint8List then base64url.
  final arrayBuffer = buffer as web.JSArrayBuffer;
  final byteLength = arrayBuffer.byteLength;
  final uint8Array = web.Uint8Array(byteLength);
  uint8Array.set(arrayBuffer);
  // Use dart:js_interop to read bytes.
  final bytes = Uint8List(byteLength);
  for (var i = 0; i < byteLength; i++) {
    bytes[i] = uint8Array.getProperty('${i}'.toJS) as int;
  }
  return base64UrlEncode(bytes).replaceAll('=', '');
}
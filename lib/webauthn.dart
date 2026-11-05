// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:AuthUI
// SPDX-License-Identifier: Apache-2.0

// Typed WebAuthn browser bindings for the hosted UI.
//
// Wraps package:web's generated WebAuthn types (webauthn.dart /
// credential_management.dart) behind small, Dart-shaped helpers used by
// the sign-in flow's passkey step. The server owns ALL verification
// (challenge, origin, rpIdHash, signature, counter); this module only
// marshals the browser ceremony.
//
// The former passkey_page.dart carried JS-unsafe getProperty/callMethod
// helpers and was wire-mismatched with the API (it POSTed `{email}` to
// verify/begin and nested the assertion object) - dead prototype code,
// replaced by these typed bindings.

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

/// The begin answer from `POST /v1/passkey/sign-in/begin`.
class PasskeySignInBegin {
  final String challenge;
  final String rpId;
  final String challengeId;
  final int timeout;
  final String userVerification;
  final List<String> allowCredentials;

  const PasskeySignInBegin({
    required this.challenge,
    required this.rpId,
    required this.challengeId,
    required this.timeout,
    required this.userVerification,
    required this.allowCredentials,
  });

  factory PasskeySignInBegin.fromJson(Map<String, dynamic> json) =>
      PasskeySignInBegin(
        challenge: json['challenge'] as String? ?? '',
        rpId: json['rp_id'] as String? ?? '',
        challengeId: json['challenge_id'] as String? ?? '',
        timeout: json['timeout'] as int? ?? 60000,
        userVerification: json['user_verification'] as String? ?? 'required',
        allowCredentials: (json['allow_credentials'] as List<dynamic>? ?? [])
            .map((e) => e as String)
            .toList(),
      );
}

/// The assertion the finish endpoint expects (flat
/// `VerifyFinishRequest` shape - challenge_id + the four ceremony
/// fields, all base64url).
class PasskeyAssertion {
  final String challengeId;
  final String credentialId;
  final String authenticatorData;
  final String clientDataJson;
  final String signature;

  const PasskeyAssertion({
    required this.challengeId,
    required this.credentialId,
    required this.authenticatorData,
    required this.clientDataJson,
    required this.signature,
  });

  Map<String, dynamic> toJson() => {
        'challenge_id': challengeId,
        'credential_id': credentialId,
        'authenticator_data': authenticatorData,
        'client_data_json': clientDataJson,
        'signature': signature,
      };
}

/// Run the WebAuthn `navigator.credentials.get()` assertion ceremony
/// with the begin answer's options (a targeted ceremony - the server
/// sent `allowCredentials`).
///
/// Throws on a user cancellation (NotAllowedError) or any browser
/// ceremony failure; the caller surfaces a friendly retry.
Future<PasskeyAssertion> getAssertion(PasskeySignInBegin begin) async {
  final challenge = _base64UrlDecode(begin.challenge);
  final allowCredentials = begin.allowCredentials
      .map(
        (id) => web.PublicKeyCredentialDescriptor(
          id: _base64UrlDecode(id).toJS,
          type: 'public-key',
        ),
      )
      .toList()
      .toJS;

  final options = web.PublicKeyCredentialRequestOptions(
    challenge: challenge.toJS,
    rpId: begin.rpId,
    timeout: begin.timeout,
    userVerification: begin.userVerification,
    allowCredentials: allowCredentials,
  );
  final requestOptions = web.CredentialRequestOptions(publicKey: options);
  final credential = await web.window.navigator.credentials
      .get(requestOptions)
      .toDart;
  final pk = credential as web.PublicKeyCredential;
  final assertion = pk.response as web.AuthenticatorAssertionResponse;

  return PasskeyAssertion(
    challengeId: begin.challengeId,
    credentialId: _base64UrlEncode(pk.rawId.toDart.asUint8List()),
    authenticatorData: _base64UrlEncode(
        assertion.authenticatorData.toDart.asUint8List()),
    clientDataJson: _base64UrlEncode(assertion.clientDataJSON.toDart.asUint8List()),
    signature: _base64UrlEncode(assertion.signature.toDart.asUint8List()),
  );
}

// ── base64url helpers (no padding - the WebAuthn wire format) ─────────

Uint8List _base64UrlDecode(String b64url) {
  final normalized = b64url.replaceAll('-', '+').replaceAll('_', '/');
  final padded = normalized.padRight(
      (normalized.length + 3) ~/ 4 * 4, '=');
  return base64Decode(padded);
}

String _base64UrlEncode(Uint8List bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

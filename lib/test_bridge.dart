// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:AuthUI
// SPDX-License-Identifier: Apache-2.0

// Sentin8 Auth UI — Test bridge for e2e automation.
//
// E2e tests interact with the app through the UI — clicking buttons,
// typing into fields — but Flutter CanvasKit's HTML input overlays are
// unreliable for Playwright's fill(). These bridge functions set
// TextEditingController values directly in Dart and call the same
// widget methods as clicking the submit button. No direct API calls
// are made from the test.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;

// Global handler functions set by each page's initState.
void Function(String, String, String, String)? _signUpHandler;
void Function(String, String)? _signInHandler;
void Function()? _denyHandler;
void Function()? _consentApproveHandler;
void Function()? _consentDenyHandler;

// Called by the Flutter app in main() to expose the bridge on window.
void registerTestBridge() {
  final w = web.window as JSObject;
  w.setProperty(
    'sentin8TestSignUp'.toJS,
    ((String email, String firstName, String lastName, String password) {
      if (_signUpHandler != null) {
        _signUpHandler!(email, firstName, lastName, password);
        return true;
      }
      return false;
    }).toJS,
  );

  w.setProperty(
    'sentin8TestSignIn'.toJS,
    ((String email, String password) {
      if (_signInHandler != null) {
        _signInHandler!(email, password);
        return true;
      }
      return false;
    }).toJS,
  );

  w.setProperty(
    'sentin8TestDeny'.toJS,
    (() {
      if (_denyHandler != null) {
        _denyHandler!();
        return true;
      }
      return false;
    }).toJS,
  );

  w.setProperty(
    'sentin8TestConsentApprove'.toJS,
    (() {
      if (_consentApproveHandler != null) {
        _consentApproveHandler!();
        return true;
      }
      return false;
    }).toJS,
  );

  w.setProperty(
    'sentin8TestConsentDeny'.toJS,
    (() {
      if (_consentDenyHandler != null) {
        _consentDenyHandler!();
        return true;
      }
      return false;
    }).toJS,
  );

  w.setProperty(
    'sentin8TestNavigate'.toJS,
    ((String path) {
      web.window.location.href = path;
      return true;
    }).toJS,
  );
}

void setDenyHandler(void Function()? handler) {
  _denyHandler = handler;
}

void setConsentHandlers({
  void Function()? approve,
  void Function()? deny,
}) {
  _consentApproveHandler = approve;
  _consentDenyHandler = deny;
}

void setSignUpHandler(void Function(String, String, String, String)? handler) {
  _signUpHandler = handler;
}

void setSignInHandler(void Function(String, String)? handler) {
  _signInHandler = handler;
}
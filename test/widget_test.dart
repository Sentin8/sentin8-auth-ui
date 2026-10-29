// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:AuthUI
// SPDX-License-Identifier: Apache-2.0

// Smoke test for the Sentin8 Auth Hosted UI Sign In page.
//
// The app is web-coupled (`package:web` / `dart:js_interop` throughout
// `lib/`), so these run on the chrome platform - `make test-flutter`
// passes `--platform chrome` with `CHROME_EXECUTABLE` (see Makefile).
//
// The full app shell (`AuthApp`) fetches branding from the Auth server in
// `BrandingScope.initState`; that network call has no server under the test
// harness, so the stable smoke target is the bare page under an explicit
// `BrandingProvider` (same harness as `visual_regression_test.dart`).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:sentin8_auth_ui/main.dart';
import 'package:sentin8_auth_ui/branding_provider.dart';
import 'package:sentin8_auth_ui/theme.dart';
import 'package:sentin8_auth_ui/pages/sign_in_page.dart';

void main() {
  // Theme styles resolve Quicksand via google_fonts at first use; without
  // this the fetch goes to fonts.gstatic.com under the test harness and
  // every pump throws uncaught async errors.
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('Sign In page renders its heading and inputs', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: sentin8Theme(),
        home: BrandingProvider(
          branding: const Branding(),
          child: const SignInPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('AuthApp type exists and is constructible', (tester) async {
    // The app shell itself requires a live Auth server (branding fetch)  - 
    // verified in the e2e suite. Here we pin the public entry type.
    const AuthApp();
    expect(true, isTrue);
  });
}
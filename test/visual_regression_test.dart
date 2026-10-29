// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:AuthUI
// SPDX-License-Identifier: Apache-2.0

// Visual regression tests for Auth UI pages - Story 1.2.14
//
// Tests that each page renders correctly with default branding and
// with custom org branding (primary color, accent color, organization
// name, logo URL, sign-in text).
//
// NOTE on package name: the pubspec package is `sentin8_auth_ui` (not
// `auth_ui`) - imports below must match. These tests run on the chrome
// platform (`flutter test --platform chrome`) because the app libs are
// web-coupled (`package:web` / `dart:js_interop`); `make test-flutter`
// handles this (see Makefile).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:sentin8_auth_ui/main.dart';
import 'package:sentin8_auth_ui/branding_provider.dart';
import 'package:sentin8_auth_ui/theme.dart';
import 'package:sentin8_auth_ui/pages/sign_in_page.dart';

/// Pump a bare SignInPage under the given branding - the app shell
/// (`AuthApp`) touches `window.location` and fetches branding from the
/// Auth server, which does not exist under the test harness. Pages read
/// branding via `BrandingProvider.of(context)`, so a bare page + explicit
/// provider + theme is the stable render target for visual assertions.
Widget brandingHarness(Branding branding) {
  return MaterialApp(
    theme: sentin8ThemeForBranding(branding),
    home: BrandingProvider(
      branding: branding,
      child: const SignInPage(),
    ),
  );
}

void main() {
  // Theme styles resolve Quicksand via google_fonts at first use; without
  // this the fetch goes to fonts.gstatic.com under the test harness and
  // every pump throws uncaught async errors.
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('Auth UI - Visual regression tests', () {
    testWidgets('Sign In page renders with default branding', (tester) async {
      await tester.pumpWidget(brandingHarness(const Branding()));
      await tester.pumpAndSettle();
      expect(find.text('Sign In'), findsOneWidget);
    });

    testWidgets('Sign In page renders with org name', (tester) async {
      await tester.pumpWidget(
        brandingHarness(const Branding(organizationName: 'Acme Corp')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sign in to Acme Corp'), findsOneWidget);
    });

    testWidgets('Sign In page renders with signInText override', (
      tester,
    ) async {
      await tester.pumpWidget(
        brandingHarness(const Branding(signInText: 'Welcome back')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('Theme uses branding primary color', (tester) async {
      final branding = const Branding(primaryColor: '#FF0000');
      final theme = sentin8ThemeForBranding(branding);
      expect(theme.colorScheme.primary, const Color(0xFFFF0000));
    });

    testWidgets('Theme uses branding accent color', (tester) async {
      final branding = const Branding(accentColor: '#00FF00');
      final theme = sentin8ThemeForBranding(branding);
      expect(theme.colorScheme.secondary, const Color(0xFF00FF00));
    });

    testWidgets('Light theme selected when themeMode is light', (
      tester,
    ) async {
      final branding = const Branding(themeMode: 'light');
      final theme = sentin8ThemeForBranding(branding);
      expect(theme.brightness, Brightness.light);
    });

    testWidgets('Dark theme is the default (no themeMode)', (tester) async {
      final theme = sentin8ThemeForBranding(const Branding());
      expect(theme.brightness, Brightness.dark);
    });

    testWidgets('Dark theme selected when themeMode is dark', (tester) async {
      final branding = const Branding(themeMode: 'dark');
      final theme = sentin8ThemeForBranding(branding);
      expect(theme.brightness, Brightness.dark);
    });

    testWidgets('Branding hasLogo is true when logoUrl is set', (
      tester,
    ) async {
      const branding = Branding(logoUrl: 'https://example.com/logo.png');
      expect(branding.hasLogo, isTrue);
    });

    testWidgets('Branding hasLogoIcon is true when logoIconUrl is set', (
      tester,
    ) async {
      const branding = Branding(logoIconUrl: 'https://example.com/icon.png');
      expect(branding.hasLogoIcon, isTrue);
    });

    testWidgets('Branding primaryColorValue parses hex', (tester) async {
      const branding = Branding(primaryColor: '#FF0000');
      expect(branding.primaryColorValue, const Color(0xFFFF0000));
    });

    testWidgets('Branding falls back to gold when no primaryColor', (
      tester,
    ) async {
      const branding = Branding();
      expect(branding.primaryColorValue, const Color(0xFFD4AF37));
    });
  });
}
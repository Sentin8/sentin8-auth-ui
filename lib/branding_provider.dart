// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:AuthUI
// SPDX-License-Identifier: Apache-2.0

// Branding provider — fetches merged org+env branding from the Auth
// server and exposes it to the Flutter UI.
//
// The Auth server resolves the tenant from TLS headers and queries
// sys_branding to return the merged branding. If no tenant is resolved
// (platform auth), empty branding is returned and the UI uses defaults.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Branding data for the current tenant.
class Branding {
  final String logoUrl;
  final String logoIconUrl;
  final String primaryColor;
  final String accentColor;
  final String fontFamily;
  final String themeMode;
  final String customCss;
  final String signInText;
  final String organizationName;

  const Branding({
    this.logoUrl = '',
    this.logoIconUrl = '',
    this.primaryColor = '',
    this.accentColor = '',
    this.fontFamily = '',
    this.themeMode = '',
    this.customCss = '',
    this.signInText = '',
    this.organizationName = '',
  });

  bool get hasLogo => logoUrl.isNotEmpty;
  bool get hasLogoIcon => logoIconUrl.isNotEmpty;
  bool get hasPrimaryColor => primaryColor.isNotEmpty;
  bool get hasAccentColor => accentColor.isNotEmpty;
  bool get hasFontFamily => fontFamily.isNotEmpty;
  bool get hasThemeMode => themeMode.isNotEmpty;
  bool get hasSignInText => signInText.isNotEmpty;
  bool get hasOrganizationName => organizationName.isNotEmpty;
  bool get isLightTheme => themeMode == 'light';
  bool get isDarkTheme => themeMode == 'dark';

  /// Parse the primary color hex string to a Color, falling back to gold.
  Color get primaryColorValue => _parseColor(primaryColor);
  /// Parse the accent color hex string to a Color, falling back to light gold.
  Color get accentColorValue => _parseColor(accentColor);

  static Color _parseColor(String hex) {
    if (hex.isEmpty) return const Color(0xFFD4AF37); // Royal Gold default
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return const Color(0xFFD4AF37);
    }
  }
}

/// InheritedWidget that provides branding to descendant widgets.
class BrandingProvider extends InheritedWidget {
  final Branding branding;
  const BrandingProvider({
    super.key,
    required this.branding,
    required super.child,
  });

  static Branding of(BuildContext context) {
    final w = context.dependOnInheritedWidgetOfExactType<BrandingProvider>();
    return w?.branding ?? const Branding();
  }

  @override
  bool updateShouldNotify(BrandingProvider oldWidget) =>
      branding.logoUrl != oldWidget.branding.logoUrl ||
      branding.logoIconUrl != oldWidget.branding.logoIconUrl ||
      branding.primaryColor != oldWidget.branding.primaryColor ||
      branding.accentColor != oldWidget.branding.accentColor ||
      branding.fontFamily != oldWidget.branding.fontFamily ||
      branding.themeMode != oldWidget.branding.themeMode ||
      branding.signInText != oldWidget.branding.signInText ||
      branding.organizationName != oldWidget.branding.organizationName;
}

/// Stateful wrapper that fetches branding on startup and provides it
/// to the child widget tree via [BrandingProvider].
class BrandingScope extends StatefulWidget {
  final Widget child;
  const BrandingScope({super.key, required this.child});

  @override
  State<BrandingScope> createState() => _BrandingScopeState();
}

class _BrandingScopeState extends State<BrandingScope> {
  Branding _branding = const Branding();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _fetchBranding();
  }

  Future<void> _fetchBranding() async {
    try {
      final response = await web.window.fetch(
        '/v1/branding'.toJS,
        web.RequestInit(method: 'GET', credentials: 'include'),
      ).toDart;
      if (response.status == 200) {
        final raw = (await response.text().toDart).toDart;
        final data = jsonDecode(raw) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _branding = Branding(
              logoUrl: data['logo_url'] as String? ?? '',
              logoIconUrl: data['logo_icon_url'] as String? ?? '',
              primaryColor: data['primary_color'] as String? ?? '',
              accentColor: data['accent_color'] as String? ?? '',
              fontFamily: data['font_family'] as String? ?? '',
              themeMode: data['theme_mode'] as String? ?? '',
              customCss: data['custom_css'] as String? ?? '',
              signInText: data['sign_in_text'] as String? ?? '',
              organizationName: data['organization_name'] as String? ?? '',
            );
            _loaded = true;
          });
        }
      } else {
        if (mounted) setState(() => _loaded = true);
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show the app immediately with default branding, then update when
    // the fetch completes. This avoids blocking the UI on branding.
    return BrandingProvider(
      branding: _branding,
      child: widget.child,
    );
  }
}
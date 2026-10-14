// SPDX-FileCopyrightText: Copyright Logically Magic Inc. <hello@logicallymagic.com>
// SPDX-FileCopyrightText: Copyright Hamid Jahanzad <Hamid@Jahanzad.com>
// SPDX-FileCopyrightText: Copyright Contributors to the Sentin8:AuthUI
// SPDX-License-Identifier: Apache-2.0

// Sentin8 Auth UI — Design system theme.
// Implements the design system defined in design/sentin8-design-system.md.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'branding_provider.dart';

/// Resolves a tenant `fontFamily` branding string (e.g. "Inter", "Lato", or a
/// CSS-style "Inter, sans-serif") to a [TextTheme] with that Google Font
/// applied to every style. Returns `null` when [fontFamily] is empty, so the
/// caller can fall back to the default Material text theme.
///
/// The branding field may carry a CSS font-stack like `"Inter, sans-serif"`;
/// only the first token is used as the Google Font family name. When the name
/// isn't in the google_fonts catalog (or network fetching is blocked, e.g.
/// e2e), the font name is preserved on each [TextStyle.fontFamily] so a
/// preloaded web `@font-face` can still resolve it.
TextTheme? sentin8TextThemeForFont(String fontFamily, TextTheme base) {
  // Strip CSS fallbacks ("Inter, sans-serif" → "Inter") and surrounding quotes.
  final family = fontFamily
      .split(',')
      .first
      .trim()
      .replaceAll("'", '')
      .replaceAll('"', '');
  if (family.isEmpty) return null;
  try {
    return GoogleFonts.getTextTheme(family, base);
  } catch (_) {
    // Unknown font family — fall back to the system font but still set the
    // fontFamily hint so a web @font-face can pick it up if preloaded.
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(fontFamily: family),
      displayMedium: base.displayMedium?.copyWith(fontFamily: family),
      displaySmall: base.displaySmall?.copyWith(fontFamily: family),
      headlineLarge: base.headlineLarge?.copyWith(fontFamily: family),
      headlineMedium: base.headlineMedium?.copyWith(fontFamily: family),
      headlineSmall: base.headlineSmall?.copyWith(fontFamily: family),
      titleLarge: base.titleLarge?.copyWith(fontFamily: family),
      titleMedium: base.titleMedium?.copyWith(fontFamily: family),
      titleSmall: base.titleSmall?.copyWith(fontFamily: family),
      bodyLarge: base.bodyLarge?.copyWith(fontFamily: family),
      bodyMedium: base.bodyMedium?.copyWith(fontFamily: family),
      bodySmall: base.bodySmall?.copyWith(fontFamily: family),
      labelLarge: base.labelLarge?.copyWith(fontFamily: family),
      labelMedium: base.labelMedium?.copyWith(fontFamily: family),
      labelSmall: base.labelSmall?.copyWith(fontFamily: family),
    );
  }
}

/// Sentin8 color palette.
class Sentin8Colors {
  static const obsidianBlack = Color(0xFF0A0A0A);
  static const carbonBlack = Color(0xFF111111);
  static const matteGraphite = Color(0xFF1C1C1C);
  static const royalGold = Color(0xFFD4AF37);
  static const softGold = Color(0xFFE6C878);
  static const successGold = Color(0xFFC6A667);
  static const warningAmber = Color(0xFFFFB84D);
  static const errorCrimson = Color(0xFFD64545);
  static const infoSoftGold = Color(0xFFE8D9A8);
  static const textPrimary = Color(0xFFF0F0F0);
  static const textSecondary = Color(0xFFA0A0A0);
  static const textMuted = Color(0xFF6E6E6E);
  static const glassFill = Color(0x0FFFFFFF);
  static const glassBorder = Color(0x1AFFFFFF);

  // Light theme colors
  static const lightSurface = Color(0xFFF5F5F5);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightInputFill = Color(0xFFE8E8E8);
  static const lightBorder = Color(0xFFD0D0D0);
  static const lightTextPrimary = Color(0xFF1A1A1A);
  static const lightTextSecondary = Color(0xFF555555);
  static const lightTextMuted = Color(0xFF888888);
}

/// Sentin8 typography.
/// Uses Quicksand (via Google Fonts) to match the Dash app and the
/// Sentin8 brand wordmark.
class Sentin8Text {
  static TextStyle get h1 => GoogleFonts.quicksand(
      fontSize: 32, fontWeight: FontWeight.w600,
      color: Sentin8Colors.textPrimary, height: 1.2);
  static TextStyle get h2 => GoogleFonts.quicksand(
      fontSize: 24, fontWeight: FontWeight.w600,
      color: Sentin8Colors.textPrimary, height: 1.3);
  static TextStyle get h3 => GoogleFonts.quicksand(
      fontSize: 20, fontWeight: FontWeight.w500,
      color: Sentin8Colors.textPrimary, height: 1.4);
  static TextStyle get body => GoogleFonts.quicksand(
      fontSize: 15, fontWeight: FontWeight.w400,
      color: Sentin8Colors.textPrimary, height: 1.5);
  static TextStyle get bodySecondary => GoogleFonts.quicksand(
      fontSize: 15, fontWeight: FontWeight.w400,
      color: Sentin8Colors.textSecondary, height: 1.5);
  static TextStyle get caption => GoogleFonts.quicksand(
      fontSize: 12, fontWeight: FontWeight.w400,
      color: Sentin8Colors.textMuted, height: 1.4);
  static TextStyle get label => GoogleFonts.quicksand(
      fontSize: 12, fontWeight: FontWeight.w500,
      color: Sentin8Colors.textSecondary, height: 1.2);

  // Light theme variants
  static TextStyle get h1Light => GoogleFonts.quicksand(
      fontSize: 32, fontWeight: FontWeight.w600,
      color: Sentin8Colors.lightTextPrimary, height: 1.2);
  static TextStyle get h2Light => GoogleFonts.quicksand(
      fontSize: 24, fontWeight: FontWeight.w600,
      color: Sentin8Colors.lightTextPrimary, height: 1.3);
  static TextStyle get h3Light => GoogleFonts.quicksand(
      fontSize: 20, fontWeight: FontWeight.w500,
      color: Sentin8Colors.lightTextPrimary, height: 1.4);
  static TextStyle get bodyLight => GoogleFonts.quicksand(
      fontSize: 15, fontWeight: FontWeight.w400,
      color: Sentin8Colors.lightTextPrimary, height: 1.5);
  static TextStyle get bodySecondaryLight => GoogleFonts.quicksand(
      fontSize: 15, fontWeight: FontWeight.w400,
      color: Sentin8Colors.lightTextSecondary, height: 1.5);
  static TextStyle get captionLight => GoogleFonts.quicksand(
      fontSize: 12, fontWeight: FontWeight.w400,
      color: Sentin8Colors.lightTextMuted, height: 1.4);
  static TextStyle get labelLight => GoogleFonts.quicksand(
      fontSize: 12, fontWeight: FontWeight.w500,
      color: Sentin8Colors.lightTextSecondary, height: 1.2);
}

/// Sentin8 spacing (4px grid).
class Sentin8Spacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

/// Sentin8 border radii.
class Sentin8Radii {
  static const small = 4.0;
  static const medium = 8.0;
  static const large = 12.0;
  static const xl = 16.0;
}

/// Builds the Sentin8 dark theme.
/// When [primary]/[accent] are provided, they override the default gold
/// colors for buttons, focused borders, and other accent points.
ThemeData sentin8Theme({Color? primary, Color? accent}) {
  final p = primary ?? Sentin8Colors.royalGold;
  final a = accent ?? Sentin8Colors.softGold;
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: p,
      brightness: Brightness.dark,
    ).copyWith(
      surface: Sentin8Colors.obsidianBlack,
      primary: p,
      onPrimary: Sentin8Colors.obsidianBlack,
      secondary: a,
      error: Sentin8Colors.errorCrimson,
    ),
    scaffoldBackgroundColor: Sentin8Colors.obsidianBlack,
    cardColor: Sentin8Colors.carbonBlack,
    dividerColor: Sentin8Colors.glassBorder,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Sentin8Colors.matteGraphite,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Sentin8Radii.medium),
        borderSide: const BorderSide(color: Sentin8Colors.glassBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Sentin8Radii.medium),
        borderSide: const BorderSide(color: Sentin8Colors.glassBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Sentin8Radii.medium),
        borderSide: BorderSide(color: p, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Sentin8Radii.medium),
        borderSide: const BorderSide(color: Sentin8Colors.errorCrimson),
      ),
      labelStyle: GoogleFonts.quicksand(color: Sentin8Colors.textMuted),
      hintStyle: GoogleFonts.quicksand(color: Sentin8Colors.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p,
        foregroundColor: Sentin8Colors.obsidianBlack,
        minimumSize: const Size(double.infinity, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Sentin8Radii.medium)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p,
        side: BorderSide(color: p),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Sentin8Radii.medium)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: a),
    ),
    textTheme: GoogleFonts.quicksandTextTheme(
      ThemeData(brightness: Brightness.dark).textTheme,
    ),
  );
}

/// Builds the Sentin8 light theme (used when branding themeMode is 'light').
/// When [primary]/[accent] are provided, they override the default gold.
ThemeData sentin8LightTheme({Color? primary, Color? accent}) {
  final p = primary ?? Sentin8Colors.royalGold;
  final a = accent ?? Sentin8Colors.softGold;
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: p,
      brightness: Brightness.light,
    ).copyWith(
      surface: Sentin8Colors.lightSurface,
      primary: p,
      onPrimary: Sentin8Colors.obsidianBlack,
      secondary: a,
      error: Sentin8Colors.errorCrimson,
    ),
    scaffoldBackgroundColor: Sentin8Colors.lightSurface,
    cardColor: Sentin8Colors.lightCard,
    dividerColor: Sentin8Colors.lightBorder,
    textTheme: GoogleFonts.quicksandTextTheme(
      ThemeData(brightness: Brightness.light).textTheme,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Sentin8Colors.lightInputFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Sentin8Radii.medium),
        borderSide: const BorderSide(color: Sentin8Colors.lightBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Sentin8Radii.medium),
        borderSide: const BorderSide(color: Sentin8Colors.lightBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Sentin8Radii.medium),
        borderSide: BorderSide(color: p, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Sentin8Radii.medium),
        borderSide: const BorderSide(color: Sentin8Colors.errorCrimson),
      ),
      labelStyle: GoogleFonts.quicksand(color: Sentin8Colors.lightTextMuted),
      hintStyle: GoogleFonts.quicksand(color: Sentin8Colors.lightTextMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p,
        foregroundColor: Sentin8Colors.obsidianBlack,
        minimumSize: const Size(double.infinity, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Sentin8Radii.medium)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p,
        side: BorderSide(color: p),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Sentin8Radii.medium)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: p),
    ),
  );
}

/// Returns the appropriate theme based on branding themeMode and colors.
/// Defaults to dark theme with Sentin8 gold if no branding.
/// When branding provides primaryColor/accentColor, those are used
/// for buttons, focused borders, and other accent points.
/// When branding provides fontFamily, a Google Font text theme is applied.
ThemeData sentin8ThemeForBranding(Branding branding) {
  final primary = branding.hasPrimaryColor
      ? branding.primaryColorValue
      : Sentin8Colors.royalGold;
  final accent = branding.hasAccentColor
      ? branding.accentColorValue
      : Sentin8Colors.softGold;
  final base = branding.isLightTheme
      ? sentin8LightTheme(primary: primary, accent: accent)
      : sentin8Theme(primary: primary, accent: accent);
  if (!branding.hasFontFamily) return base;
  final themed = sentin8TextThemeForFont(branding.fontFamily, base.textTheme);
  return themed == null ? base : base.copyWith(textTheme: themed);
}

/// Returns the appropriate h2 style based on the current theme brightness.
TextStyle h2For(BuildContext context) {
  return Theme.of(context).brightness == Brightness.light
      ? Sentin8Text.h2Light
      : Sentin8Text.h2;
}

/// Returns the appropriate body style based on the current theme brightness.
TextStyle bodyFor(BuildContext context) {
  return Theme.of(context).brightness == Brightness.light
      ? Sentin8Text.bodyLight
      : Sentin8Text.body;
}

/// Returns the appropriate body-secondary style based on the current theme brightness.
TextStyle bodySecondaryFor(BuildContext context) {
  return Theme.of(context).brightness == Brightness.light
      ? Sentin8Text.bodySecondaryLight
      : Sentin8Text.bodySecondary;
}

/// Returns the appropriate caption style based on the current theme brightness.
TextStyle captionFor(BuildContext context) {
  return Theme.of(context).brightness == Brightness.light
      ? Sentin8Text.captionLight
      : Sentin8Text.caption;
}

/// Returns the appropriate label style based on the current theme brightness.
TextStyle labelFor(BuildContext context) {
  return Theme.of(context).brightness == Brightness.light
      ? Sentin8Text.labelLight
      : Sentin8Text.label;
}

/// Returns the appropriate text color based on the current theme brightness.
Color textPrimaryFor(BuildContext context) {
  return Theme.of(context).brightness == Brightness.light
      ? Sentin8Colors.lightTextPrimary
      : Sentin8Colors.textPrimary;
}

/// Returns the appropriate text-muted icon color based on the current theme brightness.
Color iconMutedFor(BuildContext context) {
  return Theme.of(context).brightness == Brightness.light
      ? Sentin8Colors.lightTextMuted
      : Sentin8Colors.textMuted;
}

/// Glass panel — the primary surface element for auth forms.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final double? maxWidth;

  const GlassPanel(
      {super.key,
      required this.child,
      this.padding,
      this.margin,
      this.maxWidth});

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Center(
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth ?? 480),
        margin: margin ?? const EdgeInsets.all(Sentin8Spacing.lg),
        padding: padding ?? const EdgeInsets.all(Sentin8Spacing.xl),
        decoration: BoxDecoration(
          color: isLight ? Sentin8Colors.lightCard : Sentin8Colors.carbonBlack,
          borderRadius: BorderRadius.circular(Sentin8Radii.xl),
          border: Border.all(
              color:
                  isLight ? Sentin8Colors.lightBorder : Sentin8Colors.glassBorder),
          boxShadow: [
            BoxShadow(
              color:
                  isLight ? const Color(0x20000000) : const Color(0x80000000),
              blurRadius: 32,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

/// Sentin8 logo widget.
///
/// Renders the Sentin8 lockup using the SVG assets in assets/logos/.
/// For a small [size] (e.g. <= 32) only the mark is shown; for larger
/// sizes the long logo (mark + text) is shown horizontally.
///
/// If [logoIconUrl] is provided (from tenant branding), renders the tenant
/// logo icon image instead of the default Sentin8 SVG.
/// If [logoUrl] is provided (but no icon), renders the tenant logo image.
class Sentin8Logo extends StatelessWidget {
  final double size;
  final String? logoUrl;
  final String? logoIconUrl;
  const Sentin8Logo({super.key, this.size = 32, this.logoUrl, this.logoIconUrl});

  @override
  Widget build(BuildContext context) {
    // Prefer the logo icon (small mark) when available.
    if (logoIconUrl != null && logoIconUrl!.isNotEmpty) {
      return _networkImage(logoIconUrl!, fallback: logoUrl);
    }
    // Fall back to full logo URL if provided.
    if (logoUrl != null && logoUrl!.isNotEmpty) {
      return _networkImage(logoUrl!, fallback: null);
    }
    return _defaultLogo(size);
  }

  /// Render a network image, using SvgPicture.network for SVG URLs
  /// (Skia/CanvasKit can't decode SVGs via Image.network) and
  /// Image.network for raster formats (PNG, JPG, etc.).
  Widget _networkImage(String url, {String? fallback}) {
    final isSvg = url.toLowerCase().endsWith('.svg');
    if (isSvg) {
      return SvgPicture.network(
        url,
        height: size,
        placeholderBuilder: (context) => SizedBox(
          height: size,
          width: size,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorBuilder: (context, error, stackTrace) {
          if (fallback != null && fallback.isNotEmpty) {
            return _networkImage(fallback);
          }
          return _defaultLogo(size);
        },
      );
    }
    return Image.network(
      url,
      height: size,
      errorBuilder: (context, error, stackTrace) {
        if (fallback != null && fallback.isNotEmpty) {
          return _networkImage(fallback);
        }
        return _defaultLogo(size);
      },
    );
  }

  Widget _defaultLogo(double size) {
    final showText = size >= 40;
    if (showText) {
      return SvgPicture.asset(
        'assets/logos/sentin8-long-logo-gold.svg',
        height: size,
      );
    }
    return SvgPicture.asset(
      'assets/logos/sentin8-logo-icon.svg',
      height: size,
    );
  }
}

/// "Powered by" footer — shows the Sentin8 icon + "Sentin8" wordmark.
/// Used at the bottom of sign-in and sign-up forms.
class PoweredBySentin8 extends StatelessWidget {
  const PoweredBySentin8({super.key});

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final textColor =
        isLight ? Sentin8Colors.lightTextMuted : Sentin8Colors.textMuted;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Powered by ',
          style: GoogleFonts.quicksand(
            fontSize: 12,
            color: textColor,
          ),
        ),
        SvgPicture.asset(
          'assets/logos/sentin8-logo-icon.svg',
          height: 20,
        ),
        const SizedBox(width: 6),
        Text(
          'Sentin8',
          style: GoogleFonts.quicksand(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Sentin8Colors.royalGold,
          ),
        ),
      ],
    );
  }
}

/// Error banner widget.
class ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onDismiss;

  const ErrorBanner({super.key, required this.message, this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Sentin8Spacing.md, vertical: Sentin8Spacing.sm),
      decoration: BoxDecoration(
        color: const Color(0x26D64545),
        borderRadius: BorderRadius.circular(Sentin8Radii.medium),
        border: Border.all(color: const Color(0x66D64545)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline,
              color: Sentin8Colors.errorCrimson, size: 20),
          const SizedBox(width: Sentin8Spacing.sm),
          Expanded(
              child: Text(message,
                  style: const TextStyle(
                      color: Sentin8Colors.errorCrimson, fontSize: 14))),
          if (onDismiss != null)
            IconButton(
                icon: const Icon(Icons.close,
                    size: 18, color: Sentin8Colors.textMuted),
                onPressed: onDismiss),
        ],
      ),
    );
  }
}

/// Success banner widget.
class SuccessBanner extends StatelessWidget {
  final String message;
  const SuccessBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Sentin8Spacing.md, vertical: Sentin8Spacing.sm),
      decoration: BoxDecoration(
        color: const Color(0x26C6A667),
        borderRadius: BorderRadius.circular(Sentin8Radii.medium),
        border: Border.all(color: const Color(0x66C6A667)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline,
              color: Sentin8Colors.successGold, size: 20),
          const SizedBox(width: Sentin8Spacing.sm),
          Expanded(
              child: Text(message,
                  style: const TextStyle(
                      color: Sentin8Colors.successGold, fontSize: 14))),
        ],
      ),
    );
  }
}

/// Loading spinner with optional label.
class LoadingSpinner extends StatelessWidget {
  final String? label;
  const LoadingSpinner({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Sentin8Colors.royalGold)),
        if (label != null) ...[
          const SizedBox(height: Sentin8Spacing.md),
          Text(label!, style: Sentin8Text.bodySecondary),
        ],
      ],
    );
  }
}

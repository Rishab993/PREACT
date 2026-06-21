import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

class AppTextStyles {
  AppTextStyles._();

  // ─── Space Grotesk — Headers ─────────────────────────────────────────────
  static TextStyle display(BuildContext context) => GoogleFonts.spaceGrotesk(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: _textColor(context),
  );

  static TextStyle headline(BuildContext context) => GoogleFonts.spaceGrotesk(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: _textColor(context),
  );

  static TextStyle title(BuildContext context) => GoogleFonts.spaceGrotesk(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: _textColor(context),
  );

  static TextStyle titleSmall(BuildContext context) => GoogleFonts.spaceGrotesk(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: _textColor(context),
  );

  // ─── Inter — Body text ────────────────────────────────────────────────────
  static TextStyle body(BuildContext context) => GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: _textColor(context),
  );

  static TextStyle bodySmall(BuildContext context) => GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: _secondaryTextColor(context),
  );

  static TextStyle caption(BuildContext context) => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: _secondaryTextColor(context),
  );

  static TextStyle label(BuildContext context) => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
    color: _secondaryTextColor(context),
  );

  // ─── Mono — Data values / numbers ────────────────────────────────────────
  static TextStyle mono(BuildContext context) => GoogleFonts.jetBrainsMono(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: _textColor(context),
  );

  static TextStyle metricLarge(BuildContext context) => GoogleFonts.spaceGrotesk(
    fontSize: 36,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.0,
    color: _textColor(context),
  );

  static TextStyle metricMedium(BuildContext context) => GoogleFonts.spaceGrotesk(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: _textColor(context),
  );

  // ─── Static (no context) — for ThemeData ─────────────────────────────────
  static TextStyle get displayStatic => GoogleFonts.spaceGrotesk(
    fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5,
  );

  static TextStyle get headlineStatic => GoogleFonts.spaceGrotesk(
    fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.3,
  );

  static TextStyle get titleStatic => GoogleFonts.spaceGrotesk(
    fontSize: 18, fontWeight: FontWeight.w600,
  );

  static TextStyle get bodyStatic => GoogleFonts.inter(
    fontSize: 15, fontWeight: FontWeight.w400,
  );

  static TextStyle get captionStatic => GoogleFonts.inter(
    fontSize: 12, fontWeight: FontWeight.w400,
  );

  static TextStyle get labelStatic => GoogleFonts.inter(
    fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.5,
  );

  // ─── Helpers ─────────────────────────────────────────────────────────────
  static Color _textColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? AppColors.textPrimary : AppColors.textPrimaryDark;
  }

  static Color _secondaryTextColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? AppColors.textSecondary : AppColors.textSecondaryDark;
  }
}

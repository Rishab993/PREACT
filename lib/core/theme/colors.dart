import 'package:flutter/material.dart';

// ─── Brand Palette ────────────────────────────────────────────────────────────
class AppColors {
  AppColors._();

  // Dark mode backgrounds
  static const Color backgroundDark = Color(0xFF0A0E1A);
  static const Color surfaceDark    = Color(0xFF161B22);
  static const Color surfaceElevatedDark = Color(0xFF1E2530);
  static const Color borderDark     = Color(0xFF2A3240);

  // Light mode backgrounds
  static const Color backgroundLight = Color(0xFFF0F4F8);
  static const Color surfaceLight    = Color(0xFFFFFFFF);
  static const Color surfaceElevatedLight = Color(0xFFF5F8FC);
  static const Color borderLight     = Color(0xFFDDE3EC);

  // Neon accent — Hackathon brand
  static const Color neonBlue   = Color(0xFF2563EB); // primary electric blue
  static const Color amber      = Color(0xFFFFAA00); // warning
  static const Color red        = Color(0xFFFF3B3B); // critical
  static const Color green      = Color(0xFF43D97D); // success
  static const Color purple     = Color(0xFFA78BFA); // counterfactual/insight
  static const Color info       = Color(0xFF4FC3F7); // forecast line

  // Text
  static const Color textPrimary   = Color(0xFFF0F4F8);
  static const Color textSecondary = Color(0xFF8A99AA);
  static const Color textMuted     = Color(0xFF4A5568);

  // Text dark (for light mode)
  static const Color textPrimaryDark   = Color(0xFF0D1117);
  static const Color textSecondaryDark = Color(0xFF4A5568);

  // Severity tiers
  static const Color severityLow      = Color(0xFF43D97D);
  static const Color severityMedium   = Color(0xFFFFAA00);
  static const Color severityHigh     = Color(0xFFFF3B3B);
  static const Color severityCritical = Color(0xFFFF0044);

  // Map overlays
  static const Color mapLow      = Color(0x4D43D97D); // 30% opacity
  static const Color mapMedium   = Color(0x66FFAA00); // 40% opacity
  static const Color mapHigh     = Color(0x80FF3B3B); // 50% opacity

  // Glassmorphism (Solid fallbacks)
  static const Color glassWhite  = Color(0xFF161B22); // Solid surfaceDark
  static const Color glassBorder = Color(0xFF2A3240); // Solid borderDark

  // Zone badge colors
  static const Color zoneBlue   = Color(0xFF2979FF);
  static const Color zonePurple = Color(0xFF9C27B0);
  static const Color zoneGreen  = Color(0xFF00897B);
  static const Color zoneOrange = Color(0xFFFF6D00);

  // Helper: severity color from 0.0–1.0 value
  static Color fromSeverity(double value) {
    if (value < 0.4) return severityLow;
    if (value < 0.7) return severityMedium;
    if (value < 0.9) return severityHigh;
    return severityCritical;
  }

  // Helper: zone index → color
  static Color forZone(int index) {
    const colors = [
      zoneBlue, zonePurple, zoneGreen, zoneOrange,
      neonBlue, amber, red, green, purple, info,
    ];
    return colors[index % colors.length];
  }
}

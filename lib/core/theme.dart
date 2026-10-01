import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Patient side uses teal, pharmacy-owner side uses indigo (as in the mockups).
class Palette {
  final Color primary, primaryDark, soft, bg, text, muted, border;
  const Palette(this.primary, this.primaryDark, this.soft, this.bg, this.text,
      this.muted, this.border);

  static const patient = Palette(Color(0xFF12A08A), Color(0xFF0B6B5E),
      Color(0xFFDDF3EE), Color(0xFFF4F9F8), Color(0xFF16302B),
      Color(0xFF5E736E), Color(0xFFDCE8E5));
  static const owner = Palette(Color(0xFF6558E6), Color(0xFF4338B8),
      Color(0xFFECEBFF), Color(0xFFF6F5FC), Color(0xFF1E1B4B),
      Color(0xFF5F5C8A), Color(0xFFDEDCF2));

  LinearGradient get gradient => LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [primary, primaryDark]);
}

class Tint {
  final Color bg, fg;
  const Tint(this.bg, this.fg);
  static const green = Tint(Color(0xFFDDF3EE), Color(0xFF0B6B5E));
  static const purple = Tint(Color(0xFFECE8FF), Color(0xFF5B4BD5));
  static const orange = Tint(Color(0xFFFFE9E0), Color(0xFFD9532A));
  static const blue = Tint(Color(0xFFE2EEFF), Color(0xFF2A6FD6));
  static const amber = Tint(Color(0xFFFFF0D1), Color(0xFFA86A08));
  static const pink = Tint(Color(0xFFFFE6EF), Color(0xFFC93A74));
  static const all = [green, purple, orange, blue, amber, pink];
}

const okBg = Color(0xFFDDF6E6), okFg = Color(0xFF157A3D);
const noBg = Color(0xFFFFE9E0), noFg = Color(0xFFB23E19);
const loBg = Color(0xFFFFF0D1), loFg = Color(0xFF8A5A0B);
const waGreen = Color(0xFF1FA855);

ThemeData buildTheme(Palette p) {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
        seedColor: p.primaryDark, primary: p.primaryDark, surface: Colors.white),
    scaffoldBackgroundColor: p.bg,
  );
  return base.copyWith(
    textTheme: GoogleFonts.hindSiliguriTextTheme(base.textTheme)
        .apply(bodyColor: p.text, displayColor: p.text),
    appBarTheme: AppBarTheme(
        backgroundColor: p.bg, foregroundColor: p.text, elevation: 0,
        centerTitle: false),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: p.border, width: 1.5)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: p.border, width: 1.5)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: p.primaryDark, width: 1.8)),
    ),
  );
}

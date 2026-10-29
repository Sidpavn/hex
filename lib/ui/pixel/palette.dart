import 'dart:ui';

/// The one palette for every screen. Teal surfaces (the same teal as the
/// diner's paper receipts, just darker), a single gold accent, and team
/// blue/red.
class Pal {
  static const ink = Color(0xFF143231);
  static const bgTop = Color(0xFF122E2D);
  static const bgBottom = Color(0xFF122E2D);
  static const panel = Color(0xFF1C4846);
  static const panelHi = Color(0xFF276360);
  static const panelLo = Color(0xFF173938);

  static const text = Color(0xFFF4F4EA);
  static const dim = Color(0xFFA0AABE);
  static const dimmer = Color(0xFF68728C);

  static const gold = Color(0xFFF4C846);
  static const goldDark = Color(0xFFC88C28);
  static const goldLight = Color(0xFFFFE08A);

  static const blue = Color(0xFF78A0F0);
  static const red = Color(0xFFE86A5A);
  static const green = Color(0xFF6EDC82);
  static const purple = Color(0xFFC090F0);

  // The diner's printed-paper surface: a warm card against the usual slate
  // chrome. Used where the game hands the player a physical document — the
  // home screen's menu card, the day's receipt — never as the base theme.
  static const cream = Color(0xFFE8F2EE);
  static const creamDark = Color(0xFFB8D0C8);
  static const creamDim = Color(0xFF6B8880);
  static const inkWarm = Color(0xFF123331);
  static const teal = Color(0xFF1A4A48);
  static const tealDark = Color(0xFF0E2E2C);
  static const rust = Color(0xFF8B2A1A);
}

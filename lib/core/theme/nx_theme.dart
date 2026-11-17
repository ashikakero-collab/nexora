import 'package:flutter/material.dart';

import '../ui2/page_turn.dart';

/// NEXORA design tokens. Legacy gameplay colors remain stable; the app chrome
/// reads [NxThemeColors] from the active theme instead.
class NxColors {
  NxColors._();
  static const navy = Color(0xFF0A0F2C);
  static const navyDeep = Color(0xFF050818);
  static const navySoft = Color(0xFF141B45);
  static const electricBlue = Color(0xFF00C2FF);
  static const violet = Color(0xFF7B3FF2);
  static const iceWhite = Color(0xFFEAF6FF);
  static const turquoise = Color(0xFF2EE6D6);
  static const gold = Color(0xFFFFC857);
  static const pink = Color(0xFFFF4FA3);
  static const danger = Color(0xFFFF5A6E);
  static const success = Color(0xFF3DDC97);
  static const glass = Color(0x22FFFFFF);
  static const glassBorder = Color(0x44FFFFFF);
  static const textDim = Color(0xB3EAF6FF);
}

enum NxVisualTheme { gold, neon }

/// Colors and surface treatment for the two selectable NEXORA visual themes.
class NxThemeColors extends ThemeExtension<NxThemeColors> {
  const NxThemeColors({
    required this.accent,
    required this.accentSecondary,
    required this.background,
    required this.backgroundMid,
    required this.surface,
    required this.surfaceRaised,
    required this.border,
    required this.text,
    required this.muted,
    this.premiumPanels = true,
  });

  final Color accent;
  final Color accentSecondary;
  final Color background;
  final Color backgroundMid;
  final Color surface;
  final Color surfaceRaised;
  final Color border;
  final Color text;
  final Color muted;
  final bool premiumPanels;

  static const gold = NxThemeColors(
    accent: Color(0xFFF3C56B),
    accentSecondary: Color(0xFFB77D35),
    background: Color(0xFF050A14),
    backgroundMid: Color(0xFF0A1424),
    surface: Color(0xE6101B2B),
    surfaceRaised: Color(0xF0162336),
    border: Color(0xFF8F6B37),
    text: Color(0xFFF3F4F7),
    muted: Color(0xFFAEB8C7),
  );

  /// NX2 cosmic neon skin (deep violet, neon cyan/magenta) — the app skin.
  static const neon = NxThemeColors(
    accent: Color(0xFF35D6FF),
    accentSecondary: Color(0xFFB04DFF),
    background: Color(0xFF07031A),
    backgroundMid: Color(0xFF140A3A),
    surface: Color(0xE61A0C45),
    surfaceRaised: Color(0xF0241158),
    border: Color(0xFF7A45E6),
    text: Color(0xFFF4F0FF),
    muted: Color(0xFFBFB3E6),
  );

  /// Original visual language used inside active game boards and their HUDs.
  static const gameplay = NxThemeColors(
    accent: NxColors.electricBlue,
    accentSecondary: NxColors.violet,
    background: NxColors.navyDeep,
    backgroundMid: NxColors.navy,
    surface: NxColors.glass,
    surfaceRaised: NxColors.navySoft,
    border: NxColors.glassBorder,
    text: NxColors.iceWhite,
    muted: NxColors.textDim,
    premiumPanels: false,
  );

  static NxThemeColors of(BuildContext context) =>
      Theme.of(context).extension<NxThemeColors>() ?? neon;

  @override
  NxThemeColors copyWith({
    Color? accent,
    Color? accentSecondary,
    Color? background,
    Color? backgroundMid,
    Color? surface,
    Color? surfaceRaised,
    Color? border,
    Color? text,
    Color? muted,
    bool? premiumPanels,
  }) {
    return NxThemeColors(
      accent: accent ?? this.accent,
      accentSecondary: accentSecondary ?? this.accentSecondary,
      background: background ?? this.background,
      backgroundMid: backgroundMid ?? this.backgroundMid,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      border: border ?? this.border,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      premiumPanels: premiumPanels ?? this.premiumPanels,
    );
  }

  @override
  NxThemeColors lerp(ThemeExtension<NxThemeColors>? other, double t) {
    if (other is! NxThemeColors) return this;
    return NxThemeColors(
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      accentSecondary: Color.lerp(accentSecondary, other.accentSecondary, t) ??
          accentSecondary,
      background: Color.lerp(background, other.background, t) ?? background,
      backgroundMid:
          Color.lerp(backgroundMid, other.backgroundMid, t) ?? backgroundMid,
      surface: Color.lerp(surface, other.surface, t) ?? surface,
      surfaceRaised:
          Color.lerp(surfaceRaised, other.surfaceRaised, t) ?? surfaceRaised,
      border: Color.lerp(border, other.border, t) ?? border,
      text: Color.lerp(text, other.text, t) ?? text,
      muted: Color.lerp(muted, other.muted, t) ?? muted,
      premiumPanels: t < 0.5 ? premiumPanels : other.premiumPanels,
    );
  }
}

/// Per-world accents stay available to gameplay and to the worlds' own content.
class WorldPalette {
  const WorldPalette(this.primary, this.secondary, this.background,
      {this.light = false});
  final Color primary;
  final Color secondary;
  final List<Color> background;
  final bool light;
  static const hub = WorldPalette(NxColors.electricBlue, NxColors.violet,
      [Color(0xFF050818), Color(0xFF0E1640), Color(0xFF1B0F3F)]);
  static const nova = WorldPalette(Color(0xFFFF6FB5), NxColors.gold,
      [Color(0xFF1A0B2E), Color(0xFF3B1450), Color(0xFF5A1E4F)]);
  static const orbit = WorldPalette(NxColors.turquoise, NxColors.electricBlue,
      [Color(0xFF031A26), Color(0xFF06324A), Color(0xFF0A2A3F)]);
  static const arcade = WorldPalette(Color(0xFFFFB020), Color(0xFFFF4F6E),
      [Color(0xFF12051F), Color(0xFF2A0B3A), Color(0xFF3A0F2A)]);
  static const oracle = WorldPalette(Color(0xFF9D7BFF), NxColors.turquoise,
      [Color(0xFF0B0820), Color(0xFF1A1250), Color(0xFF0E2850)]);
  static const personal = WorldPalette(Color(0xFF7CF5D0), Color(0xFFB79CFF),
      [Color(0xFFEFF6FF), Color(0xFFDDE9FF), Color(0xFFEDE3FF)],
      light: true);
  static const social = WorldPalette(Color(0xFF4FD1FF), Color(0xFF7CFF8A),
      [Color(0xFF04141F), Color(0xFF0B2B33), Color(0xFF0E1F3A)]);
  static const exchange = WorldPalette(NxColors.gold, Color(0xFFFFE6A8),
      [Color(0xFF0D0B05), Color(0xFF2A2210), Color(0xFF1A1530)]);
}

class NxSpace {
  NxSpace._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

class NxRadius {
  NxRadius._();
  static const sm = 10.0;
  static const md = 16.0;
  static const lg = 24.0;
}

class NxMotion {
  NxMotion._();
  static const fast = Duration(milliseconds: 160);
  static const normal = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 520);
  static const curve = Curves.easeOutCubic;
}

/// The NX2 redesign ships one skin: cosmic neon. [style] is kept for API compatibility.
ThemeData buildNxTheme([NxVisualTheme style = NxVisualTheme.neon]) =>
    _buildTheme(NxThemeColors.neon);

/// Preserve the original Finger Soccer field, ball and player-disc palette.
ThemeData buildNxGameplayTheme() => _buildTheme(NxThemeColors.gameplay);

ThemeData _buildTheme(NxThemeColors visual) {
  final scheme = ColorScheme.dark(
    primary: visual.accent,
    secondary: visual.accentSecondary,
    tertiary:
        visual.premiumPanels ? visual.accentSecondary : NxColors.turquoise,
    surface: visual.surfaceRaised,
    error: NxColors.danger,
    onPrimary: const Color(0xFF08101A),
    onSurface: visual.text,
  );
  final base = ThemeData(
      useMaterial3: true, colorScheme: scheme, brightness: Brightness.dark);
  return base.copyWith(
    extensions: <ThemeExtension<dynamic>>[visual],
    pageTransitionsTheme: const PageTransitionsTheme(builders: <TargetPlatform, PageTransitionsBuilder>{
      TargetPlatform.android: NxPageTurnTransitionsBuilder(),
      TargetPlatform.iOS: NxPageTurnTransitionsBuilder(),
      TargetPlatform.linux: NxPageTurnTransitionsBuilder(),
      TargetPlatform.macOS: NxPageTurnTransitionsBuilder(),
      TargetPlatform.windows: NxPageTurnTransitionsBuilder(),
    }),
    scaffoldBackgroundColor: visual.background,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      foregroundColor: visual.text,
      titleTextStyle: TextStyle(
          fontFamily: kNxFontHead,
          fontFamilyFallback: kNxFontHeadFallback,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
          color: visual.text),
    ),
    textTheme: nxGameTextTheme(base.textTheme)
        .apply(bodyColor: visual.text, displayColor: visual.text),
    iconTheme: IconThemeData(color: visual.text),
    cardTheme: CardThemeData(
      color: visual.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NxRadius.md),
        side: BorderSide(color: visual.border.withValues(alpha: 0.35)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: visual.surface.withValues(alpha: 0.82),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NxRadius.md),
        borderSide: BorderSide(color: visual.border.withValues(alpha: 0.46)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NxRadius.md),
        borderSide: BorderSide(color: visual.border.withValues(alpha: 0.38)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NxRadius.md),
        borderSide: BorderSide(color: visual.accent, width: 1.5),
      ),
      labelStyle: TextStyle(color: visual.muted),
      hintStyle: TextStyle(color: visual.muted.withValues(alpha: 0.82)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: visual.accentSecondary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NxRadius.md)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: visual.accent,
        side: BorderSide(color: visual.accent.withValues(alpha: 0.7)),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NxRadius.md)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: visual.surfaceRaised,
      contentTextStyle: TextStyle(color: visual.text),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: visual.surfaceRaised,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NxRadius.lg)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: visual.backgroundMid,
      showDragHandle: true,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: visual.accent,
      unselectedLabelColor: visual.muted,
      indicatorColor: visual.accent,
      dividerColor: Colors.transparent,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: visual.accent),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xF2140A3A),
      indicatorColor: visual.accentSecondary.withValues(alpha: 0.35),
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStatePropertyAll<TextStyle>(TextStyle(
          fontSize: 11, fontWeight: FontWeight.w800, color: visual.text)),
      iconTheme: WidgetStatePropertyAll<IconThemeData>(
          IconThemeData(color: visual.text)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: const Color(0xE61A0C45),
      selectedColor: visual.accentSecondary.withValues(alpha: 0.45),
      side: BorderSide(color: visual.border.withValues(alpha: 0.7)),
      labelStyle: TextStyle(color: visual.text, fontWeight: FontWeight.w700),
      shape: const StadiumBorder(),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> s) =>
          s.contains(WidgetState.selected) ? Colors.white : visual.muted),
      trackColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> s) =>
          s.contains(WidgetState.selected)
              ? visual.accentSecondary
              : const Color(0x33FFFFFF)),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: visual.accent,
      thumbColor: Colors.white,
      inactiveTrackColor: const Color(0x33FFFFFF),
    ),
  );
}


// ------------------------------------------------------------------ fonts (bundled, OFL)
/// Latin + digits: Chakra Petch (HUD/game look). Persian falls back to Estedad (body) or Lalezar (headings).
const String kNxFont = 'ChakraPetch';
const List<String> kNxFontFallback = <String>['Estedad'];
const String kNxFontHead = 'ChakraPetch';
const List<String> kNxFontHeadFallback = <String>['Lalezar', 'Estedad'];

TextTheme nxGameTextTheme(TextTheme t) {
  TextStyle? body(TextStyle? s) => s?.copyWith(fontFamily: kNxFont, fontFamilyFallback: kNxFontFallback);
  TextStyle? head(TextStyle? s) => s?.copyWith(fontFamily: kNxFontHead, fontFamilyFallback: kNxFontHeadFallback);
  return t.copyWith(
    displayLarge: head(t.displayLarge),
    displayMedium: head(t.displayMedium),
    displaySmall: head(t.displaySmall),
    headlineLarge: head(t.headlineLarge),
    headlineMedium: head(t.headlineMedium),
    headlineSmall: head(t.headlineSmall),
    titleLarge: head(t.titleLarge),
    titleMedium: body(t.titleMedium),
    titleSmall: body(t.titleSmall),
    bodyLarge: body(t.bodyLarge),
    bodyMedium: body(t.bodyMedium),
    bodySmall: body(t.bodySmall),
    labelLarge: body(t.labelLarge),
    labelMedium: body(t.labelMedium),
    labelSmall: body(t.labelSmall),
  );
}

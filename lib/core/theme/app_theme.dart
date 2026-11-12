import 'package:flutter/material.dart';

class AppTheme {
  static const pixelMapStyle = '''[
    {"elementType":"geometry","stylers":[{"color":"#151d32"}]},
    {"elementType":"labels.text.fill","stylers":[{"color":"#f4eeda"}]},
    {"elementType":"labels.text.stroke","stylers":[{"color":"#0b1020"}]},
    {"featureType":"road","elementType":"geometry","stylers":[{"color":"#405071"}]},
    {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0b1020"}]},
    {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#193d42"}]}
  ]''';
  static const midnight = Color(0xff0b1020);
  static const panel = Color(0xff151d32);
  static const raisedPanel = Color(0xff1d2943);
  static const pixelOutline = Color(0xff405071);
  static const mint = Color(0xff6de3ce);
  static const lavender = Color(0xffb3a5ff);
  static const cream = Color(0xfff4eeda);
  static const coral = Color(0xfff49bb5);
  static const cyan = mint;
  static const sun = cream;
  static const neonPink = coral;
  static const techBlue = cyan;
  static const acidGreen = mint;
  static const spotlightYellow = sun;
  static const ink = midnight;
  static const night = panel;
  static const paper = cream;
  static const blush = Color(0xff332239);
  static const radiusSm = 0.0;
  static const radiusMd = 2.0;
  static const radiusLg = 4.0;
  static const radiusXl = 6.0;

  static ThemeData get light => whitePixel;

  static ThemeData get whitePixel {
    const scheme = ColorScheme.light(
      primary: Color(0xff176b5c),
      onPrimary: Colors.white,
      primaryContainer: Color(0xffd9f4eb),
      onPrimaryContainer: Color(0xff124b40),
      secondary: Color(0xff6750a4),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xffeee7ff),
      onSecondaryContainer: Color(0xff41306b),
      tertiary: Color(0xff8c3d62),
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xffffe5ef),
      onTertiaryContainer: Color(0xff642644),
      error: Color(0xffb32640),
      onError: Colors.white,
      errorContainer: Color(0xffffe1e7),
      onErrorContainer: Color(0xff740c27),
      surface: Colors.white,
      onSurface: Color(0xff20283b),
      surfaceContainerLowest: Color(0xfffafbfe),
      surfaceContainerLow: Color(0xfff4f6fa),
      surfaceContainer: Color(0xffeef1f7),
      surfaceContainerHigh: Color(0xffe7ebf3),
      surfaceContainerHighest: Color(0xffdfe5ee),
      onSurfaceVariant: Color(0xff4f5c72),
      outline: Color(0xff67768e),
      outlineVariant: Color(0xffa8b3c5),
      shadow: Color(0xffccd3e1),
      inverseSurface: midnight,
      onInverseSurface: cream,
      inversePrimary: mint,
      surfaceTint: Colors.transparent,
    );
    return _buildTheme(
      scheme: scheme,
      brightness: Brightness.light,
      scaffoldBackgroundColor: scheme.surface,
      cardColor: scheme.surfaceContainerLowest,
      navColor: scheme.surface,
    );
  }

  static ThemeData get morandi {
    final scheme = dark.colorScheme.copyWith(
      primary: lavender,
      onPrimary: midnight,
      primaryContainer: const Color(0xff39335c),
      onPrimaryContainer: const Color(0xffe5dfff),
      secondary: const Color(0xffa8d8ff),
      onSecondary: midnight,
      secondaryContainer: const Color(0xff23415c),
      onSecondaryContainer: const Color(0xffd7eeff),
      tertiary: mint,
      onTertiary: midnight,
      tertiaryContainer: const Color(0xff193d42),
      onTertiaryContainer: const Color(0xffc0f7e9),
      inversePrimary: const Color(0xff574696),
      surface: const Color(0xff182239),
      surfaceContainerLowest: const Color(0xff1d2943),
      surfaceContainerLow: const Color(0xff22304a),
      surfaceContainer: const Color(0xff283651),
      surfaceContainerHigh: const Color(0xff303e5b),
      surfaceContainerHighest: const Color(0xff394966),
      outlineVariant: const Color(0xff536586),
    );
    return _buildTheme(
      scheme: scheme,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: scheme.surface,
      cardColor: scheme.surfaceContainerLowest,
      navColor: scheme.surfaceContainerLowest,
    );
  }

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: mint,
      onPrimary: midnight,
      primaryContainer: Color(0xff193d42),
      onPrimaryContainer: Color(0xffc0f7e9),
      secondary: lavender,
      onSecondary: midnight,
      secondaryContainer: Color(0xff302c50),
      onSecondaryContainer: Color(0xffe5dfff),
      tertiary: cream,
      onTertiary: midnight,
      tertiaryContainer: Color(0xff3c392e),
      onTertiaryContainer: cream,
      error: coral,
      onError: midnight,
      errorContainer: Color(0xff4b2537),
      onErrorContainer: Color(0xffffd9e4),
      surface: midnight,
      onSurface: cream,
      surfaceContainerLowest: panel,
      surfaceContainerLow: panel,
      surfaceContainer: raisedPanel,
      surfaceContainerHigh: Color(0xff26334f),
      surfaceContainerHighest: Color(0xff303f5c),
      onSurfaceVariant: Color(0xffb9c5dc),
      outline: Color(0xff7a8baa),
      outlineVariant: pixelOutline,
      shadow: Color(0xff030712),
      inverseSurface: cream,
      onInverseSurface: midnight,
      inversePrimary: Color(0xff185e53),
      surfaceTint: Colors.transparent,
    );

    return _buildTheme(
      scheme: scheme,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: midnight,
      cardColor: panel,
      navColor: panel,
    );
  }

  static ThemeData _buildTheme({
    required ColorScheme scheme,
    required Brightness brightness,
    required Color scaffoldBackgroundColor,
    required Color cardColor,
    required Color navColor,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBackgroundColor,
      fontFamily: 'FusionPixel',
      fontFamilyFallback: const ['Noto Sans TC', 'Roboto'],
    );

    var textTheme = base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontWeight: FontWeight.w900,
        color: scheme.onSurface,
        height: 1.25,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w900,
        color: scheme.onSurface,
        height: 1.25,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w900,
        color: scheme.onSurface,
        height: 1.25,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w900,
        color: scheme.onSurface,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w800,
        color: scheme.onSurface,
      ),
      titleSmall: base.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w800,
        color: scheme.onSurface,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
        height: 1.42,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
        height: 1.35,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w900,
      ),
      labelSmall: base.textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w800,
      ),
    );
    textTheme = textTheme.copyWith(
      displayLarge: textTheme.displayLarge?.copyWith(letterSpacing: 0),
      displayMedium: textTheme.displayMedium?.copyWith(letterSpacing: 0),
      displaySmall: textTheme.displaySmall?.copyWith(letterSpacing: 0),
      headlineLarge: textTheme.headlineLarge?.copyWith(letterSpacing: 0),
      headlineMedium: textTheme.headlineMedium?.copyWith(letterSpacing: 0),
      headlineSmall: textTheme.headlineSmall?.copyWith(letterSpacing: 0),
      titleLarge: textTheme.titleLarge?.copyWith(letterSpacing: 0),
      titleMedium: textTheme.titleMedium?.copyWith(letterSpacing: 0),
      titleSmall: textTheme.titleSmall?.copyWith(letterSpacing: 0),
      bodyLarge: textTheme.bodyLarge?.copyWith(letterSpacing: 0),
      bodyMedium: textTheme.bodyMedium?.copyWith(letterSpacing: 0),
      bodySmall: textTheme.bodySmall?.copyWith(letterSpacing: 0),
      labelLarge: textTheme.labelLarge?.copyWith(letterSpacing: 0),
      labelMedium: textTheme.labelMedium?.copyWith(letterSpacing: 0),
      labelSmall: textTheme.labelSmall?.copyWith(letterSpacing: 0),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBackgroundColor,
      fontFamily: 'FusionPixel',
      fontFamilyFallback: const ['Noto Sans TC', 'Roboto'],
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scaffoldBackgroundColor,
        foregroundColor: scheme.onSurface,
        titleTextStyle: textTheme.titleLarge,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shadowColor: scheme.shadow,
        surfaceTintColor: Colors.transparent,
        color: cardColor,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: BorderSide(color: scheme.outlineVariant, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: scheme.surfaceContainerHigh,
          foregroundColor: scheme.primary,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          side: BorderSide(color: scheme.outlineVariant, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          textStyle: textTheme.labelLarge,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.surfaceContainerHighest,
          disabledForegroundColor: scheme.onSurfaceVariant.withValues(
            alpha: 0.55,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.secondary,
          side: BorderSide(color: scheme.secondary, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.secondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurface;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return scheme.primaryContainer;
            }
            return Colors.transparent;
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMd),
            ),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusLg)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        hintStyle: TextStyle(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: scheme.outlineVariant, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: scheme.outlineVariant, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: scheme.secondary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: scheme.primaryContainer,
        secondarySelectedColor: scheme.secondaryContainer,
        disabledColor: scheme.surfaceContainerHighest.withValues(alpha: 0.62),
        labelStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
        ),
        secondaryLabelStyle: TextStyle(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w900,
        ),
        side: BorderSide(color: scheme.outlineVariant, width: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 66,
        backgroundColor: navColor,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: BorderSide(color: scheme.primary, width: 2),
        ),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
            fontSize: 12,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            size: selected ? 25 : 22,
          );
        }),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorColor: scheme.primary,
        labelColor: scheme.onSurface,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: const TextStyle(fontWeight: FontWeight.w900),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: BorderSide(color: scheme.outlineVariant, width: 2),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardColor,
        modalBackgroundColor: cardColor,
        elevation: 0,
        modalElevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: cardColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: BorderSide(color: scheme.outlineVariant, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        elevation: 0,
        backgroundColor: scheme.surfaceContainerHighest,
        contentTextStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w800,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? scheme.onSecondary
              : null;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? scheme.secondary
              : null;
        }),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: scheme.surfaceContainerLowest,
          selectedBackgroundColor: scheme.primaryContainer,
          selectedForegroundColor: scheme.onPrimaryContainer,
          foregroundColor: scheme.onSurfaceVariant,
          side: BorderSide(color: scheme.outlineVariant, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
        ),
      ),
    );
  }
}

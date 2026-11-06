import 'package:flutter/material.dart';

class AppTheme {
  static const coral = Color(0xffd0404d);
  static const cyan = Color(0xff087f79);
  static const sun = Color(0xffffd34f);
  static const lavender = Color(0xffa78bfa);
  static const mint = Color(0xff49d6a3);
  static const neonPink = coral;
  static const techBlue = cyan;
  static const acidGreen = mint;
  static const spotlightYellow = sun;
  static const ink = Color(0xff182b30);
  static const night = Color(0xff263639);
  static const paper = Color(0xfff7faf9);
  static const blush = Color(0xffffeceb);

  static ThemeData get light => morandi;

  static ThemeData get morandi {
    const scheme = ColorScheme.light(
      primary: coral,
      onPrimary: Colors.white,
      primaryContainer: Color(0xffffe1df),
      onPrimaryContainer: Color(0xff75242c),
      secondary: cyan,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xffd8f1e9),
      onSecondaryContainer: Color(0xff07564f),
      tertiary: sun,
      onTertiary: Color(0xff352500),
      tertiaryContainer: Color(0xffffecb6),
      onTertiaryContainer: Color(0xff3d2b00),
      error: Color(0xffc4455c),
      surface: paper,
      onSurface: ink,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Color(0xfff1f7f5),
      surfaceContainer: Color(0xffeaf1ee),
      surfaceContainerHigh: Color(0xffe3ece8),
      surfaceContainerHighest: Color(0xffd7e3de),
      onSurfaceVariant: Color(0xff526568),
      outline: Color(0xff748785),
      outlineVariant: Color(0xffdce6e2),
      shadow: Color(0xff183b33),
    );

    return _buildTheme(
      scheme: scheme,
      brightness: Brightness.light,
      scaffoldBackgroundColor: paper,
      cardColor: Colors.white,
      navColor: Colors.white,
    );
  }

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: Color(0xffff8d93),
      onPrimary: ink,
      primaryContainer: Color(0xff5a2138),
      onPrimaryContainer: Color(0xffffd7e4),
      secondary: Color(0xff6dd7c4),
      onSecondary: Color(0xff002832),
      secondaryContainer: Color(0xff124942),
      onSecondaryContainer: Color(0xffc9f3fb),
      tertiary: sun,
      onTertiary: Color(0xff352500),
      tertiaryContainer: Color(0xff5c4300),
      onTertiaryContainer: Color(0xffffecb6),
      error: Color(0xffff7b91),
      surface: ink,
      onSurface: Color(0xfff8f3f6),
      surfaceContainerLowest: Color(0xff142326),
      surfaceContainerLow: Color(0xff1e2f32),
      surfaceContainer: night,
      surfaceContainerHigh: Color(0xff304345),
      surfaceContainerHighest: Color(0xff3d5152),
      onSurfaceVariant: Color(0xffcec5d1),
      outline: Color(0xff7c7382),
      outlineVariant: Color(0xff464052),
      shadow: Colors.black,
    );

    return _buildTheme(
      scheme: scheme,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xff142326),
      cardColor: const Color(0xff1e2f32),
      navColor: const Color(0xff1e2f32),
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
      fontFamily: 'Roboto',
      fontFamilyFallback: const ['Roboto', 'Noto Sans TC'],
    );

    var textTheme = base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontWeight: FontWeight.w900,
        color: scheme.onSurface,
        height: 1.04,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w900,
        color: scheme.onSurface,
        height: 1.06,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w900,
        color: scheme.onSurface,
        height: 1.08,
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
      fontFamily: 'Roboto',
      fontFamilyFallback: const ['Roboto', 'Noto Sans TC'],
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
        shadowColor: scheme.shadow.withValues(alpha: 0.12),
        color: cardColor,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.76),
          ),
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
            borderRadius: BorderRadius.circular(18),
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
          side: BorderSide(color: scheme.secondary.withValues(alpha: 0.56)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
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
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        hintStyle: TextStyle(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.secondary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.error),
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
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 66,
        backgroundColor: navColor,
        indicatorColor: scheme.primaryContainer.withValues(alpha: 0.92),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardColor,
        modalBackgroundColor: cardColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        contentTextStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w800,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
    );
  }
}

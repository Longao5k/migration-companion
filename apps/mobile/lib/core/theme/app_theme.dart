import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const _ink = Color(0xFF142231);
  static const _eucalyptus = Color(0xFF147B66);
  static const _sand = Color(0xFFF3F5F2);
  static const _amber = Color(0xFFD99B2B);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: _eucalyptus,
      brightness: Brightness.light,
      primary: _eucalyptus,
      secondary: _amber,
      surface: const Color(0xFFF7F8F5),
    );
    return _theme(scheme);
  }

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF79C6BA),
      brightness: Brightness.dark,
      surface: const Color(0xFF111B24),
    );
    return _theme(scheme);
  }

  static ThemeData _theme(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      fontFamilyFallback: const [
        'Microsoft YaHei',
        'PingFang SC',
        'Noto Sans CJK SC',
      ],
      textTheme: const TextTheme(
        displaySmall: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -1),
        headlineMedium: TextStyle(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        titleLarge: TextStyle(fontWeight: FontWeight.w700),
        titleMedium: TextStyle(fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(height: 1.45),
        bodyMedium: TextStyle(height: 1.45),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 72,
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.primaryContainer.withValues(alpha: 0.72),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      extensions: const [
        AppPalette(
          ink: _ink,
          eucalyptus: _eucalyptus,
          sand: _sand,
          amber: _amber,
        ),
      ],
    );
  }
}

class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.ink,
    required this.eucalyptus,
    required this.sand,
    required this.amber,
  });

  final Color ink;
  final Color eucalyptus;
  final Color sand;
  final Color amber;

  @override
  AppPalette copyWith({
    Color? ink,
    Color? eucalyptus,
    Color? sand,
    Color? amber,
  }) => AppPalette(
    ink: ink ?? this.ink,
    eucalyptus: eucalyptus ?? this.eucalyptus,
    sand: sand ?? this.sand,
    amber: amber ?? this.amber,
  );

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      ink: Color.lerp(ink, other.ink, t)!,
      eucalyptus: Color.lerp(eucalyptus, other.eucalyptus, t)!,
      sand: Color.lerp(sand, other.sand, t)!,
      amber: Color.lerp(amber, other.amber, t)!,
    );
  }
}

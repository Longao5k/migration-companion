import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const _ink = Color(0xFF182A3A);
  static const _eucalyptus = Color(0xFF2A6E65);
  static const _sand = Color(0xFFF4EFE6);
  static const _amber = Color(0xFFE7A93B);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: _eucalyptus,
      brightness: Brightness.light,
      primary: _eucalyptus,
      secondary: _amber,
      surface: const Color(0xFFFCFAF6),
    );
    return _theme(scheme, _sand);
  }

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF79C6BA),
      brightness: Brightness.dark,
      surface: const Color(0xFF111B24),
    );
    return _theme(scheme, const Color(0xFF1B2730));
  }

  static ThemeData _theme(ColorScheme scheme, Color mutedSurface) {
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
        headlineMedium: TextStyle(
          fontWeight: FontWeight.w700,
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
        color: mutedSurface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
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
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
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
        fillColor: mutedSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
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

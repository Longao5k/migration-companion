import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme/app_theme.dart';
import 'core/i18n/app_language.dart';
import 'features/shell/app_shell.dart';

class WaymarkApp extends StatelessWidget {
  const WaymarkApp({this.locale, super.key});

  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Waymark',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      locale: locale,
      supportedLocales: supportedWaymarkLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      localeResolutionCallback: (locale, supported) =>
          resolveWaymarkLocale(locale),
      home: const AppShell(),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migration_companion/core/data/checklist_catalog.dart';
import 'package:migration_companion/core/i18n/app_language.dart';

void main() {
  test('supports twelve common system locales', () {
    expect(supportedWaymarkLocales, hasLength(12));
    expect(resolveWaymarkLocale(const Locale('es', 'MX')).languageCode, 'es');
    expect(resolveWaymarkLocale(const Locale('ar')).languageCode, 'en');
    expect(resolveWaymarkLocale(const Locale('zh', 'TW')).scriptCode, 'Hant');
  });

  testWidgets('built-in material names follow the device locale', (
    tester,
  ) async {
    late String label;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        supportedLocales: supportedWaymarkLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(
          builder: (context) {
            label = checklistCatalog.first.label(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(label, 'Pasaporte e identidad');
  });
}

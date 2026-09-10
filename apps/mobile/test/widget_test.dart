import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migration_companion/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('renders the guest-first home experience', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: WaymarkApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Migration updates'), findsOneWidget);
    expect(find.text('Updates'), findsOneWidget);
    expect(find.text('Applications'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
  });

  testWidgets('uses Chinese for a Chinese system locale', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const ProviderScope(child: WaymarkApp(locale: Locale('zh', 'CN'))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('移民资讯'), findsOneWidget);
    expect(find.text('资料'), findsOneWidget);
    expect(find.text('申请'), findsOneWidget);
  });
}

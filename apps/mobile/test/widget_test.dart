import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migration_companion/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('renders the guest-first home experience', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const ProviderScope(child: MigrationCompanionApp()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('把申请这件事，理清楚'), findsOneWidget);
    expect(find.text('资讯'), findsOneWidget);
    expect(find.text('项目'), findsOneWidget);
  });
}

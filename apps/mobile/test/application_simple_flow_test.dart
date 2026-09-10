import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:migration_companion/core/models/models.dart';
import 'package:migration_companion/core/state/app_store.dart';
import 'package:migration_companion/features/projects/projects_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/store_fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('application UI exposes only complete and incomplete', (
    tester,
  ) async {
    final store = AppStore(InMemoryRepository());
    await store.ready;
    await store.importProject(
      const VisaProject(
        id: 'local-project',
        name: '491 application',
        visaType: 'SA 491',
        applicant: 'Applicant',
        status: ProjectStatus.active,
        items: [
          ChecklistItem(
            id: 'passport',
            title: 'Passport',
            owner: 'Applicant',
            category: 'Identity',
            status: ChecklistStatus.notStarted,
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStoreProvider.overrideWith((ref) => store)],
        child: const MaterialApp(
          home: ProjectDetailScreen(projectId: 'local-project'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Incomplete'), findsWidgets);
    expect(find.text('Preparing'), findsNothing);
    expect(find.text('Sent'), findsNothing);
    expect(find.text('Secure share'), findsNothing);

    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pumpAndSettle();

    expect(find.text('Complete'), findsWidgets);
  });
}

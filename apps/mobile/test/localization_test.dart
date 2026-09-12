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

  testWidgets('every live and canonical tag is English on an English device', (
    tester,
  ) async {
    const tags = <String>[
      '186',
      '190',
      '482',
      '491',
      '600',
      'DAMA',
      'ROI',
      '人才引进',
      '人道与保护',
      '公民入籍',
      '南澳',
      '历史节点',
      '名额',
      '学生签证',
      '工作度假',
      '工作权益',
      '提名条件',
      '政策期限',
      '永久移民计划',
      '法规',
      '活动',
      '移民代理',
      '职业清单',
      '英语要求',
      '薪资门槛',
      '费用',
      '边境与旅行',
      '邀请数据',
      '邀请轮次',
      '雇主',
      '雇主担保',
      '项目开关',
      '申请材料',
      '审理时间',
      '打分规则',
      '职业评估',
      '家庭与配偶',
      '访客签证',
    ];
    final labels = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: supportedWaymarkLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(
          builder: (context) {
            labels.addAll(tags.map((tag) => localizedTagLabel(context, tag)));
            return const SizedBox();
          },
        ),
      ),
    );

    expect(labels, hasLength(tags.length));
    expect(
      labels.where((label) => RegExp(r'[\u3400-\u9fff]').hasMatch(label)),
      isEmpty,
    );
    expect(labels[tags.indexOf('移民代理')], 'Migration agents');
    expect(labels[tags.indexOf('南澳')], 'South Australia');
    expect(labels[tags.indexOf('人才引进')], 'Talent attraction');
  });
}

import 'package:flutter/widgets.dart';

import 'ui_translations.dart';

const supportedWaymarkLocales = <Locale>[
  Locale('en'),
  Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
  Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  Locale('es'),
  Locale('pt'),
  Locale('fr'),
  Locale('de'),
  Locale('ja'),
  Locale('ko'),
  Locale('vi'),
  Locale('id'),
  Locale('hi'),
];

bool isChineseUi(BuildContext context) =>
    Localizations.localeOf(context).languageCode.toLowerCase() == 'zh';

String tr(BuildContext context, String zh, String en) {
  final locale = Localizations.localeOf(context);
  if (locale.languageCode.toLowerCase() == 'zh') {
    if (locale.scriptCode == 'Hant') {
      return uiTranslations[en]?['zh_Hant'] ?? zh;
    }
    return zh;
  }
  return uiTranslations[en]?[locale.languageCode.toLowerCase()] ?? en;
}

Locale resolveWaymarkLocale(Locale? locale) {
  if (locale == null) return const Locale('en');
  final language = locale.languageCode.toLowerCase();
  if (language == 'zh') {
    final traditional =
        locale.scriptCode == 'Hant' ||
        const {'TW', 'HK', 'MO'}.contains(locale.countryCode?.toUpperCase());
    return Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: traditional ? 'Hant' : 'Hans',
    );
  }
  return supportedWaymarkLocales.firstWhere(
    (item) => item.languageCode == language,
    orElse: () => const Locale('en'),
  );
}

String localizedTagLabel(BuildContext context, String tag) {
  const labels = <String, (String, String)>{
    '材料': ('材料', 'Documents'),
    '州担保': ('州担保', 'State nomination'),
    '雇主担保': ('雇主担保', 'Employer sponsored'),
    '学生': ('学生', 'Student'),
    '伴侣': ('伴侣', 'Partner'),
    '父母': ('父母', 'Parent'),
    '永居': ('永居', 'Permanent'),
    '临时': ('临时', 'Temporary'),
    '政策': ('政策', 'Policy'),
    '配额': ('配额', 'Allocations'),
    '邀请': ('邀请', 'Invitations'),
    '截止日期': ('截止日期', 'Deadline'),
    '职业清单': ('职业清单', 'Occupation list'),
    '技能评估': ('技能评估', 'Skills assessment'),
  };
  final value = labels[tag];
  return value == null ? tag : tr(context, value.$1, value.$2);
}

String jurisdictionLabel(String code, {required bool zh}) {
  const zhLabels = {
    'AU-FED': '全澳 / 联邦',
    'AU-ACT': '首都领地',
    'AU-NSW': '新南威尔士',
    'AU-NT': '北领地',
    'AU-QLD': '昆士兰',
    'AU-SA': '南澳',
    'AU-TAS': '塔斯马尼亚',
    'AU-VIC': '维多利亚',
    'AU-WA': '西澳',
  };
  const enLabels = {
    'AU-FED': 'Australia / Federal',
    'AU-ACT': 'ACT',
    'AU-NSW': 'New South Wales',
    'AU-NT': 'Northern Territory',
    'AU-QLD': 'Queensland',
    'AU-SA': 'South Australia',
    'AU-TAS': 'Tasmania',
    'AU-VIC': 'Victoria',
    'AU-WA': 'Western Australia',
  };
  return (zh ? zhLabels : enLabels)[code] ?? code;
}

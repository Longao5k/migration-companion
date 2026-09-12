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
    '申请材料': ('申请材料', 'Application documents'),
    '州担保': ('州担保', 'State nomination'),
    '雇主担保': ('雇主担保', 'Employer sponsored'),
    '雇主': ('雇主', 'Employers'),
    '人才引进': ('人才引进', 'Talent attraction'),
    '学生': ('学生', 'Student'),
    '学生签证': ('学生签证', 'Student visa'),
    '伴侣': ('伴侣', 'Partner'),
    '父母': ('父母', 'Parent'),
    '家庭与配偶': ('家庭与配偶', 'Family & partner'),
    '永居': ('永居', 'Permanent'),
    '永久移民计划': ('永久移民计划', 'Permanent Migration Program'),
    '临时': ('临时', 'Temporary'),
    '政策': ('政策', 'Policy'),
    '法规': ('法规', 'Legislation'),
    '配额': ('配额', 'Allocations'),
    '名额': ('名额', 'Places'),
    '邀请': ('邀请', 'Invitations'),
    '邀请轮次': ('邀请轮次', 'Invitation rounds'),
    '邀请数据': ('邀请数据', 'Invitation data'),
    '截止日期': ('截止日期', 'Deadline'),
    '政策期限': ('政策期限', 'Policy dates'),
    '职业清单': ('职业清单', 'Occupation list'),
    '技能评估': ('技能评估', 'Skills assessment'),
    '职业评估': ('职业评估', 'Skills assessment'),
    '提名条件': ('提名条件', 'Nomination requirements'),
    '审理时间': ('审理时间', 'Processing times'),
    '打分规则': ('打分规则', 'Points rules'),
    '英语要求': ('英语要求', 'English requirements'),
    '费用': ('费用', 'Fees'),
    '项目开关': ('项目开关', 'Program availability'),
    '活动': ('活动', 'Events'),
    '薪资门槛': ('薪资门槛', 'Salary threshold'),
    '访客签证': ('访客签证', 'Visitor visa'),
    '工作度假': ('工作度假', 'Working Holiday'),
    '人道与保护': ('人道与保护', 'Humanitarian & protection'),
    '公民入籍': ('公民入籍', 'Citizenship'),
    '移民代理': ('移民代理', 'Migration agents'),
    '边境与旅行': ('边境与旅行', 'Border & travel'),
    '工作权益': ('工作权益', 'Workplace rights'),
    '历史节点': ('历史节点', 'Historical milestone'),
    '南澳': ('南澳', 'South Australia'),
    '昆士兰': ('昆士兰', 'Queensland'),
    '新南威尔士': ('新南威尔士', 'New South Wales'),
    '维州': ('维州', 'Victoria'),
    '西澳': ('西澳', 'Western Australia'),
    '塔州': ('塔州', 'Tasmania'),
    '北领地': ('北领地', 'Northern Territory'),
    '首都领地': ('首都领地', 'ACT'),
    '联邦': ('联邦', 'Federal'),
  };
  final value = labels[tag];
  if (value != null) return tr(context, value.$1, value.$2);
  if (!isChineseUi(context) && RegExp(r'[\u3400-\u9fff]').hasMatch(tag)) {
    // A newly-added legal/policy term must not leak Chinese into another UI.
    // Use a neutral label until its reviewed translation joins the catalogue.
    return tr(context, '其他主题', 'Other topic');
  }
  return tag;
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

import 'package:flutter/widgets.dart';

bool isChineseUi(BuildContext context) =>
    Localizations.localeOf(context).languageCode.toLowerCase() == 'zh';

String tr(BuildContext context, String zh, String en) =>
    isChineseUi(context) ? zh : en;

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

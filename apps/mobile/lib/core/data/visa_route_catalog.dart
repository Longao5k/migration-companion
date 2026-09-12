import 'package:flutter/widgets.dart';

import '../i18n/app_language.dart';

class VisaRouteDefinition {
  const VisaRouteDefinition(this.code, this.zh, this.en, {this.jurisdiction});

  final String code;
  final String zh;
  final String en;
  final String? jurisdiction;

  String label(bool zhUi) => zhUi ? '$code · $zh' : '$code · $en';
  String localizedLabel(BuildContext context) =>
      '$code · ${tr(context, zh, en)}';
}

const visaRouteCatalog = <VisaRouteDefinition>[
  VisaRouteDefinition('189', '独立技术移民', 'Skilled Independent'),
  VisaRouteDefinition('190', '州担保技术移民', 'Skilled Nominated'),
  VisaRouteDefinition('491', '偏远地区州担保/亲属担保', 'Skilled Work Regional'),
  VisaRouteDefinition('191', '偏远地区永久居留', 'Permanent Residence Regional'),
  VisaRouteDefinition('482', '雇主担保临时技能', 'Skills in Demand'),
  VisaRouteDefinition('186', '雇主提名永久居留', 'Employer Nomination Scheme'),
  VisaRouteDefinition('494', '偏远地区雇主担保', 'Skilled Employer Sponsored Regional'),
  VisaRouteDefinition('500', '学生签证', 'Student'),
  VisaRouteDefinition('485', '毕业生临时签证', 'Temporary Graduate'),
  VisaRouteDefinition('407', '培训签证', 'Training'),
  VisaRouteDefinition('600', '访客签证', 'Visitor'),
  VisaRouteDefinition('417', '打工度假', 'Working Holiday'),
  VisaRouteDefinition('462', '工作与度假', 'Work and Holiday'),
  VisaRouteDefinition('300', '未婚伴侣', 'Prospective Marriage'),
  VisaRouteDefinition('309/100', '境外伴侣', 'Partner offshore'),
  VisaRouteDefinition('820/801', '境内伴侣', 'Partner onshore'),
  VisaRouteDefinition('103/143', '境外父母', 'Parent offshore'),
  VisaRouteDefinition('804/864', '境内年迈父母', 'Aged Parent onshore'),
  VisaRouteDefinition('101/802/445', '子女与受抚养子女', 'Child & dependent child'),
  VisaRouteDefinition('858', '国家创新', 'National Innovation'),
  VisaRouteDefinition(
    '888',
    '商业创新与投资永久签证',
    'Business Innovation & Investment permanent',
  ),
  VisaRouteDefinition('155/157', '居民返程', 'Resident Return'),
  VisaRouteDefinition(
    'Protection/Humanitarian',
    '保护与人道类别',
    'Protection & humanitarian',
  ),
  VisaRouteDefinition('Custom', '自定义申请路线', 'Custom application route'),
];

const stateJurisdictions = <String>[
  'AU-ACT',
  'AU-NSW',
  'AU-NT',
  'AU-QLD',
  'AU-SA',
  'AU-TAS',
  'AU-VIC',
  'AU-WA',
];

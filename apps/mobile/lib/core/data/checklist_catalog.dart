import 'package:flutter/widgets.dart';

import '../i18n/app_language.dart';

class ChecklistDefinition {
  const ChecklistDefinition({
    required this.id,
    required this.zh,
    required this.en,
    required this.categoryZh,
    required this.categoryEn,
    required this.icon,
  });

  final String id;
  final String zh;
  final String en;
  final String categoryZh;
  final String categoryEn;
  final String icon;

  String label(BuildContext context) => tr(context, zh, en);
  String category(BuildContext context) => tr(context, categoryZh, categoryEn);
}

const checklistCatalog = <ChecklistDefinition>[
  ChecklistDefinition(
    id: 'identity-passport',
    zh: '护照与身份证明',
    en: 'Passport & identity',
    categoryZh: '身份',
    categoryEn: 'Identity',
    icon: 'badge',
  ),
  ChecklistDefinition(
    id: 'employment-evidence',
    zh: '工作经历与工资证明',
    en: 'Employment & income evidence',
    categoryZh: '工作',
    categoryEn: 'Employment',
    icon: 'work',
  ),
  ChecklistDefinition(
    id: 'english-evidence',
    zh: '英语能力证明',
    en: 'English language evidence',
    categoryZh: '语言',
    categoryEn: 'Language',
    icon: 'language',
  ),
  ChecklistDefinition(
    id: 'skills-assessment',
    zh: '职业评估与注册',
    en: 'Skills assessment & registration',
    categoryZh: '职业',
    categoryEn: 'Skills',
    icon: 'verified',
  ),
  ChecklistDefinition(
    id: 'education-evidence',
    zh: '学历与课程证明',
    en: 'Education & study evidence',
    categoryZh: '学历',
    categoryEn: 'Education',
    icon: 'school',
  ),
  ChecklistDefinition(
    id: 'relationship-evidence',
    zh: '关系与家庭证明',
    en: 'Relationship & family evidence',
    categoryZh: '家庭',
    categoryEn: 'Family',
    icon: 'family',
  ),
  ChecklistDefinition(
    id: 'financial-evidence',
    zh: '财务证明',
    en: 'Financial evidence',
    categoryZh: '财务',
    categoryEn: 'Financial',
    icon: 'account',
  ),
  ChecklistDefinition(
    id: 'health-evidence',
    zh: '体检与保险',
    en: 'Health & insurance',
    categoryZh: '健康',
    categoryEn: 'Health',
    icon: 'health',
  ),
  ChecklistDefinition(
    id: 'character-evidence',
    zh: '无犯罪记录与品行证明',
    en: 'Police & character evidence',
    categoryZh: '品行',
    categoryEn: 'Character',
    icon: 'shield',
  ),
  ChecklistDefinition(
    id: 'sponsor-evidence',
    zh: '担保与提名材料',
    en: 'Sponsor & nomination evidence',
    categoryZh: '担保',
    categoryEn: 'Sponsorship',
    icon: 'handshake',
  ),
  ChecklistDefinition(
    id: 'translations-evidence',
    zh: '翻译与认证件',
    en: 'Translations & certified copies',
    categoryZh: '认证',
    categoryEn: 'Certification',
    icon: 'translate',
  ),
  ChecklistDefinition(
    id: 'forms-evidence',
    zh: '申请表格与授权',
    en: 'Forms & authorities',
    categoryZh: '表格',
    categoryEn: 'Forms',
    icon: 'description',
  ),
];

ChecklistDefinition? checklistDefinitionById(String? id) {
  if (id == null) return null;
  for (final item in checklistCatalog) {
    if (item.id == id || id.startsWith('${item.id}-')) return item;
  }
  return null;
}

String checklistTitle(BuildContext context, String id, String storedTitle) =>
    checklistDefinitionById(id)?.label(context) ?? storedTitle;

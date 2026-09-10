class MaterialCategoryDefinition {
  const MaterialCategoryDefinition(this.id, this.zh, this.en, this.iconName);

  final String id;
  final String zh;
  final String en;
  final String iconName;

  String label(bool zhUi) => zhUi ? zh : en;
}

const materialCategoryCatalog = <MaterialCategoryDefinition>[
  MaterialCategoryDefinition(
    'identity',
    '护照与身份',
    'Passport & identity',
    'badge',
  ),
  MaterialCategoryDefinition(
    'relationship',
    '关系与家庭',
    'Relationships & family',
    'family',
  ),
  MaterialCategoryDefinition('english', '英语成绩', 'English language', 'language'),
  MaterialCategoryDefinition(
    'education',
    '学历与课程',
    'Education & study',
    'school',
  ),
  MaterialCategoryDefinition(
    'skills',
    '职业评估与注册',
    'Skills assessment & registration',
    'verified',
  ),
  MaterialCategoryDefinition(
    'employment',
    '工作与工资证明',
    'Employment & income',
    'work',
  ),
  MaterialCategoryDefinition(
    'financial',
    '财务证明',
    'Financial evidence',
    'account',
  ),
  MaterialCategoryDefinition('health', '体检与保险', 'Health & insurance', 'health'),
  MaterialCategoryDefinition(
    'character',
    '无犯罪与品行',
    'Police & character',
    'shield',
  ),
  MaterialCategoryDefinition(
    'sponsor',
    '担保与提名',
    'Sponsor & nomination',
    'handshake',
  ),
  MaterialCategoryDefinition(
    'translations',
    '翻译与认证',
    'Translations & certification',
    'translate',
  ),
  MaterialCategoryDefinition(
    'forms',
    '表格与授权',
    'Forms & authority',
    'description',
  ),
  MaterialCategoryDefinition('other', '其他材料', 'Other documents', 'folder'),
];

MaterialCategoryDefinition? materialCategoryById(String id) {
  for (final category in materialCategoryCatalog) {
    if (category.id == id) return category;
  }
  return null;
}

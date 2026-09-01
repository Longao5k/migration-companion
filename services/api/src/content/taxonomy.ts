/**
 * 标签词表。与采集器的 `tagging.py` 是同一份，必须同步改。
 *
 * 三个轴：
 * - **辖区**是一等字段（`Source.jurisdiction`），不进 tags。在两处各留一份是双份真相，
 *   而且正是它把签证标签挤没的原因。
 * - **签证类别**与**主题**进 tags，都是封闭词表。
 *
 * 封闭是有意的：开放词表会让运营敲出 `SA`、`南澳`、`sa` 三种写法，
 * 用户订阅其中一种就漏掉另外两种。
 */

export const VISA_SUBCLASSES = [
  '189', '190', '491', '494', '186', '482', '485',
  '417', '462', '500', '590', '600', '601', '651',
  '820', '801', '309', '100', '300', '101', '102', '802',
  '103', '143', '173', '804', '864', '884', '870',
  '188', '888', '858', '400', '403', '407', '408',
  '449', '785', '790', '866',
] as const;

export const TOPICS = [
  '职业清单', '邀请轮次', '提名条件', '申请材料', '审理时间',
  '打分规则', '英语要求', '费用', '法规', '项目开关', '活动',
  '名额', 'ROI', 'DAMA', '薪资门槛', '雇主担保', '职业评估',
  '学生签证', '家庭与配偶', '访客签证', '工作度假', '人道与保护',
  '公民入籍', '移民代理', '边境与旅行', '工作权益', '永久移民计划',
] as const;

export const JURISDICTIONS: Record<string, string> = {
  'AU-SA': '南澳',
  'AU-QLD': '昆士兰',
  'AU-NSW': '新南威尔士',
  'AU-VIC': '维州',
  'AU-WA': '西澳',
  'AU-TAS': '塔州',
  'AU-NT': '北领地',
  'AU-ACT': '首都领地',
  'AU-FED': '联邦',
};

const allowed = new Set<string>([...VISA_SUBCLASSES, ...TOPICS]);

export function isKnownTag(tag: string) {
  return allowed.has(tag);
}

export function knownTags() {
  return [...allowed];
}

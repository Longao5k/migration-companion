/**
 * 一条内容该不该进某个订阅者的收件箱。
 *
 * 单独拎出来是因为这段判断决定了「谁收到提醒」，而它整个的错误方式是**静默**的：
 * 判错了不会报错、不会有日志，只是有人再也收不到提醒。上一次它错了多久没人知道——
 * 资讯扇出时一律按「不重要」传，而 `importantOnly` 默认开着，
 * 于是所有资讯通知都被丢掉，直到有人去数 outbox 才发现是空的。
 *
 * 放在服务里就只能连着数据库测；放在这里可以直接对着断言跑。
 */

export type NotifiableItem =
  | { kind: 'news'; jurisdiction: string; tags: string[] }
  | {
      kind: 'change';
      jurisdiction: string;
      tags: string[];
      isImportant: boolean;
    };

export type SubscriberPreference = {
  jurisdictions: string[];
  tags: string[];
  importantOnly: boolean;
};

export function matchesPreference(
  item: NotifiableItem,
  preference: SubscriberPreference,
): boolean {
  // 「只推重要」只管变更。资讯没有重要性分级，拿这个开关去筛它，
  // 等于把整类内容静默关掉。
  if (item.kind === 'change' && preference.importantOnly && !item.isImportant) {
    return false;
  }
  if (!preference.jurisdictions.includes(item.jurisdiction)) return false;
  // 没选标签 = 该辖区全收，不是「什么都不收」。
  return (
    preference.tags.length === 0 ||
    preference.tags.some((tag) => item.tags.includes(tag))
  );
}

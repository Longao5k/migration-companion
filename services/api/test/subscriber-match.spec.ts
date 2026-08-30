import { matchesPreference } from '../src/content/subscriber-match';

const subscriber = {
  jurisdictions: ['AU-SA', 'AU-QLD'],
  tags: ['190', '491'],
  importantOnly: true,
};

describe('谁会收到提醒', () => {
  it('资讯不被「只推重要」挡掉', () => {
    // 这是回归测试。之前资讯扇出时一律传 isImportant: false，而 importantOnly
    // 默认开着，于是**所有**资讯通知都被静默丢弃——没有报错、没有日志，
    // 只有 outbox 一直是空的。产品的核心承诺就此失效，而且看不出来。
    expect(
      matchesPreference(
        { kind: 'news', jurisdiction: 'AU-SA', tags: ['190'] },
        subscriber,
      ),
    ).toBe(true);
  });

  it('「只推重要」仍然挡得住不重要的变更', () => {
    expect(
      matchesPreference(
        {
          kind: 'change',
          jurisdiction: 'AU-SA',
          tags: ['190'],
          isImportant: false,
        },
        subscriber,
      ),
    ).toBe(false);
  });

  it('重要变更照常送达', () => {
    expect(
      matchesPreference(
        {
          kind: 'change',
          jurisdiction: 'AU-SA',
          tags: ['190'],
          isImportant: true,
        },
        subscriber,
      ),
    ).toBe(true);
  });

  it('关掉「只推重要」之后，一般变更也送达', () => {
    expect(
      matchesPreference(
        {
          kind: 'change',
          jurisdiction: 'AU-SA',
          tags: ['190'],
          isImportant: false,
        },
        { ...subscriber, importantOnly: false },
      ),
    ).toBe(true);
  });

  it('没关注的辖区不送', () => {
    // 把昆士兰的提名政策推给只关注南澳的人，会让人按错误的州准备材料。
    expect(
      matchesPreference(
        { kind: 'news', jurisdiction: 'AU-NSW', tags: ['190'] },
        subscriber,
      ),
    ).toBe(false);
  });

  it('没关注的签证类别不送', () => {
    expect(
      matchesPreference(
        { kind: 'news', jurisdiction: 'AU-SA', tags: ['482'] },
        subscriber,
      ),
    ).toBe(false);
  });

  it('没选标签等于该辖区全收，不是什么都不收', () => {
    expect(
      matchesPreference(
        { kind: 'news', jurisdiction: 'AU-SA', tags: ['482'] },
        { ...subscriber, tags: [] },
      ),
    ).toBe(true);
  });

  it('多个标签命中其中一个即可', () => {
    expect(
      matchesPreference(
        { kind: 'news', jurisdiction: 'AU-QLD', tags: ['职业清单', '491'] },
        subscriber,
      ),
    ).toBe(true);
  });

  it('内容没有任何标签时，只按辖区判断的订阅者仍然收得到', () => {
    expect(
      matchesPreference(
        { kind: 'news', jurisdiction: 'AU-SA', tags: [] },
        { ...subscriber, tags: [] },
      ),
    ).toBe(true);
    // 但选了标签的人收不到——没有标签的内容无法证明它与关注的类别相关。
    expect(
      matchesPreference({ kind: 'news', jurisdiction: 'AU-SA', tags: [] }, subscriber),
    ).toBe(false);
  });
});

import { BadRequestException } from '@nestjs/common';
import { assertExcerptQuota, excerptLimits } from '../src/content/excerpt-quota';

describe('官方原文引用配额', () => {
  it('合计超过上限时拒绝', () => {
    expect(() =>
      assertExcerptQuota({
        oldExcerpt: 'a'.repeat(600),
        newExcerpt: 'b'.repeat(600),
        context: 'c'.repeat(100),
      }),
    ).toThrow(BadRequestException);
  });

  it('短页面不允许被整页引用：固定上限之内，但超过正文比例同样拒绝', () => {
    // 实测南澳新闻页规范化正文 2,219 字符。合计 1,000 字符在固定上限之内，
    // 却已经是整页的 45%——这正是旧规则漏掉的情况。
    expect(() =>
      assertExcerptQuota({
        oldExcerpt: 'a'.repeat(500),
        newExcerpt: 'b'.repeat(500),
        sourceBodyChars: 2219,
      }),
    ).toThrow(/20%/);
  });

  it('片段足够小时通过', () => {
    expect(() =>
      assertExcerptQuota({
        oldExcerpt: 'a'.repeat(200),
        newExcerpt: 'b'.repeat(200),
        sourceBodyChars: 2219,
      }),
    ).not.toThrow();
  });

  it('缺少正文长度时仍然执行固定合计上限', () => {
    expect(() =>
      assertExcerptQuota({ oldExcerpt: 'a'.repeat(excerptLimits.combined + 1) }),
    ).toThrow(BadRequestException);
  });
});

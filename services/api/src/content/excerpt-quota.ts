import { BadRequestException } from '@nestjs/common';

/**
 * 官方原文的引用配额。
 *
 * 冻结规则：正文只保留生成差异和审计所需的最小证据，不把官方或媒体全文作为自有内容重新发布。
 *
 * 光靠固定字符上限不够。实测南澳新闻页规范化正文只有 2,219 字符，而原先 old/new 各允许
 * 2,000 字符（合计 4,000）——配额是整页的 180%，且 `/v1/content/changes` 是公开免鉴权接口。
 * 因此这里同时限制**合计字符数**和**占来源正文的比例**：短页面由比例挡住，长页面由字符数挡住。
 */
export const excerptLimits = {
  /** 单个片段上限，与 DTO 保持一致。 */
  perField: 600,
  /** 一条变更记录里 old + new + context 的合计上限。 */
  combined: 1200,
  /** 合计不得超过来源页面正文的这个比例。 */
  bodyRatio: 0.2,
};

export function assertExcerptQuota(input: {
  oldExcerpt?: string | null;
  newExcerpt?: string | null;
  context?: string | null;
  sourceBodyChars?: number | null;
}) {
  const used =
    (input.oldExcerpt?.length ?? 0) +
    (input.newExcerpt?.length ?? 0) +
    (input.context?.length ?? 0);

  if (used > excerptLimits.combined) {
    throw new BadRequestException(
      `引用的官方原文合计 ${used} 字符，超过 ${excerptLimits.combined} 字符上限。` +
        '变更记录只能保留生成差异所需的最小片段，不能承载整页原文。',
    );
  }

  const body = input.sourceBodyChars ?? 0;
  if (body > 0) {
    const allowed = Math.floor(body * excerptLimits.bodyRatio);
    if (used > allowed) {
      throw new BadRequestException(
        `引用的官方原文合计 ${used} 字符，超过该页面正文（${body} 字符）的 ` +
          `${Math.round(excerptLimits.bodyRatio * 100)}%（${allowed} 字符）。` +
          '短页面同样不允许被整页引用。',
      );
    }
  }
}

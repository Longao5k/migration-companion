ALTER TABLE "NewsItem"
  ADD COLUMN "editorialRevisionCount" INTEGER NOT NULL DEFAULT 0;

-- 原始法规记录属于法规监控/知识资料；超过 15 个月的旧闻属于历史资料。
-- 两类都保留原文、双语稿和复核记录，但退出实时资讯流与人工待办。
UPDATE "NewsItem" AS news
SET
  "editorialReviewStatus" = 'REFERENCE_ONLY',
  "isPublished" = FALSE,
  "editorialRiskReasons" = CASE
    WHEN source.url LIKE '%legislation.gov.au%'
      OR source.name ~* '\m(act|regulation|instrument|determination)\M'
      THEN ARRAY['法规原始记录：保留用于法规监控，不作为新闻逐条审核']::TEXT[]
    ELSE ARRAY['历史资料：发布时间超过 15 个月，不进入当前资讯流']::TEXT[]
  END
FROM "Source" AS source
WHERE news."sourceId" = source.id
  AND news."editorialReviewStatus" IN ('PENDING', 'HUMAN_REQUIRED', 'FAILED')
  AND (
    source.url LIKE '%legislation.gov.au%'
    OR source.name ~* '\m(act|regulation|instrument|determination)\M'
    OR news."publishedAt" < NOW() - INTERVAL '15 months'
  );

-- 保留官方原文摘录，供审核时与中文译稿并排比对。
-- 原先英文摘录被临时放在 summaryZh 里，编辑一写中文就永久覆盖。
ALTER TABLE "NewsItem" ADD COLUMN "sourceExcerpt" TEXT;

-- 已有的草稿：summaryZh 里如果还是英文（没有 CJK 字符），那就是原文摘录，搬过去。
-- 已经写了中文的条目原文已经丢了，只能留空——由采集器下一轮补回。
UPDATE "NewsItem"
SET "sourceExcerpt" = "summaryZh"
WHERE "sourceExcerpt" IS NULL
  AND "summaryZh" !~ '[一-龥]';

-- 中文编辑稿的作者。模型起草的稿子要逐字核对——它编造过邀请人数。
ALTER TABLE "NewsItem" ADD COLUMN "draftAuthor" TEXT;

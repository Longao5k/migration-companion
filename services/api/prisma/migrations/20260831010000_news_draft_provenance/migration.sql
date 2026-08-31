-- 模型稿的溯源信息：谁写的、什么时候写的、校验层验过哪些项。
--
-- 审的人最想知道的是「哪些地方机器已经核过、我可以少看一眼，哪些没核过、
-- 必须我自己盯」。这个信息此前只打在 console 日志里，一个字都没进到审核界面，
-- 于是每一条都只能当成完全没核过来审。

ALTER TABLE "NewsItem" ADD COLUMN "draftModel" TEXT;
ALTER TABLE "NewsItem" ADD COLUMN "draftedAt" TIMESTAMP(3);
ALTER TABLE "NewsItem" ADD COLUMN "draftChecks" TEXT[] DEFAULT ARRAY[]::TEXT[];

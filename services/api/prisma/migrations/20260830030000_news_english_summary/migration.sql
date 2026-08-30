-- 中英双语摘要。申请人常要把政策转述给雇主、律师或职业评估机构，那些场合要英文。
-- 与 sourceExcerpt 区分：那是官方原文摘录（受版权约束、只作核实用），
-- 这两列是我们自己写的编辑内容的英文版。
ALTER TABLE "NewsItem" ADD COLUMN "titleEn" TEXT;
ALTER TABLE "NewsItem" ADD COLUMN "summaryEn" TEXT;

ALTER TABLE "Source"
ADD COLUMN "lastSuccessAt" TIMESTAMP(3),
ADD COLUMN "lastFailureAt" TIMESTAMP(3),
ADD COLUMN "lastFailureCode" TEXT;

ALTER TABLE "ChangeLog"
ADD COLUMN "tags" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
ADD COLUMN "candidateHash" TEXT;

ALTER TABLE "NewsItem"
ADD COLUMN "isPublished" BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX "NewsItem_isPublished_publishedAt_idx"
ON "NewsItem"("isPublished", "publishedAt");

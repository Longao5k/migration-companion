CREATE TYPE "EditorialReviewStatus" AS ENUM (
  'PENDING',
  'AUTO_APPROVED',
  'HUMAN_REQUIRED',
  'HUMAN_APPROVED',
  'FAILED'
);

ALTER TABLE "NewsItem"
  ADD COLUMN "editorialReviewStatus" "EditorialReviewStatus" NOT NULL DEFAULT 'PENDING',
  ADD COLUMN "editorialReviewModel" TEXT,
  ADD COLUMN "editorialReviewedAt" TIMESTAMP(3),
  ADD COLUMN "editorialReviewRuns" INTEGER,
  ADD COLUMN "editorialFindings" JSONB,
  ADD COLUMN "editorialRiskReasons" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];

CREATE INDEX "NewsItem_editorialReviewStatus_publishedAt_idx"
  ON "NewsItem"("editorialReviewStatus", "publishedAt");

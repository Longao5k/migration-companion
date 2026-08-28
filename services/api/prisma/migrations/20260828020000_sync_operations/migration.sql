CREATE TABLE "SyncOperation" (
  "id" TEXT NOT NULL,
  "projectId" TEXT NOT NULL,
  "accountId" TEXT NOT NULL,
  "payloadHash" TEXT NOT NULL,
  "result" JSONB NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "SyncOperation_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "SyncOperation_projectId_createdAt_idx"
ON "SyncOperation"("projectId", "createdAt");

CREATE INDEX "SyncOperation_accountId_createdAt_idx"
ON "SyncOperation"("accountId", "createdAt");

ALTER TABLE "SyncOperation"
ADD CONSTRAINT "SyncOperation_projectId_fkey"
FOREIGN KEY ("projectId") REFERENCES "Project"("id")
ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "SyncOperation"
ADD CONSTRAINT "SyncOperation_accountId_fkey"
FOREIGN KEY ("accountId") REFERENCES "Account"("id")
ON DELETE CASCADE ON UPDATE CASCADE;

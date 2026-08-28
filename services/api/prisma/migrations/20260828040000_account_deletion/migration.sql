CREATE TABLE "AccountDeletionLedger" (
    "id" TEXT NOT NULL,
    "accountHash" TEXT NOT NULL,
    "requestedAt" TIMESTAMP(3) NOT NULL,
    "deletedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "objectCount" INTEGER NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'COMPLETED',

    CONSTRAINT "AccountDeletionLedger_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "AccountDeletionLedger_accountHash_deletedAt_idx"
ON "AccountDeletionLedger"("accountHash", "deletedAt");

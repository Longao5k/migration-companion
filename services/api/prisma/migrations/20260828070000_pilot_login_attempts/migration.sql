-- 内测登录失败计数与锁定。逐邮箱绑定的访问码使暴力猜测只能针对单个邮箱，
-- 未注册邮箱同样计数，避免通过响应差异枚举内测名单。
-- CreateTable
CREATE TABLE "PilotLoginAttempt" (
    "email" TEXT NOT NULL,
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "lockedUntil" TIMESTAMP(3),
    "lastAttempt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PilotLoginAttempt_pkey" PRIMARY KEY ("email")
);

-- CreateIndex
CREATE INDEX "PilotLoginAttempt_lockedUntil_idx" ON "PilotLoginAttempt"("lockedUntil");

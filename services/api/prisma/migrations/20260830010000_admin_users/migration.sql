-- 后台管理员账号从环境变量迁到数据库。
-- 原因见 schema.prisma 里 AdminUser 的注释：env 那条路要求密码跨机器、
-- 哈希过命令行、改密码要重启，而且一个格式错误会锁死所有管理员。
CREATE TABLE "AdminUser" (
    "email" TEXT NOT NULL,
    "passwordHash" TEXT NOT NULL,
    "displayName" TEXT,
    "disabled" BOOLEAN NOT NULL DEFAULT false,
    "lastLoginAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "AdminUser_pkey" PRIMARY KEY ("email")
);

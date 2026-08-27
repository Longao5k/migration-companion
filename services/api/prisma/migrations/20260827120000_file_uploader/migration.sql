-- 记录云文件的上传者，用于执行冻结的协作权限：
-- 所有者可以删除项目内任何文件；可协作成员只能删除自己上传的文件；仅查看成员不能删除。
-- 既有记录没有上传者信息，保持为 NULL，只有所有者可以删除。
-- AlterTable
ALTER TABLE "FileRecord" ADD COLUMN "uploadedById" TEXT;

-- CreateIndex
CREATE INDEX "FileRecord_uploadedById_idx" ON "FileRecord"("uploadedById");

-- AddForeignKey
ALTER TABLE "FileRecord" ADD CONSTRAINT "FileRecord_uploadedById_fkey" FOREIGN KEY ("uploadedById") REFERENCES "Account"("id") ON DELETE SET NULL ON UPDATE CASCADE;

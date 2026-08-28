ALTER TABLE "UploadSession" ADD COLUMN "fileId" TEXT;

CREATE UNIQUE INDEX "UploadSession_fileId_key" ON "UploadSession"("fileId");

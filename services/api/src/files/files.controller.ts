import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Post,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { AuthenticatedUser } from '../auth/auth.types';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { WorkerApiKeyGuard } from '../content/api-key.guard';
import { CompleteUploadDto, CreateUploadDto, DirectUploadDto, ScanResultDto } from './files.dto';
import { FilesService } from './files.service';

@Controller()
@UseGuards(JwtAuthGuard)
export class FilesController {
  constructor(private readonly files: FilesService) {}

  @Post('projects/:projectId/uploads')
  createUpload(
    @CurrentUser() user: AuthenticatedUser,
    @Param('projectId') projectId: string,
    @Body() body: CreateUploadDto,
  ) {
    return this.files.createUpload(user.accountId, projectId, body);
  }

  @Post('projects/:projectId/files')
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: 50 * 1024 * 1024, files: 1 } }))
  directUpload(
    @CurrentUser() user: AuthenticatedUser,
    @Param('projectId') projectId: string,
    @UploadedFile() file: Express.Multer.File | undefined,
    @Body() body: DirectUploadDto,
  ) {
    return this.files.directUpload(user.accountId, projectId, file, body.checklistItemId);
  }

  @Post('uploads/:uploadId/complete')
  complete(
    @CurrentUser() user: AuthenticatedUser,
    @Param('uploadId') uploadId: string,
    @Body() body: CompleteUploadDto,
  ) {
    return this.files.complete(user.accountId, uploadId, body);
  }

  @Get('files/:fileId/download')
  download(@CurrentUser() user: AuthenticatedUser, @Param('fileId') fileId: string) {
    return this.files.createDownload(user.accountId, fileId);
  }

  @Delete('files/:fileId')
  remove(@CurrentUser() user: AuthenticatedUser, @Param('fileId') fileId: string) {
    return this.files.deleteFile(user.accountId, fileId);
  }
}

@Controller('file-worker')
export class FileWorkerController {
  constructor(private readonly files: FilesService) {}

  @Post('cleanup-expired-uploads')
  cleanupExpiredUploads() {
    return this.files.cleanupExpiredUploads();
  }

  @Post(':fileId/scan-result')
  @UseGuards(WorkerApiKeyGuard)
  scanResult(@Param('fileId') fileId: string, @Body() body: ScanResultDto) {
    return this.files.applyScanResult(fileId, body);
  }
}

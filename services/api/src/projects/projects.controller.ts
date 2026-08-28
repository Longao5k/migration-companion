import { Body, Controller, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { AuthenticatedUser } from '../auth/auth.types';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import {
  CloudFilesConsentDto,
  CreateChecklistItemDto,
  CreateProjectDto,
  SyncOperationDto,
  UpdateChecklistDto,
  ViewerDownloadDto,
} from './projects.dto';
import { ProjectsService } from './projects.service';

@Controller('projects')
@UseGuards(JwtAuthGuard)
export class ProjectsController {
  constructor(private readonly projects: ProjectsService) {}

  @Get()
  list(@CurrentUser() user: AuthenticatedUser) {
    return this.projects.list(user.accountId);
  }

  @Post()
  create(@CurrentUser() user: AuthenticatedUser, @Body() body: CreateProjectDto) {
    return this.projects.create(user.accountId, user.email, body);
  }

  @Get(':projectId')
  get(@CurrentUser() user: AuthenticatedUser, @Param('projectId') projectId: string) {
    return this.projects.get(user.accountId, projectId);
  }

  @Patch(':projectId/checklist/:itemId')
  updateChecklist(
    @CurrentUser() user: AuthenticatedUser,
    @Param('projectId') projectId: string,
    @Param('itemId') itemId: string,
    @Body() body: UpdateChecklistDto,
  ) {
    return this.projects.updateChecklist(user.accountId, projectId, itemId, body);
  }

  @Patch(':projectId/cloud-files')
  setCloudFiles(
    @CurrentUser() user: AuthenticatedUser,
    @Param('projectId') projectId: string,
    @Body() body: CloudFilesConsentDto,
  ) {
    return this.projects.setCloudFiles(user.accountId, projectId, body.enabled);
  }

  @Patch(':projectId/viewer-download')
  setViewerDownload(
    @CurrentUser() user: AuthenticatedUser,
    @Param('projectId') projectId: string,
    @Body() body: ViewerDownloadDto,
  ) {
    return this.projects.setViewerDownload(user.accountId, projectId, body.enabled);
  }

  @Post(':projectId/checklist')
  addChecklistItem(
    @CurrentUser() user: AuthenticatedUser,
    @Param('projectId') projectId: string,
    @Body() body: CreateChecklistItemDto,
  ) {
    return this.projects.addChecklistItem(user.accountId, projectId, body);
  }

  @Post(':projectId/sync-operations')
  applySyncOperation(
    @CurrentUser() user: AuthenticatedUser,
    @Param('projectId') projectId: string,
    @Body() body: SyncOperationDto,
  ) {
    return this.projects.applySyncOperation(user.accountId, projectId, body);
  }
}

import { Module } from '@nestjs/common';
import { AuthController } from './auth/auth.controller';
import { JwtAuthGuard } from './auth/jwt-auth.guard';
import { ContentController } from './content/content.controller';
import { ContentService } from './content/content.service';
import { CollaborationController } from './collaboration/collaboration.controller';
import { CollaborationService } from './collaboration/collaboration.service';
import { AdminApiKeyGuard, WorkerApiKeyGuard } from './content/api-key.guard';
import { HealthController } from './health.controller';
import { FilesController, FileWorkerController } from './files/files.controller';
import { FilesService } from './files/files.service';
import {
  EntitlementsController,
  StoreEventsController,
} from './entitlements/entitlements.controller';
import { EntitlementsService } from './entitlements/entitlements.service';
import { PrismaService } from './prisma.service';
import { ProjectsController } from './projects/projects.controller';
import { ProjectsService } from './projects/projects.service';
import { SharesController } from './shares/shares.controller';
import { SharesService } from './shares/shares.service';

@Module({
  imports: [],
  controllers: [
    HealthController,
    AuthController,
    ProjectsController,
    SharesController,
    ContentController,
    FilesController,
    FileWorkerController,
    CollaborationController,
    EntitlementsController,
    StoreEventsController,
  ],
  providers: [
    PrismaService,
    JwtAuthGuard,
    ProjectsService,
    SharesService,
    ContentService,
    AdminApiKeyGuard,
    WorkerApiKeyGuard,
    FilesService,
    CollaborationService,
    EntitlementsService,
  ],
})
export class AppModule {}

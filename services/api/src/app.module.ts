import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
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
import { AccountDeletionService } from './account-deletion/account-deletion.service';
import { AccountDeletionWorkerController } from './account-deletion/account-deletion.controller';
import {
  NotificationPreferencesController,
  NotificationWorkerController,
} from './notifications/notifications.controller';
import { NotificationsService } from './notifications/notifications.service';
import { AdminAuthController } from './auth/admin-auth.controller';
import { AdminAuthService } from './auth/admin-auth.service';
import { PilotAuthController } from './auth/pilot-auth.controller';
import { PilotAuthService } from './auth/pilot-auth.service';

@Module({
  imports: [JwtModule.register({})],
  controllers: [
    HealthController,
    AdminAuthController,
    PilotAuthController,
    AuthController,
    ProjectsController,
    SharesController,
    ContentController,
    FilesController,
    FileWorkerController,
    CollaborationController,
    EntitlementsController,
    StoreEventsController,
    AccountDeletionWorkerController,
    NotificationPreferencesController,
    NotificationWorkerController,
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
    AccountDeletionService,
    NotificationsService,
    AdminAuthService,
    PilotAuthService,
  ],
})
export class AppModule {}

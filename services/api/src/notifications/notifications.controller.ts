import { Body, Controller, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { AuthenticatedUser } from '../auth/auth.types';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { WorkerApiKeyGuard } from '../content/api-key.guard';
import {
  ClaimNotificationsDto,
  NotificationResultDto,
  UpdateNotificationPreferenceDto,
} from './notifications.dto';
import { NotificationsService } from './notifications.service';

@Controller('notification-preferences')
@UseGuards(JwtAuthGuard)
export class NotificationPreferencesController {
  constructor(private readonly notifications: NotificationsService) {}

  @Get()
  get(@CurrentUser() user: AuthenticatedUser) {
    return this.notifications.getPreference(user.accountId);
  }

  @Patch()
  update(
    @CurrentUser() user: AuthenticatedUser,
    @Body() body: UpdateNotificationPreferenceDto,
  ) {
    return this.notifications.updatePreference(user.accountId, body);
  }
}

@Controller('notification-worker')
@UseGuards(WorkerApiKeyGuard)
export class NotificationWorkerController {
  constructor(private readonly notifications: NotificationsService) {}

  @Post('claim')
  claim(@Body() body: ClaimNotificationsDto) {
    return this.notifications.claim(body);
  }

  @Post(':id/result')
  result(@Param('id') id: string, @Body() body: NotificationResultDto) {
    return this.notifications.recordResult(id, body);
  }
}

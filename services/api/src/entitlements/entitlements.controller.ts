import { Body, Controller, Get, Post, UseGuards } from '@nestjs/common';
import { AuthenticatedUser } from '../auth/auth.types';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { WorkerApiKeyGuard } from '../content/api-key.guard';
import { SubmitPurchaseDto, VerifiedStoreEventDto } from './entitlements.dto';
import { EntitlementsService } from './entitlements.service';

@Controller('entitlements')
@UseGuards(JwtAuthGuard)
export class EntitlementsController {
  constructor(private readonly entitlements: EntitlementsService) {}

  @Get('me')
  me(@CurrentUser() user: AuthenticatedUser) {
    return this.entitlements.get(user.accountId, user.email);
  }

  @Post('trial')
  startTrial(@CurrentUser() user: AuthenticatedUser) {
    return this.entitlements.startTrial(user.accountId, user.email);
  }

  @Post('restore')
  restore(@CurrentUser() user: AuthenticatedUser) {
    return this.entitlements.restore(user.accountId, user.email);
  }

  @Post('purchases')
  purchase(@CurrentUser() user: AuthenticatedUser, @Body() body: SubmitPurchaseDto) {
    return this.entitlements.submitPurchase(user.accountId, user.email, body);
  }
}

@Controller('store-events')
@UseGuards(WorkerApiKeyGuard)
export class StoreEventsController {
  constructor(private readonly entitlements: EntitlementsService) {}

  @Post('verified')
  verified(@Body() body: VerifiedStoreEventDto) {
    return this.entitlements.applyVerifiedStoreEvent(body);
  }
}

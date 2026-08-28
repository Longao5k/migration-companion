import { Controller, Delete, Get, Post, UseGuards } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { AccountDeletionService } from '../account-deletion/account-deletion.service';
import { CurrentUser } from './current-user.decorator';
import { JwtAuthGuard } from './jwt-auth.guard';
import { AuthenticatedUser } from './auth.types';

@Controller('auth')
@UseGuards(JwtAuthGuard)
export class AuthController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly deletion: AccountDeletionService,
  ) {}

  @Get('me')
  async me(@CurrentUser() user: AuthenticatedUser) {
    return this.prisma.account.upsert({
      where: { id: user.accountId },
      create: { id: user.accountId, email: user.email || `${user.accountId}@cognito.invalid` },
      update: {},
      select: {
        id: true,
        email: true,
        createdAt: true,
        deletionRequestedAt: true,
        subscription: { select: { status: true, productId: true, currentPeriodEndsAt: true } },
      },
    });
  }

  @Delete('me')
  deleteMe(@CurrentUser() user: AuthenticatedUser) {
    return this.deletion.request(user.accountId);
  }

  @Post('me/deletion/cancel')
  cancelDeletion(@CurrentUser() user: AuthenticatedUser) {
    return this.deletion.cancel(user.accountId);
  }
}

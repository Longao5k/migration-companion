import { Controller, Delete, Get, UseGuards } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { CurrentUser } from './current-user.decorator';
import { JwtAuthGuard } from './jwt-auth.guard';
import { AuthenticatedUser } from './auth.types';

@Controller('auth')
@UseGuards(JwtAuthGuard)
export class AuthController {
  constructor(private readonly prisma: PrismaService) {}

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
        subscription: { select: { status: true, productId: true, currentPeriodEndsAt: true } },
      },
    });
  }

  @Delete('me')
  async deleteMe(@CurrentUser() user: AuthenticatedUser) {
    await this.prisma.account.update({
      where: { id: user.accountId },
      data: { deletionRequestedAt: new Date() },
    });
    return { accepted: true, targetDeletionDays: 7, backupRemovalDays: 35 };
  }
}

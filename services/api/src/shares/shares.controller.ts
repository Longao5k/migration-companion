import { Body, Controller, Delete, Get, Param, Post, UseGuards } from '@nestjs/common';
import { AuthenticatedUser } from '../auth/auth.types';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { AccessShareDto, CreateShareDto } from './shares.dto';
import { SharesService } from './shares.service';

@Controller()
export class SharesController {
  constructor(private readonly shares: SharesService) {}

  @Post('projects/:projectId/shares')
  @UseGuards(JwtAuthGuard)
  create(
    @CurrentUser() user: AuthenticatedUser,
    @Param('projectId') projectId: string,
    @Body() body: CreateShareDto,
  ) {
    return this.shares.create(user.accountId, projectId, body);
  }

  @Post('public/shares/:shareId/access')
  access(@Param('shareId') shareId: string, @Body() body: AccessShareDto) {
    return this.shares.access(shareId, body);
  }

  @Get('projects/:projectId/shares')
  @UseGuards(JwtAuthGuard)
  list(@CurrentUser() user: AuthenticatedUser, @Param('projectId') projectId: string) {
    return this.shares.list(user.accountId, projectId);
  }

  @Delete('shares/:shareId')
  @UseGuards(JwtAuthGuard)
  revoke(@CurrentUser() user: AuthenticatedUser, @Param('shareId') shareId: string) {
    return this.shares.revoke(user.accountId, shareId);
  }
}

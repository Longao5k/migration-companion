import { Body, Controller, Delete, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { AuthenticatedUser } from '../auth/auth.types';
import { CurrentUser } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import {
  AcceptInvitationDto,
  CreateCommentDto,
  CreateInvitationDto,
  UpdateCollaboratorDto,
} from './collaboration.dto';
import { CollaborationService } from './collaboration.service';

@Controller()
@UseGuards(JwtAuthGuard)
export class CollaborationController {
  constructor(private readonly collaboration: CollaborationService) {}

  @Post('projects/:projectId/invitations')
  invite(
    @CurrentUser() user: AuthenticatedUser,
    @Param('projectId') projectId: string,
    @Body() body: CreateInvitationDto,
  ) {
    return this.collaboration.createInvitation(user.accountId, user.email, projectId, body);
  }

  @Post('collaboration-invitations/:invitationId/accept')
  accept(
    @CurrentUser() user: AuthenticatedUser,
    @Param('invitationId') invitationId: string,
    @Body() body: AcceptInvitationDto,
  ) {
    return this.collaboration.accept(user.accountId, user.email, invitationId, body);
  }

  @Get('projects/:projectId/collaboration')
  list(@CurrentUser() user: AuthenticatedUser, @Param('projectId') projectId: string) {
    return this.collaboration.list(user.accountId, projectId);
  }

  @Patch('projects/:projectId/collaborators/:accountId')
  updateCollaborator(
    @CurrentUser() user: AuthenticatedUser,
    @Param('projectId') projectId: string,
    @Param('accountId') collaboratorAccountId: string,
    @Body() body: UpdateCollaboratorDto,
  ) {
    return this.collaboration.updateCollaborator(
      user.accountId,
      projectId,
      collaboratorAccountId,
      body,
    );
  }

  @Delete('projects/:projectId/collaborators/:accountId')
  removeCollaborator(
    @CurrentUser() user: AuthenticatedUser,
    @Param('projectId') projectId: string,
    @Param('accountId') collaboratorAccountId: string,
  ) {
    return this.collaboration.removeCollaborator(
      user.accountId,
      projectId,
      collaboratorAccountId,
    );
  }

  @Delete('projects/:projectId/invitations/:invitationId')
  revokeInvitation(
    @CurrentUser() user: AuthenticatedUser,
    @Param('projectId') projectId: string,
    @Param('invitationId') invitationId: string,
  ) {
    return this.collaboration.revokeInvitation(user.accountId, projectId, invitationId);
  }

  @Get('projects/:projectId/comments')
  comments(@CurrentUser() user: AuthenticatedUser, @Param('projectId') projectId: string) {
    return this.collaboration.listComments(user.accountId, projectId);
  }

  @Post('projects/:projectId/comments')
  comment(
    @CurrentUser() user: AuthenticatedUser,
    @Param('projectId') projectId: string,
    @Body() body: CreateCommentDto,
  ) {
    return this.collaboration.createComment(user.accountId, user.email, projectId, body);
  }
}


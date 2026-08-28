import {
  BadRequestException,
  ForbiddenException,
  GoneException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { CollaboratorRole } from '@prisma/client';
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { publicShareOrigin } from '../public-origin';
import { PrismaService } from '../prisma.service';
import {
  AcceptInvitationDto,
  CreateCommentDto,
  CreateInvitationDto,
  UpdateCollaboratorDto,
} from './collaboration.dto';

function hashToken(value: string) {
  return createHash('sha256').update(value).digest();
}

@Injectable()
export class CollaborationService {
  constructor(private readonly prisma: PrismaService) {}

  async createInvitation(
    accountId: string,
    email: string,
    projectId: string,
    dto: CreateInvitationDto,
  ) {
    if (dto.role === CollaboratorRole.OWNER) {
      throw new BadRequestException('不能通过邀请转移项目所有权');
    }
    const project = await this.prisma.project.findFirst({
      where: { id: projectId, ownerId: accountId },
      select: { id: true, name: true },
    });
    if (!project) throw new ForbiddenException('只有项目所有者可以邀请成员');
    const normalizedEmail = dto.email.trim().toLowerCase();
    if (normalizedEmail === email.toLowerCase()) {
      throw new BadRequestException('项目所有者不需要邀请自己');
    }
    await this.ensureAccount(accountId, email);

    const secret = randomBytes(32).toString('base64url');
    const invitation = await this.prisma.collaborationInvite.create({
      data: {
        projectId,
        invitedById: accountId,
        email: normalizedEmail,
        role: dto.role,
        tokenHash: hashToken(secret).toString('hex'),
        expiresAt: new Date(Date.now() + 7 * 86_400_000),
      },
      select: { id: true, email: true, role: true, expiresAt: true },
    });
    await this.prisma.auditEvent.create({
      data: {
        accountId,
        projectId,
        action: 'collaboration.invited',
        targetType: 'collaboration_invite',
        targetId: invitation.id,
        safeMetadata: { role: invitation.role },
      },
    });
    const origin = publicShareOrigin();
    return {
      ...invitation,
      projectName: project.name,
      url: `${origin}/invite/${invitation.id}#${secret}`,
      warning: '邀请链接仅供指定邮箱登录后接受，有效期为 7 天。',
    };
  }

  async accept(accountId: string, email: string, invitationId: string, dto: AcceptInvitationDto) {
    const invitation = await this.prisma.collaborationInvite.findUnique({
      where: { id: invitationId },
      include: { project: { select: { name: true, ownerId: true } } },
    });
    const suppliedHash = hashToken(dto.secret);
    const storedHash = invitation ? Buffer.from(invitation.tokenHash, 'hex') : randomBytes(32);
    if (!invitation || suppliedHash.length !== storedHash.length || !timingSafeEqual(suppliedHash, storedHash)) {
      throw new NotFoundException('邀请不存在');
    }
    if (invitation.revokedAt) throw new GoneException('邀请已撤销');
    if (invitation.expiresAt <= new Date()) throw new GoneException('邀请已过期');
    if (invitation.acceptedAt) throw new GoneException('邀请已使用');
    if (invitation.email !== email.toLowerCase()) {
      throw new ForbiddenException('请使用邀请指定的邮箱登录');
    }
    await this.ensureAccount(accountId, email);
    await this.prisma.$transaction([
      this.prisma.collaborator.upsert({
        where: { projectId_accountId: { projectId: invitation.projectId, accountId } },
        create: {
          projectId: invitation.projectId,
          accountId,
          role: invitation.role,
          acceptedAt: new Date(),
        },
        update: { role: invitation.role, acceptedAt: new Date() },
      }),
      this.prisma.collaborationInvite.update({
        where: { id: invitation.id },
        data: { acceptedAt: new Date() },
      }),
      this.prisma.auditEvent.create({
        data: {
          accountId,
          projectId: invitation.projectId,
          action: 'collaboration.accepted',
          targetType: 'collaboration_invite',
          targetId: invitation.id,
          safeMetadata: { role: invitation.role },
        },
      }),
    ]);
    return { accepted: true, projectId: invitation.projectId, projectName: invitation.project.name };
  }

  async list(accountId: string, projectId: string) {
    await this.assertOwner(accountId, projectId);
    const [collaborators, invitations] = await Promise.all([
      this.prisma.collaborator.findMany({
        where: { projectId },
        select: {
          accountId: true,
          role: true,
          acceptedAt: true,
          createdAt: true,
          account: { select: { email: true } },
        },
        orderBy: { createdAt: 'asc' },
      }),
      this.prisma.collaborationInvite.findMany({
        where: { projectId, acceptedAt: null, revokedAt: null, expiresAt: { gt: new Date() } },
        select: { id: true, email: true, role: true, expiresAt: true, createdAt: true },
        orderBy: { createdAt: 'desc' },
      }),
    ]);
    return { collaborators, invitations };
  }

  async updateCollaborator(
    accountId: string,
    projectId: string,
    collaboratorAccountId: string,
    dto: UpdateCollaboratorDto,
  ) {
    if (dto.role === CollaboratorRole.OWNER) throw new BadRequestException('不能转移所有权');
    await this.assertOwner(accountId, projectId);
    if (accountId === collaboratorAccountId) throw new BadRequestException('不能修改所有者角色');
    const updated = await this.prisma.collaborator.updateMany({
      where: { projectId, accountId: collaboratorAccountId, role: { not: CollaboratorRole.OWNER } },
      data: { role: dto.role },
    });
    if (updated.count !== 1) throw new NotFoundException('未找到协作者');
    await this.prisma.auditEvent.create({
      data: {
        accountId,
        projectId,
        action: 'collaboration.role_changed',
        targetType: 'account',
        targetId: collaboratorAccountId,
        safeMetadata: { role: dto.role },
      },
    });
    return { updated: true, role: dto.role };
  }

  async removeCollaborator(accountId: string, projectId: string, collaboratorAccountId: string) {
    await this.assertOwner(accountId, projectId);
    if (accountId === collaboratorAccountId) throw new BadRequestException('不能移除项目所有者');
    const removed = await this.prisma.collaborator.deleteMany({
      where: { projectId, accountId: collaboratorAccountId, role: { not: CollaboratorRole.OWNER } },
    });
    if (removed.count !== 1) throw new NotFoundException('未找到协作者');
    await this.prisma.auditEvent.create({
      data: {
        accountId,
        projectId,
        action: 'collaboration.removed',
        targetType: 'account',
        targetId: collaboratorAccountId,
      },
    });
    return { removed: true };
  }

  async revokeInvitation(accountId: string, projectId: string, invitationId: string) {
    await this.assertOwner(accountId, projectId);
    const revoked = await this.prisma.collaborationInvite.updateMany({
      where: { id: invitationId, projectId, acceptedAt: null, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    if (revoked.count !== 1) throw new NotFoundException('未找到有效邀请');
    return { revoked: true };
  }

  async listComments(accountId: string, projectId: string) {
    await this.assertReadable(accountId, projectId);
    return this.prisma.projectComment.findMany({
      where: { projectId },
      select: {
        id: true,
        body: true,
        createdAt: true,
        updatedAt: true,
        author: { select: { id: true, email: true } },
      },
      orderBy: { createdAt: 'asc' },
      take: 500,
    });
  }

  async createComment(accountId: string, email: string, projectId: string, dto: CreateCommentDto) {
    await this.assertWritable(accountId, projectId);
    await this.ensureAccount(accountId, email);
    return this.prisma.projectComment.create({
      data: { projectId, authorId: accountId, body: dto.body.trim() },
      select: { id: true, body: true, createdAt: true },
    });
  }

  private async ensureAccount(accountId: string, email: string) {
    await this.prisma.account.upsert({
      where: { id: accountId },
      create: { id: accountId, email },
      update: { email },
    });
  }

  private async role(accountId: string, projectId: string) {
    const project = await this.prisma.project.findUnique({
      where: { id: projectId },
      select: {
        ownerId: true,
        collaborators: {
          where: { accountId, acceptedAt: { not: null } },
          select: { role: true },
        },
      },
    });
    if (!project) throw new NotFoundException('未找到项目');
    if (project.ownerId === accountId) return CollaboratorRole.OWNER;
    return project.collaborators[0]?.role;
  }

  private async assertOwner(accountId: string, projectId: string) {
    if ((await this.role(accountId, projectId)) !== CollaboratorRole.OWNER) {
      throw new ForbiddenException('只有项目所有者可以执行此操作');
    }
  }

  private async assertReadable(accountId: string, projectId: string) {
    if (!(await this.role(accountId, projectId))) throw new ForbiddenException('无权查看项目');
  }

  private async assertWritable(accountId: string, projectId: string) {
    const role = await this.role(accountId, projectId);
    if (role !== CollaboratorRole.OWNER && role !== CollaboratorRole.COLLABORATOR) {
      throw new ForbiddenException('当前角色不能修改项目');
    }
  }
}


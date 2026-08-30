import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma.service';
import {
  ClaimNotificationsDto,
  NotificationResultDto,
  UpdateNotificationPreferenceDto,
} from './notifications.dto';

@Injectable()
export class NotificationsService {
  constructor(private readonly prisma: PrismaService) {}

  getPreference(accountId: string) {
    return this.prisma.notificationPreference.upsert({
      where: { accountId },
      create: { accountId },
      update: {},
    });
  }

  updatePreference(accountId: string, dto: UpdateNotificationPreferenceDto) {
    return this.prisma.notificationPreference.upsert({
      where: { accountId },
      create: {
        accountId,
        policyUpdates: dto.policyUpdates,
        productUpdates: dto.productUpdates ?? false,
        jurisdictions: this.clean(dto.jurisdictions),
        tags: this.clean(dto.tags),
        importantOnly: dto.importantOnly,
        timezone: dto.timezone,
      },
      update: {
        policyUpdates: dto.policyUpdates,
        productUpdates: dto.productUpdates,
        jurisdictions: this.clean(dto.jurisdictions),
        tags: this.clean(dto.tags),
        importantOnly: dto.importantOnly,
        timezone: dto.timezone,
      },
    });
  }

  /**
   * App 端收件箱。
   *
   * outbox 原本是给推送/邮件 worker 用的（`claim` + `recordResult`），但那条链路需要
   * FCM/APNs，要引入 Google 依赖并重做隐私说明。在那之前，**App 自己就是投递通道**：
   * 它本来就会定期拉内容，顺带把该给这个账号的提醒取走即可。
   *
   * 只返回未送达的。已确认的不再出现，否则用户每次打开都看到同一批。
   */
  async inbox(accountId: string) {
    const items = await this.prisma.notificationOutbox.findMany({
      where: { accountId, status: { in: ['PENDING', 'PROCESSING'] } },
      orderBy: { createdAt: 'desc' },
      take: 50,
      select: { id: true, kind: true, entityId: true, payload: true, createdAt: true },
    });
    return items;
  }

  /** App 确认已展示。只允许确认自己的，否则任何账号都能替别人清空收件箱。 */
  async acknowledge(accountId: string, ids: string[]) {
    if (ids.length === 0) return { acknowledged: 0 };
    const result = await this.prisma.notificationOutbox.updateMany({
      where: { id: { in: ids.slice(0, 100) }, accountId },
      data: { status: 'SENT', sentAt: new Date() },
    });
    return { acknowledged: result.count };
  }

  async claim(dto: ClaimNotificationsDto) {
    const now = new Date();
    const stale = new Date(now.getTime() - 15 * 60_000);
    await this.prisma.notificationOutbox.updateMany({
      where: { status: 'PROCESSING', claimedAt: { lt: stale } },
      data: { status: 'PENDING', claimedAt: null },
    });
    const candidates = await this.prisma.notificationOutbox.findMany({
      where: { status: 'PENDING', availableAt: { lte: now } },
      orderBy: { createdAt: 'asc' },
      take: dto.batchSize ?? 25,
    });
    const claimed = [];
    for (const candidate of candidates) {
      const changed = await this.prisma.notificationOutbox.updateMany({
        where: { id: candidate.id, status: 'PENDING' },
        data: {
          status: 'PROCESSING',
          claimedAt: now,
          attempts: { increment: 1 },
        },
      });
      if (changed.count === 1) {
        claimed.push({
          id: candidate.id,
          accountId: candidate.accountId,
          kind: candidate.kind,
          payload: candidate.payload,
        });
      }
    }
    return claimed;
  }

  async recordResult(id: string, dto: NotificationResultDto) {
    if (dto.status === 'FAILED' && !dto.errorCode) {
      throw new BadRequestException('失败结果必须提供非敏感错误类别');
    }
    const current = await this.prisma.notificationOutbox.findUnique({ where: { id } });
    if (!current) throw new NotFoundException('未找到通知任务');
    if (current.status === 'SENT') return { id, status: 'SENT', idempotent: true };
    return this.prisma.notificationOutbox.update({
      where: { id },
      data:
        dto.status === 'SENT'
          ? { status: 'SENT', sentAt: new Date(), errorCode: null }
          : {
              status: current.attempts >= 5 ? 'FAILED' : 'PENDING',
              errorCode: dto.errorCode,
              claimedAt: null,
              availableAt: new Date(Date.now() + Math.min(current.attempts, 5) * 60_000),
            },
      select: { id: true, status: true, attempts: true, errorCode: true },
    });
  }

  static notificationPayload(changeId: string): Prisma.InputJsonObject {
    return {
      route: `/changes/${changeId}`,
      title: '有一项已核实的政策变化',
      privacy: 'generic-lock-screen-copy',
    };
  }

  /**
   * 新闻发布的通知内容。
   *
   * 标题只写「有更新」，不写具体是哪条政策——通知会显示在锁屏上，旁人能看见。
   * 用户订阅的标签本身就是敏感信息（关注 491 意味着此人在申请 491），
   * 不该出现在别人扫一眼就能读到的地方。
   */
  static newsPayload(newsId: string, jurisdiction: string): Prisma.InputJsonObject {
    return {
      route: `/news/${newsId}`,
      title: `${jurisdiction === 'AU-FED' ? '联邦' : '你关注的地区'}有新的官方资讯`,
      privacy: 'generic-lock-screen-copy',
    };
  }

  private clean(values: string[]) {
    return [...new Set(values.map((value) => value.trim()).filter(Boolean))];
  }
}

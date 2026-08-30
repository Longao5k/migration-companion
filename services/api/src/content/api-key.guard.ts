import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { createHash, timingSafeEqual } from 'node:crypto';
import { Request } from 'express';
import { AdminAuthService } from '../auth/admin-auth.service';

function equal(left: string, right: string) {
  const a = createHash('sha256').update(left).digest();
  const b = createHash('sha256').update(right).digest();
  return timingSafeEqual(a, b);
}

/**
 * 后台鉴权接受两种凭据：
 *
 * - **会话 token**（`Authorization: Bearer`）——人在浏览器里登录后拿到的，8 小时过期。
 * - **共享密钥**（`x-admin-key`）——给脚本用的，比如摘要工具经 ssh 在服务器上调接口。
 *
 * 保留共享密钥不是偷懒：它只存在服务器本机的 .env 里，脚本经 ssh 现取现用，
 * 从不落到别的机器上。但**放到公网子域名之前，人的入口必须换成会话 token**——
 * 一个没有有效期、会被复制粘贴、泄露了也无从察觉的字符串，不该是发布政策内容的唯一凭据。
 */
@Injectable()
export class AdminApiKeyGuard implements CanActivate {
  constructor(private readonly adminAuth: AdminAuthService) {}

  async canActivate(context: ExecutionContext) {
    const request = context.switchToHttp().getRequest<Request>();

    const bearer = request.headers.authorization;
    if (typeof bearer === 'string' && bearer.startsWith('Bearer ')) {
      const session = await this.adminAuth.verify(bearer.slice(7).trim());
      if (session) {
        // 审计要知道是谁操作的，共享密钥给不出这个信息。
        (request as Request & { adminEmail?: string }).adminEmail = session.email;
        return true;
      }
    }

    const expected = process.env.ADMIN_API_KEY;
    const supplied = request.headers['x-admin-key'];
    if (!expected || typeof supplied !== 'string' || !equal(supplied, expected)) {
      throw new UnauthorizedException('后台身份验证失败');
    }
    return true;
  }
}

@Injectable()
export class WorkerApiKeyGuard implements CanActivate {
  canActivate(context: ExecutionContext) {
    const expected = process.env.WORKER_API_KEY;
    const supplied = context.switchToHttp().getRequest<Request>().headers['x-worker-key'];
    if (!expected || typeof supplied !== 'string' || !equal(supplied, expected)) {
      throw new UnauthorizedException('采集服务身份验证失败');
    }
    return true;
  }
}


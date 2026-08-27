import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { createHash, timingSafeEqual } from 'node:crypto';
import { Request } from 'express';

function equal(left: string, right: string) {
  const a = createHash('sha256').update(left).digest();
  const b = createHash('sha256').update(right).digest();
  return timingSafeEqual(a, b);
}

@Injectable()
export class AdminApiKeyGuard implements CanActivate {
  canActivate(context: ExecutionContext) {
    const expected = process.env.ADMIN_API_KEY;
    const supplied = context.switchToHttp().getRequest<Request>().headers['x-admin-key'];
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


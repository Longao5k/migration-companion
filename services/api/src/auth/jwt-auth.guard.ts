import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { CognitoJwtVerifier } from 'aws-jwt-verify';
import { Request } from 'express';
import { createHash } from 'node:crypto';
import { AuthenticatedUser } from './auth.types';

@Injectable()
export class JwtAuthGuard implements CanActivate {
  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<Request & { user?: AuthenticatedUser }>();
    const header = request.headers.authorization;
    if (!header?.startsWith('Bearer ')) throw new UnauthorizedException('需要登录');

    if (process.env.NODE_ENV !== 'production' && process.env.DEV_AUTH === 'true') {
      const suppliedEmail = request.headers['x-dev-account-email'];
      const email =
        typeof suppliedEmail === 'string' && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(suppliedEmail)
          ? suppliedEmail.toLowerCase()
          : (process.env.DEV_ACCOUNT_EMAIL ?? 'dev@example.invalid');
      request.user = {
        accountId:
          process.env.DEV_ACCOUNT_ID ??
          `dev-${createHash('sha256').update(email).digest('hex').slice(0, 24)}`,
        email,
      };
      return true;
    }

    const userPoolId = process.env.COGNITO_USER_POOL_ID;
    const clientId = process.env.COGNITO_CLIENT_ID;
    if (!userPoolId || !clientId) throw new UnauthorizedException('身份服务尚未配置');

    try {
      const verifier = CognitoJwtVerifier.create({ userPoolId, clientId, tokenUse: 'access' });
      const payload = await verifier.verify(header.slice(7));
      request.user = {
        accountId: payload.sub,
        email: typeof payload.email === 'string' ? payload.email : '',
      };
      return true;
    } catch {
      throw new UnauthorizedException('登录已过期');
    }
  }
}

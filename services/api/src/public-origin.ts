import { ServiceUnavailableException } from '@nestjs/common';

/**
 * 安全分享与协作邀请链接的对外地址。
 *
 * 这个值只在生成给**收件人**的链接时使用。以前它在缺失时会静默退回 `http://localhost:3001`，
 * 结果是生产环境照常返回 201、用户以为分享成功，但对方拿到的是一条打不开的本地地址——
 * 而分享者已经把链接和访问码发出去了。因此生产环境缺失时必须直接失败并说明原因。
 */
export function publicShareOrigin() {
  const origin = process.env.SHARE_ORIGIN?.trim();
  if (origin) return origin.replace(/\/+$/, '');
  if (process.env.NODE_ENV === 'production') {
    throw new ServiceUnavailableException(
      '分享与邀请链接的对外地址未配置（SHARE_ORIGIN）。未配置时生成的链接会指向 localhost，接收方无法打开。',
    );
  }
  return 'http://localhost:3001';
}

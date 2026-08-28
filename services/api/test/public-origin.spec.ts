import { ServiceUnavailableException } from '@nestjs/common';
import { publicShareOrigin } from '../src/public-origin';

describe('publicShareOrigin', () => {
  const original = { nodeEnv: process.env.NODE_ENV, origin: process.env.SHARE_ORIGIN };

  afterEach(() => {
    if (original.nodeEnv === undefined) delete process.env.NODE_ENV;
    else process.env.NODE_ENV = original.nodeEnv;
    if (original.origin === undefined) delete process.env.SHARE_ORIGIN;
    else process.env.SHARE_ORIGIN = original.origin;
  });

  it('生产环境缺少 SHARE_ORIGIN 时直接失败，而不是生成指向 localhost 的链接', () => {
    process.env.NODE_ENV = 'production';
    delete process.env.SHARE_ORIGIN;

    // 静默退回 localhost 会让分享者以为成功，但收件人拿到的是打不开的地址。
    expect(() => publicShareOrigin()).toThrow(ServiceUnavailableException);
    expect(() => publicShareOrigin()).toThrow(/SHARE_ORIGIN/);
  });

  it('配置存在时去掉结尾斜杠，避免拼出双斜杠链接', () => {
    process.env.NODE_ENV = 'production';
    process.env.SHARE_ORIGIN = 'https://migration-companion.example.com/';

    expect(publicShareOrigin()).toBe('https://migration-companion.example.com');
  });

  it('非生产环境保留本地默认值，方便开发', () => {
    process.env.NODE_ENV = 'test';
    delete process.env.SHARE_ORIGIN;

    expect(publicShareOrigin()).toBe('http://localhost:3001');
  });
});

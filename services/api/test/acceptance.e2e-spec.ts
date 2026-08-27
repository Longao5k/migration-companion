import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { createHash, randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/prisma.service';
import { applyLocalE2eEnv } from './local-e2e-env';

// Runs before the Nest container is built, which is when FilesService and SharesService
// read their bucket and endpoint configuration.
applyLocalE2eEnv();

const run = randomUUID().slice(0, 8);
const ownerEmail = `e2e-owner-${run}@migration-companion.invalid`;
const collaboratorEmail = `e2e-collaborator-${run}@migration-companion.invalid`;
const viewerEmail = `e2e-viewer-${run}@migration-companion.invalid`;
const testEmails = [ownerEmail, collaboratorEmail, viewerEmail];

const samplePdf = readFileSync(join(__dirname, 'fixtures', 'sample.pdf'));
const samplePdfSha256 = createHash('sha256').update(samplePdf).digest('hex');

function as(email: string) {
  return {
    authorization: 'Bearer local-development-token',
    'x-dev-account-email': email,
  };
}

function secretFromUrl(url: string) {
  const secret = url.split('#')[1];
  if (!secret) throw new Error(`链接缺少 fragment secret：${url}`);
  return secret;
}

describe('第一阶段 API 验收（本地 PostgreSQL + MinIO）', () => {
  let app: INestApplication;
  let http: ReturnType<INestApplication['getHttpServer']>;
  let prisma: PrismaService;

  let projectId: string;
  let projectVersion: number;
  let firstItemId: string;
  let secondItemId: string;
  let fileId: string;

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = configureApp(moduleRef.createNestApplication());
    await app.init();
    http = app.getHttpServer();
    prisma = app.get(PrismaService);
    await prisma.account.deleteMany({ where: { email: { in: testEmails } } });
  });

  afterAll(async () => {
    if (prisma) await prisma.account.deleteMany({ where: { email: { in: testEmails } } });
    if (app) await app.close();
  });

  it('1. 访客升级后的账号可以创建 SA 491 项目并获得官方来源标注的模板清单', async () => {
    const response = await request(http)
      .post('/v1/projects')
      .set(as(ownerEmail))
      .send({ name: 'SA 491 验收项目', template: 'SA_491', applicantName: '申请人 A' })
      .expect(201);

    projectId = response.body.id;
    projectVersion = response.body.version;
    expect(response.body.checklist).toHaveLength(5);
    firstItemId = response.body.checklist[0].id;
    secondItemId = response.body.checklist[1].id;
    // 产品门槛 5.3：模板条目必须能回到官方来源。
    for (const item of response.body.checklist) {
      expect(item.sourceUrl).toMatch(/^https:\/\/migration\.sa\.gov\.au\//);
      expect(item.sourceAsOf).toBeTruthy();
      expect(item.reviewAsOf).toBeTruthy();
    }
  });

  it('2. 未开启云文件同意时不能上传，开启后才允许', async () => {
    await request(http)
      .post(`/v1/projects/${projectId}/files`)
      .set(as(ownerEmail))
      .attach('file', samplePdf, { filename: 'passport.pdf', contentType: 'application/pdf' })
      .expect(403);

    const consent = await request(http)
      .patch(`/v1/projects/${projectId}/cloud-files`)
      .set(as(ownerEmail))
      .send({ enabled: true })
      .expect(200);

    expect(consent.body.cloudFilesEnabled).toBe(true);
    expect(consent.body.version).toBeGreaterThan(projectVersion);
    projectVersion = consent.body.version;
  });

  it('3. 账号可以明确开启 7 天试用，且试用不创建商店订阅', async () => {
    const trial = await request(http)
      .post('/v1/entitlements/trial')
      .set(as(ownerEmail))
      .expect(201);

    expect(trial.body.tier).toBe('TRIAL');
    expect(trial.body.advancedEditing).toBe(true);
    expect(trial.body.subscription).toBeNull();
    expect(trial.body.cloudStorageBytes).toBe(10 * 1024 ** 3);

    await request(http).post('/v1/entitlements/trial').set(as(ownerEmail)).expect(409);
  });

  it('4. 上传真实 PDF 后进入扫描流程，开发扫描返回 CLEAN', async () => {
    const upload = await request(http)
      .post(`/v1/projects/${projectId}/files`)
      .set(as(ownerEmail))
      .field('checklistItemId', firstItemId)
      .attach('file', samplePdf, { filename: 'passport.pdf', contentType: 'application/pdf' })
      .expect(201);

    fileId = upload.body.id;
    expect(upload.body.scanStatus).toBe('CLEAN');
    expect(upload.body.localDevelopmentScan).toBe(true);
    expect(upload.body.sha256).toBe(samplePdfSha256);
    expect(upload.body.compatibility).toBe('PDF_SUPPORTED');
    expect(typeof upload.body.byteSize).toBe('string');
  });

  it('5. 审计记录不包含文件名、正文或存储位置', async () => {
    const events = await prisma.auditEvent.findMany({ where: { projectId } });
    expect(events.length).toBeGreaterThan(0);
    const serialised = JSON.stringify(events);
    expect(serialised).not.toContain('passport.pdf');
    expect(serialised).not.toContain('quarantine/');
    expect(serialised).not.toContain('clean/');
  });

  it('6. 登录用户获得 60 秒下载链接，且链接确实返回原始字节', async () => {
    const download = await request(http)
      .get(`/v1/files/${fileId}/download`)
      .set(as(ownerEmail))
      .expect(200);

    expect(download.body.expiresInSeconds).toBe(60);
    expect(download.body.downloadUrl).toContain('X-Amz-Signature');

    const object = await fetch(download.body.downloadUrl);
    expect(object.status).toBe(200);
    const bytes = Buffer.from(await object.arrayBuffer());
    expect(createHash('sha256').update(bytes).digest('hex')).toBe(samplePdfSha256);
  });

  it('7. 项目详情返回可序列化的文件列表，不泄露存储键', async () => {
    const detail = await request(http)
      .get(`/v1/projects/${projectId}`)
      .set(as(ownerEmail))
      .expect(200);

    expect(detail.body.files).toHaveLength(1);
    // byteSize 是 BigInt 列：响应必须是字符串，否则 JSON 序列化会 500。
    expect(typeof detail.body.files[0].byteSize).toBe('string');
    expect(detail.body.files[0]).not.toHaveProperty('storageKey');
  });

  it('8. 用 PDF 内容冒充 image/png 上传被拒绝', async () => {
    await request(http)
      .post(`/v1/projects/${projectId}/files`)
      .set(as(ownerEmail))
      .attach('file', samplePdf, { filename: 'passport.png', contentType: 'image/png' })
      .expect(400);
  });

  it('9. 安全分享默认不可下载，无账号访问码交换只返回被选中的内容', async () => {
    const accessCode = 'E2ELOCALCODE';
    const created = await request(http)
      .post(`/v1/projects/${projectId}/shares`)
      .set(as(ownerEmail))
      .send({
        expiresInDays: 7,
        allowDownload: false,
        accessCode,
        checklistItemIds: [firstItemId],
        fileIds: [fileId],
        includeNotes: false,
      })
      .expect(201);

    const shareId = created.body.id;
    const secret = secretFromUrl(created.body.url);
    expect(created.body.allowDownload).toBe(false);

    await request(http)
      .post(`/v1/public/shares/${shareId}/access`)
      .send({ secret, accessCode: 'WRONGCODE1' })
      .expect(403);

    const opened = await request(http)
      .post(`/v1/public/shares/${shareId}/access`)
      .send({ secret, accessCode })
      .expect(201);

    expect(opened.body.items).toHaveLength(1);
    expect(opened.body.files).toHaveLength(1);
    expect(opened.body.files[0].downloadUrl).toBeNull();
    expect(opened.body.items[0].note).toBeUndefined();

    const list = await request(http)
      .get(`/v1/projects/${projectId}/shares`)
      .set(as(ownerEmail))
      .expect(200);
    expect(list.body[0].status).toBe('ACTIVE');
    expect(list.body[0].lastAccessedAt).toBeTruthy();

    await request(http).delete(`/v1/shares/${shareId}`).set(as(ownerEmail)).expect(200);

    await request(http)
      .post(`/v1/public/shares/${shareId}/access`)
      .send({ secret, accessCode })
      .expect(410);

    const afterRevoke = await request(http)
      .get(`/v1/projects/${projectId}/shares`)
      .set(as(ownerEmail))
      .expect(200);
    expect(afterRevoke.body[0].status).toBe('REVOKED');
  });

  it('10. 仅查看成员默认不能下载，所有者开启项目级下载后才可以', async () => {
    const invitation = await request(http)
      .post(`/v1/projects/${projectId}/invitations`)
      .set(as(ownerEmail))
      .send({ email: viewerEmail, role: 'VIEWER' })
      .expect(201);

    await request(http)
      .post(`/v1/collaboration-invitations/${invitation.body.id}/accept`)
      .set(as(viewerEmail))
      .send({ secret: secretFromUrl(invitation.body.url) })
      .expect(201);

    await request(http).get(`/v1/files/${fileId}/download`).set(as(viewerEmail)).expect(403);

    await request(http)
      .patch(`/v1/projects/${projectId}/viewer-download`)
      .set(as(ownerEmail))
      .send({ enabled: true })
      .expect(200);

    await request(http).get(`/v1/files/${fileId}/download`).set(as(viewerEmail)).expect(200);

    // 仅查看成员始终不能上传或评论。
    await request(http)
      .post(`/v1/projects/${projectId}/comments`)
      .set(as(viewerEmail))
      .send({ body: '仅查看成员不应能评论' })
      .expect(403);
  });

  it('11. 可协作成员能更新清单和评论，被降权后立即失去写权限', async () => {
    const invitation = await request(http)
      .post(`/v1/projects/${projectId}/invitations`)
      .set(as(ownerEmail))
      .send({ email: collaboratorEmail, role: 'COLLABORATOR' })
      .expect(201);

    await request(http)
      .post(`/v1/collaboration-invitations/${invitation.body.id}/accept`)
      .set(as(collaboratorEmail))
      .send({ secret: secretFromUrl(invitation.body.url) })
      .expect(201);

    const current = await request(http)
      .get(`/v1/projects/${projectId}`)
      .set(as(ownerEmail))
      .expect(200);
    projectVersion = current.body.version;

    const updated = await request(http)
      .patch(`/v1/projects/${projectId}/checklist/${secondItemId}`)
      .set(as(collaboratorEmail))
      .send({ status: 'PREPARING', expectedProjectVersion: projectVersion })
      .expect(200);
    projectVersion = updated.body.projectVersion;

    await request(http)
      .post(`/v1/projects/${projectId}/comments`)
      .set(as(collaboratorEmail))
      .send({ body: '已补齐工作经历证明的第二页' })
      .expect(201);

    const collaboratorAccountId = `dev-${createHash('sha256')
      .update(collaboratorEmail)
      .digest('hex')
      .slice(0, 24)}`;
    await request(http)
      .patch(`/v1/projects/${projectId}/collaborators/${collaboratorAccountId}`)
      .set(as(ownerEmail))
      .send({ role: 'VIEWER' })
      .expect(200);

    await request(http)
      .post(`/v1/projects/${projectId}/comments`)
      .set(as(collaboratorEmail))
      .send({ body: '降权后不应能评论' })
      .expect(403);
  });

  it('12. 并发编辑返回 409，不静默覆盖', async () => {
    const stale = projectVersion - 1;
    await request(http)
      .patch(`/v1/projects/${projectId}/checklist/${secondItemId}`)
      .set(as(ownerEmail))
      .send({ status: 'READY', expectedProjectVersion: stale })
      .expect(409);

    const fresh = await request(http)
      .get(`/v1/projects/${projectId}`)
      .set(as(ownerEmail))
      .expect(200);

    const retried = await request(http)
      .patch(`/v1/projects/${projectId}/checklist/${secondItemId}`)
      .set(as(ownerEmail))
      .send({ status: 'READY', expectedProjectVersion: fresh.body.version })
      .expect(200);
    projectVersion = retried.body.projectVersion;
  });

  it('13. 本地沙盒订阅写入服务端权益，恢复购买读取的是服务端事实', async () => {
    const purchase = await request(http)
      .post('/v1/entitlements/purchases')
      .set(as(ownerEmail))
      .send({
        provider: 'LOCAL_SANDBOX',
        productId: 'migration_companion_premium_monthly',
        verificationData: `local-e2e-${run}`,
      })
      .expect(201);

    expect(purchase.body.sandbox).toBe(true);
    expect(purchase.body.entitlement.tier).toBe('PREMIUM');

    const restored = await request(http)
      .post('/v1/entitlements/restore')
      .set(as(ownerEmail))
      .expect(201);
    expect(restored.body.tier).toBe('PREMIUM');
    expect(restored.body.subscription.status).toBe('ACTIVE');

    // 客户端提交的收据本身不能授予权益。
    await request(http)
      .post('/v1/entitlements/purchases')
      .set(as(ownerEmail))
      .send({
        provider: 'APPLE',
        productId: 'migration_companion_premium_monthly',
        verificationData: 'client-supplied-receipt-not-verified',
      })
      .expect(201)
      .expect((response) => {
        expect(response.body.pendingVerification).toBe(true);
        expect(response.body.accepted).toBe(true);
      });
  });

  it('14. 退款/撤销事件会立即收回权益', async () => {
    const subscription = await prisma.subscription.findFirst({
      where: { account: { email: ownerEmail } },
      select: { originalTransaction: true, productId: true },
    });
    expect(subscription).not.toBeNull();

    await request(http)
      .post('/v1/store-events/verified')
      .set('x-worker-key', process.env.WORKER_API_KEY as string)
      .send({
        provider: 'GOOGLE',
        productId: subscription!.productId,
        status: 'REFUNDED',
        originalTransaction: subscription!.originalTransaction,
        accountEmail: ownerEmail,
      })
      .expect(201);

    const entitlement = await request(http)
      .get('/v1/entitlements/me')
      .set(as(ownerEmail))
      .expect(200);
    // 试用仍在有效期内，因此退款后回落到 TRIAL 而不是 PREMIUM。
    expect(entitlement.body.tier).toBe('TRIAL');
    expect(entitlement.body.subscription.status).toBe('REFUNDED');
  });

  it('15. 未授权的工作者密钥不能写入商店事件', async () => {
    await request(http)
      .post('/v1/store-events/verified')
      .set('x-worker-key', 'not-the-worker-key')
      .send({
        provider: 'GOOGLE',
        productId: 'migration_companion_premium_monthly',
        status: 'ACTIVE',
        originalTransaction: `forged-${run}`,
        accountEmail: ownerEmail,
      })
      .expect(401);
  });
  it('16. 仅查看成员不能删除云文件', async () => {
    await request(http).delete(`/v1/files/${fileId}`).set(as(viewerEmail)).expect(403);
  });

  it('17. 可协作成员只能删除自己上传的文件', async () => {
    const collaboratorAccountId = `dev-${createHash('sha256')
      .update(collaboratorEmail)
      .digest('hex')
      .slice(0, 24)}`;
    await request(http)
      .patch(`/v1/projects/${projectId}/collaborators/${collaboratorAccountId}`)
      .set(as(ownerEmail))
      .send({ role: 'COLLABORATOR' })
      .expect(200);

    await request(http).delete(`/v1/files/${fileId}`).set(as(collaboratorEmail)).expect(403);

    const own = await request(http)
      .post(`/v1/projects/${projectId}/files`)
      .set(as(collaboratorEmail))
      .attach('file', samplePdf, { filename: 'evidence.pdf', contentType: 'application/pdf' })
      .expect(201);

    await request(http).delete(`/v1/files/${own.body.id}`).set(as(collaboratorEmail)).expect(200);
    await request(http)
      .get(`/v1/files/${own.body.id}/download`)
      .set(as(ownerEmail))
      .expect(404);
  });

  it('18. 所有者删除文件后，下载与项目详情都不再返回它', async () => {
    await request(http).delete(`/v1/files/${fileId}`).set(as(ownerEmail)).expect(200);
    await request(http).get(`/v1/files/${fileId}/download`).set(as(ownerEmail)).expect(404);

    const detail = await request(http)
      .get(`/v1/projects/${projectId}`)
      .set(as(ownerEmail))
      .expect(200);
    expect(detail.body.files).toHaveLength(0);
  });
  it('19. 安全分享支持 1/7/14/30 天有效期，不提供永久链接', async () => {
    for (const days of [1, 14, 30]) {
      const created = await request(http)
        .post(`/v1/projects/${projectId}/shares`)
        .set(as(ownerEmail))
        .send({
          expiresInDays: days,
          allowDownload: false,
          accessCode: 'E2EEXPIRY01',
          checklistItemIds: [firstItemId],
          fileIds: [],
          includeNotes: false,
        })
        .expect(201);

      const lifetimeDays =
        (new Date(created.body.expiresAt).getTime() - Date.now()) / 86_400_000;
      expect(lifetimeDays).toBeGreaterThan(days - 0.01);
      expect(lifetimeDays).toBeLessThan(days + 0.01);
      await request(http).delete(`/v1/shares/${created.body.id}`).set(as(ownerEmail));
    }

    await request(http)
      .post(`/v1/projects/${projectId}/shares`)
      .set(as(ownerEmail))
      .send({
        expiresInDays: 3650,
        allowDownload: false,
        accessCode: 'E2EEXPIRY01',
        checklistItemIds: [firstItemId],
        fileIds: [],
        includeNotes: false,
      })
      .expect(400);
  });

  it('20. 访问码连续错误会锁定入口，正确访问码在锁定期内同样被拒', async () => {
    const created = await request(http)
      .post(`/v1/projects/${projectId}/shares`)
      .set(as(ownerEmail))
      .send({
        expiresInDays: 7,
        allowDownload: false,
        accessCode: 'E2ELOCKOUT1',
        checklistItemIds: [firstItemId],
        fileIds: [],
        includeNotes: false,
      })
      .expect(201);
    const secret = secretFromUrl(created.body.url);

    for (let attempt = 0; attempt < 5; attempt += 1) {
      await request(http)
        .post(`/v1/public/shares/${created.body.id}/access`)
        .send({ secret, accessCode: 'WRONGCODE1' })
        .expect(403);
    }

    await request(http)
      .post(`/v1/public/shares/${created.body.id}/access`)
      .send({ secret, accessCode: 'E2ELOCKOUT1' })
      .expect(429);

    await request(http).delete(`/v1/shares/${created.body.id}`).set(as(ownerEmail));
  });

  it('21. 允许下载的分享返回短时下载链接，删除云文件后该文件不再下发', async () => {
    const upload = await request(http)
      .post(`/v1/projects/${projectId}/files`)
      .set(as(ownerEmail))
      .attach('file', samplePdf, { filename: 'statement.pdf', contentType: 'application/pdf' })
      .expect(201);

    const created = await request(http)
      .post(`/v1/projects/${projectId}/shares`)
      .set(as(ownerEmail))
      .send({
        expiresInDays: 7,
        allowDownload: true,
        accessCode: 'E2EDOWNLOAD1',
        checklistItemIds: [],
        fileIds: [upload.body.id],
        includeNotes: false,
      })
      .expect(201);
    const secret = secretFromUrl(created.body.url);

    const opened = await request(http)
      .post(`/v1/public/shares/${created.body.id}/access`)
      .send({ secret, accessCode: 'E2EDOWNLOAD1' })
      .expect(201);
    expect(opened.body.files).toHaveLength(1);
    expect(opened.body.files[0].downloadUrl).toContain('X-Amz-Signature');

    const object = await fetch(opened.body.files[0].downloadUrl);
    expect(object.status).toBe(200);
    const bytes = Buffer.from(await object.arrayBuffer());
    expect(createHash('sha256').update(bytes).digest('hex')).toBe(samplePdfSha256);

    await request(http).delete(`/v1/files/${upload.body.id}`).set(as(ownerEmail)).expect(200);

    const afterDelete = await request(http)
      .post(`/v1/public/shares/${created.body.id}/access`)
      .send({ secret, accessCode: 'E2EDOWNLOAD1' })
      .expect(201);
    expect(afterDelete.body.files).toHaveLength(0);
  });
});

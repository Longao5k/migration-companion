import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { HeadObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { createHash, randomBytes, randomUUID, scryptSync } from 'node:crypto';
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
const deletionEmail = `e2e-delete-${run}@migration-companion.invalid`;
const pilotEmail = `e2e-pilot-${run}@migration-companion.invalid`;
const testEmails = [ownerEmail, collaboratorEmail, viewerEmail, deletionEmail, pilotEmail];

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
  let contentSourceId: string | undefined;

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = configureApp(moduleRef.createNestApplication());
    await app.init();
    http = app.getHttpServer();
    prisma = app.get(PrismaService);
    await prisma.account.deleteMany({ where: { email: { in: testEmails } } });
  });

  afterAll(async () => {
    if (prisma) {
      await prisma.uploadSession.deleteMany({
        where: { storageKey: { startsWith: `e2e-${run}/` } },
      });
      if (contentSourceId) {
        await prisma.newsItem.deleteMany({ where: { sourceId: contentSourceId } });
        await prisma.changeLog.deleteMany({ where: { sourceId: contentSourceId } });
        await prisma.source.deleteMany({ where: { id: contentSourceId } });
      }
    }
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
        productId: 'waymark_premium_monthly',
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
        productId: 'waymark_premium_monthly',
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
        productId: 'waymark_premium_monthly',
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

  it('22. 免费额度会计入未完成上传，超额后仍保留读取通道', async () => {
    const account = await prisma.account.findUniqueOrThrow({
      where: { email: ownerEmail },
      select: { id: true },
    });
    await prisma.account.update({
      where: { id: account.id },
      data: { trialEndsAt: new Date(Date.now() - 60_000) },
    });
    const reservedUpload = await prisma.uploadSession.create({
      data: {
        id: randomUUID(),
        projectId,
        accountId: account.id,
        storageKey: `e2e-${run}/reserved-free-quota`,
        originalName: 'reserved.pdf',
        contentType: 'application/pdf',
        byteSize: BigInt(1024 ** 3),
        sha256: 'a'.repeat(64),
        expiresAt: new Date(Date.now() + 10 * 60_000),
      },
    });

    const entitlement = await request(http)
      .get('/v1/entitlements/me')
      .set(as(ownerEmail))
      .expect(200);
    expect(entitlement.body.tier).toBe('FREE');
    expect(entitlement.body.cloudStorageReservedBytes).toBe(String(1024 ** 3));
    expect(entitlement.body.cloudStorageAllocatedBytes).toBe(String(1024 ** 3));

    await request(http)
      .post(`/v1/projects/${projectId}/uploads`)
      .set(as(ownerEmail))
      .send({
        originalName: 'extra.pdf',
        contentType: 'application/pdf',
        byteSize: 1,
        sha256: 'b'.repeat(64),
        checklistItemId: firstItemId,
      })
      .expect(403)
      .expect((response) => {
        expect(response.body.message).toContain('云存储空间不足');
      });

    // 超额只限制新增上传，不影响用户读取并取回已有项目数据。
    await request(http).get(`/v1/projects/${projectId}`).set(as(ownerEmail)).expect(200);
    await prisma.uploadSession.delete({ where: { id: reservedUpload.id } });
  });

  it('23. Worker 上报证据健康状态，新闻草稿只有明确发布后才进入 App API', async () => {
    const sourceUrl = `https://migration.sa.gov.au/e2e/${run}`;
    const checkedAt = new Date().toISOString();
    const sourceCheck = await request(http)
      .post('/v1/content/worker/source-checks')
      .set('x-worker-key', process.env.WORKER_API_KEY as string)
      .send({
        sourceUrl,
        sourceName: `E2E source ${run}`,
        jurisdiction: 'AU-SA',
        status: 'SUCCESS',
        checkedAt,
        contentHash: 'c'.repeat(64),
        snapshotKey: `e2e/${run}/snapshot`,
        httpStatus: 200,
      })
      .expect(201);
    contentSourceId = sourceCheck.body.sourceId;

    const health = await request(http)
      .get('/v1/content/admin/source-health')
      .set('x-admin-key', process.env.ADMIN_API_KEY as string)
      .expect(200);
    const sourceHealth = health.body.find(
      (item: { id: string }) => item.id === contentSourceId,
    );
    expect(sourceHealth.snapshots).toHaveLength(1);
    expect(sourceHealth.lastSuccessAt).toBeTruthy();

    const draft = await request(http)
      .post('/v1/content/admin/news')
      .set('x-admin-key', process.env.ADMIN_API_KEY as string)
      .send({
        sourceId: contentSourceId,
        titleZh: `E2E 南澳新闻 ${run}`,
        summaryZh: '仅概述官方事实，并要求用户回到原文核对。',
        sourceTitle: 'E2E official update',
        sourceUrl,
        tags: ['SA', '190'],
        publishedAt: checkedAt,
        isPublished: false,
      })
      .expect(201);

    const beforePublish = await request(http).get('/v1/content/news').expect(200);
    expect(beforePublish.body.some((item: { id: string }) => item.id === draft.body.id)).toBe(false);

    await request(http)
      .patch(`/v1/content/admin/news/${draft.body.id}`)
      .set('x-admin-key', process.env.ADMIN_API_KEY as string)
      .send({ isPublished: true })
      .expect(200);
    const afterPublish = await request(http).get('/v1/content/news').expect(200);
    expect(afterPublish.body.some((item: { id: string }) => item.id === draft.body.id)).toBe(true);
  });

  it('24. 重要变化幂等入队，必须有编辑摘要才能发布，更正保留审计记录', async () => {
    const candidate = {
      sourceUrl: `https://migration.sa.gov.au/e2e/${run}`,
      sourceName: `E2E source ${run}`,
      titleZh: `E2E 重要变化 ${run}`,
      oldExcerpt: '旧版本要求。',
      newExcerpt: '新版本要求。',
      context: '只描述页面差异，不判断个人影响。',
      importance: 'IMPORTANT',
      discoveredAt: new Date().toISOString(),
      tags: ['SA', '491'],
    };
    const first = await request(http)
      .post('/v1/content/worker/changes')
      .set('x-worker-key', process.env.WORKER_API_KEY as string)
      .send(candidate)
      .expect(201);
    const retried = await request(http)
      .post('/v1/content/worker/changes')
      .set('x-worker-key', process.env.WORKER_API_KEY as string)
      .send(candidate)
      .expect(201);
    expect(retried.body.id).toBe(first.body.id);

    const unpublished = await request(http).get('/v1/content/changes').expect(200);
    expect(unpublished.body.some((item: { id: string }) => item.id === first.body.id)).toBe(false);

    await request(http)
      .patch(`/v1/content/admin/changes/${first.body.id}/review`)
      .set('x-admin-key', process.env.ADMIN_API_KEY as string)
      .send({ status: 'VERIFIED' })
      .expect(400);
    await request(http)
      .patch(`/v1/content/admin/changes/${first.body.id}/review`)
      .set('x-admin-key', process.env.ADMIN_API_KEY as string)
      .send({ status: 'VERIFIED', editorSummaryZh: '官方页面出现已人工核对的重要文字变化。' })
      .expect(200);

    const published = await request(http).get('/v1/content/changes').expect(200);
    expect(published.body.some((item: { id: string }) => item.id === first.body.id)).toBe(true);

    await request(http)
      .patch(`/v1/content/admin/changes/${first.body.id}/review`)
      .set('x-admin-key', process.env.ADMIN_API_KEY as string)
      .send({
        status: 'CORRECTED',
        editorSummaryZh: '更正后的事实性摘要。',
        correctionNote: '修正了首次摘要中的日期表述；页面证据未删除。',
      })
      .expect(200);
    const corrections = await request(http)
      .get('/v1/content/admin/corrections')
      .set('x-admin-key', process.env.ADMIN_API_KEY as string)
      .expect(200);
    expect(corrections.body.some((item: { id: string }) => item.id === first.body.id)).toBe(true);
  });

  it('25. 离线操作可按同一 ID 安全重试，旧版本必须由用户处理冲突', async () => {
    const current = await request(http)
      .get(`/v1/projects/${projectId}`)
      .set(as(ownerEmail))
      .expect(200);
    const operationId = randomUUID();
    const operation = {
      operationId,
      baseVersion: current.body.version,
      kind: 'UPDATE_CHECKLIST',
      clientItemId: 'local-second-item',
      remoteItemId: secondItemId,
      status: 'CONFIRMED',
      note: '本机离线完成，恢复联网后提交。',
      clearDueAt: true,
      clearReminderAt: true,
    };

    const first = await request(http)
      .post(`/v1/projects/${projectId}/sync-operations`)
      .set(as(ownerEmail))
      .send(operation)
      .expect(201);
    const retried = await request(http)
      .post(`/v1/projects/${projectId}/sync-operations`)
      .set(as(ownerEmail))
      .send(operation)
      .expect(201);
    expect(retried.body).toEqual(first.body);

    const afterRetry = await request(http)
      .get(`/v1/projects/${projectId}`)
      .set(as(ownerEmail))
      .expect(200);
    expect(afterRetry.body.version).toBe(current.body.version + 1);
    expect(
      afterRetry.body.checklist.find((item: { id: string }) => item.id === secondItemId).status,
    ).toBe('CONFIRMED');
    expect(await prisma.syncOperation.count({ where: { id: operationId } })).toBe(1);

    await request(http)
      .post(`/v1/projects/${projectId}/sync-operations`)
      .set(as(ownerEmail))
      .send({ ...operation, status: 'SENT' })
      .expect(409);

    const stale = await request(http)
      .post(`/v1/projects/${projectId}/sync-operations`)
      .set(as(ownerEmail))
      .send({
        ...operation,
        operationId: randomUUID(),
        baseVersion: current.body.version,
      })
      .expect(409);
    const conflict =
      typeof stale.body.message === 'object' ? stale.body.message : stale.body;
    expect(conflict.code).toBe('PROJECT_VERSION_CONFLICT');
    expect(conflict.serverVersion).toBe(afterRetry.body.version);
  });

  it('26. 预签名直传不经过 API 内存，完成响应丢失时可幂等恢复', async () => {
    const created = await request(http)
      .post('/v1/projects')
      .set(as(ownerEmail))
      .send({ name: '预签名上传验收', template: 'SA_190', applicantName: '申请人 A' })
      .expect(201);
    await request(http)
      .patch(`/v1/projects/${created.body.id}/cloud-files`)
      .set(as(ownerEmail))
      .send({ enabled: true })
      .expect(200);

    const session = await request(http)
      .post(`/v1/projects/${created.body.id}/uploads`)
      .set(as(ownerEmail))
      .send({
        originalName: 'presigned-passport.pdf',
        contentType: 'application/pdf',
        byteSize: samplePdf.length,
        sha256: samplePdfSha256,
        checklistItemId: created.body.checklist[0].id,
      })
      .expect(201);
    const uploaded = await fetch(session.body.uploadUrl, {
      method: 'PUT',
      headers: session.body.requiredHeaders,
      body: samplePdf,
    });
    expect(uploaded.status).toBe(200);

    const completed = await request(http)
      .post(`/v1/uploads/${session.body.uploadId}/complete`)
      .set(as(ownerEmail))
      .send({ checklistItemId: created.body.checklist[0].id })
      .expect(201);
    expect(completed.body.scanStatus).toBe('CLEAN');
    expect(completed.body.sha256).toBe(samplePdfSha256);

    const retried = await request(http)
      .post(`/v1/uploads/${session.body.uploadId}/complete`)
      .set(as(ownerEmail))
      .send({ checklistItemId: created.body.checklist[0].id })
      .expect(201);
    expect(retried.body.id).toBe(completed.body.id);
    expect(retried.body.idempotent).toBe(true);
    expect(
      await prisma.fileRecord.count({ where: { projectId: created.body.id } }),
    ).toBe(1);

    await request(http)
      .delete(`/v1/files/${completed.body.id}`)
      .set(as(ownerEmail))
      .expect(200);
  });

  it('27. 人工核实后按关注规则写入幂等通知 Outbox，锁屏载荷不含政策正文', async () => {
    await request(http)
      .patch('/v1/notification-preferences')
      .set(as(ownerEmail))
      .send({
        policyUpdates: true,
        productUpdates: false,
        jurisdictions: ['AU-SA'],
        tags: ['491'],
        importantOnly: true,
        timezone: 'Australia/Adelaide',
      })
      .expect(200);
    const candidate = await request(http)
      .post('/v1/content/worker/changes')
      .set('x-worker-key', process.env.WORKER_API_KEY as string)
      .send({
        sourceUrl: `https://migration.sa.gov.au/e2e/${run}`,
        sourceName: `E2E source ${run}`,
        titleZh: `通知验收变化 ${run}`,
        oldExcerpt: '不应进入锁屏通知的旧正文。',
        newExcerpt: '不应进入锁屏通知的新正文。',
        context: '通知只携带内容 ID 和泛化文案。',
        importance: 'IMPORTANT',
        discoveredAt: new Date().toISOString(),
        tags: ['491'],
      })
      .expect(201);
    await request(http)
      .patch(`/v1/content/admin/changes/${candidate.body.id}/review`)
      .set('x-admin-key', process.env.ADMIN_API_KEY as string)
      .send({ status: 'VERIFIED', editorSummaryZh: '仅在 App 内打开后展示的编辑摘要。' })
      .expect(200);

    const claimed = await request(http)
      .post('/v1/notification-worker/claim')
      .set('x-worker-key', process.env.WORKER_API_KEY as string)
      .send({ batchSize: 10 })
      .expect(201);
    const task = claimed.body.find(
      (item: { payload: { route: string } }) =>
        item.payload.route === `/changes/${candidate.body.id}`,
    );
    expect(task).toBeTruthy();
    const serialised = JSON.stringify(task);
    expect(serialised).not.toContain('旧正文');
    expect(serialised).not.toContain('新正文');
    expect(serialised).not.toContain('编辑摘要');

    await request(http)
      .post(`/v1/notification-worker/${task.id}/result`)
      .set('x-worker-key', process.env.WORKER_API_KEY as string)
      .send({ status: 'SENT' })
      .expect(201);
    const repeated = await request(http)
      .post(`/v1/notification-worker/${task.id}/result`)
      .set('x-worker-key', process.env.WORKER_API_KEY as string)
      .send({ status: 'SENT' })
      .expect(201);
    expect(repeated.body.idempotent).toBe(true);
    expect(
      await prisma.notificationOutbox.count({
        where: { entityId: candidate.body.id },
      }),
    ).toBe(1);
  });

  it('28. 账号删除有 7 天撤回窗口，到期作业先清对象再保留最小删除证明', async () => {
    await request(http).get('/v1/auth/me').set(as(deletionEmail)).expect(200);
    const created = await request(http)
      .post('/v1/projects')
      .set(as(deletionEmail))
      .send({ name: '待删除项目', template: 'SA_190', applicantName: '待删除申请人' })
      .expect(201);
    await request(http)
      .patch(`/v1/projects/${created.body.id}/cloud-files`)
      .set(as(deletionEmail))
      .send({ enabled: true })
      .expect(200);
    const uploaded = await request(http)
      .post(`/v1/projects/${created.body.id}/files`)
      .set(as(deletionEmail))
      .field('checklistItemId', created.body.checklist[0].id)
      .attach('file', samplePdf, {
        filename: 'deletion-proof.pdf',
        contentType: 'application/pdf',
      })
      .expect(201);

    const requested = await request(http)
      .delete('/v1/auth/me')
      .set(as(deletionEmail))
      .expect(200);
    expect(new Date(requested.body.scheduledFor).getTime()).toBeGreaterThan(Date.now());
    await request(http)
      .post('/v1/auth/me/deletion/cancel')
      .set(as(deletionEmail))
      .expect(201);
    const afterCancel = await request(http)
      .get('/v1/auth/me')
      .set(as(deletionEmail))
      .expect(200);
    expect(afterCancel.body.deletionRequestedAt).toBeNull();

    await request(http).delete('/v1/auth/me').set(as(deletionEmail)).expect(200);
    const deletionAccount = await prisma.account.findUniqueOrThrow({
      where: { email: deletionEmail },
      select: { id: true },
    });
    await prisma.account.update({
      where: { id: deletionAccount.id },
      data: { deletionRequestedAt: new Date(Date.now() - 8 * 24 * 60 * 60_000) },
    });
    const worker = await request(http)
      .post('/v1/account-worker/run-due-deletions')
      .set('x-worker-key', process.env.WORKER_API_KEY as string)
      .expect(201);
    expect(worker.body.deleted).toBe(1);
    expect(worker.body.failed).toBe(0);
    expect(await prisma.account.count({ where: { id: deletionAccount.id } })).toBe(0);
    expect(await prisma.project.count({ where: { id: created.body.id } })).toBe(0);
    expect(await prisma.fileRecord.count({ where: { id: uploaded.body.id } })).toBe(0);
    const ledger = await prisma.accountDeletionLedger.findFirst({
      orderBy: { deletedAt: 'desc' },
    });
    expect(ledger?.accountHash).toMatch(/^[a-f0-9]{64}$/);
    expect(ledger?.objectCount).toBeGreaterThanOrEqual(1);
    await prisma.accountDeletionLedger.delete({
      where: { id: ledger!.id },
    });
  });

  it('29. 过期未完成上传会清除隔离对象和会话', async () => {
    const created = await request(http)
      .post('/v1/projects')
      .set(as(ownerEmail))
      .send({ name: '过期上传清理', template: 'SA_491', applicantName: '申请人 A' })
      .expect(201);
    await request(http)
      .patch(`/v1/projects/${created.body.id}/cloud-files`)
      .set(as(ownerEmail))
      .send({ enabled: true })
      .expect(200);
    const upload = await request(http)
      .post(`/v1/projects/${created.body.id}/uploads`)
      .set(as(ownerEmail))
      .send({
        originalName: 'abandoned.pdf',
        contentType: 'application/pdf',
        byteSize: samplePdf.length,
        sha256: samplePdfSha256,
        checklistItemId: created.body.checklist[0].id,
      })
      .expect(201);
    const uploaded = await fetch(upload.body.uploadUrl, {
      method: 'PUT',
      headers: upload.body.requiredHeaders,
      body: samplePdf,
    });
    expect(uploaded.status).toBe(200);
    const session = await prisma.uploadSession.update({
      where: { id: upload.body.uploadId },
      data: { expiresAt: new Date(Date.now() - 60_000) },
      select: { id: true, storageKey: true },
    });

    const cleanup = await request(http)
      .post('/v1/file-worker/cleanup-expired-uploads')
      .set('x-worker-key', process.env.WORKER_API_KEY as string)
      .expect(201);
    expect(cleanup.body.deleted).toBeGreaterThanOrEqual(1);
    expect(await prisma.uploadSession.count({ where: { id: session.id } })).toBe(0);

    const s3 = new S3Client({
      region: process.env.S3_REGION,
      endpoint: process.env.S3_ENDPOINT,
      forcePathStyle: true,
    });
    await expect(
      s3.send(
        new HeadObjectCommand({
          Bucket: process.env.S3_USER_BUCKET,
          Key: session.storageKey,
        }),
      ),
    ).rejects.toBeTruthy();
    s3.destroy();
  });

  it('34. 云文件未开放时拒绝新增上传，但仍允许取回与删除既有文件', async () => {
    // 先在开放状态下放入一个文件，再关闭开关，验证“只挡新增、不锁数据”。
    const upload = await request(http)
      .post(`/v1/projects/${projectId}/files`)
      .set(as(ownerEmail))
      .attach('file', samplePdf, { filename: 'gated.pdf', contentType: 'application/pdf' })
      .expect(201);

    const previous = process.env.CLOUD_FILES_ENABLED;
    process.env.CLOUD_FILES_ENABLED = 'false';
    try {
      const blocked = await request(http)
        .post(`/v1/projects/${projectId}/files`)
        .set(as(ownerEmail))
        .attach('file', samplePdf, { filename: 'blocked.pdf', contentType: 'application/pdf' })
        .expect(503);
      expect(blocked.body.message).toContain('云文件上传尚未开放');

      await request(http)
        .post(`/v1/projects/${projectId}/uploads`)
        .set(as(ownerEmail))
        .send({
          originalName: 'blocked.pdf',
          contentType: 'application/pdf',
          byteSize: samplePdf.length,
          sha256: samplePdfSha256,
        })
        .expect(503);

      // 权益接口告知客户端，避免用户在上传时才发现不可用。
      const entitlement = await request(http)
        .get('/v1/entitlements/me')
        .set(as(ownerEmail))
        .expect(200);
      expect(entitlement.body.cloudFileUploads.enabled).toBe(false);
      expect(entitlement.body.cloudFileUploads.disabledReason).toContain('只保存在你的设备上');

      // 关闭上传不能把既有数据锁死：下载与删除必须仍然可用。
      await request(http)
        .get(`/v1/files/${upload.body.id}/download`)
        .set(as(ownerEmail))
        .expect(200);
      await request(http)
        .delete(`/v1/files/${upload.body.id}`)
        .set(as(ownerEmail))
        .expect(200);
    } finally {
      restoreEnv('CLOUD_FILES_ENABLED', previous);
    }
  });

  it('34. 监控状态区分「已监控无变化」与「根本没在监控」', async () => {
    const unreachable = `e2e-unreachable-${run}`;
    const healthy = `e2e-healthy-${run}`;
    await prisma.source.createMany({
      data: [
        {
          name: unreachable,
          url: `https://example.invalid/${unreachable}`,
          jurisdiction: 'AU-FED',
          sourceType: 'official',
          enabled: false,
        },
        {
          name: healthy,
          url: `https://example.invalid/${healthy}`,
          jurisdiction: 'AU-SA',
          sourceType: 'official',
          enabled: true,
          lastSuccessAt: new Date(),
        },
      ],
    });

    try {
      const status = await request(http).get('/v1/content/monitoring').expect(200);

      const names = status.body.unavailableSources.map(
        (item: { name: string }) => item.name,
      );
      expect(names).toContain(unreachable);
      expect(names).not.toContain(healthy);
      expect(status.body.unavailableJurisdictions).toContain('AU-FED');
      expect(status.body.monitoredCount).toBeGreaterThan(0);

      // 公开接口不得下发失败细节与内部标识。
      const serialised = JSON.stringify(status.body);
      expect(serialised).not.toContain('lastFailureCode');
      expect(serialised).not.toContain('example.invalid');
    } finally {
      await prisma.source.deleteMany({
        where: { name: { in: [unreachable, healthy] } },
      });
    }
  });

  it('30. 公网内测登录签发受验证 JWT，不依赖可伪造的邮箱请求头', async () => {
    const accessCode = 'e2e-pilot-access';
    await withPilotAuth({ [pilotEmail]: accessCode }, async () => {
      const login = await request(http)
        .post('/v1/auth/pilot')
        .send({ email: pilotEmail, accessCode })
        .expect(201);
      expect(login.body.accessToken).toEqual(expect.any(String));

      const account = await request(http)
        .get('/v1/auth/me')
        .set('authorization', `Bearer ${login.body.accessToken}`)
        .set('x-dev-account-email', 'attacker@migration-companion.invalid')
        .expect(200);
      expect(account.body.email).toBe(pilotEmail);
      expect(account.body.id).toMatch(/^pilot-/);

      await request(http)
        .get('/v1/auth/me')
        .set('authorization', 'Bearer invalid-pilot-token')
        .set('x-dev-account-email', pilotEmail)
        .expect(401);
    });
  });

  it('31. 内测访问码绑定邮箱：拿别人的码登录自己的邮箱会被拒绝', async () => {
    const ownCode = 'e2e-pilot-access';
    const otherEmail = `e2e-pilot-other-${run}@migration-companion.invalid`;
    await withPilotAuth(
      { [pilotEmail]: ownCode, [otherEmail]: 'e2e-other-access' },
      async () => {
        // 持有 pilotEmail 的码，却试图登录 otherEmail —— 这正是共享码方案下的冒充路径。
        await request(http)
          .post('/v1/auth/pilot')
          .send({ email: otherEmail, accessCode: ownCode })
          .expect(401);

        // 不在名单内的邮箱与错误访问码返回同一个响应，不泄露内测名单。
        const unknown = await request(http)
          .post('/v1/auth/pilot')
          .send({ email: `nobody-${run}@migration-companion.invalid`, accessCode: ownCode })
          .expect(401);
        expect(unknown.body.message).toBe('邮箱或内测访问码无效');
      },
    );
  });

  it('32. 内测登录连续失败会锁定该邮箱，正确访问码在锁定期内同样被拒', async () => {
    const accessCode = 'e2e-pilot-access';
    const lockedEmail = `e2e-pilot-locked-${run}@migration-companion.invalid`;
    await withPilotAuth({ [lockedEmail]: accessCode }, async () => {
      for (let attempt = 0; attempt < 5; attempt += 1) {
        await request(http)
          .post('/v1/auth/pilot')
          .send({ email: lockedEmail, accessCode: 'wrong-access-code' })
          .expect(401);
      }
      await request(http)
        .post('/v1/auth/pilot')
        .send({ email: lockedEmail, accessCode })
        .expect(429);
    });
    await prisma.pilotLoginAttempt.deleteMany({ where: { email: lockedEmail } });
  });

  it('33. 旧的共享访问码配置被拒绝启动，不允许静默沿用', async () => {
    const previous = {
      nodeEnv: process.env.NODE_ENV,
      enabled: process.env.PILOT_AUTH_ENABLED,
      secret: process.env.PILOT_JWT_SECRET,
      codes: process.env.PILOT_ACCESS_CODES,
      legacy: process.env.PILOT_ACCESS_CODE_SCRYPT,
    };
    const salt = randomBytes(16);
    process.env.NODE_ENV = 'production';
    process.env.PILOT_AUTH_ENABLED = 'true';
    process.env.PILOT_JWT_SECRET = 'e2e-only-jwt-secret-with-at-least-32-characters';
    delete process.env.PILOT_ACCESS_CODES;
    process.env.PILOT_ACCESS_CODE_SCRYPT = `${salt.toString('hex')}:${scryptSync('shared-code', salt, 32).toString('hex')}`;
    try {
      const response = await request(http)
        .post('/v1/auth/pilot')
        .send({ email: pilotEmail, accessCode: 'shared-code' })
        .expect(503);
      expect(response.body.message).toContain('PILOT_ACCESS_CODES');
    } finally {
      restoreEnv('NODE_ENV', previous.nodeEnv);
      restoreEnv('PILOT_AUTH_ENABLED', previous.enabled);
      restoreEnv('PILOT_JWT_SECRET', previous.secret);
      restoreEnv('PILOT_ACCESS_CODES', previous.codes);
      restoreEnv('PILOT_ACCESS_CODE_SCRYPT', previous.legacy);
    }
  });

  it('31. 爬虫新闻只能进入草稿，中文编辑完成前不能公开', async () => {
    expect(contentSourceId).toBeTruthy();
    const source = await prisma.source.findUniqueOrThrow({ where: { id: contentSourceId } });
    await prisma.source.update({ where: { id: source.id }, data: { enabled: true } });
    const sourceUrl = `${source.url}/official-article-${run}`;
    const payload = {
      sourceRegistryUrl: source.url,
      sourceUrl,
      sourceTitle: 'Official English source title',
      sourceExcerpt: 'Official English source excerpt retained only inside the editorial draft.',
      tags: ['南澳'],
      publishedAt: new Date().toISOString(),
    };
    const draft = await request(http)
      .post('/v1/content/worker/news')
      .set('x-worker-key', process.env.WORKER_API_KEY as string)
      .send(payload)
      .expect(201);
    const retried = await request(http)
      .post('/v1/content/worker/news')
      .set('x-worker-key', process.env.WORKER_API_KEY as string)
      .send(payload)
      .expect(201);
    expect(retried.body.id).toBe(draft.body.id);
    expect(draft.body.isPublished).toBe(false);

    await request(http)
      .patch(`/v1/content/admin/news/${draft.body.id}`)
      .set('x-admin-key', process.env.ADMIN_API_KEY as string)
      .send({ isPublished: true })
      .expect(400);
    await request(http)
      .patch(`/v1/content/admin/news/${draft.body.id}`)
      .set('x-admin-key', process.env.ADMIN_API_KEY as string)
      .send({
        titleZh: '南澳官方资讯更新',
        summaryZh: '这是一段经过人工核对的中文原创事实摘要，用户仍需返回官方原文确认。',
        isPublished: true,
      })
      .expect(200);
    const publicNews = await request(http).get('/v1/content/news').expect(200);
    expect(publicNews.body.some((item: { id: string }) => item.id === draft.body.id)).toBe(true);
  });
});

function restoreEnv(name: string, value: string | undefined) {
  if (value === undefined) delete process.env[name];
  else process.env[name] = value;
}

/// 以“逐邮箱绑定的内测访问码”配置运行一段验收，并在结束后恢复原环境。
async function withPilotAuth(
  codesByEmail: Record<string, string>,
  body: () => Promise<void>,
) {
  const previous = {
    nodeEnv: process.env.NODE_ENV,
    enabled: process.env.PILOT_AUTH_ENABLED,
    secret: process.env.PILOT_JWT_SECRET,
    codes: process.env.PILOT_ACCESS_CODES,
    legacy: process.env.PILOT_ACCESS_CODE_SCRYPT,
  };
  process.env.NODE_ENV = 'production';
  process.env.PILOT_AUTH_ENABLED = 'true';
  process.env.PILOT_JWT_SECRET = 'e2e-only-jwt-secret-with-at-least-32-characters';
  delete process.env.PILOT_ACCESS_CODE_SCRYPT;
  process.env.PILOT_ACCESS_CODES = Object.entries(codesByEmail)
    .map(([email, code]) => {
      const salt = randomBytes(16);
      return `${email}=${salt.toString('hex')}:${scryptSync(code, salt, 32).toString('hex')}`;
    })
    .join(',');
  try {
    await body();
  } finally {
    restoreEnv('NODE_ENV', previous.nodeEnv);
    restoreEnv('PILOT_AUTH_ENABLED', previous.enabled);
    restoreEnv('PILOT_JWT_SECRET', previous.secret);
    restoreEnv('PILOT_ACCESS_CODES', previous.codes);
    restoreEnv('PILOT_ACCESS_CODE_SCRYPT', previous.legacy);
  }
}

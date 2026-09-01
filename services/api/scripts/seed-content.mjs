// 初始内容播种。只在部署时手工跑（pnpm content:seed），不参与日常运营。
//
// 两处「看起来像漏了」的地方是有意的，改之前请先读这里：
//
// 1. registry 的 `enabled: false` 是代码审查过的安全停用（robots、403 或许可边界），
//    每次部署都必须同步到数据库；否则采集器虽会跳过，后台却仍把来源显示为启用。
//    `enabled: true` 不反向写回，避免部署把管理员临时停用的来源重新打开。
//
// 2. reviewed-news 只负责首次创建。已经入库的条目绝不在每次容器启动时覆盖：
//    官方原文变化后采集器会撤下旧摘要并重新审核；如果 seed 又把它改回已发布，
//    就绕过了整条编辑流水线。首次创建也不走通知扇出，避免历史内容刷屏。
import { PrismaClient } from '@prisma/client'
import { readFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'

const prisma = new PrismaClient()
const registryPath = process.env.CONTENT_SOURCE_REGISTRY
  ?? fileURLToPath(new URL('../../crawler/sources.json', import.meta.url))
const reviewedNewsPath = process.env.REVIEWED_NEWS_PATH
  ?? fileURLToPath(new URL('../content/reviewed-news.json', import.meta.url))

try {
  const records = JSON.parse(await readFile(registryPath, 'utf8'))
  for (const record of records) {
    await prisma.source.upsert({
      where: { url: record.url },
      create: {
        name: record.name,
        url: record.url,
        jurisdiction: record.jurisdiction,
        sourceType: 'official',
        enabled: record.enabled === true,
        licenseNote: record.license_note,
      },
      update: {
        name: record.name,
        jurisdiction: record.jurisdiction,
        sourceType: 'official',
        licenseNote: record.license_note,
        ...(record.enabled === false ? { enabled: false } : {}),
      },
    })
  }
  console.log(`Content source registry ready: ${records.length} sources`)

  const reviewedNews = JSON.parse(await readFile(reviewedNewsPath, 'utf8'))
  for (const item of reviewedNews) {
    const source = await prisma.source.findUniqueOrThrow({
      where: { url: item.sourceRegistryUrl },
    })
    await prisma.newsItem.upsert({
      where: { sourceUrl: item.sourceUrl },
      create: {
        sourceId: source.id,
        titleZh: item.titleZh,
        summaryZh: item.summaryZh,
        sourceTitle: item.sourceTitle,
        sourceUrl: item.sourceUrl,
        tags: item.tags,
        publishedAt: new Date(item.publishedAt),
        isPublished: true,
        draftAuthor: 'editor',
        editorialReviewStatus: 'HUMAN_APPROVED',
        editorialReviewedAt: new Date(),
      },
      update: {},
    })
  }
  console.log(`Reviewed news ready: ${reviewedNews.length} published items`)
} finally {
  await prisma.$disconnect()
}

// 初始内容播种。只在部署时手工跑（pnpm content:seed），不参与日常运营。
//
// 两处「看起来像漏了」的地方是有意的，改之前请先读这里：
//
// 1. update 分支不写 `enabled`。来源的启停由后台控制（管理员在来源卡片上点
//    「停用」），重跑播种不能把这个决定盖回去——比如某个来源开始对 robots.txt
//    返回 403、我们据此停用了它，重跑一次 seed 就会把它重新打开并继续抓。
//    registry 决定来源存在与否，后台决定它开不开。
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

// 初始内容播种。只在部署时手工跑（pnpm content:seed），不参与日常运营。
//
// 两处「看起来像漏了」的地方是有意的，改之前请先读这里：
//
// 1. update 分支不写 `enabled`。来源的启停由后台控制（管理员在来源卡片上点
//    「停用」），重跑播种不能把这个决定盖回去——比如某个来源开始对 robots.txt
//    返回 403、我们据此停用了它，重跑一次 seed 就会把它重新打开并继续抓。
//    registry 决定来源存在与否，后台决定它开不开。
//
// 2. 直接写 isPublished，不走发布扇出，因此订阅者不会收到通知。这对历史内容
//    是对的：一次播种几十条陈年公告，挨个推送就是刷屏。**新内容不要走这里**，
//    走后台发布，那条路径才会通知订阅者。
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
      },
      update: {
        sourceId: source.id,
        titleZh: item.titleZh,
        summaryZh: item.summaryZh,
        sourceTitle: item.sourceTitle,
        tags: item.tags,
        publishedAt: new Date(item.publishedAt),
        isPublished: true,
      },
    })
  }
  console.log(`Reviewed news ready: ${reviewedNews.length} published items`)
} finally {
  await prisma.$disconnect()
}

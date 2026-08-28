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

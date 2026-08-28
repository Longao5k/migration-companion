import { PrismaClient } from '@prisma/client'
import { readFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'

const prisma = new PrismaClient()
const registryUrl = new URL('../../crawler/sources.json', import.meta.url)

try {
  const records = JSON.parse(await readFile(fileURLToPath(registryUrl), 'utf8'))
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
} finally {
  await prisma.$disconnect()
}

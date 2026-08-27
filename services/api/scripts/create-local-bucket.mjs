import { CreateBucketCommand, HeadBucketCommand, S3Client } from '@aws-sdk/client-s3'

const bucket = process.env.S3_USER_BUCKET ?? 'migration-user-files'
const client = new S3Client({
  region: process.env.S3_REGION ?? 'ap-southeast-2',
  endpoint: process.env.S3_ENDPOINT ?? 'http://127.0.0.1:59000',
  forcePathStyle: true,
})

try {
  await client.send(new HeadBucketCommand({ Bucket: bucket }))
} catch {
  await client.send(new CreateBucketCommand({ Bucket: bucket }))
}

console.log(`Local bucket ready: ${bucket}`)

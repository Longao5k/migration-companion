# Infrastructure boundary

Local development uses synthetic data in PostgreSQL and MinIO only. Production is an Australia data cell in AWS Sydney (`ap-southeast-2`) with separate accounts for development, staging and production.

Production infrastructure is intentionally gated until the AWS account, domain, Cognito pool, Apple/Google store accounts, Apryse/ONLYOFFICE commercial terms, DPA and security ownership are supplied. It must include private S3/KMS keyspaces, RDS PostgreSQL Multi-AZ, ECS services, WAF/ALB, SQS/DLQ, Cognito, Secrets Manager, deletion ledger, monitoring and independent backup credentials. Console-created resources are not an accepted production baseline.

```powershell
docker compose -f infra\docker-compose.yml up -d postgres minio
$env:DATABASE_URL='postgresql://migration:local-only-migration@localhost:55432/migration?schema=public'
pnpm --filter @migration-companion/api prisma db push
```


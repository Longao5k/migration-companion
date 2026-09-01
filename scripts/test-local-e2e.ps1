<#
.SYNOPSIS
    运行第一阶段 API 端到端验收套件。

.DESCRIPTION
    把交接文档第 4 节里手工跑过的验收步骤变成可重复执行的自动化验收：
    启动本地 PostgreSQL 与 MinIO、同步数据库结构、准备文件桶，然后运行
    services/api 的 e2e 套件。

    套件使用与生产相同的 Nest 管道（全局前缀、校验管道、helmet），只在
    DEV_AUTH / DEV_AUTO_SCAN / DEV_STORE 三个开发开关下运行，永远不会在
    NODE_ENV=production 下启动。

.PARAMETER KeepStack
    验收结束后保留 PostgreSQL 与 MinIO 容器（默认行为）。传入 -StopStack 可在结束后停止容器。
#>
param(
    [switch]$StopStack
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'lib\pnpm.ps1')

$pnpm = Resolve-PnpmCommand
if (-not $env:LOCAL_POSTGRES_PORT) { $env:LOCAL_POSTGRES_PORT = '55432' }
if (-not $env:LOCAL_MINIO_PORT) { $env:LOCAL_MINIO_PORT = '45900' }
if (-not $env:LOCAL_MINIO_CONSOLE_PORT) { $env:LOCAL_MINIO_CONSOLE_PORT = '45901' }
$env:DATABASE_URL = "postgresql://migration:local-only-migration@localhost:$($env:LOCAL_POSTGRES_PORT)/migration?schema=public"
$env:AWS_ACCESS_KEY_ID = 'localmigration'
$env:AWS_SECRET_ACCESS_KEY = 'local-only-migration-storage'
$env:S3_ENDPOINT = "http://127.0.0.1:$($env:LOCAL_MINIO_PORT)"
$env:S3_FORCE_PATH_STYLE = 'true'
$env:S3_USER_BUCKET = 'migration-user-files'

Push-Location $projectRoot
try {
    Write-Host '[1/4] 启动本地 PostgreSQL 与 MinIO ...'
    docker compose -f infra\docker-compose.yml up -d --wait
    if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL/MinIO 启动失败' }

    Write-Host '[2/4] 同步数据库结构 ...'
    # This URL is pinned above to the disposable local acceptance database.
    # Production deploys use checked-in migrations and `prisma migrate deploy`.
    Invoke-Expression "$pnpm --filter @migration-companion/api exec prisma db push --accept-data-loss"
    if ($LASTEXITCODE -ne 0) { throw '数据库结构初始化失败' }

    Write-Host '[3/4] 准备本地文件桶 ...'
    node services\api\scripts\create-local-bucket.mjs
    if ($LASTEXITCODE -ne 0) { throw '本地文件桶初始化失败' }

    Write-Host '[4/4] 运行 API 端到端验收 ...'
    Invoke-Expression "$pnpm --filter @migration-companion/api test:e2e"
    if ($LASTEXITCODE -ne 0) { throw 'API 端到端验收失败' }
} finally {
    if ($StopStack) {
        docker compose -f infra\docker-compose.yml stop | Out-Null
    }
    Pop-Location
}

Write-Host ''
Write-Host 'API 端到端验收通过。'
if (-not $StopStack) {
    Write-Host 'PostgreSQL 与 MinIO 仍在运行；停止请执行 .\scripts\stop-local.ps1'
}

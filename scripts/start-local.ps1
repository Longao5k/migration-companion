param(
    [switch]$SkipMobileWeb
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$stateDirectory = Join-Path $projectRoot '.local'
$logDirectory = Join-Path $stateDirectory 'logs'
$statePath = Join-Path $stateDirectory 'run-state.json'
. (Join-Path $PSScriptRoot 'lib\pnpm.ps1')
$pnpm = Resolve-PnpmCommand

# 后台进程用哪个 PowerShell 宿主：优先 PowerShell 7，未安装时退回 Windows PowerShell 5.1。
$powerShellHost = $null
foreach ($candidate in @('pwsh', 'powershell')) {
    $resolved = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($resolved) { $powerShellHost = $resolved.Source; break }
}
if (-not $powerShellHost) { throw '找不到 pwsh 或 powershell，无法启动本地服务进程。' }

New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null

if (Test-Path -LiteralPath $statePath) {
    throw '本地服务状态文件已存在。请先运行 scripts\stop-local.ps1，避免重复启动。'
}

Push-Location $projectRoot
try {
    docker compose -f infra\docker-compose.yml up -d --wait
    if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL/MinIO 启动失败' }

    $env:DATABASE_URL = 'postgresql://migration:local-only-migration@localhost:55432/migration?schema=public'
    Invoke-Expression "$pnpm --filter @migration-companion/api exec prisma db push"
    if ($LASTEXITCODE -ne 0) { throw '数据库结构初始化失败' }

    $env:AWS_ACCESS_KEY_ID = 'localmigration'
    $env:AWS_SECRET_ACCESS_KEY = 'local-only-migration-storage'
    $env:S3_ENDPOINT = 'http://127.0.0.1:59000'
    $env:S3_FORCE_PATH_STYLE = 'true'
    $env:S3_USER_BUCKET = 'migration-user-files'
    node services\api\scripts\create-local-bucket.mjs
    if ($LASTEXITCODE -ne 0) { throw '本地文件桶初始化失败' }

    Invoke-Expression "$pnpm --filter @migration-companion/api build"
    if ($LASTEXITCODE -ne 0) { throw 'API 编译失败' }
} finally {
    Pop-Location
}

function Start-LocalProcess {
    param(
        [string]$Name,
        [string]$WorkingDirectory,
        [string]$Command
    )
    $stdoutPath = Join-Path $logDirectory "$Name.out.log"
    $stderrPath = Join-Path $logDirectory "$Name.err.log"
    $process = Start-Process `
        -FilePath $script:powerShellHost `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $Command) `
        -WorkingDirectory $WorkingDirectory `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -PassThru
    return [ordered]@{
        name = $Name
        pid = $process.Id
        startedAt = $process.StartTime.ToUniversalTime().ToString('o')
    }
}

$processes = @()
$processes += Start-LocalProcess -Name 'api' -WorkingDirectory (Join-Path $projectRoot 'services\api') -Command "& '.\scripts\start-local-api.ps1'"
$processes += Start-LocalProcess -Name 'web' -WorkingDirectory (Join-Path $projectRoot 'apps\web') -Command "`$env:NEXT_PUBLIC_API_BASE='http://127.0.0.1:53001'; $pnpm exec next dev -H 127.0.0.1 -p 53003"
$processes += Start-LocalProcess -Name 'admin' -WorkingDirectory (Join-Path $projectRoot 'apps\admin') -Command "$pnpm dev"
if (-not $SkipMobileWeb) {
    $processes += Start-LocalProcess -Name 'mobile-web' -WorkingDirectory (Join-Path $projectRoot 'apps\mobile') -Command "fvm flutter run -d web-server --web-hostname 127.0.0.1 --web-port 53004 --dart-define=API_BASE_URL=http://127.0.0.1:53001/v1 --dart-define=WEB_BASE_URL=http://127.0.0.1:53003"
}

[ordered]@{
    projectRoot = $projectRoot
    startedAt = [DateTime]::UtcNow.ToString('o')
    processes = $processes
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $statePath -Encoding UTF8

Write-Host ''
Write-Host 'Migration Companion 本地环境已启动：'
if (-not $SkipMobileWeb) {
    Write-Host '  App 网页预览  http://127.0.0.1:53004'
}
Write-Host '  安全分享网页  http://127.0.0.1:53003'
Write-Host '  内容运营后台  http://127.0.0.1:53002  （本地密钥 local-admin）'
Write-Host '  API 健康检查 http://127.0.0.1:53001/v1/health'
Write-Host ''
Write-Host '停止时运行：.\scripts\stop-local.ps1'

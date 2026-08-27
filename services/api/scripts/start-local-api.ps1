$env:DATABASE_URL = 'postgresql://migration:local-only-migration@localhost:55432/migration?schema=public'
$env:DEV_AUTH = 'true'
$env:PORT = '53001'
$env:ADMIN_API_KEY = 'local-admin'
$env:WORKER_API_KEY = 'local-worker'
$env:DEV_STORE = 'true'
$env:DEV_AUTO_SCAN = 'true'
$env:AWS_ACCESS_KEY_ID = 'localmigration'
$env:AWS_SECRET_ACCESS_KEY = 'local-only-migration-storage'
$env:S3_ENDPOINT = 'http://127.0.0.1:59000'
$env:S3_FORCE_PATH_STYLE = 'true'
$env:S3_USER_BUCKET = 'migration-user-files'
$env:SHARE_ORIGIN = 'http://127.0.0.1:53003'
# 允许的浏览器来源：内容后台 53002、分享网页 53003、Flutter Web 调试预览 53004、
# release 预览（scripts\preview-web-release.ps1）53005。缺少任何一个都会让该页面的 API 调用被 CORS 拒绝。
$env:APP_ORIGIN = 'http://127.0.0.1:53002,http://localhost:53002,http://127.0.0.1:53003,http://localhost:53003,http://127.0.0.1:53004,http://localhost:53004,http://127.0.0.1:53005,http://localhost:53005'

. (Join-Path $PSScriptRoot '..\..\..\scripts\lib\pnpm.ps1')
Invoke-Expression "$(Resolve-PnpmCommand) --filter @migration-companion/api start"

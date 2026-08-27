<#
.SYNOPSIS
    构建并本地预览 Flutter Web release 版本，附带固定手机视口的检查页。

.DESCRIPTION
    交接文档 P0-A 第 4 条要求分别用 Chrome Web、Android 模拟器和 release Web build
    复测 390x844 视口下的启动问题。debug 的 `flutter run -d web-server` 依赖调试连接，
    不能作为 release 行为的证据，所以这里固定使用 release 产物。

    脚本会在构建产物里生成 _viewport-390x844.html：它用一个固定 390x844 的 iframe 承载
    应用，因此不需要改变浏览器窗口大小就能复测手机视口的首帧与刷新。

.PARAMETER Port
    静态服务端口，默认 53005，避开 start-local.ps1 使用的 53001-53004。

.PARAMETER SkipBuild
    复用已有的 build\web 产物，不重新构建。
#>
param(
    [int]$Port = 53005,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$mobileRoot = Join-Path $projectRoot 'apps\mobile'
$webRoot = Join-Path $mobileRoot 'build\web'

if (-not $SkipBuild) {
    Push-Location $mobileRoot
    try {
        fvm flutter build web --release `
            --dart-define=API_BASE_URL=http://127.0.0.1:53001/v1 `
            --dart-define=WEB_BASE_URL=http://127.0.0.1:53003
        if ($LASTEXITCODE -ne 0) { throw 'Flutter Web release 构建失败' }
    } finally {
        Pop-Location
    }
}

if (-not (Test-Path -LiteralPath $webRoot)) {
    throw "找不到 $webRoot。请先不带 -SkipBuild 运行一次。"
}

$harness = @'
<!doctype html>
<meta charset="utf-8">
<title>390x844 viewport check</title>
<style>
  body { margin: 0; background: #222; display: flex; justify-content: center; }
  iframe { width: 390px; height: 844px; border: 0; background: #fff; }
</style>
<iframe id="app" src="/index.html"></iframe>
'@
Set-Content -LiteralPath (Join-Path $webRoot '_viewport-390x844.html') -Value $harness -Encoding utf8

Write-Host ''
Write-Host "Flutter Web release 预览：http://127.0.0.1:$Port"
Write-Host "390x844 视口检查：      http://127.0.0.1:$Port/_viewport-390x844.html"
Write-Host 'Ctrl+C 结束。'
Write-Host ''

Push-Location $webRoot
try {
    python -m http.server $Port --bind 127.0.0.1
} finally {
    Pop-Location
}

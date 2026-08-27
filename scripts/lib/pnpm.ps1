# 解析可用的 pnpm 调用方式。
#
# 仓库通过根 package.json 的 packageManager 字段锁定 pnpm 版本，因此本机既可以安装全局 pnpm，
# 也可以使用 Node 自带的 corepack。脚本不会自动放宽 corepack 的签名校验：如果本机 corepack 过旧、
# 无法验证当前 npm 签名密钥，则退回 npm 自带的 npx，按根 package.json 锁定的精确版本临时执行 pnpm。
# 这个回退不会安装全局包，也不会修改 PATH。

function Resolve-PnpmCommand {
    if (Get-Command pnpm -ErrorAction SilentlyContinue) { return 'pnpm' }

    if (Get-Command corepack -ErrorAction SilentlyContinue) {
        & corepack pnpm --version 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { return 'corepack pnpm' }
    }

    $projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $packageJsonPath = Join-Path $projectRoot 'package.json'
    $packageManager = (Get-Content -LiteralPath $packageJsonPath -Raw | ConvertFrom-Json).packageManager
    if ($packageManager -notmatch '^pnpm@(\d+\.\d+\.\d+)$') {
        throw '根 package.json 必须使用精确的 pnpm@x.y.z packageManager 版本。'
    }

    if (Get-Command npx -ErrorAction SilentlyContinue) {
        $pnpmVersion = $Matches[1]
        & npx --yes "pnpm@$pnpmVersion" --version 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { return "npx --yes pnpm@$pnpmVersion --" }
    }

    throw @'
找不到可运行的 pnpm。corepack 可能过旧且 npx 回退也失败。
请任选其一后重试：
  1. npm install -g corepack@latest   然后 corepack enable
  2. npm install -g pnpm@11.19.0
'@
}

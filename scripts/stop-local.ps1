$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$statePath = Join-Path $projectRoot '.local\run-state.json'

function Stop-ProcessTree {
    param([int]$ProcessId)
    $children = Get-CimInstance Win32_Process -Filter "ParentProcessId = $ProcessId"
    foreach ($child in $children) {
        Stop-ProcessTree -ProcessId $child.ProcessId
    }
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

if (Test-Path -LiteralPath $statePath) {
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ($state.projectRoot -ne $projectRoot) {
        throw '状态文件不属于当前项目，已拒绝停止进程。'
    }
    foreach ($entry in $state.processes) {
        $process = Get-Process -Id $entry.pid -ErrorAction SilentlyContinue
        if ($null -eq $process) { continue }
        $recordedStart = ([DateTime]$entry.startedAt).ToUniversalTime()
        $actualStart = $process.StartTime.ToUniversalTime()
        if ([Math]::Abs(($actualStart - $recordedStart).TotalSeconds) -le 2) {
            Stop-ProcessTree -ProcessId $entry.pid
        }
    }
    Remove-Item -LiteralPath $statePath -Force
}

Push-Location $projectRoot
try {
    docker compose -f infra\docker-compose.yml stop
} finally {
    Pop-Location
}

Write-Host '本地服务已停止；PostgreSQL 和 MinIO 数据卷仍保留。'

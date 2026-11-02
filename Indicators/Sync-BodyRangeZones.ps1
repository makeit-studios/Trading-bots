param(
    [switch]$Watch
)

$ErrorActionPreference = 'Stop'
$sourceDir = $PSScriptRoot
$targetDir = Join-Path $env:APPDATA 'MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Indicators'
$compiler = 'C:\Program Files\MetaTrader 5\MetaEditor64.exe'
$source = Join-Path $sourceDir 'BodyRangeZones.mq5'
$binary = Join-Path $sourceDir 'BodyRangeZones.ex5'
$compileLog = Join-Path $sourceDir 'BodyRangeZones.compile.log'
$syncLog = Join-Path $sourceDir 'BodyRangeZones.sync.log'

function Get-CurrentHash([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
}

function Write-SyncLog([string]$message) {
    Add-Content -LiteralPath $syncLog -Value ("$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $message")
}

function Sync-File([string]$name) {
    $from = Join-Path $sourceDir $name
    $to = Join-Path $targetDir $name
    if (-not (Test-Path -LiteralPath $from -PathType Leaf)) { return }
    if ((Get-CurrentHash $from) -eq (Get-CurrentHash $to)) { return }
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            Copy-Item -LiteralPath $from -Destination $to -Force
            if ((Get-CurrentHash $from) -ne (Get-CurrentHash $to)) {
                throw "Hash mismatch after copying $name"
            }
            Write-SyncLog "Copied $name into MT5 Indicators"
            return
        }
        catch {
            if ($attempt -eq 5) { throw }
            Start-Sleep -Milliseconds 400
        }
    }
}

function Compile-Indicator {
    if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
        Write-SyncLog 'MetaEditor compiler missing; source was copied but EX5 was not rebuilt'
        return
    }
    $arguments = '/compile:"' + $source + '" /log:"' + $compileLog + '"'
    $process = Start-Process -FilePath $compiler -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
    $result = Get-Content -LiteralPath $compileLog -ErrorAction SilentlyContinue | Select-String '^Result:' | Select-Object -Last 1
    if ($null -eq $result -or $result.Line -notmatch 'Result: 0 errors') {
        Write-SyncLog "Compilation failed after source edit; old EX5 retained. See $compileLog"
        return
    }
    Sync-File 'BodyRangeZones.ex5'
}

if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
    throw "MT5 Indicators directory missing: $targetDir"
}

Sync-File 'BodyRangeZones.mq5'
Sync-File 'BodyRangeZones.ex5'

if (-not $Watch) { return }

Write-SyncLog 'Watcher started'
$lastSourceHash = Get-CurrentHash $source
$lastBinaryHash = Get-CurrentHash $binary
while ($true) {
    Start-Sleep -Seconds 2
    try {
        $currentSourceHash = Get-CurrentHash $source
        if ($currentSourceHash -ne '' -and $currentSourceHash -ne $lastSourceHash) {
            $lastSourceHash = $currentSourceHash
            Sync-File 'BodyRangeZones.mq5'
            Compile-Indicator
            $lastBinaryHash = Get-CurrentHash $binary
            continue
        }
        $currentBinaryHash = Get-CurrentHash $binary
        if ($currentBinaryHash -ne '' -and $currentBinaryHash -ne $lastBinaryHash) {
            $lastBinaryHash = $currentBinaryHash
            Sync-File 'BodyRangeZones.ex5'
        }
    }
    catch {
        Write-SyncLog "Sync error: $($_.Exception.Message)"
    }
}

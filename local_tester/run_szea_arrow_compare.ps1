param([switch]$SmokeOnly)

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$data = 'C:\Users\Karikari\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075'
$terminal = 'C:\Program Files\MetaTrader 5\terminal64.exe'
$expertDir = Join-Path $data 'MQL5\Experts'
$setDir = Join-Path $data 'MQL5\Profiles\Tester'
$runId = Get-Date -Format 'yyyyMMdd_HHmmss'

if (Get-Process terminal64 -ErrorAction SilentlyContinue) {
    throw 'MT5 is already running. Close that session before this comparison.'
}
Copy-Item -LiteralPath (Join-Path $project 'Experts\StructureZoneEntryEA.mq5') -Destination (Join-Path $expertDir 'StructureZoneEntryEA.mq5') -Force
Copy-Item -LiteralPath (Join-Path $project 'Experts\StructureZoneEntryEA.ex5') -Destination (Join-Path $expertDir 'StructureZoneEntryEA.ex5') -Force
foreach ($name in @('SZEA_arrow_smoke', 'SZEA_arrow_only', 'SZEA_arrow_aligned')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "$name.set") -Destination (Join-Path $setDir "$name.set") -Force
}

$runs = @(@{ Tag = 'smoke'; Set = 'SZEA_arrow_smoke'; From = '2026.10.18'; To = '2026.10.20' })
if (-not $SmokeOnly) {
    foreach ($window in @(@{ Tag = 'development'; From = '2026.05.01'; To = '2026.07.31' }, @{ Tag = 'holdout'; From = '2026.08.01'; To = '2026.10.20' })) {
        foreach ($variant in @('arrow_only', 'arrow_aligned')) {
            $runs += @{ Tag = "$($window.Tag)_$variant"; Set = "SZEA_$variant"; From = $window.From; To = $window.To }
        }
    }
}

$archive = Join-Path $PSScriptRoot "reports\arrow_compare_$runId"
New-Item -ItemType Directory -Path $archive -Force | Out-Null
foreach ($run in $runs) {
    if (Get-Process terminal64 -ErrorAction SilentlyContinue) {
        throw "MT5 became occupied before $($run.Tag)."
    }
    $name = "SZEA_$($run.Tag)_$runId"
    $ini = Join-Path $PSScriptRoot "$name.ini"
    @(
        '[Tester]',
        'Expert=StructureZoneEntryEA.ex5',
        "ExpertParameters=$($run.Set).set",
        'Symbol=XAUUSDm',
        'Period=M15',
        'Model=0',
        "FromDate=$($run.From)",
        "ToDate=$($run.To)",
        'Deposit=10000',
        'Currency=USD',
        'Leverage=1:2000',
        'Visual=0',
        'ShutdownTerminal=1',
        'ReplaceReport=1',
        'Optimization=0',
        "Report=$name"
    ) | Set-Content -LiteralPath $ini -Encoding ascii
    $started = Get-Date
    Write-Output "Starting $($run.Tag): $($run.From) through $($run.To)"
    $process = Start-Process -FilePath $terminal -ArgumentList ('/config:"' + $ini + '"') -WindowStyle Hidden -PassThru -Wait
    $report = Join-Path $data "$name.htm"
    if (-not (Test-Path -LiteralPath $report) -or (Get-Item -LiteralPath $report).LastWriteTime -lt $started) {
        throw "No fresh report for $($run.Tag); terminal exit $($process.ExitCode)."
    }
    Copy-Item -LiteralPath $report -Destination (Join-Path $archive "$name.htm") -Force
    Write-Output "Completed $($run.Tag): $report"
}
Write-Output "Reports: $archive"

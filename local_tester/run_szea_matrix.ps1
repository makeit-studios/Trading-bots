param([switch]$SmokeOnly)

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$data = 'C:\Users\Karikari\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075'
$terminal = 'C:\Program Files\MetaTrader 5\terminal64.exe'
$expertDir = Join-Path $data 'MQL5\Experts'
$setDir = Join-Path $data 'MQL5\Profiles\Tester'
$runId = Get-Date -Format 'yyyyMMdd_HHmmss'

if (Get-Process terminal64 -ErrorAction SilentlyContinue) {
    throw 'The shared MT5 terminal is running. Leave the other test alone and rerun after it exits.'
}
Copy-Item -LiteralPath (Join-Path $project 'Experts\StructureZoneEntryEA.mq5') -Destination (Join-Path $expertDir 'StructureZoneEntryEA.mq5') -Force
Copy-Item -LiteralPath (Join-Path $project 'Experts\StructureZoneEntryEA.ex5') -Destination (Join-Path $expertDir 'StructureZoneEntryEA.ex5') -Force
foreach ($name in @('SZEA_smoke', 'SZEA_baseline', 'SZEA_any_two', 'SZEA_imbalance_only')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "$name.set") -Destination (Join-Path $setDir "$name.set") -Force
}

$runs = @(@{ Tag = 'smoke'; Set = 'SZEA_smoke'; From = '2026.10.18'; To = '2026.10.20' })
if (-not $SmokeOnly) {
    foreach ($window in @(@{ Tag = 'development'; From = '2026.05.01'; To = '2026.07.31' }, @{ Tag = 'holdout'; From = '2026.08.01'; To = '2026.10.20' })) {
        foreach ($variant in @('baseline', 'any_two', 'imbalance_only')) {
            $runs += @{ Tag = "$($window.Tag)_$variant"; Set = "SZEA_$variant"; From = $window.From; To = $window.To }
        }
    }
}

foreach ($run in $runs) {
    if (Get-Process terminal64 -ErrorAction SilentlyContinue) {
        throw "MT5 became occupied before $($run.Tag); stopping this matrix."
    }
    $reportName = "SZEA_$($run.Tag)_$runId"
    $ini = Join-Path $PSScriptRoot "$reportName.ini"
    @(
        '[Tester]',
        'Expert=StructureZoneEntryEA.ex5',
        "ExpertParameters=$($run.Set).set",
        'Symbol=XAUUSDm',
        'Period=M5',
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
        "Report=$reportName"
    ) | Set-Content -LiteralPath $ini -Encoding ascii
    $start = Get-Date
    Write-Output "Starting $($run.Tag) at $start"
    $process = Start-Process -FilePath $terminal -ArgumentList ('/config:"' + $ini + '"') -WindowStyle Hidden -PassThru -Wait
    $report = Join-Path $data "$reportName.htm"
    if (-not (Test-Path -LiteralPath $report)) {
        throw "No report for $($run.Tag) (terminal exit $($process.ExitCode))."
    }
    $item = Get-Item -LiteralPath $report
    if ($item.LastWriteTime -lt $start) { throw "Stale report for $($run.Tag)." }
    Write-Output "Completed $($run.Tag): $report ($($item.Length) bytes)"
}

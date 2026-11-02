$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$data = 'C:\Users\Karikari\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075'
$terminal = 'C:\Program Files\MetaTrader 5\terminal64.exe'
$expertDir = Join-Path $data 'MQL5\Experts'
$setDir = Join-Path $data 'MQL5\Profiles\Tester'
$runId = Get-Date -Format 'yyyyMMdd_HHmmss'

if (Get-Process terminal64 -ErrorAction SilentlyContinue) {
    throw 'MT5 is already running. Leave that session alone and run this after it closes.'
}
Copy-Item -LiteralPath (Join-Path $project 'Experts\StructureZoneEntryEA.mq5') -Destination (Join-Path $expertDir 'StructureZoneEntryEA.mq5') -Force
Copy-Item -LiteralPath (Join-Path $project 'Experts\StructureZoneEntryEA.ex5') -Destination (Join-Path $expertDir 'StructureZoneEntryEA.ex5') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'SZEA_visual.set') -Destination (Join-Path $setDir 'SZEA_visual.set') -Force

$name = "SZEA_visual_$runId"
$ini = Join-Path $PSScriptRoot "$name.ini"
@(
    '[Tester]',
    'Expert=StructureZoneEntryEA.ex5',
    'ExpertParameters=SZEA_visual.set',
    'Symbol=XAUUSDm',
    'Period=M5',
    'Model=0',
    'FromDate=2026.08.17',
    'ToDate=2026.08.18',
    'Deposit=10000',
    'Currency=USD',
    'Leverage=1:2000',
    'Visual=1',
    'ShutdownTerminal=1',
    'ReplaceReport=1',
    'Optimization=0',
    "Report=$name"
) | Set-Content -LiteralPath $ini -Encoding ascii

$started = Get-Date
Write-Output "Starting visual replay: $name"
$process = Start-Process -FilePath $terminal -ArgumentList ('/config:"' + $ini + '"') -WindowStyle Hidden -PassThru -Wait
$report = Join-Path $data "$name.htm"
if (-not (Test-Path -LiteralPath $report)) {
    throw "No fresh MT5 report; terminal exit $($process.ExitCode)."
}
if ((Get-Item -LiteralPath $report).LastWriteTime -lt $started) {
    throw 'The MT5 report is stale.'
}
Write-Output "Report: $report"
$archive = Join-Path $PSScriptRoot "reports\$name"
New-Item -ItemType Directory -Path $archive -Force | Out-Null
Copy-Item -LiteralPath $report -Destination (Join-Path $archive "$name.htm") -Force
$screenshots = @(
    (Join-Path -Path $data -ChildPath 'MQL5\Files')
    (Join-Path -Path (Split-Path -Parent (Split-Path -Parent $data)) -ChildPath 'Tester\D0E8209F77C8CF37AD8BF550E51FF075\Agent-127.0.0.1-3000\MQL5\Files')
)
foreach ($folder in $screenshots) {
    if (Test-Path -LiteralPath $folder) {
        Get-ChildItem -LiteralPath $folder -Filter 'SZEA_visual_20260817*.png' -File |
            Where-Object { $_.LastWriteTime -ge $started } |
            ForEach-Object {
                $copy = Join-Path $archive $_.Name
                Copy-Item -LiteralPath $_.FullName -Destination $copy -Force
                Get-Item -LiteralPath $copy | Select-Object FullName, Length, LastWriteTime
            }
    }
}

param(
    [string]$From = '2026.10.19',
    [string]$To = '2026.10.23',
    [string]$RunId = (Get-Date -Format 'yyyyMMdd_HHmmss')
)

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$data = 'C:\Users\Karikari\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075'
$terminal = 'C:\Program Files\MetaTrader 5\terminal64.exe'
$expertDir = Join-Path $data 'MQL5\Experts'
$archive = Join-Path $PSScriptRoot "reports\arrow_lead_$RunId"
New-Item -ItemType Directory -Path $archive -Force | Out-Null

if (Get-Process terminal64 -ErrorAction SilentlyContinue) {
    throw 'MT5 is already running. Close the existing session before starting this probe.'
}
Copy-Item -LiteralPath (Join-Path $project 'Experts\ArrowLeadProbe.mq5') -Destination (Join-Path $expertDir 'ArrowLeadProbe.mq5') -Force
Copy-Item -LiteralPath (Join-Path $project 'Experts\ArrowLeadProbe.ex5') -Destination (Join-Path $expertDir 'ArrowLeadProbe.ex5') -Force

$name = "ALP_$RunId"
$ini = Join-Path $archive "$name.ini"
@(
    '[Tester]',
    'Expert=ArrowLeadProbe.ex5',
    'Symbol=XAUUSDm',
    'Period=M5',
    'Model=4',
    "FromDate=$From",
    "ToDate=$To",
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
Write-Output "Starting ${name}: $From through $To on real ticks"
$process = Start-Process -FilePath $terminal -ArgumentList ('/config:"' + $ini + '"') -WindowStyle Hidden -PassThru -Wait
$report = Join-Path $data "$name.htm"
if (-not (Test-Path -LiteralPath $report) -or (Get-Item -LiteralPath $report).LastWriteTime -lt $started) {
    throw "No fresh report; terminal exit $($process.ExitCode)."
}
Copy-Item -LiteralPath $report -Destination (Join-Path $archive "$name.htm") -Force
Write-Output "Report: $archive\$name.htm"
Write-Output "Journal: $(Join-Path $data ('Tester\logs\' + (Get-Date -Format 'yyyyMMdd') + '.log'))"

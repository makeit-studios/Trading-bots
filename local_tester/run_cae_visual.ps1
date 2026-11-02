param(
    [ValidateSet('ArrowOnly', 'Aligned')]
    [string]$Filter = 'ArrowOnly',
    [string]$FromDate = '2026.10.18',
    [string]$ToDate = '2026.10.20'
)

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$data = 'C:\Users\Karikari\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075'
$terminal = 'C:\Program Files\MetaTrader 5\terminal64.exe'
$expertDir = Join-Path $data 'MQL5\Experts'
$setDir = Join-Path $data 'MQL5\Profiles\Tester'

if (Get-Process terminal64 -ErrorAction SilentlyContinue) {
    throw 'MT5 is already running. Leave that session alone or close it before starting a new visual replay.'
}
$setName = if ($Filter -eq 'Aligned') { 'CAE_aligned.set' } else { 'CAE_arrow_only.set' }
Copy-Item -LiteralPath (Join-Path $project 'Experts\ConfirmedArrowEA.mq5') -Destination (Join-Path $expertDir 'ConfirmedArrowEA.mq5') -Force
Copy-Item -LiteralPath (Join-Path $project 'Experts\ConfirmedArrowEA.ex5') -Destination (Join-Path $expertDir 'ConfirmedArrowEA.ex5') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot $setName) -Destination (Join-Path $setDir $setName) -Force

$name = 'CAE_visual_' + $Filter + '_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
$ini = Join-Path $PSScriptRoot "$name.ini"
@(
    '[Tester]',
    'Expert=ConfirmedArrowEA.ex5',
    "ExpertParameters=$setName",
    'Symbol=XAUUSDm',
    'Period=M15',
    'Model=0',
    "FromDate=$FromDate",
    "ToDate=$ToDate",
    'Deposit=10000',
    'Currency=USD',
    'Leverage=1:2000',
    'Visual=1',
    'ShutdownTerminal=0',
    'ReplaceReport=1',
    'Optimization=0',
    "Report=$name"
) | Set-Content -LiteralPath $ini -Encoding ascii

# A visible interactive terminal is intentional: the user requested to watch the replay.
$process = Start-Process -FilePath $terminal -ArgumentList ('/config:"' + $ini + '"') -PassThru
Write-Output "Started visible $Filter replay in MT5 (PID $($process.Id))."
Write-Output "Dates: $FromDate through $ToDate"
Write-Output "Config: $ini"
Write-Output 'The chart panel explains each entry, exit, reversal, and skipped order.'

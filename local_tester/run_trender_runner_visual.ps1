param(
    [ValidateSet('XAUUSDm','BTCUSDm','EURUSDm','USTECm')]
    [string]$Symbol = 'USTECm',
    [ValidateSet(0,1,2,3)]
    [int]$Entry = 3,
    [ValidateSet(0,3,5)]
    [int]$StopBand = 3,
    [ValidateSet(1,4)]
    [int]$Trend = 1,
    [ValidateSet(0,1,2)]
    [int]$Exit = 2,
    [string]$FromDate = '2026.10.21',
    [string]$ToDate = '2026.10.25'
)

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$data = 'C:\Users\Karikari\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075'
$terminal = 'C:\Program Files\MetaTrader 5\terminal64.exe'
$expertDir = Join-Path $data 'MQL5\Experts'
$setDir = Join-Path $data 'MQL5\Profiles\Tester'
if (Get-Process terminal64 -ErrorAction SilentlyContinue) {
    throw 'MT5 is already running; close that session before starting the visual test.'
}
foreach ($extension in @('mq5','ex5')) {
    $name = "TrenderRunnerResearchEA.$extension"
    Copy-Item -LiteralPath (Join-Path $project "Experts\$name") -Destination (Join-Path $expertDir $name) -Force
}
$tag = 'TRR_visual_' + $Symbol + '_n' + $Entry + '_s' + $StopBand + '_h' + $Trend + '_e' + $Exit + '_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
$period = if ($Entry -ge 2) { 'M1' } else { 'M5' }
$setName = "$tag.set"
$setFile = Join-Path $PSScriptRoot $setName
@(
    "InpEntry=$Entry||$Entry||1||$Entry||N",
    "InpStopBand=$StopBand||$StopBand||1||$StopBand||N",
    "InpTrend=$Trend||$Trend||1||$Trend||N",
    "InpExit=$Exit||$Exit||1||$Exit||N",
    "InpRunId=$tag",
    'InpMagic=26102800||26102800||1||26102800||N',
    'InpSymbolRiskPct=0.5||0.5||0.1||0.5||N'
) | Set-Content -LiteralPath $setFile -Encoding ascii
Copy-Item -LiteralPath $setFile -Destination (Join-Path $setDir $setName) -Force
$ini = Join-Path $PSScriptRoot "$tag.ini"
@(
    '[Tester]',
    'Expert=TrenderRunnerResearchEA.ex5',
    "ExpertParameters=$setName",
    "Symbol=$Symbol",
    "Period=$period",
    'Model=4',
    "FromDate=$FromDate",
    "ToDate=$ToDate",
    'Deposit=10000',
    'Currency=USD',
    'Leverage=1:2000',
    'Visual=1',
    'ShutdownTerminal=0',
    'ReplaceReport=1',
    'Optimization=0',
    "Report=$tag"
) | Set-Content -LiteralPath $ini -Encoding ascii
# The user asked to see the actual EA run interactively in MT5 Visual Tester.
$process = Start-Process -FilePath $terminal -ArgumentList ('/config:"' + $ini + '"') -PassThru
Write-Output "Started visible MT5 Strategy Tester for $Symbol, entry $Entry, stop band $StopBand, H$Trend info, exit mode $Exit (PID $($process.Id))."
Write-Output "Dates: $FromDate through $ToDate; config: $ini"
Write-Output 'Keeping this launcher attached while MT5 remains open.'
Wait-Process -Id $process.Id

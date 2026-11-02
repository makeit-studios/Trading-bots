param(
    [ValidateSet('ArrowOnly', 'Aligned', 'M15', 'M15H1', 'M15H2', 'M15H4', 'M15All')]
    [string]$Filter = 'ArrowOnly',
    [ValidateSet(1, 2)]
    [int]$TargetR = 1,
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
    throw 'MT5 is already running. Close that session before starting a new visual replay.'
}
$filterValues = @{ ArrowOnly = 0; Aligned = 1; M15 = 2; M15H1 = 3; M15H2 = 4; M15H4 = 5; M15All = 6 }
$setName = "LA5_visual_$($Filter)_r$TargetR.set"
$setFile = Join-Path $PSScriptRoot $setName
@(
    "InpFilter=$($filterValues[$Filter])||$($filterValues[$Filter])||0||6||N",
    'InpTradingEnabled=true||false||0||true||N',
    'InpRiskPct=1.0||1.0||0.1||4.0||N',
    'InpMaxCombinedRiskPct=4.0||4.0||0.1||10.0||N',
    "InpTargetR=$($TargetR).0||$($TargetR).0||0.1||2.0||N",
    'InpMagic=26102305||26102305||1||26102305||N',
    'InpMaxDeviationPoints=20||20||1||100||N'
) | Set-Content -LiteralPath $setFile -Encoding ascii
Copy-Item -LiteralPath (Join-Path $project 'Experts\LiveArrowM5EA.mq5') -Destination (Join-Path $expertDir 'LiveArrowM5EA.mq5') -Force
Copy-Item -LiteralPath (Join-Path $project 'Experts\LiveArrowM5EA.ex5') -Destination (Join-Path $expertDir 'LiveArrowM5EA.ex5') -Force
Copy-Item -LiteralPath $setFile -Destination (Join-Path $setDir $setName) -Force

$name = 'LA5_visual_' + $Filter + '_R' + $TargetR + '_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
$ini = Join-Path $PSScriptRoot "$name.ini"
@(
    '[Tester]',
    'Expert=LiveArrowM5EA.ex5',
    "ExpertParameters=$setName",
    'Symbol=XAUUSDm',
    'Period=M5',
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
    "Report=$name"
) | Set-Content -LiteralPath $ini -Encoding ascii

# The user requested a visible interactive replay.
$process = Start-Process -FilePath $terminal -ArgumentList ('/config:"' + $ini + '"') -PassThru
Write-Output "Started visible $Filter 1:$TargetR target replay in MT5 (PID $($process.Id))."
Write-Output "Config: $ini"

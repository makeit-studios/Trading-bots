param(
    [switch]$SmokeOnly,
    [string]$RunId = (Get-Date -Format 'yyyyMMdd_HHmmss'),
    [string]$OnlyTag
)

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$data = 'C:\Users\Karikari\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075'
$terminal = 'C:\Program Files\MetaTrader 5\terminal64.exe'
$expertDir = Join-Path $data 'MQL5\Experts'
$setDir = Join-Path $data 'MQL5\Profiles\Tester'
$archive = Join-Path $PSScriptRoot "reports\la5_bands_$RunId"
New-Item -ItemType Directory -Path $archive -Force | Out-Null

if (Get-Process terminal64 -ErrorAction SilentlyContinue) {
    throw 'MT5 is already running. Close the existing session before starting the matrix.'
}
Copy-Item -LiteralPath (Join-Path $project 'Experts\LiveArrowM5EA.mq5') -Destination (Join-Path $expertDir 'LiveArrowM5EA.mq5') -Force
Copy-Item -LiteralPath (Join-Path $project 'Experts\LiveArrowM5EA.ex5') -Destination (Join-Path $expertDir 'LiveArrowM5EA.ex5') -Force

$filters = @(
    @{ Name = 'arrow'; Value = 0 },
    @{ Name = 'm15'; Value = 2 },
    @{ Name = 'm15_h1'; Value = 3 },
    @{ Name = 'm15_h2'; Value = 4 },
    @{ Name = 'm15_h4'; Value = 5 },
    @{ Name = 'm15_all'; Value = 6 }
)
$windows = if ($SmokeOnly) {
    @(@{ Name = 'smoke'; From = '2026.10.19'; To = '2026.10.23' })
} else {
    @(
        @{ Name = 'development'; From = '2026.07.01'; To = '2026.07.31' },
        @{ Name = 'holdout'; From = '2026.10.01'; To = '2026.10.23' }
    )
}
$runs = foreach ($window in $windows) {
    foreach ($filter in $filters) {
        foreach ($target in @(1, 2)) {
            [pscustomobject]@{
                Tag = "$($window.Name)_$($filter.Name)_r$target"
                Filter = $filter.Value; Target = $target
                From = $window.From; To = $window.To
            }
        }
    }
}
if ($SmokeOnly -and -not $OnlyTag) {
    $runs = @($runs | Where-Object { $_.Tag -eq 'smoke_m15_h1_r1' })
}
if ($OnlyTag) {
    $runs = @($runs | Where-Object Tag -eq $OnlyTag)
    if ($runs.Count -ne 1) { throw "Unknown run tag: $OnlyTag" }
}

foreach ($run in $runs) {
    if (Get-Process terminal64 -ErrorAction SilentlyContinue) {
        throw "MT5 became occupied before $($run.Tag)."
    }
    $name = "LA5B_$($run.Tag)_$RunId"
    $setName = "$name.set"
    $setFile = Join-Path $archive $setName
    @(
        "InpFilter=$($run.Filter)||$($run.Filter)||0||6||N",
        'InpTradingEnabled=true||false||0||true||N',
        'InpRiskPct=1.0||1.0||0.1||4.0||N',
        'InpMaxCombinedRiskPct=4.0||4.0||0.1||10.0||N',
        "InpTargetR=$($run.Target).0||$($run.Target).0||0.1||2.0||N",
        'InpMagic=26102305||26102305||1||26102305||N',
        'InpMaxDeviationPoints=20||20||1||100||N'
    ) | Set-Content -LiteralPath $setFile -Encoding ascii
    Copy-Item -LiteralPath $setFile -Destination (Join-Path $setDir $setName) -Force
    $ini = Join-Path $archive "$name.ini"
    @(
        '[Tester]',
        'Expert=LiveArrowM5EA.ex5',
        "ExpertParameters=$setName",
        'Symbol=XAUUSDm',
        'Period=M5',
        'Model=4',
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
    $html = Get-Content -LiteralPath $report -Raw
    if ($html -notmatch '<b>LiveArrowM5EA</b>' -or
        $html -notmatch '<b>XAUUSDm</b>' -or
        $html -notmatch '<b>M5 \(2026\.' -or
        $html -match '<b>M0 \(1970\.') {
        throw "Invalid tester report for $($run.Tag); stopping the matrix."
    }
    Copy-Item -LiteralPath $report -Destination (Join-Path $archive "$name.htm") -Force
    Write-Output "Completed $($run.Tag)"
}
Write-Output "Reports: $archive"

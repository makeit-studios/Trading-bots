param(
    [string[]]$Symbols = @('XAUUSDm','BTCUSDm','EURUSDm','USTECm'),
    [ValidateSet('control_fixed','m15_fixed','m15_runner','m1_fixed','m1_runner',
                 'm1m5_m3_fixed','m1m5_m3_runner','m1m5_m5_fixed','m1m5_m5_runner')]
    [string[]]$Configurations = @('m1m5_m3_fixed','m1m5_m3_runner',
                                  'm1m5_m5_fixed','m1m5_m5_runner'),
    [string[]]$Windows = @('jul26','oct26'),
    [string]$RunId = (Get-Date -Format 'yyyyMMdd_HHmmss')
)

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$terminalData = 'C:\Users\Karikari\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075'
$terminal = 'C:\Program Files\MetaTrader 5\terminal64.exe'
$commonFiles = 'C:\Users\Karikari\AppData\Roaming\MetaQuotes\Terminal\Common\Files'
$archive = Join-Path $PSScriptRoot "reports\trender_runner_$RunId"
$expertDir = Join-Path $terminalData 'MQL5\Experts'
$setDir = Join-Path $terminalData 'MQL5\Profiles\Tester'
$windowMap = @{
    jul26 = @{ From='2026.07.01'; To='2026.08.01' }
    oct26 = @{ From='2026.10.01'; To='2026.10.26' }
    smoke = @{ From='2026.10.01'; To='2026.10.06' }
}
$configurationMap = @{
    control_fixed   = @{ Entry=0; Trend=1; Exit=0; Stop=0 }
    m15_fixed       = @{ Entry=1; Trend=1; Exit=0; Stop=0 }
    m15_runner      = @{ Entry=1; Trend=1; Exit=2; Stop=0 }
    m1_fixed        = @{ Entry=2; Trend=1; Exit=0; Stop=0 }
    m1_runner       = @{ Entry=2; Trend=1; Exit=2; Stop=0 }
    m1m5_m3_fixed   = @{ Entry=3; Trend=1; Exit=0; Stop=3 }
    m1m5_m3_runner  = @{ Entry=3; Trend=1; Exit=2; Stop=3 }
    m1m5_m5_fixed   = @{ Entry=3; Trend=1; Exit=0; Stop=5 }
    m1m5_m5_runner  = @{ Entry=3; Trend=1; Exit=2; Stop=5 }
}

if (Get-Process terminal64 -ErrorAction SilentlyContinue) {
    throw 'MT5 is already running; close it before this headless test.'
}
foreach ($window in $Windows) {
    if (-not $windowMap.ContainsKey($window)) { throw "Unsupported window $window" }
}
New-Item -ItemType Directory -Path $archive -Force | Out-Null
foreach ($extension in @('mq5','ex5')) {
    $name = "TrenderRunnerResearchEA.$extension"
    $source = Join-Path $project "Experts\$name"
    Copy-Item -LiteralPath $source -Destination (Join-Path $expertDir $name) -Force
    Copy-Item -LiteralPath $source -Destination (Join-Path $archive $name) -Force
}
@(
    "source_sha256=$((Get-FileHash -LiteralPath (Join-Path $archive 'TrenderRunnerResearchEA.mq5') -Algorithm SHA256).Hash)",
    "binary_sha256=$((Get-FileHash -LiteralPath (Join-Path $archive 'TrenderRunnerResearchEA.ex5') -Algorithm SHA256).Hash)",
    'model_requested=4 (real ticks)',
    'deposit=10000 USD',
    'leverage=1:2000',
    "windows=$($Windows -join ',')",
    "symbols=$($Symbols -join ',')"
    "configurations=$($Configurations -join ',')"
) | Set-Content -LiteralPath (Join-Path $archive 'manifest.txt') -Encoding ascii

$rows = @()
foreach ($window in $Windows) {
    $from = $windowMap[$window].From
    $to = $windowMap[$window].To
    foreach ($symbol in $Symbols) {
        foreach ($configuration in $Configurations) {
                $entry = $configurationMap[$configuration].Entry
                $trend = $configurationMap[$configuration].Trend
                $exit = $configurationMap[$configuration].Exit
                $stopBand = $configurationMap[$configuration].Stop
                $period = if ($entry -ge 2) { 'M1' } else { 'M5' }
                if (Get-Process terminal64 -ErrorAction SilentlyContinue) {
                    throw "MT5 became occupied before $symbol $configuration."
                }
                $tag = "TRR_${symbol}_${configuration}_${window}_$RunId"
                $setName = "$tag.set"
                $setFile = Join-Path $archive $setName
                @(
                    "InpEntry=$entry||$entry||1||$entry||N",
                    "InpStopBand=$stopBand||$stopBand||1||$stopBand||N",
                    "InpTrend=$trend||$trend||1||$trend||N",
                    "InpExit=$exit||$exit||1||$exit||N",
                    "InpRunId=$tag",
                    'InpMagic=26102800||26102800||1||26102800||N',
                    'InpSymbolRiskPct=0.5||0.5||0.1||0.5||N'
                ) | Set-Content -LiteralPath $setFile -Encoding ascii
                Copy-Item -LiteralPath $setFile -Destination (Join-Path $setDir $setName) -Force
                $ini = Join-Path $archive "$tag.ini"
                @(
                    '[Tester]',
                    'Expert=TrenderRunnerResearchEA.ex5',
                    "ExpertParameters=$setName",
                    "Symbol=$symbol",
                    "Period=$period",
                    'Model=4',
                    "FromDate=$from",
                    "ToDate=$to",
                    'Deposit=10000',
                    'Currency=USD',
                    'Leverage=1:2000',
                    'Visual=0',
                    'ShutdownTerminal=1',
                    'ReplaceReport=1',
                    'Optimization=0',
                    "Report=$tag"
                ) | Set-Content -LiteralPath $ini -Encoding ascii
                $events = Join-Path $commonFiles "TrenderRunner_$tag.csv"
                if (Test-Path -LiteralPath $events) { throw "Stale event file $events" }
                $started = Get-Date
                Write-Output "Starting $symbol $configuration (entry $entry, stop $stopBand, exit $exit) $window"
                $process = Start-Process -FilePath $terminal -ArgumentList ('/config:"' + $ini + '"') -WindowStyle Hidden -PassThru -Wait
                $report = Join-Path $terminalData "$tag.htm"
                if (-not (Test-Path -LiteralPath $report) -or (Get-Item $report).LastWriteTime -lt $started) {
                    throw "No fresh report for $tag; terminal exit $($process.ExitCode)."
                }
                if (-not (Test-Path -LiteralPath $events)) { throw "No events file for $tag" }
                $html = Get-Content -LiteralPath $report -Raw
                if ($html -notmatch '<b>TrenderRunnerResearchEA</b>' -or
                    $html -notmatch [regex]::Escape("<b>$symbol</b>")) {
                    throw "Wrong tester report for $tag"
                }
                Copy-Item -LiteralPath $report -Destination (Join-Path $archive "$tag.htm") -Force
                Copy-Item -LiteralPath $events -Destination (Join-Path $archive "$tag.events.csv") -Force
                foreach ($suffix in @('', '-hst', '-mfemae', '-holding')) {
                    $graph = Join-Path $terminalData "$tag$suffix.png"
                    if (Test-Path -LiteralPath $graph) {
                        Copy-Item -LiteralPath $graph -Destination (Join-Path $archive "$tag$suffix.png") -Force
                    }
                }
                $metrics = [ordered]@{ Symbol=$symbol; Configuration=$configuration; Entry=$entry; SignalTimeframe=$period; StopBand=$stopBand; Trend=$trend; Exit=$exit; Window=$window; From=$from; To=$to; Report=$tag }
                foreach ($key in @('History Quality','Total Net Profit','Profit Factor','Total Trades','Expected Payoff','Equity Drawdown Relative','Long Trades (won %)','Short Trades (won %)')) {
                    $pattern = '<td[^>]*>\s*' + [regex]::Escape($key) + ':\s*</td>\s*<td[^>]*>\s*<b>([^<]*)</b>'
                    $match = [regex]::Match($html,$pattern)
                    $metrics[$key] = if ($match.Success) { [System.Net.WebUtility]::HtmlDecode($match.Groups[1].Value.Trim()) } else { '' }
                }
                if (-not $metrics['History Quality'] -or -not $metrics['Total Trades']) { throw "Could not parse $tag" }
                $rows += [pscustomobject]$metrics
                $rows | Export-Csv -LiteralPath (Join-Path $archive 'summary.csv') -NoTypeInformation
                Write-Output "Completed ${tag}: $($metrics['History Quality']), $($metrics['Total Trades']) trades, net $($metrics['Total Net Profit'])"
        }
    }
}
Write-Output "Reports: $archive"

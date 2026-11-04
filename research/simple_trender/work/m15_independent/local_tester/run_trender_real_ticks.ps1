param(
    [string[]]$Symbols = @('XAUUSDm','BTCUSDm','EURUSDm','USTECm'),
    [string[]]$SignalTimeframes = @('M1','M3','M5'),
    [string[]]$Profiles = @('base','fast','smooth'),
    [ValidateSet(0,2)][int]$ExitMode = 0,
    [ValidateRange(50,500)][int]$MajorEma = 200,
    [int]$BandEmaOverride = 0,
    [int]$VwapSmoothOverride = 0,
    [int]$SlopeBarsOverride = 0,
    [ValidateRange(1,10000000)][double]$Deposit = 1000,
    [ValidateRange(0.01,3)][double]$RiskPct = 2,
    [ValidateRange(0.5,3)][double]$FixedTargetR = 1.5,
    [ValidateSet('cross','ema_reclaim')][string]$SignalTrigger = 'cross',
    [switch]$StageEnabled,
    [string]$FromDate = '2026.10.12',
    [string]$ToDate = '2026.10.26',
    [string]$RunId = (Get-Date -Format 'yyyyMMdd_HHmmss')
)

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$terminalData = 'C:\Users\Karikari\AppData\Roaming\MetaQuotes\Terminal\3799BB92AB7FD40329FDE24ED7BF8C70'
$terminal = 'C:\MT5\Slave1\terminal64.exe'
$commonFiles = 'C:\Users\Karikari\AppData\Roaming\MetaQuotes\Terminal\Common\Files'
$terminalCommon = Join-Path $terminalData 'config\common.ini'
$activeLogin = ([regex]::Match((Get-Content -LiteralPath $terminalCommon -Raw), '(?m)^Login=(\d+)\s*$')).Groups[1].Value
$activeServer = ([regex]::Match((Get-Content -LiteralPath $terminalCommon -Raw), '(?m)^Server=(.+?)\s*$')).Groups[1].Value
if (-not $activeLogin -or -not $activeServer) { throw 'No saved MT5 login/server in terminal common.ini.' }
$archive = Join-Path $PSScriptRoot "reports\trender_quick_$RunId"
$expertDir = Join-Path $terminalData 'MQL5\Experts'
$setDir = Join-Path $terminalData 'MQL5\Profiles\Tester'
New-Item -ItemType Directory -Path $setDir -Force | Out-Null
$profileMap = @{
    base   = @{ Band=26; Vwap=13; Slope=3 }
    fast   = @{ Band=23; Vwap=11; Slope=2 }
    smooth = @{ Band=30; Vwap=15; Slope=4 }
    ema23  = @{ Band=23; Vwap=13; Slope=3 }
    ema30  = @{ Band=30; Vwap=13; Slope=3 }
    vwap11 = @{ Band=26; Vwap=11; Slope=3 }
    vwap15 = @{ Band=26; Vwap=15; Slope=3 }
    slope2 = @{ Band=26; Vwap=13; Slope=2 }
    slope4 = @{ Band=26; Vwap=13; Slope=4 }
}
$timeframeMap = @{ M1=1; M3=3; M5=5; M15=15 }
if (Get-Process terminal64 -ErrorAction SilentlyContinue | Where-Object Path -eq $terminal) {
    throw 'The dedicated MT5 test terminal is already running.'
}
foreach ($name in $Profiles) {
    if (-not $profileMap.ContainsKey($name)) { throw "Unknown profile $name" }
}
foreach ($name in $SignalTimeframes) {
    if (-not $timeframeMap.ContainsKey($name)) { throw "Unknown timeframe $name" }
}
if ($StageEnabled -and ($ExitMode -ne 2 -or $SignalTimeframes.Count -ne 1 -or $SignalTimeframes[0] -ne 'M1')) {
    throw 'Staged entry requires ExitMode 2 and M1 signal timeframe.'
}
$fixedTargetText = $FixedTargetR.ToString('0.###',[System.Globalization.CultureInfo]::InvariantCulture)
$fixedTargetTag = $fixedTargetText.Replace('.','p')
$stageTag = [int][bool]$StageEnabled
$signalTriggerCode = if ($SignalTrigger -eq 'ema_reclaim') { 1 } else { 0 }
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
    'model_requested=4 (every tick based on real ticks)',
    'entry=closed signal-timeframe arrow; direction=closed M5 band only',
    "stop=latest completed M5 band; exit=$ExitMode",
    "major_ema=$MajorEma",
    'history_bars=1800 (screen-only cap; full tests use default)',
    "deposit=$Deposit USD",
    "nominal_symbol_risk_pct=$RiskPct (EA applies its existing 90% sizing buffer)",
    "fixed_target_r=$fixedTargetText",
    'independent_fixed=true (M15 exits affect runner only)',
    "signal_trigger=$SignalTrigger",
    "staged_entry=$stageTag (25% probe; M1 close >= +0.5R within 10 minutes; add uses remaining stop-risk budget)",
    'leverage=1:2000',
    "period=$FromDate to $ToDate",
    "symbols=$($Symbols -join ',')",
    "signal_timeframes=$($SignalTimeframes -join ',')",
    "profiles=$($Profiles -join ',')"
) | Set-Content -LiteralPath (Join-Path $archive 'manifest.txt') -Encoding ascii

$rows = @()
foreach ($symbol in $Symbols) {
    foreach ($signalTf in $SignalTimeframes) {
        foreach ($profile in $Profiles) {
            if (Get-Process terminal64 -ErrorAction SilentlyContinue | Where-Object Path -eq $terminal) {
                throw "The dedicated MT5 test terminal became occupied before $symbol $signalTf $profile."
            }
            $p = @{ Band=$profileMap[$profile].Band;
                    Vwap=$profileMap[$profile].Vwap;
                    Slope=$profileMap[$profile].Slope }
            if ($BandEmaOverride -gt 0) { $p.Band = $BandEmaOverride }
            if ($VwapSmoothOverride -gt 0) { $p.Vwap = $VwapSmoothOverride }
            if ($SlopeBarsOverride -gt 0) { $p.Slope = $SlopeBarsOverride }
            $tfCode = $timeframeMap[$signalTf]
            $tag = "TQS_${symbol}_${signalTf}_b$($p.Band)_v$($p.Vwap)_s$($p.Slope)_e${ExitMode}_ema${MajorEma}_r${fixedTargetTag}_sg${signalTriggerCode}_st${stageTag}_d${Deposit}_$RunId"
            $setName = "$tag.set"
            $setFile = Join-Path $archive $setName
            @(
                'InpEntry=3||3||1||3||N',
                'InpStopBand=5||5||1||5||N',
                'InpTrend=1||1||1||1||N',
                "InpExit=$ExitMode||$ExitMode||1||$ExitMode||N",
                "InpM5OnlySignalTf=$tfCode||$tfCode||1||$tfCode||N",
                "InpSignalTrigger=$signalTriggerCode||$signalTriggerCode||1||$signalTriggerCode||N",
                "InpBandEmaPeriod=$($p.Band)||$($p.Band)||1||$($p.Band)||N",
                "InpVwapSmoothPeriod=$($p.Vwap)||$($p.Vwap)||1||$($p.Vwap)||N",
                "InpMajorEmaPeriod=$MajorEma||$MajorEma||1||$MajorEma||N",
                "InpTrendSlopeBars=$($p.Slope)||$($p.Slope)||1||$($p.Slope)||N",
                'InpScreenHistoryBars=1800||1800||1||1800||N',
                "InpRunId=$tag",
                'InpMagic=26102800||26102800||1||26102800||N',
                "InpSymbolRiskPct=$RiskPct||$RiskPct||0.1||$RiskPct||N"
                "InpFixedTargetR=$fixedTargetText||$fixedTargetText||0.1||$fixedTargetText||N"
                'InpIndependentFixed=true||true||0||true||N'
                "InpStageEnabled=$($StageEnabled.ToString().ToLowerInvariant())||$($StageEnabled.ToString().ToLowerInvariant())||0||$($StageEnabled.ToString().ToLowerInvariant())||N"
            ) | Set-Content -LiteralPath $setFile -Encoding ascii
            Copy-Item -LiteralPath $setFile -Destination (Join-Path $setDir $setName) -Force
            $ini = Join-Path $archive "$tag.ini"
            @(
                '[Common]',
                "Login=$activeLogin",
                "Server=$activeServer",
                '',
                '[Tester]',
                'Expert=TrenderRunnerResearchEA.ex5',
                "ExpertParameters=$setName",
                "Symbol=$symbol",
                'Period=M1',
                'Model=4',
                "FromDate=$FromDate",
                "ToDate=$ToDate",
                "Deposit=$Deposit",
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
            Write-Output "Starting $symbol $signalTf $profile (real ticks)"
            $process = Start-Process -FilePath $terminal -ArgumentList ('/login:' + $activeLogin + ' /config:"' + $ini + '"') -WindowStyle Hidden -PassThru -Wait
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
            $metrics = [ordered]@{
                Symbol=$symbol; Configuration="${signalTf}_b$($p.Band)_v$($p.Vwap)_s$($p.Slope)_e${ExitMode}_ema${MajorEma}_r${fixedTargetTag}_st${stageTag}_d${Deposit}";
                Entry=3; Trend=1; SignalTrigger=$SignalTrigger; Window="quick_${FromDate}_${ToDate}";
                SignalTimeframe=$signalTf; Profile=$profile;
                BandEma=$p.Band; VwapSmooth=$p.Vwap; SlopeBars=$p.Slope;
                StopBand='M5'; Exit=$ExitMode; MajorEma=$MajorEma;
                Deposit=$Deposit; Leverage='1:2000'; RiskPct=$RiskPct;
                FixedTargetR=$FixedTargetR; StageEnabled=$stageTag;
                Model='real ticks';
                From=$FromDate; To=$ToDate; Report=$tag
            }
            foreach ($key in @('History Quality','Bars','Ticks','Total Net Profit','Profit Factor','Total Trades',
                               'Expected Payoff','Equity Drawdown Relative',
                               'Long Trades (won %)','Short Trades (won %)')) {
                $pattern = '<td[^>]*>\s*' + [regex]::Escape($key) + ':\s*</td>\s*<td[^>]*>\s*<b>([^<]*)</b>'
                $match = [regex]::Match($html,$pattern)
                $metrics[$key] = if ($match.Success) {
                    [System.Net.WebUtility]::HtmlDecode($match.Groups[1].Value.Trim())
                } else { '' }
            }
            if (-not $metrics['Total Trades'] -or
                -not $metrics['Bars'] -or [int]$metrics['Bars'] -le 0 -or
                -not $metrics['Ticks'] -or [int]$metrics['Ticks'] -le 0) {
                throw "Tester generated no usable bars/ticks for $tag"
            }
            $rows += [pscustomobject]$metrics
            $rows | Export-Csv -LiteralPath (Join-Path $archive 'summary.csv') -NoTypeInformation
            Write-Output "Completed ${tag}: $($metrics['Total Trades']) trades, net $($metrics['Total Net Profit'])"
        }
    }
}
Write-Output "Reports: $archive"

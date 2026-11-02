param(
    [string[]]$Symbols = @('XAUUSDm'),
    [int[]]$Modes = @(0,1),
    [string]$FromDate = '2026.10.01',
    [string]$ToDate = '2026.10.26',
    [string]$RunId = (Get-Date -Format 'yyyyMMdd_HHmmss')
)

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$terminalData = 'C:\Users\Karikari\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075'
$terminal = 'C:\Program Files\MetaTrader 5\terminal64.exe'
$archive = Join-Path $PSScriptRoot "reports\trender_market_$RunId"
$expertDir = Join-Path $terminalData 'MQL5\Experts'
$setDir = Join-Path $terminalData 'MQL5\Profiles\Tester'

if (Get-Process terminal64 -ErrorAction SilentlyContinue) {
    throw 'MT5 is already running; close it before this headless test.'
}
New-Item -ItemType Directory -Path $archive -Force | Out-Null
foreach ($extension in @('mq5','ex5')) {
    $name = "TrenderMarketResearchEA.$extension"
    $source = Join-Path $project "Experts\$name"
    Copy-Item -LiteralPath $source -Destination (Join-Path $expertDir $name) -Force
    Copy-Item -LiteralPath $source -Destination (Join-Path $archive $name) -Force
}
@(
    "source_sha256=$((Get-FileHash -LiteralPath (Join-Path $archive 'TrenderMarketResearchEA.mq5') -Algorithm SHA256).Hash)",
    "binary_sha256=$((Get-FileHash -LiteralPath (Join-Path $archive 'TrenderMarketResearchEA.ex5') -Algorithm SHA256).Hash)",
    "from=$FromDate",
    "to_exclusive=$ToDate",
    'model_requested=4 (real ticks)',
    'deposit=10000 USD',
    'leverage=1:2000'
) | Set-Content -LiteralPath (Join-Path $archive 'manifest.txt') -Encoding ascii

$rows = @()
foreach ($symbol in $Symbols) {
    foreach ($mode in $Modes) {
        if (Get-Process terminal64 -ErrorAction SilentlyContinue) {
            throw "MT5 became occupied before $symbol mode $mode."
        }
        $tag = "TMR_${symbol}_m${mode}_$RunId"
        $setName = "$tag.set"
        $setFile = Join-Path $archive $setName
        @(
            "InpMode=$mode||$mode||1||$mode||N",
            "InpRunId=$tag",
            'InpMagic=26102715||26102715||1||26102715||N',
            'InpRiskPct=0.5||0.5||0.1||0.5||N',
            'InpTargetR=2.0||2.0||0.1||2.0||N',
            'InpExpiryM15Bars=2||2||1||2||N',
            'InpMaxSpreadRiskFraction=0.10||0.10||0.01||0.10||N',
            'InpMaxBandDistanceATR=0.50||0.50||0.05||0.50||N'
        ) | Set-Content -LiteralPath $setFile -Encoding ascii
        Copy-Item -LiteralPath $setFile -Destination (Join-Path $setDir $setName) -Force
        $ini = Join-Path $archive "$tag.ini"
        @(
            '[Tester]',
            'Expert=TrenderMarketResearchEA.ex5',
            "ExpertParameters=$setName",
            "Symbol=$symbol",
            'Period=M15',
            'Model=4',
            "FromDate=$FromDate",
            "ToDate=$ToDate",
            'Deposit=10000',
            'Currency=USD',
            'Leverage=1:2000',
            'Visual=0',
            'ShutdownTerminal=1',
            'ReplaceReport=1',
            'Optimization=0',
            "Report=$tag"
        ) | Set-Content -LiteralPath $ini -Encoding ascii
        $started = Get-Date
        Write-Output "Starting $symbol mode $mode ($FromDate to $ToDate)"
        $process = Start-Process -FilePath $terminal -ArgumentList ('/config:"' + $ini + '"') -WindowStyle Hidden -PassThru -Wait
        $report = Join-Path $terminalData "$tag.htm"
        if (-not (Test-Path -LiteralPath $report) -or (Get-Item -LiteralPath $report).LastWriteTime -lt $started) {
            throw "No fresh report for $tag; terminal exit $($process.ExitCode)."
        }
        $html = Get-Content -LiteralPath $report -Raw
        if ($html -notmatch '<b>TrenderMarketResearchEA</b>' -or
            $html -notmatch [regex]::Escape("<b>$symbol</b>") -or
            $html -match '<b>M0 \(1970\.') {
            throw "Invalid tester report for $tag."
        }
        Copy-Item -LiteralPath $report -Destination (Join-Path $archive "$tag.htm") -Force
        foreach ($suffix in @('', '-hst', '-mfemae', '-holding')) {
            $graph = Join-Path $terminalData "$tag$suffix.png"
            if (Test-Path -LiteralPath $graph) {
                Copy-Item -LiteralPath $graph -Destination (Join-Path $archive "$tag$suffix.png") -Force
            }
        }
        $metrics = [ordered]@{ Symbol=$symbol; Mode=$mode; From=$FromDate; To=$ToDate; Report=$tag }
        foreach ($key in @('History Quality','Total Net Profit','Profit Factor','Total Trades','Expected Payoff','Equity Drawdown Relative','Long Trades (won %)','Short Trades (won %)')) {
            $pattern = '<td[^>]*>\s*' + [regex]::Escape($key) + ':\s*</td>\s*<td[^>]*>\s*<b>([^<]*)</b>'
            $match = [regex]::Match($html,$pattern)
            $metrics[$key] = if ($match.Success) { [System.Net.WebUtility]::HtmlDecode($match.Groups[1].Value.Trim()) } else { '' }
        }
        if (-not $metrics['History Quality'] -or -not $metrics['Total Trades']) {
            throw "Could not parse report metrics for $tag."
        }
        $rows += [pscustomobject]$metrics
        $rows | Export-Csv -LiteralPath (Join-Path $archive 'summary.csv') -NoTypeInformation
        Write-Output "Completed ${tag}: $($metrics['History Quality']), $($metrics['Total Trades']) trades, net $($metrics['Total Net Profit'])"
    }
}
Write-Output "Reports: $archive"

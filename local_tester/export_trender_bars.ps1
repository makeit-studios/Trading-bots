param(
    [string[]]$Symbols = @('XAUUSDm','BTCUSDm','EURUSDm','USTECm'),
    [string]$FromDate = '2026.10.01',
    [string]$ToDate = '2026.10.26',
    [string]$RunId = (Get-Date -Format 'yyyyMMdd_HHmmss')
)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$terminalData = 'C:\Users\Karikari\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075'
$terminal = 'C:\Program Files\MetaTrader 5\terminal64.exe'
$commonFiles = 'C:\Users\Karikari\AppData\Roaming\MetaQuotes\Terminal\Common\Files'
$archive = Join-Path $PSScriptRoot "reports\trender_bars_$RunId"
$expertDir = Join-Path $terminalData 'MQL5\Experts'
$setDir = Join-Path $terminalData 'MQL5\Profiles\Tester'
if (Get-Process terminal64 -ErrorAction SilentlyContinue) {
    throw 'MT5 is already running; close it before this export.'
}
New-Item -ItemType Directory -Path $archive -Force | Out-Null
foreach ($extension in @('mq5','ex5')) {
    $name = "TrenderBarExport.$extension"
    $source = Join-Path $project "Experts\$name"
    Copy-Item -LiteralPath $source -Destination (Join-Path $expertDir $name) -Force
    Copy-Item -LiteralPath $source -Destination (Join-Path $archive $name) -Force
}
@(
    "source_sha256=$((Get-FileHash -LiteralPath (Join-Path $archive 'TrenderBarExport.mq5') -Algorithm SHA256).Hash)",
    'model_requested=2 (open prices only)',
    'timeframes=M1,M3,M5,M15',
    "period=$FromDate to $ToDate",
    "symbols=$($Symbols -join ',')"
) | Set-Content -LiteralPath (Join-Path $archive 'manifest.txt') -Encoding ascii
foreach ($symbol in $Symbols) {
    if (Get-Process terminal64 -ErrorAction SilentlyContinue) {
        throw "MT5 became occupied before $symbol."
    }
    $tag = "TBE_${symbol}_$RunId"
    $setName = "$tag.set"
    $setFile = Join-Path $archive $setName
    "InpRunId=$RunId" | Set-Content -LiteralPath $setFile -Encoding ascii
    Copy-Item -LiteralPath $setFile -Destination (Join-Path $setDir $setName) -Force
    $ini = Join-Path $archive "$tag.ini"
    @(
        '[Tester]',
        'Expert=TrenderBarExport.ex5',
        "ExpertParameters=$setName",
        "Symbol=$symbol",
        'Period=M1',
        'Model=2',
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
    $export = Join-Path $commonFiles "TrenderBars_${RunId}_${symbol}.csv"
    if (Test-Path -LiteralPath $export) { throw "Stale bar export $export" }
    Write-Output "Exporting $symbol bars"
    $process = Start-Process -FilePath $terminal -ArgumentList ('/config:"' + $ini + '"') -WindowStyle Hidden -PassThru -Wait
    if (-not (Test-Path -LiteralPath $export)) {
        throw "No export for $symbol; terminal exit $($process.ExitCode)."
    }
    Copy-Item -LiteralPath $export -Destination (Join-Path $archive "$symbol.csv") -Force
    $count = (Get-Content -LiteralPath (Join-Path $archive "$symbol.csv") | Measure-Object -Line).Lines - 1
    Write-Output "Exported $symbol $count bars"
}
Write-Output "Bars: $archive"

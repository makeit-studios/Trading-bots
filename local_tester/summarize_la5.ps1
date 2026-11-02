param([string]$ReportDirectory)

$ErrorActionPreference = 'Stop'
if (-not $ReportDirectory) {
    $ReportDirectory = (Get-ChildItem (Join-Path $PSScriptRoot 'reports') -Directory -Filter 'la5_compare_*' |
        Sort-Object Name -Descending | Select-Object -First 1).FullName
}
$ReportDirectory = (Resolve-Path -LiteralPath $ReportDirectory).Path

function Read-Field([string]$Html, [string]$Label) {
    $pattern = '<td[^>]*>\s*' + [regex]::Escape($Label) + '</td>\s*<td[^>]*>\s*<b>([^<]*)</b>'
    $match = [regex]::Match($Html, $pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($match.Success) { return [Net.WebUtility]::HtmlDecode($match.Groups[1].Value).Trim() }
    return ''
}

$summary = foreach ($report in (Get-ChildItem -LiteralPath $ReportDirectory -Filter '*.htm' | Sort-Object Name)) {
    $html = Get-Content -LiteralPath $report.FullName -Raw
    $long = 0.0; $short = 0.0; $overlap = 0; $dealCount = 0
    foreach ($line in (Get-Content -LiteralPath $report.FullName)) {
        if ($line -match '<td>XAUUSDm</td><td>(buy|sell)</td><td>(in|out)</td><td>([0-9.]+)</td>') {
            $side = $Matches[1]; $action = $Matches[2]
            $volume = [double]::Parse($Matches[3], [Globalization.CultureInfo]::InvariantCulture)
            if ($action -eq 'in' -and $side -eq 'buy') { $long += $volume }
            elseif ($action -eq 'in' -and $side -eq 'sell') { $short += $volume }
            elseif ($action -eq 'out' -and $side -eq 'sell') { $long -= $volume }
            elseif ($action -eq 'out' -and $side -eq 'buy') { $short -= $volume }
            $long = [math]::Round($long, 6); $short = [math]::Round($short, 6)
            if ($long -gt 0.000001 -and $short -gt 0.000001) { $overlap++ }
            $dealCount++
        }
    }
    [pscustomobject]@{
        Report = $report.BaseName
        Quality = Read-Field $html 'History Quality:'
        Trades = Read-Field $html 'Total Trades:'
        Net = Read-Field $html 'Total Net Profit:'
        Expectancy = Read-Field $html 'Expected Payoff:'
        EquityDrawdown = Read-Field $html 'Equity Drawdown Relative:'
        ProfitFactor = Read-Field $html 'Profit Factor:'
        Deals = $dealCount
        OppositeOverlap = $overlap
        FinalBuyVolume = $long
        FinalSellVolume = $short
    }
}
$csv = Join-Path $ReportDirectory 'summary.csv'
$summary | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
$summary | Format-Table -AutoSize
Write-Output "Summary CSV: $csv"

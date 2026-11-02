$ErrorActionPreference = 'Stop'
$runner = Join-Path $PSScriptRoot 'run_trender_market_research.ps1'
$symbols = @('XAUUSDm', 'BTCUSDm', 'EURUSDm', 'USTECm')
$windows = @(
    @{ From = '2026.08.01'; To = '2026.09.01'; Id = 'aug26f' },
    @{ From = '2026.09.01'; To = '2026.10.01'; Id = 'sep26f' }
)
foreach ($window in $windows) {
    & $runner -Symbols $symbols -Modes 0,1 -FromDate $window.From -ToDate $window.To -RunId $window.Id
    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
        throw "Research run $($window.Id) failed with exit $LASTEXITCODE"
    }
}

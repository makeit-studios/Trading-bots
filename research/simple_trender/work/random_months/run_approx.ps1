$ErrorActionPreference = 'Stop'
$selection = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'selection.json') -Raw | ConvertFrom-Json
$allowed = @($selection.yyyymm | Where-Object { $_ -match '^202[45]\d{2}$' })
if ($allowed.Count -ne 4) { throw 'The locked draw does not contain four months in 2024-2025.' }
$allowedCsv = $allowed -join ','
$runId = 'r6a_20261104'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class RandomMonthsWake {
 [DllImport("kernel32.dll", SetLastError=true)] public static extern uint SetThreadExecutionState(uint flags);
}
'@
if ([RandomMonthsWake]::SetThreadExecutionState([uint32]2147483649) -eq 0) {
    throw 'Could not keep computer awake during the tester run.'
}
try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'local_tester\run_trender_real_ticks.ps1') `
        -Symbols USTECm -SignalTimeframes M15 -Profiles base `
        -BandEmaOverride 30 -VwapSmoothOverride 17 -SlopeBarsOverride 3 `
        -ExitMode 2 -MajorEma 210 -Deposit 1000 -RiskPct 3 `
        -FixedTargetR 1 -SignalTrigger ema_reclaim -Tiered `
        -FromDate 2024.01.01 -ToDate 2026.01.01 `
        -AllowedMonths $allowedCsv -TesterModel 2 -RunId $runId
    if ($LASTEXITCODE -ne 0) { throw "MT5 test failed with exit code $LASTEXITCODE" }
    $archive = Join-Path $PSScriptRoot "local_tester\reports\trender_quick_$runId"
    & python (Join-Path $PSScriptRoot 'local_tester\analyze_trender_runner.py') --allow-open-prices $archive
    if ($LASTEXITCODE -ne 0) { throw "Trade ledger audit failed with exit code $LASTEXITCODE" }
    Write-Output "Analyzed archive: $archive"
} finally {
    [void][RandomMonthsWake]::SetThreadExecutionState([uint32]2147483648)
}

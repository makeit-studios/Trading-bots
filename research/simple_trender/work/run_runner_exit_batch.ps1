$ErrorActionPreference = 'Stop'
$systemModules = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\Modules'
$env:PSModulePath = "$systemModules;$env:PSModulePath"
Import-Module (Join-Path $systemModules 'Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1')
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class RunnerExitWake {
 [DllImport("kernel32.dll",SetLastError=true)] public static extern uint SetThreadExecutionState(uint flags);
}
'@
if ([RunnerExitWake]::SetThreadExecutionState([uint32]2147483649) -eq 0) { throw 'Could not keep the computer awake.' }
try {
 $runs = @(
   @{tf='M5'; mode=0; id='cont_m5_base_20261102'},
   @{tf='M5'; mode=1; id='cont_m5_be_portable_20261102'},
   @{tf='M5'; mode=2; id='cont_m5_beatr_20261102'},
   @{tf='M15'; mode=1; id='cont_m15_be_20261102'},
   @{tf='M15'; mode=0; id='cont_m15_base_snap_20261102'}
 )
 foreach ($run in $runs) {
  $archive = ".\work\runner_exit\local_tester\reports\trender_quick_$($run.id)"
  if (-not (Test-Path -LiteralPath (Join-Path $archive 'summary.csv'))) {
   & powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\work\runner_exit\local_tester\run_trender_real_ticks.ps1' -Symbols USTECm -SignalTimeframes $run.tf -Profiles base -BandEmaOverride 30 -VwapSmoothOverride 17 -SlopeBarsOverride 3 -ExitMode 2 -MajorEma 210 -Deposit 1000 -RiskPct 3 -FixedTargetR 1 -SignalTrigger ema_reclaim -FromDate 2026.07.01 -ToDate 2026.10.26 -RunId $run.id -RunnerManagement $run.mode
   if ($LASTEXITCODE -ne 0) { throw "Tester failed for $($run.id)" }
  }
  & python '.\work\runner_exit\local_tester\analyze_trender_runner.py' $archive
  if ($LASTEXITCODE -ne 0) { throw "Ledger audit failed for $($run.id)" }
  & python '.\work\runner_exit\verify_independent.py' $archive
  if ($LASTEXITCODE -ne 0) { throw "Fixed-leg audit failed for $($run.id)" }
 }
 & python '.\work\runner_exit_report.py'
 if ($LASTEXITCODE -ne 0) { throw 'Final comparison or stop audit failed.' }
} finally { [void][RunnerExitWake]::SetThreadExecutionState([uint32]2147483648) }

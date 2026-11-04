$ErrorActionPreference = 'Stop'
$systemModules = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\Modules'
$env:PSModulePath = "$systemModules;$env:PSModulePath"
Import-Module (Join-Path $systemModules 'Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1')
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class YearlyTestWake {
 [DllImport("kernel32.dll", SetLastError=true)] public static extern uint SetThreadExecutionState(uint flags);
}
'@
if ([YearlyTestWake]::SetThreadExecutionState([uint32]2147483649) -eq 0) { throw 'Could not keep computer awake' }
try {
 foreach ($run in @(@{risk=3; prefix='y26t3'},@{risk=5; prefix='y26t5'})) {
  $complete = Get-ChildItem '.\work\yearly\local_tester\reports' -Directory -Filter "trender_quick_$($run.prefix)*" -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'summary.csv') } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($complete) { $archive=$complete.FullName } else {
   $runId=$run.prefix+'_'+(Get-Date -Format 'HHmmssfff')
   $archive=".\work\yearly\local_tester\reports\trender_quick_$runId"
   & powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\work\yearly\local_tester\run_trender_real_ticks.ps1' -Symbols USTECm -SignalTimeframes M15 -Profiles base -BandEmaOverride 30 -VwapSmoothOverride 17 -SlopeBarsOverride 3 -ExitMode 2 -MajorEma 210 -Deposit 1000 -RiskPct $run.risk -FixedTargetR 1 -SignalTrigger ema_reclaim -FromDate 2026.01.01 -ToDate 2026.11.03 -RunId $runId -Tiered
   if ($LASTEXITCODE -ne 0) { throw "Tester failed $($run.prefix)" }
  }
  & python '.\work\yearly\local_tester\analyze_trender_runner.py' $archive
  if ($LASTEXITCODE -ne 0) { throw "Ledger failed $($run.prefix)" }
  & python '.\work\yearly\audit_tiered.py' $archive
  if ($LASTEXITCODE -ne 0) { throw "Safety audit failed $($run.prefix)" }
 }
 & python '.\work\yearly\report.py'
 if ($LASTEXITCODE -ne 0) { throw 'Yearly report failed' }
} finally { [void][YearlyTestWake]::SetThreadExecutionState([uint32]2147483648) }

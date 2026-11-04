param([string]$FromDate,[string]$ToDate,[string]$RunId)
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class M15IndependentWake {
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern uint SetThreadExecutionState(uint flags);
}
'@
$previous=[M15IndependentWake]::SetThreadExecutionState([uint32]2147483649)
if ($previous -eq 0) { throw 'Could not keep system awake.' }
try {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\work\m15_independent\local_tester\run_trender_real_ticks.ps1' -Symbols USTECm -SignalTimeframes M15 -Profiles base -BandEmaOverride 30 -VwapSmoothOverride 17 -SlopeBarsOverride 3 -ExitMode 2 -MajorEma 210 -Deposit 1000 -RiskPct 3 -FixedTargetR 1 -SignalTrigger ema_reclaim -FromDate $FromDate -ToDate $ToDate -RunId $RunId
  if($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
  [void][M15IndependentWake]::SetThreadExecutionState([uint32]2147483648)
}

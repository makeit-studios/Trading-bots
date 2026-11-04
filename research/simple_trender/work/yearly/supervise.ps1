param([int]$InitialProcess)
$ErrorActionPreference='Stop'
$systemModules=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\Modules'
$env:PSModulePath="$systemModules;$env:PSModulePath"
Import-Module (Join-Path $systemModules 'Microsoft.PowerShell.Management\Microsoft.PowerShell.Management.psd1')
Import-Module (Join-Path $systemModules 'Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1')
$workspace=(Get-Location).Path
$runner=Join-Path $workspace 'work\run_yearly_tiered.ps1'
$previousError=Join-Path $workspace 'work\yearly\background_retry_stderr.log'
$first=Get-Process -Id $InitialProcess -ErrorAction SilentlyContinue
if ($first) { Wait-Process -Id $InitialProcess }
for ($attempt=1; $attempt -le 4; $attempt++) {
 if (Test-Path -LiteralPath (Join-Path $workspace 'outputs\SimpleTrender_2026_YTD_Study.md')) { exit 0 }
 if (-not (Test-Path -LiteralPath $previousError)) { exit 2 }
 $failure=Get-Content -LiteralPath $previousError -Raw
 if ($failure -notmatch 'No events file|No fresh report') { exit 3 }
 $out=Join-Path $workspace "work\yearly\supervised_${attempt}_stdout.log"
 $err=Join-Path $workspace "work\yearly\supervised_${attempt}_stderr.log"
 $p=Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$runner+'"')) -WorkingDirectory $workspace -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -Wait -PassThru
 if ($p.ExitCode -eq 0) { exit 0 }
 $previousError=$err
}
exit 4

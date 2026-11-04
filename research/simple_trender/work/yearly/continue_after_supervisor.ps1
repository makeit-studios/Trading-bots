param([int]$InitialSupervisor)
$ErrorActionPreference='Stop'
$systemModules=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\Modules'
$env:PSModulePath="$systemModules;$env:PSModulePath"
Import-Module (Join-Path $systemModules 'Microsoft.PowerShell.Management\Microsoft.PowerShell.Management.psd1')
Import-Module (Join-Path $systemModules 'Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1')
$w=(Get-Location).Path
$current=Get-Process -Id $InitialSupervisor -ErrorAction SilentlyContinue
if ($current) { Wait-Process -Id $InitialSupervisor }
for ($attempt=1; $attempt -le 8; $attempt++) {
 if (Test-Path -LiteralPath (Join-Path $w 'outputs\SimpleTrender_2026_YTD_Study.md')) { exit 0 }
 if ($attempt -eq 1) { $errorFile=Join-Path $w 'work\yearly\supervised_4_stderr.log' }
 else { $errorFile=Join-Path $w ("work\yearly\continued_"+($attempt-1)+'_stderr.log') }
 if (-not (Test-Path -LiteralPath $errorFile)) { exit 2 }
 $failure=Get-Content -LiteralPath $errorFile -Raw
 if ($failure -notmatch 'No events file|No fresh report') { exit 3 }
 $out=Join-Path $w "work\yearly\continued_${attempt}_stdout.log"
 $err=Join-Path $w "work\yearly\continued_${attempt}_stderr.log"
 $runner=Join-Path $w 'work\run_yearly_tiered.ps1'
 $p=Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$runner+'"')) -WorkingDirectory $w -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -Wait -PassThru
 if ($p.ExitCode -eq 0) { exit 0 }
}
exit 4

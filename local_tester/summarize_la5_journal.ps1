param(
    [string]$Journal = 'C:\Users\Karikari\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\Tester\logs\20261023.log',
    [int]$Last = 9,
    [string]$OutputCsv
)

$ErrorActionPreference = 'Stop'
$records = [Collections.Generic.List[object]]::new()
$current = $null
$events = Select-String -LiteralPath $Journal -Pattern 'LA5 START|LA5 SIGNAL|LA5 ORDER|LA5 SKIP|LA5 REVERSE|LA5 EXIT deal|final balance'
foreach ($event in $events) {
    $line = $event.Line
    if ($line -match '(\d{4}\.\d\d\.\d\d \d\d:\d\d:\d\d)\s+LA5 START filter=(.*?) target=([0-9.]+)R') {
        $current = [ordered]@{
            Start = $Matches[1]; Filter = $Matches[2]; TargetR = $Matches[3]
            Signals = 0; Orders = 0; Skips = 0; Reversals = 0
            TargetsHit = 0; StopsHit = 0; OtherExits = 0; FinalBalance = ''
        }
    } elseif ($null -ne $current) {
        if ($line -match 'LA5 SIGNAL ') { $current.Signals++ }
        elseif ($line -match 'LA5 ORDER ') { $current.Orders++ }
        elseif ($line -match 'LA5 SKIP ') { $current.Skips++ }
        elseif ($line -match 'LA5 REVERSE ') { $current.Reversals++ }
        elseif ($line -match 'LA5 EXIT deal ') {
            if ($line -match 'fixed target hit') { $current.TargetsHit++ }
            elseif ($line -match 'stop hit') { $current.StopsHit++ }
            else { $current.OtherExits++ }
        } elseif ($line -match 'final balance\s+([0-9.]+) USD') {
            $current.FinalBalance = $Matches[1]
            $records.Add([pscustomobject]$current)
            $current = $null
        }
    }
}
$selected = @($records | Select-Object -Last $Last)
if ($OutputCsv) { $selected | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8 }
$selected | Format-Table -AutoSize

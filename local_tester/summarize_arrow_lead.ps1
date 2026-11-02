param(
    [string]$Journal = 'C:\Users\Karikari\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\Tester\logs\20261024.log',
    [int]$Run = -1,
    [string]$OutputCsv
)

$ErrorActionPreference = 'Stop'
$culture = [Globalization.CultureInfo]::InvariantCulture
$all = [Collections.Generic.List[object]]::new()
$runNumber = -1
foreach ($hit in (Select-String -LiteralPath $Journal -Pattern 'ALP\|')) {
    $tail = $hit.Line.Substring($hit.Line.IndexOf('ALP|'))
    $parts = $tail.Split('|', 6)
    if ($parts.Length -lt 3) { continue }
    if ($parts[1] -eq 'START') { $runNumber++ }
    if ($parts.Length -lt 6) { continue }
    $eventTime = [datetime]::ParseExact($parts[2], 'yyyy.MM.dd HH:mm:ss', $culture)
    $barTime = [datetime]::ParseExact($parts[3], 'yyyy.MM.dd HH:mm:ss', $culture)
    $extras = @{}
    foreach ($part in $parts[5].Split(';')) {
        if ($part.Contains('=')) {
            $kv = $part.Split('=', 2)
            $extras[$kv[0]] = $kv[1]
        }
    }
    $all.Add([pscustomobject]@{
        Run = $runNumber; Kind = $parts[1]; Time = $eventTime
        Bar = $barTime; Side = $parts[4]; Extra = $extras
    })
}
if ($Run -lt 0) { $Run = $runNumber }
$events = @($all | Where-Object { $_.Run -eq $Run })
if (-not $events) { throw "No ALP events for run $Run" }

$m5First = @($events | Where-Object Kind -eq 'M5_FIRST')
$m15First = @($events | Where-Object Kind -eq 'M15_FIRST')
$m5Close = @($events | Where-Object Kind -eq 'M5_CLOSE')
$m15Close = @($events | Where-Object Kind -eq 'M15_CLOSE')

$rows = foreach ($event in $m5First) {
    $m15Bar = $event.Bar.AddMinutes(-($event.Bar.Minute % 15))
    $live = @($m15First | Where-Object { $_.Bar -eq $m15Bar -and $_.Side -eq $event.Side } | Sort-Object Time | Select-Object -First 1)
    $final15 = @($m15Close | Where-Object { $_.Extra['closed_bar'] -eq $m15Bar.ToString('yyyy.MM.dd HH:mm:ss') } | Select-Object -First 1)
    $final5 = @($m5Close | Where-Object { $_.Extra['closed_bar'] -eq $event.Bar.ToString('yyyy.MM.dd HH:mm:ss') } | Select-Object -First 1)
    $band = $event.Extra['m15_band']
    $vwap = $event.Extra['m15_vwap']
    $liveStatus = if (-not $live) { 'never_live' } elseif ($live[0].Time -gt $event.Time) { 'm5_led' } else { 'm15_first' }
    $leadSeconds = if ($liveStatus -eq 'm5_led') { [int]($live[0].Time - $event.Time).TotalSeconds } else { $null }
    [pscustomobject]@{
        M5Time = $event.Time; M5Bar = $event.Bar; M15Bar = $m15Bar; Side = $event.Side
        LastClosedM15Band = $band; LastClosedM15VwapSide = $vwap
        BandAligned = ($band -eq $event.Side)
        BandAndVwapAligned = ($band -eq $event.Side -and $vwap -eq $event.Side)
        M5Confirmed = ($final5.Count -gt 0 -and $final5[0].Side -eq $event.Side)
        M15LiveStatus = $liveStatus
        LeadSecondsToM15Live = $leadSeconds
        M15Confirmed = ($final15.Count -gt 0 -and $final15[0].Side -eq $event.Side)
        M15FinalSide = if ($final15.Count) { $final15[0].Side } else { 'missing' }
    }
}

function ShowGroup($label, $group) {
    $group = @($group)
    $led = @($group | Where-Object M15LiveStatus -eq 'm5_led')
    $confirmed = @($group | Where-Object M15Confirmed)
    $m5Confirmed = @($group | Where-Object M5Confirmed)
    $ledConfirmed = @($led | Where-Object M15Confirmed)
    $leads = @($led | ForEach-Object LeadSecondsToM15Live | Sort-Object)
    $median = if ($leads.Count) { [math]::Round($leads[[int][math]::Floor(($leads.Count - 1)/2)] / 60, 2) } else { 0 }
    [pscustomobject]@{
        Group = $label; M5First = $group.Count; M5Closed = $m5Confirmed.Count
        M5LedM15Live = $led.Count; MedianLeadMinutes = $median
        LedAndM15Closed = $ledConfirmed.Count; M15ClosedSameSide = $confirmed.Count
        NoSameM15Live = @($group | Where-Object M15LiveStatus -eq 'never_live').Count
    }
}

$summary = @(
    ShowGroup 'all M5 first-sight' $rows
    ShowGroup 'last closed M15 band aligned' @($rows | Where-Object BandAligned)
    ShowGroup 'band and VWAP side aligned' @($rows | Where-Object BandAndVwapAligned)
    ShowGroup 'M5 candle also closed with arrow' @($rows | Where-Object M5Confirmed)
)
Write-Output "Run $Run; M15 first-sight arrows: $($m15First.Count); M15 closed arrows: $(@($m15Close | Where-Object { $_.Side -ne 'NONE' }).Count)"
$summary | Format-Table -AutoSize
$firstPerM15Bar = @($rows | Sort-Object M5Time | Group-Object { "$($_.M15Bar.ToString('s'))|$($_.Side)" } |
    ForEach-Object { $_.Group[0] })
Write-Output 'First M5 arrow per M15 bar and direction:'
@(
    ShowGroup 'all' $firstPerM15Bar
    ShowGroup 'last closed M15 band aligned' @($firstPerM15Bar | Where-Object BandAligned)
) | Format-Table -AutoSize
$m15LedByM5 = 0
$m15LedByAlignedM5 = 0
foreach ($event in $m15First) {
    $prior = @($rows | Where-Object {
        $_.M15Bar -eq $event.Bar -and $_.Side -eq $event.Side -and $_.M5Time -lt $event.Time
    })
    if ($prior.Count) {
        $m15LedByM5++
        if (@($prior | Where-Object BandAligned).Count) { $m15LedByAlignedM5++ }
    }
}
Write-Output "M15 live arrows preceded by same-side M5 first-sight within that M15 candle: $m15LedByM5 / $($m15First.Count); with last closed M15 band aligned: $m15LedByAlignedM5 / $($m15First.Count)"
if ($OutputCsv) {
    $rows | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation
    Write-Output "Event comparison: $OutputCsv"
}

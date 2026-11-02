# Body Range Zones indicator

This is a visual research indicator for the blue body range boxes in `../Pics/Screenshot 2026-10-20 013342.png`. It does not place orders.

## Zone rules

- Box edges use candle opens and closes, not wicks.
- A zone is identified as soon as closed candle bodies touch alternating edges in a low-high-low or high-low-high sequence: an incomplete W or M. The earliest pattern uses three closed candles; `InpMaxBars` limits how far back the formation search can look. The body width must be within the configured range relative to recent average candle bodies.
- A box starts at the first candle of that pattern. Its dotted line marks the closed candle where the incomplete W or M became visible. This is the earliest identification point, not a later confirmation after a full W or M.
- After identification the box edges stay fixed. Wicks may leave the box and return; the zone stays active if the candle closes inside or on an edge. Only a completed close above the upper edge or below the lower edge ends it. Ended zones are removed from the chart, CSV, and indicator buffers.

## Market Watch and retention

The selected chart timeframe is scanned across Market Watch symbols. The indicator checks one symbol every `InpSecondsPerSymbol` seconds. It keeps only active candidates in memory and ranks them by the time their early W/M pattern was identified. The newest `InpMaxRetainedBoxes` are drawn or exported across all symbols combined. The default is **five**; set the input to **three** for three boxes. The chart only draws retained boxes for its own symbol, including when you scroll back; old boxes are never redrawn. Symbols with unavailable history are retried on the next pass.

The current retained list is written to `MQL5/Files/BodyRangeZones_MarketWatch.csv` in the MT5 terminal data folder after each scan step. The file is overwritten, so invalid or displaced boxes are cleared. It is deleted when the indicator is removed. The chart comment shows the same list. A newly closed candle invalidates a cached candidate until that symbol is scanned again; this prevents an unchecked old box from remaining visible. Completing a scan pass takes roughly the Market Watch symbol count times `InpSecondsPerSymbol`, plus any history loading time.

Buffer 0 contains the upper edge, buffer 1 the lower edge, and buffer 2 is `1` only on the latest closed bar when the chart symbol has a retained active box. Otherwise the upper and lower buffers are empty and state is `0`. Historical ended zones are not kept in the buffers.

## Load in MT5

The source and compiled indicator are synced to the local MetaTrader 5 terminal's `MQL5/Indicators` folder. Refresh Navigator and attach **BodyRangeZones** to a chart. The chart timeframe selects the timeframe for the whole Market Watch scan. A chart with the indicator already attached may need the indicator reloaded to use a newly compiled executable.

`Sync-BodyRangeZones.ps1` copies the project source and compiled EX5 into the local MT5 Indicators folder. With `-Watch`, it checks source edits every two seconds and compiles with MetaEditor. The project source is the source of truth; sync activity is recorded in `BodyRangeZones.sync.log`.

These thresholds are provisional. Compare the live boxes against the example screenshot before using them to assess a trading strategy. Broker price history can differ from the Capital.com chart.

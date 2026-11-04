import csv, glob, re, statistics, json
from collections import Counter, defaultdict
from pathlib import Path

ROOT=Path(__file__).resolve().parent.parent
BASE=ROOT/'work/runner_exit/local_tester/reports'
OUT=ROOT/'outputs'
RUNS=[('M5','baseline','cont_m5_base_20261102'),('M5','break-even','cont_m5_be_portable_20261102'),('M5','break-even + ATR','cont_m5_beatr_20261102'),('M15','baseline','cont_m15_base_snap_20261102'),('M15','break-even','cont_m15_be_20261102'),('M15','break-even + ATR','cont_m15_beatr_20261102')]
def read(p,**kw):
 with p.open(newline='',encoding='utf-8-sig') as f: return list(csv.DictReader(f,**kw))
def fields(s): return dict(re.findall(r'(\w+)=([^ ]+)',s))
def mean(v): return statistics.mean(v) if v else 0
rows=[]; months=[]; audits=[]
for tf,variant,run in RUNS:
 p=BASE/('trender_quick_'+run)
 summary=read(p/'summary.csv')[0]; audit=read(p/'audited_summary.csv')[0]; trades=read(p/'trades.csv')
 ev=read(next(p.glob('*.events.csv')),delimiter=';'); counter=Counter(e['kind'] for e in ev)
 if summary['History Quality']!='100% real ticks' or ev[0]['kind']!='START' or ev[-1]['kind']!='END': raise ValueError(run+' invalid')
 fills={fields(e['detail'])['id']:fields(e['detail']) for e in ev if e['kind']=='FILL'}
 trigger=set(); trail=set(); last={}; changes=Counter(); rejects=Counter(); actual_reasons=Counter(); snapshots=[]
 for e in ev:
  d=fields(e['detail']); kind=e['kind']; ident=d.get('id')
  if kind in ('BE_TRIGGER','TRAIL_TRIGGER'):
   if not ident or ident not in fills or fills[ident]['leg']!='1': raise ValueError('Bad trigger '+str(e))
   if float(d['moveR']) < (2 if kind=='BE_TRIGGER' else 5): raise ValueError('Trigger below threshold')
   (trigger if kind=='BE_TRIGGER' else trail).add(ident)
  if kind=='STOP_MODIFIED':
   if d.get('leg')!='1' or ident not in trigger: raise ValueError('Invalid stop target '+str(e))
   f=fills[ident]; direction=1 if float(f['entry'])>float(f['stop']) else -1
   old=float(d['old']); new=float(d['desired']); entry=float(f['entry'])
   if direction*(new-old)<-0.00001 or direction*(new-entry)<-0.011: raise ValueError('Stop moved backward '+str(e))
   if d.get('trail')=='1' and ident not in trail: raise ValueError('Trail before threshold')
   if ident in last and direction*(new-last[ident])<-0.00001: raise ValueError('Stop moved backwards between requests')
   last[ident]=new; changes['trail' if d['trail']=='1' else 'break_even']+=1
  if kind=='STOP_REJECTED': rejects[d.get('code','unknown')]+=1
  if kind=='STOP_DEFER' and run=='cont_m15_beatr_20261102':
   # This run used the first compiled version. Confirm the later fallback
   # change could not affect it: break-even was already protected.
   f=fills[ident]; direction=1 if float(f['entry'])>float(f['stop']) else -1
   if ident not in last or direction*(last[ident]-float(f['entry']))<-0.011:
    raise ValueError('Earlier build deferred an unprotected stop '+str(e))
  if kind=='MONTH_SNAPSHOT': snapshots.append((e['time'],d))
  if kind=='EXIT':
   if d.get('leg')=='1': actual_reasons['SL' if d['reason']=='4' else 'TP' if d['reason']=='5' else d['exitRule']]+=1
 if len(snapshots)!=4: raise ValueError('Expected four monthly snapshots '+run)
 fixed=[t for t in trades if t['Leg']=='2']; runner=[t for t in trades if t['Leg']=='1']; measured=[t for t in runner if t['EndOfTest']=='0']; resolved=[t for t in fixed if t['ExitReason'] in ('SL','TP')]
 net=lambda x:sum(float(t['NetUSD']) for t in x)
 row=dict(timeframe=tf,variant=variant,entries=int(audit['AcceptedSignals']),total_net=float(summary['Total Net Profit'].replace(' ','')),profit_factor=summary['Profit Factor'],equity_drawdown=summary['Equity Drawdown Relative'],fixed_count=len(fixed),fixed_tp=sum(t['ExitReason']=='TP' for t in resolved),fixed_resolved=len(resolved),fixed_net=round(net(fixed),2),fixed_mean_net_r=round(mean([float(t['NetR']) for t in resolved]),4),runner_count=len(runner),runner_net=round(net(runner),2),runner_measured=len(measured),runner_mean_net_r=round(mean([float(t['NetR']) for t in measured]),4),runner_mean_mfe_r=round(mean([float(t['MFER']) for t in measured]),4),runner_ge5=sum(float(t['MFER'])>=5 for t in measured),runner_ge10=sum(float(t['MFER'])>=10 for t in measured),runner_ge15=sum(float(t['MFER'])>=15 for t in measured),runner_eot_unmeasured=len(runner)-len(measured),be_triggers=len(trigger),trail_triggers=len(trail),stop_changes=sum(changes.values()),stop_rejections=sum(rejects.values()),market_closed_rejections=rejects['10018'],stop_deferred=counter['STOP_DEFER'],close_errors=counter['ERROR'],min_volume_skips=sum(e['kind']=='SKIP' and 'minimum volume exceeds risk' in e['detail'] for e in ev))
 rows.append(row)
 for time,d in snapshots:
  mon=d['month']; mt=[t for t in trades if t['ExitTime'].replace('.','')[:6]==mon]
  months.append(dict(timeframe=tf,variant=variant,month=mon,first_tick=time,starting_balance=d['balance'],starting_equity=d['equity'],open_positions=d['positions'],realized_trade_net=round(net(mt),2),fixed_realized=round(net([t for t in mt if t['Leg']=='2']),2),runner_realized=round(net([t for t in mt if t['Leg']=='1']),2)))
 audits.append(dict(timeframe=tf,variant=variant,exit_reasons=dict(actual_reasons),stop_rejection_codes=dict(rejects),archive=str(p),source_hash=(p/'manifest.txt').read_text().splitlines()[0],binary_hash=(p/'manifest.txt').read_text().splitlines()[1]))
def write(path,data):
 with path.open('w',encoding='utf-8',newline='') as f:
  w=csv.DictWriter(f,fieldnames=list(data[0]));w.writeheader();w.writerows(data)
write(OUT/'SimpleTrender_Continuous_Runner_Comparison.csv',rows)
write(OUT/'SimpleTrender_Continuous_Monthly_Snapshots.csv',months)
(OUT/'SimpleTrender_Continuous_Runner_Audit.json').write_text(json.dumps(audits,indent=2),encoding='utf-8')
lines=['# Simple Trender: continuous real-tick runner exit study','',
 'Each row starts its own $1,000 account and runs continuously from July 1 through October 25, 2026. USTECm, real ticks, fixed 1R leg, M5 band initial stop, 3% nominal combined equity risk with the existing 90% sizing reserve, and M15 runner exit remain in effect. Returns are development-sample results, not out-of-sample evidence.','',
 '| Signal | Runner management | Entries | Net | Profit factor | Maximum equity drawdown | Fixed net | Runner net | Runner mean net R | 5R / 10R / 15R peaks |',
 '|---|---|---:|---:|---:|---:|---:|---:|---:|---:|']
for x in rows:
 lines.append(f"| {x['timeframe']} | {x['variant']} | {x['entries']} | ${x['total_net']:.2f} | {x['profit_factor']} | {x['equity_drawdown']} | ${x['fixed_net']:.2f} | ${x['runner_net']:.2f} | {x['runner_mean_net_r']:.3f} | {x['runner_ge5']} / {x['runner_ge10']} / {x['runner_ge15']} |")
lines += ['', 'Runner net R and MFE counts exclude positions forced closed at the end of the test because their MFE was not logged; cash totals include them. The 5R, 10R and 15R peak counts overlap and are not realized profit. Trade paths, position sizes, and accepted signals can differ between variants. Each stop-trigger and stop-modification event was checked against the original position risk and direction.','',
 '## Monthly account snapshots','',
 'Snapshots are taken on the first available tick of each broker-server month, before processing that tick. Open positions carry across month boundaries. Realized trade net is attributed to the month of the final exit and includes the full trade’s entry costs; it is not the change in month-end equity. October ends on October 25.','',
 '| Signal | Management | Month | First-tick balance | First-tick equity | Open positions | Trade net closed in month |', '|---|---|---|---:|---:|---:|---:|']
for x in months:
 lines.append(f"| {x['timeframe']} | {x['variant']} | {x['month']} | ${x['starting_balance']} | ${x['starting_equity']} | {x['open_positions']} | ${x['realized_trade_net']:.2f} |")
lines += ['', '## Execution observations','', '| Signal | Management | BE triggers | Trail triggers | Accepted stop changes | Stop rejections | Market-closed stop rejections | Deferred invalid stops | Close errors | Minimum-volume skips |', '|---|---|---:|---:|---:|---:|---:|---:|---:|---:|']
for x in rows:
 lines.append(f"| {x['timeframe']} | {x['variant']} | {x['be_triggers']} | {x['trail_triggers']} | {x['stop_changes']} | {x['stop_rejections']} | {x['market_closed_rejections']} | {x['stop_deferred']} | {x['close_errors']} | {x['min_volume_skips']} |")
lines += ['', 'Break-even is entry price, not guaranteed net zero after spread, commission, swap, gaps or slippage. Trailing updates use M15 ATR(14) from the last completed candle and completed M15 candles entirely after entry; an entry-bar partial candle is excluded to avoid using pre-entry highs or lows. Stop changes use broker tick-size, stop-distance and freeze checks. Rejected or invalid changes retain the last accepted stop.','',
 'The M15 trail run used an earlier build. Its deferred-stop events were audited: every affected position already had an accepted stop at or beyond break-even, so the later fallback change could not alter those events. Rejection counts are attempts, not unique positions. Historical spreads and simulated fills do not guarantee live execution. The existing entry-to-stop risk calculation is scoped to matching positions, not total account exposure.','',
 'All completed reports stated 100% real-tick history and reconciled against the trade/event ledger. The M15 baseline, break-even and trail rules and the M5 rules were chosen using these development months. Freeze any future candidate before evaluation on a genuinely unseen period.']
(OUT/'SimpleTrender_Continuous_Runner_Study.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print(json.dumps(rows,indent=2));print(json.dumps(audits,indent=2))

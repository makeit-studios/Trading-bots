import csv, json, re, statistics
from collections import Counter
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]; OUT=ROOT/'outputs'; BASE=ROOT/'work/yearly/local_tester/reports'
def completed(prefix):
 options=[p for p in BASE.glob('trender_quick_'+prefix+'*') if (p/'summary.csv').exists() and (p/'tiered_audit.json').exists()]
 if not options:raise ValueError('No audited completed run: '+prefix)
 return max(options,key=lambda p:p.stat().st_mtime)
RUNS=[(3,completed('y26t3')),(5,completed('y26t5'))]
def read(p,**kw):
 with p.open(encoding='utf-8-sig',newline='') as f:return list(csv.DictReader(f,**kw))
def fields(s):return dict(re.findall(r'(\w+)=([^ ]+)',s))
def num(s):return float(s.replace(' ',''))
def avg(x):return round(statistics.mean(x),4) if x else 0
rows=[]; months=[]; warnings=[]
for risk,p in RUNS:
 s=read(p/'summary.csv')[0];tr=read(p/'trades.csv');events=read(next(p.glob('*.events.csv')),delimiter=';');a=read(p/'audited_summary.csv')[0]
 if not (p/'tiered_audit.json').exists() or s['History Quality']!='100% real ticks':raise ValueError('Missing audit or real tick verification: '+str(p))
 snapshots=[e for e in events if e['kind']=='MONTH_SNAPSHOT']; observed=[fields(e['detail'])['month'] for e in snapshots]
 expected=[f'2026{x:02d}' for x in range(1,12)]
 if observed!=expected:warnings.append(f'{risk}% observed monthly snapshots {observed}, expected {expected}; full-period coverage not established.')
 start=events[0]['time'];end=events[-1]['time']
 if not start.startswith('2026.01.') or end[:10]<'2026.11.02':warnings.append(f'{risk}% event range {start} to {end}; requested Jan 1 through Nov 2 not fully established.')
 labels={1:'runner',2:'fixed1',4:'fixed2'}; groups={v:[t for t in tr if int(t['Leg'])==k] for k,v in labels.items()}
 row={'nominal_risk_pct':risk,'start_event':start,'end_event':end,'bars':s['Bars'],'ticks':s['Ticks'],'history_quality':s['History Quality'],'entries':int(a['AcceptedSignals']),'net_usd':num(s['Total Net Profit']),'final_balance_usd':1000+num(s['Total Net Profit']),'profit_factor':s['Profit Factor'],'equity_drawdown':s['Equity Drawdown Relative']}
 for name,g in groups.items():
  resolved=[t for t in g if t['EndOfTest']=='0']; targets=[t for t in resolved if t['ExitReason'] in ('TP','SL')] if name!='runner' else resolved
  row.update({name+'_positions':len(g),name+'_net_usd':round(sum(float(t['NetUSD']) for t in g),2),name+'_mean_net_r':avg([float(t['NetR']) for t in resolved]),name+'_resolved':len(targets),name+'_tp':sum(t['ExitReason']=='TP' for t in targets),'eot_'+name:len(g)-len(resolved)})
 rr=[t for t in groups['runner'] if t['EndOfTest']=='0']
 row.update({f'runner_mfe_ge{k}':sum(float(t['MFER'])>=k for t in rr) for k in (5,10,15)})
 c=Counter(e['kind'] for e in events); rb=[fields(e['detail']) for e in events if e['kind']=='TIER_ROLLBACK_START']
 row.update(set_opens=c['TIER_SET_OPEN'],rollbacks=len(rb),rollback_with_positions=sum(any(z.get(t)=='1' for t in ('a','b','c')) for z in rb),close_errors=c['ERROR'],minimum_volume_skips=sum(e['kind']=='SKIP' and 'minimum volume exceeds risk' in e['detail'] for e in events),order_check_skips=sum(e['kind']=='SKIP' and 'order check' in e['detail'] for e in events))
 rows.append(row)
 for e in snapshots:
  x=fields(e['detail']);m=x['month'];z=[t for t in tr if t['ExitTime'].replace('.','')[:6]==m]
  months.append({'nominal_risk_pct':risk,'month':m,'first_tick':e['time'],'starting_balance':x['balance'],'starting_equity':x['equity'],'open_positions':x['positions'],'trade_net_closed':round(sum(float(t['NetUSD']) for t in z),2)})
if rows[0]['bars']!=rows[1]['bars'] or rows[0]['ticks']!=rows[1]['ticks']:warnings.append('The test reports have different bar or tick counts; exact history parity requires investigation.')
def save(p,records):
 with p.open('w',encoding='utf-8',newline='') as f:
  w=csv.DictWriter(f,fieldnames=list(records[0]));w.writeheader();w.writerows(records)
save(OUT/'SimpleTrender_2026_YTD_Comparison.csv',rows);save(OUT/'SimpleTrender_2026_YTD_Monthly.csv',months)
lines=['# Simple Trender: 2026 year-to-date real-tick study','', 'Requested period: 2026-01-01 through 2026-11-02 inclusive; MT5 excludes the current day. Each run starts with a separate $1,000 continuous account on USTECm using the M15 three-leg system and current-equity sizing. Each uses independent 1R and 2R legs and the original M15 runner exit, with the M5 initial stop and no break-even or ATR trail.','']
if warnings:lines+=['## Coverage warnings','']+['- '+w for w in warnings]+['']
lines+=['| Nominal risk | Actual event span | Entries | Net | Final balance | Profit factor | Maximum equity drawdown | 1R net | 2R net | Runner net |', '|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|']
for x in rows:lines.append(f"| {x['nominal_risk_pct']}% | {x['start_event']} – {x['end_event']} | {x['entries']} | ${x['net_usd']:.2f} | ${x['final_balance_usd']:.2f} | {x['profit_factor']} | {x['equity_drawdown']} | ${x['fixed1_net_usd']:.2f} | ${x['fixed2_net_usd']:.2f} | ${x['runner_net_usd']:.2f} |")
lines+=['','| Nominal risk | 1R TP / TP+SL | 2R TP / TP+SL | 1R mean net R | 2R mean net R | Runner mean net R | Runner peak ≥5R / ≥10R / ≥15R |','|---:|---:|---:|---:|---:|---:|---:|']
for x in rows:lines.append(f"| {x['nominal_risk_pct']}% | {x['fixed1_tp']} / {x['fixed1_resolved']} | {x['fixed2_tp']} / {x['fixed2_resolved']} | {x['fixed1_mean_net_r']:.3f} | {x['fixed2_mean_net_r']:.3f} | {x['runner_mean_net_r']:.3f} | {x['runner_mfe_ge5']} / {x['runner_mfe_ge10']} / {x['runner_mfe_ge15']} |")
lines+=['','R averages exclude end-of-test positions but include rollback exits; net cash includes all exits. Target-hit denominators include only TP and SL exits. Runner MFE thresholds overlap and are peak excursions, not realized profit. Leg-level R values use each leg’s own initial risk.','', '## Monthly account snapshots','', 'Balance and equity are measured on the first available broker tick of each month; positions are carried across month boundaries. Closed-trade net is attributed to the month of final exit and includes the trade’s full costs. November contains November 1–2 only.','', '| Nominal risk | Month | First-tick balance | First-tick equity | Open positions | Closed-trade net |','|---:|---|---:|---:|---:|---:|']
for x in months:lines.append(f"| {x['nominal_risk_pct']}% | {x['month']} | ${x['starting_balance']} | ${x['starting_equity']} | {x['open_positions']} | ${x['trade_net_closed']:.2f} |")
lines+=['','## Risk and execution','', 'The EA applies a 90% sizing reserve: the nominal 3% and 5% settings correspond to an intended maximum of 2.7% and 4.5% of current equity, respectively, before lot rounding and execution effects. Modeled open risk is entry-to-stop on matching EA positions for this symbol, not account-wide or current-equity-to-stop exposure. Gaps, slippage, rejected requests and market closures can produce larger losses.','', '| Risk | Successful tier sets | Rollback starts | Rollbacks with opened positions | Minimum-volume skips | Order-check skips | Close errors |','|---:|---:|---:|---:|---:|---:|---:|']
for x in rows:lines.append(f"| {x['nominal_risk_pct']}% | {x['set_opens']} | {x['rollbacks']} | {x['rollback_with_positions']} | {x['minimum_volume_skips']} | {x['order_check_skips']} | {x['close_errors']} |")
lines+=['', 'Reports and event ledgers were reconciled and checked for 100% real-tick history. July–October were used in strategy development, so the full period is mixed in-sample/out-of-sample, not an untouched validation.']
(OUT/'SimpleTrender_2026_YTD_Study.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print(json.dumps({'results':rows,'warnings':warnings},indent=2))

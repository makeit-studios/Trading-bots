import csv, json, re, statistics
from collections import Counter
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]; OUT=ROOT/'outputs'; B=ROOT/'work/tiered/local_tester/reports'
RUNS=[('two-leg',3,ROOT/'work/runner_exit/local_tester/reports/trender_quick_cont_m15_base_snap_20261102'),('two-leg',4.5,B/'trender_quick_two_4p5_20261103'),('three-leg',3,B/'trender_quick_tier_3pct_20261103'),('three-leg',4.5,B/'trender_quick_tier_4p5_20261103')]
def read(p,**kw):
 with p.open(encoding='utf-8-sig',newline='') as f:return list(csv.DictReader(f,**kw))
def fields(s):return dict(re.findall(r'(\w+)=([^ ]+)',s))
def num(s):return float(s.replace(' ',''))
def avg(x):return round(statistics.mean(x),4) if x else 0
rows=[]; months=[]; reasons=[]
for variant,risk,p in RUNS:
 s=read(p/'summary.csv')[0];tr=read(p/'trades.csv');events=read(next(p.glob('*.events.csv')),delimiter=';');a=read(p/'audited_summary.csv')[0]
 if s['History Quality']!='100% real ticks':raise ValueError('Data quality mismatch '+str(p))
 if p.parent==B and not (p/'tiered_audit.json').exists():raise ValueError('Missing audit '+str(p))
 if len([e for e in events if e['kind']=='MONTH_SNAPSHOT'])!=4:raise ValueError('Missing monthly snapshot')
 labels={1:'runner',2:'fixed1',4:'fixed2'};groups={v:[t for t in tr if int(t['Leg'])==k] for k,v in labels.items()}
 row={'variant':variant,'risk_pct_nominal':risk,'entries':int(a['AcceptedSignals']),'net_usd':num(s['Total Net Profit']),'final_balance_usd':1000+num(s['Total Net Profit']),'profit_factor':s['Profit Factor'],'equity_drawdown':s['Equity Drawdown Relative']}
 for name,g in groups.items():
  resolved=[t for t in g if t['EndOfTest']=='0']; hit=[t for t in resolved if t['ExitReason']=='TP']; targets=[t for t in resolved if t['ExitReason'] in ('TP','SL')] if name!='runner' else resolved
  row.update({name+'_count':len(g),name+'_net_usd':round(sum(float(t['NetUSD']) for t in g),2),name+'_mean_net_r':avg([float(t['NetR']) for t in resolved]),name+'_resolved':len(targets),name+'_tp':len(hit)})
 runner=[t for t in groups['runner'] if t['EndOfTest']=='0']
 row.update({f'runner_mfe_ge{threshold}':sum(float(t['MFER'])>=threshold for t in runner) for threshold in (5,10,15)})
 c=Counter(e['kind'] for e in events)
 rb=[fields(e['detail']) for e in events if e['kind']=='TIER_ROLLBACK_START']
 row.update(set_opens=c['TIER_SET_OPEN'],rollbacks=len(rb),rollbacks_with_positions=sum(x.get('a')=='1' or x.get('b')=='1' or x.get('c')=='1' for x in rb),close_errors=c['ERROR'],minimum_volume_skips=sum(e['kind']=='SKIP' and 'minimum volume exceeds risk' in e['detail'] for e in events),order_check_skips=sum(e['kind']=='SKIP' and 'order check' in e['detail'] for e in events))
 rows.append(row)
 for e in events:
  if e['kind']=='MONTH_SNAPSHOT':
   x=fields(e['detail']);m=x['month']; z=[t for t in tr if t['ExitTime'].replace('.','')[:6]==m]
   months.append({'variant':variant,'risk_pct_nominal':risk,'month':m,'first_tick':e['time'],'balance':x['balance'],'equity':x['equity'],'open_positions':x['positions'],'trade_net_closed':round(sum(float(t['NetUSD']) for t in z),2)})
 for e in events:
  if e['kind']=='EXIT':
   x=fields(e['detail']); reason='SL' if x['reason']=='4' else 'TP' if x['reason']=='5' else x['exitRule'];reasons.append({'variant':variant,'risk_pct_nominal':risk,'leg':x['leg'],'reason':reason})
def save(p,records):
 with p.open('w',encoding='utf-8',newline='') as f:
  w=csv.DictWriter(f,fieldnames=list(records[0]));w.writeheader();w.writerows(records)
save(OUT/'SimpleTrender_Tiered_Comparison.csv',rows);save(OUT/'SimpleTrender_Tiered_Monthly.csv',months)
lines=['# M15 tiered runner study','', 'Each run starts with a separate $1,000 account and spans July 1–October 25, 2026 continuously on USTECm real ticks. All use current-equity sizing with the existing 90% reserve, an M5 initial stop, an independent 1R fixed leg and the M15 runner exit. The three-leg version adds an independent 2R target, with initial risk divided across three legs.','', '| Configuration | Nominal risk | Entries | Net | Final balance | PF | Maximum equity DD | 1R net | 2R net | Runner net | Runner mean R |', '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|']
for x in rows: lines.append(f"| {x['variant']} | {x['risk_pct_nominal']}% | {x['entries']} | ${x['net_usd']:.2f} | ${x['final_balance_usd']:.2f} | {x['profit_factor']} | {x['equity_drawdown']} | ${x['fixed1_net_usd']:.2f} | ${x['fixed2_net_usd']:.2f} | ${x['runner_net_usd']:.2f} | {x['runner_mean_net_r']:.3f} |")
lines+=['','R averages exclude end-of-test exits but include rollback exits; dollar net includes all exits. R uses each leg’s own initial stop risk and should not be added as if it were account-level expectancy. Initial lot rounding, different entry paths and equity-dependent sizing can affect all outcomes.','', '| Configuration | Risk | 1R TP / TP+SL | 2R TP / TP+SL | Runner peaks ≥5R / ≥10R / ≥15R | Minimum-volume skips | Order-check skips | Close errors |', '|---|---:|---:|---:|---:|---:|---:|---:|']
for x in rows:lines.append(f"| {x['variant']} | {x['risk_pct_nominal']}% | {x['fixed1_tp']} / {x['fixed1_resolved']} | {x['fixed2_tp']} / {x['fixed2_resolved']} | {x['runner_mfe_ge5']} / {x['runner_mfe_ge10']} / {x['runner_mfe_ge15']} | {x['minimum_volume_skips']} | {x['order_check_skips']} | {x['close_errors']} |")
lines+=['','Peak thresholds overlap and measure excursions before the original exit, not realized profit.','', '## Monthly account snapshots', '', 'Balances and equity are sampled at the first available tick of each broker-server month. Closed-trade net is assigned to the month of final exit; October ends October 25. Positions remain open across month boundaries.','', '| Configuration | Risk | Month | Balance | Equity | Open positions | Closed-trade net |','|---|---:|---|---:|---:|---:|---:|']
for x in months:lines.append(f"| {x['variant']} | {x['risk_pct_nominal']}% | {x['month']} | ${x['balance']} | ${x['equity']} | {x['open_positions']} | ${x['trade_net_closed']:.2f} |")
lines+=['','## Implementation and limitations','','The 2R tier is a separate broker position (leg 4), with the same initial stop. Its target and the 1R tier are independent of M15 runner exits. Opening new three-leg sets is best-effort with retryable rollback if a leg cannot be opened or post-fill modeled risk exceeds the cap; a rejected close can delay rollback. Repeat 1R orders remain allowed while a runner is open. Modeled open risk is entry-to-stop for this EA and symbol; it is not a global portfolio or current-equity-to-stop risk measure.','', 'The 3% tiered run recorded 7 rollback starts, of which 2 involved opened positions; the 4.5% tiered run recorded 8, of which 3 involved opened positions. Remaining rollback starts followed failed initial orders. Rollback exits and their costs are included in the results.','', 'All reports require 100% real ticks and reconcile to their trade/event ledgers. Commission, spread, lot rounding, available margin, rejection and execution behavior are reflected in these tester results, but real fills may differ. July–October are development data, so these results cannot establish a reliable edge or select a live risk level.']
(OUT/'SimpleTrender_Tiered_Study.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print(json.dumps(rows,indent=2))

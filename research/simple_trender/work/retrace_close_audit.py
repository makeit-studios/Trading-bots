"""Retrospective M1-close path descriptions; not a stop replay."""
import bisect, csv, statistics
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASE = Path(r'C:\Users\Karikari\OneDrive\Documents\Projects\EAs\local_tester\reports')
SOURCES = {
 'July': BASE / 'trender_bars_quick_jul_20261029' / 'USTECm.csv',
 'October 1-25': BASE / 'trender_bars_regime_warm_sep_oct_20261031' / 'USTECm.csv',
}
fmt='%Y.%m.%d %H:%M:%S'
with (ROOT/'outputs'/'SimpleTrender_runners_5plus_map.csv').open(newline='',encoding='utf-8-sig') as f:
    trades=list(csv.DictReader(f))
output=[]
for month, path in SOURCES.items():
    bars=[]
    with path.open(newline='',encoding='ascii') as f:
        for row in csv.DictReader(f,delimiter=';'):
            if row['tf'] != '1': continue
            t=datetime.strptime(row['time'],'%Y.%m.%d %H:%M')+timedelta(minutes=1)
            bars.append((t,float(row['close']),int(row['spread_points'])*0.01))
    bars.sort()
    times=[x[0] for x in bars]
    for trade in (x for x in trades if x['Month']==month):
        entry=datetime.strptime(trade['EntryTime'],fmt)
        end=datetime.strptime(trade['ExitTime'],fmt)
        a=bisect.bisect_right(times,entry)
        z=bisect.bisect_right(times,end)
        risk=abs(float(trade['Entry'])-float(trade['Stop']))
        direction=1 if trade['Direction']=='long' else -1
        path_bars=bars[a:z]
        path_r=[direction*((bid if direction==1 else bid+spread)-float(trade['Entry']))/risk for _,bid,spread in path_bars]
        if not path_r:
            continue
        mismatch=max(path_r)-float(trade['MFER'])
        first1=next((i for i,x in enumerate(path_r) if x>=1),None)
        first5=next((i for i,x in enumerate(path_r) if x>=5),None)
        observed=first1 is not None and first5 is not None and first1<=first5 and mismatch<=0.25
        before=path_r[first1+1:first5] if observed else []
        best=path_r[first1] if observed else 0.0
        worst=0.0
        for x in before:
            best=max(best,x)
            worst=max(worst,best-x)
        output.append({'Month':month,'PositionId':trade['PositionId'],'Direction':trade['Direction'],
           'EntryTime':trade['EntryTime'],'ExitTime':trade['ExitTime'],'TickMFER':trade['MFER'],
           'SampledCloseMFER':round(max(path_r),3),'ClosePeakMinusTickMFE':round(mismatch,3),
           'CloseSeen1R':first1 is not None,'CloseSeen5R':first5 is not None,'UsableForBefore5':observed,
           'FirstSample1R':path_bars[first1][0].strftime(fmt) if observed else '',
           'FirstSample5R':path_bars[first5][0].strftime(fmt) if observed else '',
           'Minutes1Rto5R':round((path_bars[first5][0]-path_bars[first1][0]).total_seconds()/60,2) if observed else '',
           'CloseAtOrBelowEntryBefore5':any(x<=0 for x in before) if observed else '',
           'MaxClosePullbackBefore5R':round(worst,3) if observed else '',
           'Note':'M1 closes; short ask approximated using bar spread; intrabar path not observed'})
out=ROOT/'outputs'/'SimpleTrender_M1_Close_Retracement_Exploration.csv'
with out.open('w',newline='',encoding='utf-8') as f:
    w=csv.DictWriter(f,fieldnames=list(output[0]))
    w.writeheader(); w.writerows(output)
for month in SOURCES:
    rows=[x for x in output if x['Month']==month]
    use=[x for x in rows if x['UsableForBefore5']]
    print(month,'large runners',len(rows),'seen5',sum(x['CloseSeen5R'] for x in rows),
          'usable',len(use),'close back to entry',sum(x['CloseAtOrBelowEntryBefore5'] for x in use),
          'median max close pullback',round(statistics.median(x['MaxClosePullbackBefore5R'] for x in use),2) if use else 'NA',
          'mismatch_over_0.25R',sum(x['ClosePeakMinusTickMFE']>0.25 for x in rows))

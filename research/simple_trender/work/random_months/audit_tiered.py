import csv, json, re, sys
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

def read(path, **kwargs):
    with path.open(newline='', encoding='utf-8-sig') as f:
        return list(csv.DictReader(f, **kwargs))
def fields(s): return dict(re.findall(r'(\w+)=([^ ]+)',s))
def audit(path, allow_open_prices=False):
    path=Path(path); summary=read(path/'summary.csv')[0]; trades=read(path/'trades.csv')
    events=read(next(path.glob('*.events.csv')),delimiter=';'); settings=next(path.glob('*.set')).read_text()
    tiered='InpTiered=true||' in settings
    if events[0]['kind']!='START' or events[-1]['kind']!='END':
        raise ValueError('Incomplete run')
    if allow_open_prices:
        if summary['Model']!='open prices only' or float(summary['History Quality'].rstrip('%'))<98:
            raise ValueError('Open-prices-only run or minimum bar coverage not verified')
    elif summary['History Quality']!='100% real ticks':
        raise ValueError('Real ticks not verified')
    match=re.search(r'^InpAllowedMonths=(.*)$', settings, re.M)
    allowed=set(match.group(1).split(',')) if match else set()
    if len(allowed)!=4 or allowed!={'202403','202408','202508','202511'}:
        raise ValueError('Selected-month input differs from the locked 2024-2025 draw')
    expected=[f'{year}{month:02d}' for year in (2024,2025) for month in range(1,13)]
    observed=[fields(e['detail']).get('month') for e in events if e['kind']=='MONTH_SNAPSHOT']
    if observed!=expected:
        raise ValueError(f'Monthly coverage incomplete: {observed}')
    bar_counts=Counter(e['time'][:7].replace('.','') for e in events if e['kind']=='M15_STATE')
    if any(bar_counts[month]<1500 for month in allowed):
        raise ValueError(f'Insufficient M15 bars in a selected month: {bar_counts}')
    if int(summary['Bars'])<500000 or int(summary['Ticks'])<500000:
        raise ValueError('Insufficient bars or ticks for a two-year run')
    for t in trades:
        if t['EntryTime'][:7].replace('.','') not in allowed:
            raise ValueError('Position opened outside the selected months: '+str(t))
    if not all(x in settings for x in ('InpIndependentFixed=true||','InpExit=2||','InpSignalTrigger=1||','InpFixedTargetR=1||','InpStageEnabled=false||','InpRunnerManagement=0||')): raise ValueError('Settings mismatch')
    orders=defaultdict(list); counts=Counter(e['kind'] for e in events)
    for e in events:
        d=fields(e['detail'])
        if e['kind']=='ORDER':
            leg=int(d['leg']); entry=float(d['requested']); stop=float(d['stop']); target=float(d['target']); risk=abs(entry-stop)
            if leg in (2,4):
                expected=1 if leg==2 else 2
                if risk<=0 or abs(abs(target-entry)-expected*risk)>0.021: raise ValueError('Wrong target '+str(e))
            if float(d.get('riskOpen','0'))>float(d.get('cap','0'))+0.05:
                # Filled-price slippage may push risk over its budget, but then
                # a rollback must be recorded for the complete set.
                if not any(z['kind']=='TIER_ROLLBACK_START' and fields(z['detail']).get('signal')==d.get('signal') for z in events):
                    raise ValueError('Unaccounted risk cap breach '+str(e))
            orders[d['signal']].append(leg)
        if e['kind']=='TIER_SET_OPEN':
            if float(d['riskOpen'])>float(d['cap'])+0.011: raise ValueError('Opened set over cap')
            if orders[d['signal']]!=[1,2,4]: raise ValueError('Incomplete or wrong set '+str(e))
    if counts['TIER_ROLLBACK_START']!=counts['TIER_ROLLBACK_DONE']: raise ValueError('Incomplete rollback')
    if tiered and not counts['TIER_SET_OPEN']: raise ValueError('No tiered sets opened')
    for leg in (2,4):
        items=sorted((t for t in trades if int(t['Leg'])==leg),key=lambda t:t['EntryTime'])
        for a,b in zip(items,items[1:]):
            if b['EntryTime']<a['ExitTime']: raise ValueError('Overlapping target leg '+str(leg))
        for t in items:
            if t['ExitReason'] not in ('SL','TP','end of test','TIER_ROLLBACK'):
                raise ValueError('Target leg changed exit '+str(t))
    if tiered:
        targets=[t for t in trades if int(t['Leg']) in (2,4)]
        for runner in (t for t in trades if t['Leg']=='1'):
            if any(t['EntryTime']<runner['EntryTime']<t['ExitTime'] for t in targets): raise ValueError('Runner opened with earlier target active')
    result={'tiered':tiered,'risk':summary['RiskPct'],'model':summary['Model'],'quality':summary['History Quality'],'selected_months':sorted(allowed),'net':summary['Total Net Profit'],'drawdown':summary['Equity Drawdown Relative'],'trades':len(trades),'set_opens':counts['TIER_SET_OPEN'],'rollbacks':counts['TIER_ROLLBACK_START'],'errors':counts['ERROR']}
    (path/'tiered_audit.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result))
if __name__=='__main__': audit(sys.argv[-1], '--allow-open-prices' in sys.argv)

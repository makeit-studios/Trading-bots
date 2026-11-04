import csv, re, sys, json
from collections import Counter
from pathlib import Path

def read(path, **kw):
    with path.open(newline='',encoding='utf-8-sig') as f:
        return list(csv.DictReader(f,**kw))

def verify(path):
    path=Path(path)
    summary=read(path/'summary.csv')[0]
    trades=read(path/'trades.csv')
    events=read(next(path.glob('*.events.csv')),delimiter=';')
    sets=next(path.glob('*.set')).read_text()
    required=('InpIndependentFixed=true||','InpExit=2||','InpSignalTrigger=1||',
              'InpFixedTargetR=1||','InpStageEnabled=false||','InpSymbolRiskPct=3||')
    if summary['History Quality']!='100% real ticks' or any(x not in sets for x in required):
        raise ValueError('Wrong data quality or research settings')
    if events[0]['kind']!='START' or 'independentFixed=1' not in events[0]['detail'] or events[-1]['kind']!='END':
        raise ValueError('Missing independent mode or incomplete ledger')
    fixed=[t for t in trades if t['Leg']=='2']
    runner=[t for t in trades if t['Leg']=='1']
    unexpected=[t for t in fixed if t['ExitReason'] not in ('TP','SL','end of test')]
    if unexpected: raise ValueError('Fixed leg had an unexpected exit '+str(unexpected[:1]))
    f_sorted=sorted(fixed,key=lambda t:t['EntryTime'])
    for a,b in zip(f_sorted,f_sorted[1:]):
        if b['EntryTime']<a['ExitTime']: raise ValueError('Fixed legs overlap')
    # A runner already present may coexist with a new fixed leg; a new runner
    # must not be opened while a fixed leg from an earlier signal remains.
    for r in runner:
        if any(f['EntryTime']<r['EntryTime']<f['ExitTime'] for f in fixed):
            raise ValueError('New runner opened while previous fixed leg remained')
    orders=[]
    for event in events:
        if event['kind']!='ORDER': continue
        fields=dict(re.findall(r'(\w+)=([^\s]+)',event['detail']))
        if fields.get('leg')!='2': continue
        entry=float(fields['requested']); stop=float(fields['stop']); target=float(fields['target'])
        risk=abs(entry-stop)
        if risk<=0 or abs(abs(target-entry)-risk)>0.011:
            raise ValueError('Requested fixed target is not 1R on the price grid')
        orders.append(fields)
    if len(orders)!=len(fixed):
        raise ValueError('Fixed orders and closed positions differ')
    exits=Counter(t['ExitReason'] for t in fixed)
    if exits['TP']+exits['SL']==0: raise ValueError('No resolved fixed trades')
    skips=Counter()
    for e in events:
        if e['kind']=='SKIP': skips[e['detail'].split(' signal=',1)[0]]+=1
    runner_with_mfe=[t for t in runner if t['EndOfTest']=='0']
    import statistics
    out={'archive':str(path),'quality':summary['History Quality'],
         'entries':int(read(path/'audited_summary.csv')[0]['AcceptedSignals']),
         'net':float(summary['Total Net Profit']),'pf':summary['Profit Factor'],
         'dd':summary['Equity Drawdown Relative'],
         'fixed':len(fixed),'fixed_tp':exits['TP'],'fixed_sl':exits['SL'],
         'fixed_eot':exits['end of test'],'fixed_net':round(sum(float(t['NetUSD']) for t in fixed),2),
         'runner':len(runner),'runner_net':round(sum(float(t['NetUSD']) for t in runner),2),
         'runner_median_mfe':round(statistics.median(float(t['MFER']) for t in runner_with_mfe),3),
         'runner_5r':sum(float(t['MFER'])>=5 for t in runner_with_mfe),
         'runner_mfe_unmeasured':len(runner)-len(runner_with_mfe),
         'orphan_slot_skips':skips['satellite remains after core'],
         'errors':sum(e['kind']=='ERROR' for e in events)}
    print(json.dumps(out))

if __name__=='__main__': verify(sys.argv[1])

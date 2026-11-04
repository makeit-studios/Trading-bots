"""Validate and compare independent-fixed research runs by signal timeframe."""
import csv, json, re, statistics, subprocess, sys
from collections import Counter
from datetime import datetime
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
OLD=ROOT/'work'/'independent_fixed'
M15=ROOT/'work'/'m15_independent'
MONTHS=[('July','jul',31),('August','aug',31),('September','sep',30),('October 1-25','oct',25)]
TF={'M1':60,'M3':180,'M5':300,'M15':900}
def read(p, **kwargs):
    with p.open(newline='',encoding='utf-8-sig') as f:
        return list(csv.DictReader(f,**kwargs))
def lines(path):
    return next(path.glob('*.set')).read_text().splitlines()
rows=[]
for label,month,days in MONTHS:
    base=OLD/'local_tester'/'reports'/('trender_quick_u_'+month+'_indfixed')
    common_settings={x for x in lines(base) if not x.startswith(('InpRunId=','InpM5OnlySignalTf='))}
    common_ini={x for x in next(base.glob('*.ini')).read_text().splitlines()
                if not x.startswith(('ExpertParameters=','Report='))}
    baseline=read(base/'summary.csv')[0]
    for tf,seconds in TF.items():
        root=M15 if tf=='M15' else OLD
        suffix='_indfixed' if tf=='M1' else '_'+tf.lower()+'_ind'
        d=root/'local_tester'/'reports'/('trender_quick_u_'+month+suffix)
        info=json.loads(subprocess.check_output([sys.executable,str(root/'verify_independent.py'),str(d)],text=True))
        summary=read(d/'summary.csv')[0]
        settings=lines(d)
        signal_code={'M1':1,'M3':3,'M5':5,'M15':15}[tf]
        if f'InpM5OnlySignalTf={signal_code}||{signal_code}||1||{signal_code}||N' not in settings:
            raise ValueError(f'Incorrect signal timeframe: {d}')
        if {x for x in settings if not x.startswith(('InpRunId=','InpM5OnlySignalTf='))}!=common_settings:
            raise ValueError(f'Unexpected set difference: {d}')
        ini={x for x in next(d.glob('*.ini')).read_text().splitlines()
             if not x.startswith(('ExpertParameters=','Report='))}
        if ini!=common_ini or not {'Period=M1','Model=4'}.issubset(ini):
            raise ValueError(f'Tester config mismatch: {d}')
        if summary['From']!=baseline['From'] or summary['To']!=baseline['To'] or summary['SignalTimeframe']!=tf:
            raise ValueError(f'Wrong period or TF: {d}')
        events=read(next(d.glob('*.events.csv')),delimiter=';')
        signals=[e for e in events if e['kind']=='SIGNAL']
        for e in signals:
            vals=dict(re.findall(r'(\w+)=([^\s]+)',e['detail']))
            now=int((datetime.strptime(e['time'],'%Y.%m.%d %H:%M:%S')-datetime(1970,1,1)).total_seconds())
            if vals.get('signalTf')!=str(signal_code) or now-int(vals['bar'])<seconds:
                raise ValueError(f'Incomplete or wrong signal bar: {d} {e}')
        trades=read(d/'trades.csv')
        runner=[t for t in trades if t['Leg']=='1' and t['EndOfTest']=='0']
        fixed=[t for t in trades if t['Leg']=='2']
        resolved=info['fixed_tp']+info['fixed_sl']
        errors=Counter(e['detail'].rsplit('code=',1)[-1] if 'code=' in e['detail'] else 'unknown'
                       for e in events if e['kind']=='ERROR')
        rows.append(dict(month=label,timeframe=tf,calendar_days=days,entries=info['entries'],
            entries_per_calendar_day=round(info['entries']/days,3),fixed_tp=info['fixed_tp'],fixed_sl=info['fixed_sl'],
            fixed_eot=info['fixed_eot'],fixed_tp_rate_pct=round(100*info['fixed_tp']/resolved,2) if resolved else '',
            fixed_net=info['fixed_net'],runner_count=info['runner'],runner_net=info['runner_net'],
            runner_measured=len(runner),runner_eot_unmeasured=info['runner_mfe_unmeasured'],
            runner_mfe_ge5=sum(float(t['MFER'])>=5 for t in runner),
            runner_mfe_ge10=sum(float(t['MFER'])>=10 for t in runner),
            runner_mfe_ge15=sum(float(t['MFER'])>=15 for t in runner),
            runner_median_mfe=round(statistics.median(float(t['MFER']) for t in runner),3) if runner else '',
            runner_median_giveback=round(statistics.median(float(t['GivebackR']) for t in runner),3) if runner else '',
            combined_net=info['net'],profit_factor=info['pf'],equity_drawdown=info['dd'],
            bars=summary['Bars'],ticks=summary['Ticks'],error_count=info['errors'],
            error_codes=';'.join(f'{k}:{v}' for k,v in sorted(errors.items())),signals_checked=len(signals),archive=str(d)))
out=ROOT/'outputs'/'SimpleTrender_M1_M3_M5_M15_Comparison_20261102.csv'
with out.open('w',newline='',encoding='utf-8') as f:
    w=csv.DictWriter(f,fieldnames=rows[0].keys());w.writeheader();w.writerows(rows)
print(json.dumps(rows,indent=2))

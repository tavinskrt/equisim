import json

with open('docs/validacao/audit_universe_comparison.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

by_ticker = {d['ticker']: d for d in data}

focus = ['PETR4', 'VALE3', 'PRIO3', 'CSNA3', 'GGBR4', 'USIM5']

for t in focus:
    d = by_ticker.get(t)
    if not d:
        print(f"Ticker {t} not found")
        continue
    print(f"================== {t} ==================")
    print(f"Sector: {d.get('sector')} | Industry: {d.get('industry')}")
    print(f"Price: R$ {d.get('price')}")
    print(f"10y: FV={d.get('fv10')} | Upside={d.get('upside10', 0)*100:.1f}% | Lane={d.get('lane10')} | Factor={d.get('factor10')}")
    print(f"5y:  FV={d.get('fv5')} | Upside={d.get('upside5', 0)*100:.1f}% | Lane={d.get('lane5')} | Factor={d.get('factor5')}")
    croic = d.get('currentRoic') or 0
    yroic = d.get('cycleRoic') or 0
    w10 = d.get('wacc10') or 0
    w5 = d.get('wacc5') or 0
    nd = d.get('netDebt') or 0
    sh = d.get('shares') or 0
    print(f"Current ROIC: {croic*100:.2f}% | Cycle ROIC: {yroic*100:.2f}% | Phi: {d.get('phi')}")
    print(f"WACC10: {w10*100:.2f}% | WACC5: {w5*100:.2f}%")
    print(f"Net Debt: R$ {nd:,.0f} | Shares: {sh:,.0f}")
    print("Warnings 10y:")
    for w in d.get('warnings10', []):
        print(f"  * {w}")
    if d.get('warnings5') != d.get('warnings10'):
        print("Warnings 5y (different from 10y):")
        for w in d.get('warnings5', []):
            if w not in d.get('warnings10', []):
                print(f"  + {w}")
    print()

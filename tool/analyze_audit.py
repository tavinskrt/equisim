import json

with open('docs/validacao/audit_universe_comparison.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

evals = [d for d in data if d['outcome10'] == 'OK' and d['outcome5'] == 'OK']

print('=== TOP 20 UPSIDE (10Y) ===')
for d in sorted(evals, key=lambda x: x['upside10'], reverse=True)[:20]:
    t = d['ticker']
    u10 = d['upside10'] * 100
    u5 = d['upside5'] * 100
    diff = u5 - u10
    p = d['price']
    fv10 = d['fv10']
    fv5 = d['fv5']
    f10 = d.get('factor10', 1.0)
    f5 = d.get('factor5', 1.0)
    lane = d['lane10']
    sec = d.get('sector', '')
    print(f"{t:<8} 10y: {u10:6.1f}% | 5y: {u5:6.1f}% | Diff: {diff:6.1f}% | P: {p:6.2f} | FV10: {fv10:6.2f} | FV5: {fv5:6.2f} | F10: {f10} | F5: {f5} | {lane} | {sec}")

print('\n=== TOP 20 UPSIDE (5Y) ===')
for d in sorted(evals, key=lambda x: x['upside5'], reverse=True)[:20]:
    t = d['ticker']
    u10 = d['upside10'] * 100
    u5 = d['upside5'] * 100
    diff = u5 - u10
    p = d['price']
    fv10 = d['fv10']
    fv5 = d['fv5']
    f10 = d.get('factor10', 1.0)
    f5 = d.get('factor5', 1.0)
    lane = d['lane5']
    sec = d.get('sector', '')
    print(f"{t:<8} 5y: {u5:6.1f}% | 10y: {u10:6.1f}% | Diff: {diff:6.1f}% | P: {p:6.2f} | FV5: {fv5:6.2f} | FV10: {fv10:6.2f} | F5: {f5} | F10: {f10} | {lane} | {sec}")

print('\n=== TOP 20 DIVERGENCES (5Y vs 10Y) ===')
for d in sorted(evals, key=lambda x: abs(x['upside5'] - x['upside10']), reverse=True)[:20]:
    t = d['ticker']
    u10 = d['upside10'] * 100
    u5 = d['upside5'] * 100
    diff = u5 - u10
    p = d['price']
    fv10 = d['fv10']
    fv5 = d['fv5']
    f10 = d.get('factor10', 1.0)
    f5 = d.get('factor5', 1.0)
    lane10 = d['lane10']
    lane5 = d['lane5']
    print(f"{t:<8} 10y: {u10:6.1f}% | 5y: {u5:6.1f}% | Diff: {diff:6.1f}% | P: {p:6.2f} | FV10: {fv10:6.2f} | FV5: {fv5:6.2f} | F10: {f10} | F5: {f5} | {lane10} -> {lane5}")

print('\n=== TOP 20 WORST UPSIDE (10Y) ===')
for d in sorted(evals, key=lambda x: x['upside10'])[:20]:
    t = d['ticker']
    u10 = d['upside10'] * 100
    u5 = d['upside5'] * 100
    p = d['price']
    fv10 = d['fv10']
    lane = d['lane10']
    sec = d.get('sector', '')
    print(f"{t:<8} 10y: {u10:6.1f}% | 5y: {u5:6.1f}% | P: {p:6.2f} | FV10: {fv10:6.2f} | {lane} | {sec}")

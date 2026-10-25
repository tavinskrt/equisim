"""Tabelas dos casos de estudo, tiradas do rastro do motor e reconferidas.

Uso, da raiz do repositório, depois de `npm run tool -- study-cases`:

    python tool/tabelas_casos.py WEGE3 ITUB4 VALE3 SAPR11 RENT3

Imprime, em Markdown, as tabelas ano a ano que os casos de docs/estudo/casos/
reproduzem.

Cada linha é recalculada a partir das fórmulas do capítulo 4 e comparada com o
valor que o motor escreveu; divergência acima da tolerância aborta.
"""
import json
import math
import re
import sys

BASE = 'docs/estudo/casos/dados/'


def br(x, decimals=2):
    s = f'{x:,.{decimals}f}'
    return s.replace(',', 'X').replace('.', ',').replace('X', '.')


def pct(x, decimals=2):
    return br(x * 100, decimals) + '%'


def num(s):
    return float(s)


def step(trace, prefix):
    for c in trace['calculations']:
        if c['formulaName'].startswith(prefix):
            return c
    return None


def firm(t):
    d = json.load(open(BASE + t + '.json', encoding='utf-8'))
    r = d['rastro']
    proj = step(r, 'Projeção do fluxo da firma')
    desc = step(r, 'Fluxo do acionista e desconto')
    term = step(r, 'Valor terminal')
    bridge = step(r, 'Capital próprio pelo fluxo')
    out = []
    rx_p = re.compile(r'ano (\d+) → g = ([\d.\-]+)%, ROIC = ([\d.\-]+)%, retenção = ([\d.\-]+)%; NOPAT ([\d.\-e]+) × \(1 − retenção\) → fluxo da firma ([\d.\-e]+)')
    rx_d = re.compile(r'ano (\d+) → fluxo da firma ([\d.\-e]+) − serviço da dívida ([\d.\-e]+) = fluxo do acionista ([\d.\-e]+); K_e = ([\d.\-]+)%, fator acumulado ([\d.]+), levantamento ([\d.]+) → valor presente ([\d.\-e]+)')
    years = {}
    for s in proj['intermediateSteps']:
        m = rx_p.search(s)
        if m:
            a = int(m.group(1))
            years[a] = dict(g=num(m.group(2)) / 100, roic=num(m.group(3)) / 100,
                           b=num(m.group(4)) / 100, nopat=num(m.group(5)),
                           fcff=num(m.group(6)))
    for s in desc['intermediateSteps']:
        m = rx_d.search(s)
        if m:
            a = int(m.group(1))
            years[a].update(serv=num(m.group(3)), fcfe=num(m.group(4)),
                           ke=num(m.group(5)) / 100, fator=num(m.group(6)),
                           lev=num(m.group(7)), vp=num(m.group(8)))
    # Reconferência: FCFF = NOPAT(1−b) é aproximado pela retenção arredondada
    # a 0,1 p.p. no texto; FCFE = FCFF − serviço e VP = FCFE·lev/fator são
    # exatos a menos do arredondamento de 6 casas do fator.
    for a, v in years.items():
        assert abs(v['fcff'] - v['serv'] - v['fcfe']) < 1.0, (t, a)
        vp = v['fcfe'] * v['lev'] / v['fator']
        assert abs(vp - v['vp']) / abs(v['vp']) < 2e-6, (t, a, vp, v['vp'])
        assert abs(v['lev'] - math.sqrt(v['fator'] / (years[a - 1]['fator'] if a > 1 else 1.0))) < 2e-6, (t, a)
    million = 1e6
    out.append('| Ano | g | ROIC | Retenção | NOPAT (R$ mi) | Fluxo da firma (R$ mi) | Serviço da dívida (R$ mi) | Fluxo do acionista (R$ mi) | Ke | Fator acumulado | Meio de ano | Valor presente (R$ mi) |')
    out.append('|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|')
    total_sum = 0
    for a in sorted(years):
        v = years[a]
        total_sum += v['vp']
        out.append(f"| {a} | {pct(v['g'],1)} | {pct(v['roic'],1)} | {pct(v['b'],1)} | {br(v['nopat']/million,1)} | {br(v['fcff']/million,1)} | {br(v['serv']/million,1)} | {br(v['fcfe']/million,1)} | {pct(v['ke'],1)} | {br(v['fator'],4)} | {br(v['lev'],4)} | {br(v['vp']/million,1)} |")
    out.append(f'| **Soma** | | | | | | | | | | | **{br(total_sum/million,1)}** |')
    assert abs(total_sum - desc['finalValue']) < 5, (t, total_sum, desc['finalValue'])
    print(f'## {t} — tabela da via da firma\n')
    print('\n'.join(out))
    print('\nterminal:', json.dumps(term['mappedVariables'], ensure_ascii=False))
    for s in term['intermediateSteps']:
        print('  ', s)
    print('ponte:', json.dumps(bridge['mappedVariables'], ensure_ascii=False))
    print()


def equity(t):
    d = json.load(open(BASE + t + '.json', encoding='utf-8'))
    r = d['rastro']
    proj = step(r, 'Projeção e desconto do período explícito')
    rx = re.compile(r'ano (\d+) → g = ([\d.\-]+)%, retenção = ([\d.\-]+)%, K_e = ([\d.\-]+)%; lucro ([\d.\-]+) × \(1 − retenção\) = ([\d.\-]+) ÷ fator acumulado ([\d.]+) × levantamento ([\d.]+) → valor presente ([\d.\-]+)')
    out = ['| Ano | g | Retenção | Ke | LPA (R$) | Distribuível (R$) | Fator acumulado | Meio de ano | Valor presente (R$) |',
           '|---:|---:|---:|---:|---:|---:|---:|---:|---:|']
    total_sum = 0
    for s in proj['intermediateSteps']:
        m = rx.search(s)
        if not m:
            continue
        a = int(m.group(1))
        g, b, ke = num(m.group(2)) / 100, num(m.group(3)) / 100, num(m.group(4)) / 100
        eps, dist, factor, lev, vp = map(num, m.group(5, 6, 7, 8, 9))
        total_sum += vp
        out.append(f'| {a} | {pct(g,1)} | {pct(b,1)} | {pct(ke,1)} | {br(eps)} | {br(dist)} | {br(factor,4)} | {br(lev,4)} | {br(vp)} |')
    out.append(f'| **Soma** | | | | | | | | **{br(total_sum)}** |')
    print(f'## {t} — tabela da via do acionista\n')
    print('\n'.join(out))
    print()


for t in sys.argv[1:]:
    d = json.load(open(BASE + t + '.json', encoding='utf-8'))
    if d['resultado'] is None:
        print(f'## {t} — recusado: {d["recusa"]}\n')
    elif d['resultado']['modelo'] == 'dcfFcff':
        firm(t)
    else:
        equity(t)

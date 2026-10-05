"""O prêmio a mais das estatais no backtest: a posição delas e a ordenação (item B46).

Lê `docs/validacao/backtest_trimestral.json`, gerado com
`--premio-estatal 0.005,0.01,0.02,0.03`: cada observação de companhia de
controle estatal na data traz, em `potencialComPremioEstatal`, o potencial
recalculado com cada prêmio a mais no custo do capital próprio. Para cada
horizonte e cada prêmio, troca o potencial das estatais pelo da variante —
a observação que a variante recusa sai — e mede, coorte a coorte:

- o IC de Spearman do potencial contra o retorno total, no universo inteiro;
- a posição de cada estatal no retorno menos a posição no potencial, de 0 a 1
  — negativo é render abaixo do que o potencial ordenava;
- a diferença de potencial e de retorno entre estatais e privadas.

O controle é o de `assets/cvm/controle.json`, na data da coorte. O `t` é o
ingênuo, sem a correção pela sobreposição das janelas.

Uso, da raiz do repositório:

    python tool/estatais_backtest.py

Grava `docs/validacao/backtest_estatais.json`.
"""
import json
import math
import statistics as st
from collections import defaultdict

d = json.load(open('docs/validacao/backtest_trimestral.json', encoding='utf-8'))
controle = json.load(open('assets/cvm/controle.json', encoding='utf-8'))['emissores']


def estatal(ticker, data):
    p = controle.get(ticker[:4])
    if not p:
        return False
    vale = None
    for x in p:
        if x['desde'] <= data:
            vale = x['controle']
    return vale == 'state'


def postos(v):
    ordem = sorted(range(len(v)), key=lambda i: v[i])
    r = [0.0] * len(v)
    i = 0
    while i < len(v):
        j = i
        while j + 1 < len(v) and v[ordem[j + 1]] == v[ordem[i]]:
            j += 1
        for k in range(i, j + 1):
            r[ordem[k]] = (i + j) / 2
        i = j + 1
    return r


def spearman(a, b):
    ra, rb = postos(a), postos(b)
    ma, mb = st.mean(ra), st.mean(rb)
    num = sum((x - ma) * (y - mb) for x, y in zip(ra, rb))
    den = math.sqrt(sum((x - ma) ** 2 for x in ra) * sum((y - mb) ** 2 for y in rb))
    return num / den if den else float('nan')


variantes = [None, '0.005', '0.01', '0.02', '0.03']
saida = {}
for h, chave in [(12, 'ret12tot'), (36, 'ret36tot')]:
    for var in variantes:
        por = defaultdict(list)
        for r in d:
            if r.get('upside') is None or r.get(chave) is None:
                continue
            e = estatal(r['ticker'], r['coorte'])
            up = r['upside']
            if var is not None and e:
                alt = (r.get('potencialComPremioEstatal') or {}).get(var)
                if alt is None:
                    continue
                up = alt
            por[r['coorte']].append((e, up, r[chave]))
        ics, resid, difpot, difret, n_est = [], [], [], [], 0
        for c, obs in sorted(por.items()):
            if len(obs) < 30:
                continue
            ups = [o[1] for o in obs]
            rets = [o[2] for o in obs]
            ics.append(spearman(ups, rets))
            n = len(obs)
            rp, rr = postos(ups), postos(rets)
            es = [i for i, o in enumerate(obs) if o[0]]
            pr = [i for i, o in enumerate(obs) if not o[0]]
            n_est += len(es)
            for i in es:
                resid.append((rr[i] - rp[i]) / (n - 1))
            if len(es) >= 3:
                difpot.append(st.median(ups[i] for i in es) - st.median(ups[i] for i in pr))
                difret.append(st.median(rets[i] for i in es) - st.median(rets[i] for i in pr))
        tic = st.mean(ics) / (st.stdev(ics) / math.sqrt(len(ics)))
        rot = 'base' if var is None else f'+{float(var) * 100:.1f} p.p.'
        print(f'h{h} {rot:>10}: {len(ics)} coortes, IC médio {st.mean(ics):.4f} '
              f'(t ingênuo {tic:.2f}); estatais {n_est} obs, posição no retorno − no '
              f'potencial {st.mean(resid):+.3f}; potencial estatal − privada '
              f'{st.median(difpot):+.1%} ({sum(x > 0 for x in difpot)}/{len(difpot)}); '
              f'retorno estatal − privada {st.median(difret):+.1%} '
              f'({sum(x > 0 for x in difret)}/{len(difret)})')
        saida[f'h{h}_{rot}'] = {
            'coortes': len(ics), 'icMedio': st.mean(ics), 'tIngenuo': tic,
            'obsEstatais': n_est, 'residuoDaPosicao': st.mean(resid),
            'difPotencialMediana': st.median(difpot), 'difRetornoMediana': st.median(difret),
            'coortesEstatalAcimaNoPotencial': sum(x > 0 for x in difpot),
            'coortesEstatalAcimaNoRetorno': sum(x > 0 for x in difret),
            'coortesComparadas': len(difpot),
        }
json.dump(saida, open('docs/validacao/backtest_estatais.json', 'w', encoding='utf-8'),
          indent=1, ensure_ascii=False)
print('escrito docs/validacao/backtest_estatais.json')

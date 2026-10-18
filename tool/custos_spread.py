"""Spread de compra e venda por observação de coorte (item C4).

**O que mede.** O custo de ida e volta que um investidor pagaria para montar e
desmontar a posição de cada observação do backtest: a tarifa da B3 nos dois
lados e **meio spread** em cada ponta. O spread não é publicado papel a papel
na série histórica, e é estimado pelo método de **Abdi e Ranaldo (2017)**, que
o recupera do fechamento e do ponto médio entre máxima e mínima:

    s² = 4 · E[(c_t − η_t)(c_t − η_{t+1})]

com `c` o log do fechamento e `η` a média dos logs da máxima e da mínima. O
fechamento cai no preço de compra ou no de venda; o ponto médio, no meio deles;
e a covariância entre o desvio de hoje e o ponto médio de amanhã isola o meio
spread, descontada a volatilidade. Média nos 63 pregões até a data, e
covariância negativa vira spread zero.

**Por que não Corwin e Schultz (2012)**, que é o mais citado. Medido aqui em
22/09/2026, sobre as mesmas observações: a mediana dele sai **invertida** —
0,57% no tercil menos líquido contra 0,90% no mais líquido —, porque pregão com
um negócio só tem máxima igual à mínima e zera o par, e a volatilidade do papel
líquido entra como spread. O de Abdi e Ranaldo ordena como deve: **1,72%, 0,87%
e 0,42%** do menos ao mais líquido. Ele também superestima o papel muito
líquido — a PETR4 sai com 0,72%, contra um spread cotado de centésimos —, e por
isso o custo aqui é **conservador**: pune mais do que o investidor pagaria.

**A ponta da compra** é a data da coorte; **a da venda**, o último pregão até a
coorte mais o horizonte — que numa deslistada é o último pregão dela. Sem
spread estimável numa ponta, vale o da outra; sem nas duas, a mediana do tercil
de liquidez da coorte.

**O custo por ponta** é `tarifa + s/2`, com a tarifa de negociação e
liquidação da B3 para ações à vista: 0,005% + 0,025% = **0,030%**. Corretagem
fica em zero, que é o que as corretoras de varejo cobram em ações desde 2019.
O retorno líquido é `(1 + r)·(1 − c_compra)·(1 − c_venda) − 1`.

Grava `docs/validacao/custos_spread.json`, que `tool/regressao_condicional.dart
--custos` lê para medir a habilidade sobre o retorno líquido.

Uso:
    python tool/b3_baixar.py --extremos --de 2017   # máxima e mínima
    python tool/custos_spread.py
"""

from __future__ import annotations

import bisect
import calendar
import csv
import datetime as dt
import json
import math
import statistics as st
import sys
from pathlib import Path

B3_FEE = 0.0003          # negociação 0,005% + liquidação 0,025%, por ponta
WINDOW = 63                 # pregões: um trimestre
MIN_PAIRS = 20        # abaixo disso, o papel não tem spread estimável
JUMP = 0.4                 # |ln(C₂/C₁)| acima disso é evento, não pregão


def read_extremes(tickers: set[str]) -> dict[str, list[tuple]]:
    """Pregões por ticker: (data, máxima, mínima, fechamento, fator)."""
    out: dict[str, list[tuple]] = {}
    files = sorted(Path("data/b3").glob("extremos_*.csv"))
    if not files:
        print("Faltam data/b3/extremos_*.csv. Rode antes:\n"
              "  python tool/b3_baixar.py --extremos --de 2017", file=sys.stderr)
        sys.exit(2)
    for f in files:
        with f.open(encoding="utf-8") as h:
            for r in csv.DictReader(h, delimiter=";"):
                if r["ticker"] not in tickers:
                    continue
                hi, lo, c = int(r["maxima"]), int(r["minima"]), int(r["fechamento"])
                if hi <= 0 or lo <= 0 or c <= 0 or hi < lo:
                    continue
                out.setdefault(r["ticker"], []).append(
                    (r["data"], hi, lo, c, int(r["fatorCotacao"])))
    for v in out.values():
        v.sort()
    return out


def term(a: tuple, b: tuple) -> float | None:
    """`(c_t − η_t)(c_t − η_{t+1})` para dois pregões consecutivos."""
    _, h1, l1, c1, f1 = a
    _, h2, l2, c2, f2 = b
    if f1 != f2 or abs(math.log(c2 / c1)) > JUMP:
        return None
    c = math.log(c1)
    return ((c - (math.log(h1) + math.log(l1)) / 2)
            * (c - (math.log(h2) + math.log(l2)) / 2))


def spread_until(sessions: list[tuple], dates: list[str], until: str) -> float | None:
    """Spread de Abdi e Ranaldo nos `WINDOW` pregões até [until], inclusive."""
    end = bisect.bisect_right(dates, until)
    start = max(0, end - WINDOW)
    terms = [term(sessions[i - 1], sessions[i]) for i in range(start + 1, end)]
    terms = [x for x in terms if x is not None]
    if len(terms) < MIN_PAIRS:
        return None
    return math.sqrt(max(4 * st.mean(terms), 0.0))


def add_months(iso: str, months: int) -> str:
    d = dt.date.fromisoformat(iso)
    year, month = divmod(d.month - 1 + months, 12)
    year, month = d.year + year, month + 1
    return dt.date(year, month, min(d.day, calendar.monthrange(year, month)[1])).isoformat()


def main() -> int:
    source = Path("docs/validacao/backtest_trimestral.json")
    obs = json.loads(source.read_text(encoding="utf-8"))
    extremes = read_extremes({o["ticker"] for o in obs})
    dates = {t: [p[0] for p in v] for t, v in extremes.items()}

    raw: dict[str, dict] = {}
    for o in obs:
        t, c = o["ticker"], o["coorte"]
        sessions = extremes.get(t)
        line = {"compra": None, "venda12": None, "venda36": None}
        if sessions:
            line["compra"] = spread_until(sessions, dates[t], c)
            for h, months in (("venda12", 12), ("venda36", 36)):
                line[h] = spread_until(sessions, dates[t], add_months(c, months))
        raw[f"{c}|{t}"] = line

    # Recuo: sem spread numa ponta, o da outra; sem nas duas, a mediana do
    # tercil de liquidez da mesma coorte.
    by_cohort: dict[str, list] = {}
    for o in obs:
        by_cohort.setdefault(o["coorte"], []).append(o)
    tercile_median: dict[str, float] = {}
    for c, g in by_cohort.items():
        com = sorted((o for o in g if o.get("liquidez")), key=lambda o: o["liquidez"])
        for i, o in enumerate(com):
            o["_tercil"] = min(2, 3 * i // max(len(com), 1))
        for k in range(3):
            xs = [raw[f"{c}|{o['ticker']}"]["compra"] for o in com
                  if o["_tercil"] == k and raw[f"{c}|{o['ticker']}"]["compra"] is not None]
            if xs:
                tercile_median[f"{c}|{k}"] = st.median(xs)
    overall = st.median([v["compra"] for v in raw.values() if v["compra"] is not None])

    output: dict[str, dict] = {}
    fallbacks = {"outraPonta": 0, "tercil": 0, "geral": 0}
    for o in obs:
        k = f"{o['coorte']}|{o['ticker']}"
        v = raw[k]
        line = {}
        for h in ("12", "36"):
            buy, sell = v["compra"], v[f"venda{h}"]
            if buy is None and sell is None:
                m = tercile_median.get(f"{o['coorte']}|{o.get('_tercil')}")
                fallbacks["tercil" if m is not None else "geral"] += 1
                buy = sell = m if m is not None else overall
            elif buy is None or sell is None:
                fallbacks["outraPonta"] += 1
                buy = sell = buy if buy is not None else sell
            factor = (1 - B3_FEE - buy / 2) * (1 - B3_FEE - sell / 2)
            line[f"fator{h}"] = round(factor, 6)
        line.update({kk: (None if vv is None else round(vv, 6)) for kk, vv in v.items()})
        output[k] = line

    # --- resumo -------------------------------------------------------------
    buy = [v["compra"] for v in raw.values() if v["compra"] is not None]
    by_liquidity: dict[str, list[float]] = {"alta": [], "media": [], "baixa": []}
    liq = sorted(o["liquidez"] for o in obs if o.get("liquidez"))
    t1, t2 = liq[len(liq) // 3], liq[2 * len(liq) // 3]
    for o in obs:
        v = output.get(f"{o['coorte']}|{o['ticker']}", {}).get("compra")
        if v is None or not o.get("liquidez"):
            continue
        group = "baixa" if o["liquidez"] < t1 else "media" if o["liquidez"] < t2 else "alta"
        by_liquidity[group].append(v)

    def q(xs, p):
        xs = sorted(xs)
        return xs[int(p * (len(xs) - 1))] if xs else None

    summary = {
        "observacoes": len(obs),
        "comSpreadNaCompra": len(buy),
        "spreadNaCompra": {"p25": q(buy, .25), "mediana": q(buy, .5),
                           "p75": q(buy, .75), "p90": q(buy, .9)},
        "medianaPorTercilDeLiquidez": {k: q(v, .5) for k, v in by_liquidity.items()},
        "recuos": fallbacks,
        "custoIdaEVoltaMediano": {
            h: round(1 - st.median(v[f"fator{h}"] for v in output.values()), 6)
            for h in ("12", "36")},
        "tarifaB3PorPonta": B3_FEE,
        "janelaEmPregoes": WINDOW,
    }
    Path("docs/validacao/custos_spread.json").write_text(
        json.dumps({"medidoEm": dt.date.today().isoformat(), "resumo": summary,
                    "porObservacao": output}, ensure_ascii=False),
        encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())

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

TARIFA_B3 = 0.0003          # negociação 0,005% + liquidação 0,025%, por ponta
JANELA = 63                 # pregões: um trimestre
MINIMO_DE_PARES = 20        # abaixo disso, o papel não tem spread estimável
SALTO = 0.4                 # |ln(C₂/C₁)| acima disso é evento, não pregão


def ler_extremos(tickers: set[str]) -> dict[str, list[tuple]]:
    """Pregões por ticker: (data, máxima, mínima, fechamento, fator)."""
    out: dict[str, list[tuple]] = {}
    arquivos = sorted(Path("data/b3").glob("extremos_*.csv"))
    if not arquivos:
        print("Faltam data/b3/extremos_*.csv. Rode antes:\n"
              "  python tool/b3_baixar.py --extremos --de 2017", file=sys.stderr)
        sys.exit(2)
    for f in arquivos:
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


def termo(a: tuple, b: tuple) -> float | None:
    """`(c_t − η_t)(c_t − η_{t+1})` para dois pregões consecutivos."""
    _, h1, l1, c1, f1 = a
    _, h2, l2, c2, f2 = b
    if f1 != f2 or abs(math.log(c2 / c1)) > SALTO:
        return None
    c = math.log(c1)
    return ((c - (math.log(h1) + math.log(l1)) / 2)
            * (c - (math.log(h2) + math.log(l2)) / 2))


def spread_ate(pregoes: list[tuple], datas: list[str], ate: str) -> float | None:
    """Spread de Abdi e Ranaldo nos `JANELA` pregões até [ate], inclusive."""
    fim = bisect.bisect_right(datas, ate)
    ini = max(0, fim - JANELA)
    termos = [termo(pregoes[i - 1], pregoes[i]) for i in range(ini + 1, fim)]
    termos = [x for x in termos if x is not None]
    if len(termos) < MINIMO_DE_PARES:
        return None
    return math.sqrt(max(4 * st.mean(termos), 0.0))


def somar_meses(iso: str, meses: int) -> str:
    d = dt.date.fromisoformat(iso)
    ano, mes = divmod(d.month - 1 + meses, 12)
    ano, mes = d.year + ano, mes + 1
    return dt.date(ano, mes, min(d.day, calendar.monthrange(ano, mes)[1])).isoformat()


def main() -> int:
    fonte = Path("docs/validacao/backtest_trimestral.json")
    obs = json.loads(fonte.read_text(encoding="utf-8"))
    extremos = ler_extremos({o["ticker"] for o in obs})
    datas = {t: [p[0] for p in v] for t, v in extremos.items()}

    bruto: dict[str, dict] = {}
    for o in obs:
        t, c = o["ticker"], o["coorte"]
        pregoes = extremos.get(t)
        linha = {"compra": None, "venda12": None, "venda36": None}
        if pregoes:
            linha["compra"] = spread_ate(pregoes, datas[t], c)
            for h, meses in (("venda12", 12), ("venda36", 36)):
                linha[h] = spread_ate(pregoes, datas[t], somar_meses(c, meses))
        bruto[f"{c}|{t}"] = linha

    # Recuo: sem spread numa ponta, o da outra; sem nas duas, a mediana do
    # tercil de liquidez da mesma coorte.
    por_coorte: dict[str, list] = {}
    for o in obs:
        por_coorte.setdefault(o["coorte"], []).append(o)
    mediana_do_tercil: dict[str, float] = {}
    for c, g in por_coorte.items():
        com = sorted((o for o in g if o.get("liquidez")), key=lambda o: o["liquidez"])
        for i, o in enumerate(com):
            o["_tercil"] = min(2, 3 * i // max(len(com), 1))
        for k in range(3):
            xs = [bruto[f"{c}|{o['ticker']}"]["compra"] for o in com
                  if o["_tercil"] == k and bruto[f"{c}|{o['ticker']}"]["compra"] is not None]
            if xs:
                mediana_do_tercil[f"{c}|{k}"] = st.median(xs)
    geral = st.median([v["compra"] for v in bruto.values() if v["compra"] is not None])

    saida: dict[str, dict] = {}
    recuos = {"outraPonta": 0, "tercil": 0, "geral": 0}
    for o in obs:
        k = f"{o['coorte']}|{o['ticker']}"
        v = bruto[k]
        linha = {}
        for h in ("12", "36"):
            compra, venda = v["compra"], v[f"venda{h}"]
            if compra is None and venda is None:
                m = mediana_do_tercil.get(f"{o['coorte']}|{o.get('_tercil')}")
                recuos["tercil" if m is not None else "geral"] += 1
                compra = venda = m if m is not None else geral
            elif compra is None or venda is None:
                recuos["outraPonta"] += 1
                compra = venda = compra if compra is not None else venda
            fator = (1 - TARIFA_B3 - compra / 2) * (1 - TARIFA_B3 - venda / 2)
            linha[f"fator{h}"] = round(fator, 6)
        linha.update({kk: (None if vv is None else round(vv, 6)) for kk, vv in v.items()})
        saida[k] = linha

    # --- resumo -------------------------------------------------------------
    compra = [v["compra"] for v in bruto.values() if v["compra"] is not None]
    por_liquidez: dict[str, list[float]] = {"alta": [], "media": [], "baixa": []}
    liq = sorted(o["liquidez"] for o in obs if o.get("liquidez"))
    t1, t2 = liq[len(liq) // 3], liq[2 * len(liq) // 3]
    for o in obs:
        v = saida.get(f"{o['coorte']}|{o['ticker']}", {}).get("compra")
        if v is None or not o.get("liquidez"):
            continue
        grupo = "baixa" if o["liquidez"] < t1 else "media" if o["liquidez"] < t2 else "alta"
        por_liquidez[grupo].append(v)

    def q(xs, p):
        xs = sorted(xs)
        return xs[int(p * (len(xs) - 1))] if xs else None

    resumo = {
        "observacoes": len(obs),
        "comSpreadNaCompra": len(compra),
        "spreadNaCompra": {"p25": q(compra, .25), "mediana": q(compra, .5),
                           "p75": q(compra, .75), "p90": q(compra, .9)},
        "medianaPorTercilDeLiquidez": {k: q(v, .5) for k, v in por_liquidez.items()},
        "recuos": recuos,
        "custoIdaEVoltaMediano": {
            h: round(1 - st.median(v[f"fator{h}"] for v in saida.values()), 6)
            for h in ("12", "36")},
        "tarifaB3PorPonta": TARIFA_B3,
        "janelaEmPregoes": JANELA,
    }
    Path("docs/validacao/custos_spread.json").write_text(
        json.dumps({"medidoEm": dt.date.today().isoformat(), "resumo": resumo,
                    "porObservacao": saida}, ensure_ascii=False),
        encoding="utf-8")
    print(json.dumps(resumo, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())

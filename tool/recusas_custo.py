"""C0 — o que as recusas custam.

A §0 do plano achou que, nas observações que o motor recusa, o book-to-market
dá o maior spread de quintil de todos os recortes. Antes de ler isso como sinal
perdido, é preciso separar a cauda — recusado costuma ser pequeno e ilíquido —
do que a Porta 0 e as guardas descartam por excesso de zelo.

Três perguntas, por motivo de recusa:

1. **O B/M ordena o retorno dentro do grupo?** Spread de quintil e IC de
   Spearman por coorte, sobre o retorno total (decisão 89).
2. **É liquidez?** O mesmo, por tercil de volume financeiro mediano dentro dos
   recusados, contra o corte de R$ 2 milhões da Porta 0.
3. **Soltar a recusa daria ao motor o que o B/M tem?** Só a recusa por
   liquidez tem contrafactual sem mexer no núcleo: sem a série de cotações a
   Porta 0 omite o corte, e `tool/backtest-valuation.ts` grava o potencial
   que sairia. O IC dele, sozinho e condicionado ao B/M, é o que decide.
4. **É reversão do fechamento?** Sinal escalado pelo preço divide pelo mesmo
   fechamento em que o retorno começa. O retorno que começa um mês depois da
   coorte (``ret12totPulo``, ``ret36totPulo``) separa a reversão do sinal.

**Coortes por data (C1c).** A coorte é o ano ou a data ISO. O `t` de cada
IC sai de três jeitos: entre coortes, com Newey-West e corrigido pela estrutura
da sobreposição contra o crítico simulado dela (decisão 96), com a defasagem
`h/passo − 1` do passo das coortes da entrada — doze meses nas anuais, três nas
trimestrais.

Entrada: ``docs/validacao/backtest_trimestral.json``, de
``npm run tool -- backtest-valuation --montagem aplicativo --com-deslistadas
--trimestral``.

Uso:
    python tool/recusas_custo.py --grupo todas --saida docs/validacao/recusas_custo_trimestral.json
    python tool/recusas_custo.py --entrada docs/validacao/backtest_aplicativo.json   # o C0
"""

from __future__ import annotations

import datetime as dt
import json
import math
import statistics as st
from collections import defaultdict
from pathlib import Path

INPUT = Path("docs/validacao/backtest_trimestral.json")
OUTPUT = Path("docs/validacao/recusas_custo_trimestral.json")
LIQUIDITY_CUTOFF = 2_000_000.0


# --------------------------------------------------------------- estatística


def ranks(v: list[float]) -> list[float]:
    idx = sorted(range(len(v)), key=lambda i: v[i])
    r = [0.0] * len(v)
    i = 0
    while i < len(idx):
        j = i
        # Empate é valor igual até a precisão da máquina — e não `==` entre
        # floats, que a regra do projeto veda.
        while j + 1 < len(idx) and math.isclose(v[idx[j + 1]], v[idx[i]], rel_tol=1e-12, abs_tol=0.0):
            j += 1
        for k in range(i, j + 1):
            r[idx[k]] = (i + j) / 2 + 1
        i = j + 1
    return r


def spearman(a: list[float], b: list[float]) -> float | None:
    if len(a) < 8:
        return None
    ra, rb = ranks(a), ranks(b)
    ma, mb = st.mean(ra), st.mean(rb)
    num = sum((x - ma) * (y - mb) for x, y in zip(ra, rb))
    den = math.sqrt(sum((x - ma) ** 2 for x in ra) * sum((y - mb) ** 2 for y in rb))
    return num / den if den > 0 else None


def residual(y: list[float], x: list[float]) -> list[float]:
    """Resíduo de ``y`` contra ``x`` em postos — o que ``y`` ordena além de ``x``."""
    ry, rx = ranks(y), ranks(x)
    mx, my = st.mean(rx), st.mean(ry)
    sxx = sum((v - mx) ** 2 for v in rx)
    b = sum((u - mx) * (w - my) for u, w in zip(rx, ry)) / sxx if sxx > 0 else 0.0
    return [w - my - b * (u - mx) for u, w in zip(rx, ry)]


def t_newey_west(v: list[float], lag: int) -> float | None:
    """`t` da média com Newey-West e núcleo de Bartlett (item C1a).

    A mesma conta de `Regression.neweyWestMean` em `tool/validation/regression.ts`:
    com o fator `k/(k−1)`, defasagem zero é o `t` entre coortes de sempre.
    """
    k = len(v)
    if k < 2:
        return None
    m = sum(v) / k
    lags = min(lag, k - 1)

    def gamma(j):
        return sum((v[t] - m) * (v[t - j] - m) for t in range(j, k)) / k

    lrv = gamma(0) + sum(2 * (1 - j / (lags + 1)) * gamma(j) for j in range(1, lags + 1))
    var = lrv / k * k / (k - 1)
    return m / math.sqrt(var) if var > 0 else None


class SplitMix64:
    """O gerador de `SplitMix64` em `tool/validation/regression.ts`, bit a bit."""

    M = (1 << 64) - 1

    def __init__(self, seed: int):
        self.x = seed & self.M

    def next_int(self) -> int:
        self.x = (self.x + 0x9E3779B97F4A7C15) & self.M
        z = self.x
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & self.M
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & self.M
        return z ^ (z >> 31)

    def next_double(self) -> float:
        return (self.next_int() >> 11) * (1.0 / 9007199254740992)


# Nível unilateral de t > 2 sob a normal, e a nula simulada da sobreposição, com
# a mesma semente e o mesmo número de séries de `Regression.overlapNull`.
R3_TAIL = 0.022750131948179195
_NULLS: dict = {}


def overlap_t(v: list[float], overlap: int) -> float | None:
    """`Regression.overlapAdjustedT`: o t entre coortes vezes √(c/F)."""
    k = len(v)
    if k < 2 or overlap < 0:
        return None
    m = sum(v) / k
    sd = math.sqrt(sum((x - m) ** 2 for x in v) / (k - 1))
    if not sd > 0:
        return None
    l = min(overlap, k - 1)
    sum_c = sum((k - j) * (1 - j / (l + 1)) for j in range(1, l + 1))
    sum_f = sum((1 - j / k) * (1 - j / (l + 1)) for j in range(1, l + 1))
    c = 1 - 2 / (k * (k - 1)) * sum_c
    f = 1 + 2 * sum_f
    if not (c > 0 and f > 0):
        return None
    return m / (sd / math.sqrt(k)) * math.sqrt(c / f)


def overlap_null(k: int, overlap: int, series: int = 20000, rng_seed: int = 20260915) -> list[float]:
    l = min(overlap, k - 1)
    key = (k, l, series, rng_seed)
    if key not in _NULLS:
        g = SplitMix64(rng_seed)
        out = []
        while len(out) < series:
            shocks = []
            for _ in range(k + l):
                u = 1 - g.next_double()
                w = g.next_double()
                shocks.append(math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * w))
            path_sums = [sum(shocks[t:t + l + 1]) for t in range(k)]
            t = overlap_t(path_sums, l)
            if t is not None and math.isfinite(t):
                out.append(t)
        _NULLS[key] = sorted(out)
    return _NULLS[key]


def overlap_critical(k: int, overlap: int) -> float:
    null = overlap_null(k, overlap)
    return null[min(max(int(math.floor((1 - R3_TAIL) * len(null))), 0), len(null) - 1)]


def cohort_date(c) -> dt.date:
    return dt.date(c, 9, 30) if isinstance(c, int) else dt.date.fromisoformat(str(c))


def step_in_months(lines: list[dict]) -> int:
    """O menor intervalo entre coortes da entrada: 12 nas anuais, 3 nas trimestrais."""
    dates = sorted({cohort_date(l["coorte"]) for l in lines})
    steps = [(b.year - a.year) * 12 + b.month - a.month for a, b in zip(dates, dates[1:])]
    return min(steps) if steps else 12


STEP = 12


def ic_summary(by_cohort: dict, lag: int = 0) -> dict:
    ordered = [by_cohort[c] for c in sorted(by_cohort) if by_cohort[c] is not None]
    v = ordered
    if not v:
        return {"coortes": 0}
    mean = st.mean(v)
    t = None
    if len(v) >= 3 and st.stdev(v) > 0:
        t = mean / (st.stdev(v) / math.sqrt(len(v)))
    t_nw = t_newey_west(v, lag) if len(v) >= 3 else None
    t_overlap = overlap_t(v, lag) if len(v) >= 3 else None
    critical = overlap_critical(len(v), lag) if t_overlap is not None else None
    return {
        "coortes": len(v),
        "icMedio": round(mean, 4),
        "tEntreCoortes": None if t is None else round(t, 2),
        "tNeweyWest": None if t_nw is None else round(t_nw, 2),
        "tSobreposicao": None if t_overlap is None else round(t_overlap, 2),
        "criticoSobreposicao": None if critical is None else round(critical, 2),
        "defasagem": min(lag, max(len(v) - 1, 0)),
        "positivas": sum(1 for x in v if x > 0),
        "porCoorte": {str(k): round(x, 4) for k, x in sorted(by_cohort.items()) if x is not None},
    }


def spread_quintile(lines: list[dict], signal: str, ret: str) -> float | None:
    """Média, entre coortes, do retorno do quintil superior menos o inferior."""
    spreads = []
    by_group = defaultdict(list)
    for l in lines:
        if l.get(signal) is not None and l.get(ret) is not None:
            by_group[l["coorte"]].append(l)
    for g in by_group.values():
        if len(g) < 10:
            continue
        g = sorted(g, key=lambda l: l[signal])
        n = len(g) // 5
        low = [l[ret] for l in g[:n]]
        high = [l[ret] for l in g[-n:]]
        spreads.append(st.mean(high) - st.mean(low))
    return round(st.mean(spreads), 4) if spreads else None


def measure_signal(lines: list[dict], signal: str, ret: str, control: str | None = None) -> dict:
    by_group = defaultdict(list)
    for l in lines:
        if l.get(signal) is None or l.get(ret) is None:
            continue
        if control is not None and l.get(control) is None:
            continue
        by_group[l["coorte"]].append(l)
    ics = {}
    for c, g in by_group.items():
        s = [l[signal] for l in g]
        r = [l[ret] for l in g]
        if control is not None:
            s = residual(s, [l[control] for l in g])
        ics[c] = spearman(s, r)
    # A janela de h meses sobrepõe as h/passo − 1 coortes seguintes.
    months = 36 if ret.startswith("ret36") else 12
    out = ic_summary(ics, lag=max(months // STEP - 1, 0))
    out["n"] = sum(len(g) for g in by_group.values())
    if control is None:
        out["spreadQuintil"] = spread_quintile(lines, signal, ret)
    return out


# ------------------------------------------------------------------ motivos


def reason(l: dict) -> str:
    m = l.get("recusa")
    if l.get("upside") is not None:
        return "avaliado"
    if m is None:
        return "sem mensagem"
    if m.startswith("Ativo fora do universo analisável"):
        ratios = [r.strip().rstrip(".") for r in m.split(":", 1)[1].split(";")]
        keys = []
        for r in ratios:
            if r.startswith("liquidez"):
                keys.append("liquidez")
            elif r.startswith("histórico"):
                keys.append("histórico curto")
            elif r.startswith("patrimônio"):
                keys.append("patrimônio não positivo")
            else:
                keys.append(r)
        if keys == ["liquidez"]:
            return "Porta 0 — só liquidez"
        if keys == ["histórico curto"]:
            return "Porta 0 — só histórico curto"
        if keys == ["patrimônio não positivo"]:
            return "Porta 0 — só patrimônio não positivo"
        return "Porta 0 — mais de um motivo"
    if "não sustenta a via" in m:
        return "estrutura de capital recusada"
    if "capital próprio responde por apenas" in m:
        return "ponte frágil sem via do acionista"
    # Desde a decisão 102 a via da firma avalia pelo fluxo do acionista
    # derivado, e não migra: o capital próprio não positivo é recusa própria, e
    # absorve a "ponte frágil" das execuções anteriores.
    if "derivado do da firma, não sustenta capital próprio positivo" in m:
        return "capital próprio não positivo pela firma"
    if "não sustentam nenhuma das duas vias" in m:
        return "nenhuma via aplicável"
    if "Nenhum exercício" in m:
        return "nenhum exercício divulgado"
    if "sem demonstração de resultado" in m:
        return "exercícios sem resultado"
    if "contagem de papéis" in m:
        return "sem contagem de papéis"
    raise SystemExit(f"motivo de recusa sem família: {m[:120]}")


def main() -> None:
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--entrada", type=Path, default=INPUT)
    ap.add_argument("--saida", type=Path, default=OUTPUT)
    # C0b: com as deslistadas na entrada, o grupo diz quais linhas medir — as
    # listadas repetem o C0 na mesma execução, e `todas` é a amostra sem viés.
    ap.add_argument("--grupo", choices=("todas", "listadas", "deslistadas"), default="todas")
    args = ap.parse_args()
    global STEP
    lines = json.loads(args.entrada.read_text(encoding="utf-8"))
    STEP = step_in_months(lines)
    if args.grupo == "listadas":
        lines = [l for l in lines if not l.get("deslistada")]
    elif args.grupo == "deslistadas":
        lines = [l for l in lines if l.get("deslistada")]
    for l in lines:
        l["motivo"] = reason(l)
    groups = defaultdict(list)
    for l in lines:
        groups[l["motivo"]].append(l)
    refused = [l for l in lines if l["upside"] is None]

    output: dict = {"entrada": args.entrada.as_posix(), "grupo": args.grupo,
                   "passoEmMeses": STEP, "observacoes": len(lines), "motivos": {}}
    print(f"observações: {len(lines)}   avaliadas: {len(groups['avaliado'])}   "
          f"recusadas: {len(refused)}\n")

    def line_of(name: str, g: list[dict]) -> dict:
        liq = [l["liquidez"] for l in g if l.get("liquidez") is not None]
        d = {
            "n": len(g),
            "liquidezMediana": round(st.median(liq)) if liq else None,
            "acimaDoCorte": sum(1 for x in liq if x >= LIQUIDITY_CUTOFF),
        }
        for h in (12, 36):
            d[f"bm{h}"] = measure_signal(g, "bookToMarket", f"ret{h}tot")
        return d

    all_groups = {"avaliado": groups["avaliado"], "todos os recusados": refused}
    for k in sorted(groups):
        if k != "avaliado":
            all_groups[k] = groups[k]
    print(f"{'grupo':42s} {'n':>5s} {'liq. med.':>11s} | "
          f"{'IC B/M 12m':>10s} {'t':>6s} {'Q5−Q1':>7s} | {'IC B/M 36m':>10s} {'t':>6s} {'Q5−Q1':>7s}")
    for name, g in all_groups.items():
        d = line_of(name, g)
        output["motivos"][name] = d

        def f(x, p=3):
            return "—" if x is None else f"{x:.{p}f}"

        b12, b36 = d["bm12"], d["bm36"]
        print(f"{name:42s} {d['n']:5d} {f(d['liquidezMediana'] and d['liquidezMediana'] / 1e6, 2):>9s}mi | "
              f"{f(b12.get('icMedio')):>10s} {f(b12.get('tEntreCoortes'), 2):>6s} {f(b12.get('spreadQuintil')):>7s} | "
              f"{f(b36.get('icMedio')):>10s} {f(b36.get('tEntreCoortes'), 2):>6s} {f(b36.get('spreadQuintil')):>7s}")

    # Liquidez: terciles dentro dos recusados.
    print("\n== B/M nos recusados, por tercil de liquidez ==")
    with_liq = sorted((l for l in refused if l.get("liquidez") is not None),
                     key=lambda l: l["liquidez"])
    terciles = [with_liq[: len(with_liq) // 3], with_liq[len(with_liq) // 3: 2 * len(with_liq) // 3],
            with_liq[2 * len(with_liq) // 3:]]
    output["tercisDeLiquidez"] = []
    for i, g in enumerate(terciles):
        liquidity_range = (g[0]["liquidez"], g[-1]["liquidez"])
        d = {"faixa": [round(liquidity_range[0]), round(liquidity_range[1])], "n": len(g),
             "bm12": measure_signal(g, "bookToMarket", "ret12tot"),
             "bm36": measure_signal(g, "bookToMarket", "ret36tot")}
        output["tercisDeLiquidez"].append(d)
        print(f"  tercil {i + 1}: R$ {liquidity_range[0] / 1e3:,.0f} mil a R$ {liquidity_range[1] / 1e3:,.0f} mil, n={len(g)}: "
              f"IC 12m {d['bm12'].get('icMedio')} (t {d['bm12'].get('tEntreCoortes')}), "
              f"Q5−Q1 12m {d['bm12'].get('spreadQuintil')}; "
              f"IC 36m {d['bm36'].get('icMedio')} (t {d['bm36'].get('tEntreCoortes')}), "
              f"Q5−Q1 36m {d['bm36'].get('spreadQuintil')}")

    # Contrafactual: o motor sem o corte de liquidez.
    print("\n== Contrafactual: o potencial sem o corte de liquidez ==")
    loose = [l for l in refused if l.get("upsideSemLiquidez") is not None]
    only_liq = [l for l in loose if l["motivo"] == "Porta 0 — só liquidez"]
    for l in loose:
        l["upsideSolto"] = l["upsideSemLiquidez"]
    for l in groups["avaliado"]:
        l["upsideSolto"] = l["upside"]
    output["contrafactual"] = {}
    for name, g in [("avaliados (referência)", groups["avaliado"]),
                    ("recusados só por liquidez, soltos", only_liq)]:
        no_trade_days = [l["semNegocio"] for l in g if l.get("semNegocio") is not None]
        d = {"n": len(g), "semNegocioMediano": round(st.median(no_trade_days), 3) if no_trade_days else None}
        print(f"  {name} (n={len(g)}, pregões sem negócio na janela: "
              f"{d['semNegocioMediano']} na mediana)")
        for suffix, label in (("", "da data da coorte"), ("Pulo", "começando um mês depois")):
            for h in (12, 36):
                ret = f"ret{h}tot{suffix}"
                key = f"{h}{suffix}"
                d[f"motor{key}"] = measure_signal(g, "upsideSolto", ret)
                d[f"bm{key}"] = measure_signal(g, "bookToMarket", ret)
                d[f"motorDadoBm{key}"] = measure_signal(g, "upsideSolto", ret, control="bookToMarket")
                print(f"    {h}m {label}: motor IC {d[f'motor{key}'].get('icMedio')} "
                      f"(t {d[f'motor{key}'].get('tEntreCoortes')}, Q5−Q1 {d[f'motor{key}'].get('spreadQuintil')})   "
                      f"B/M IC {d[f'bm{key}'].get('icMedio')} (t {d[f'bm{key}'].get('tEntreCoortes')}, "
                      f"Q5−Q1 {d[f'bm{key}'].get('spreadQuintil')})   motor dado B/M IC "
                      f"{d[f'motorDadoBm{key}'].get('icMedio')} (t {d[f'motorDadoBm{key}'].get('tEntreCoortes')}, "
                      f"t_NW {d[f'motorDadoBm{key}'].get('tNeweyWest')}, t_sob "
                      f"{d[f'motorDadoBm{key}'].get('tSobreposicao')}/{d[f'motorDadoBm{key}'].get('criticoSobreposicao')})")
        output["contrafactual"][name] = d

    # O mesmo pulo sobre o B/M, por motivo: o spread que sobrevive ao mês.
    print("\n== B/M por motivo, com o retorno começando um mês depois ==")
    output["bmPulandoUmMes"] = {}
    for name, g in all_groups.items():
        d = {h: measure_signal(g, "bookToMarket", f"ret{h}totPulo") for h in (12, 36)}
        output["bmPulandoUmMes"][name] = d
        print(f"  {name:42s} 12m IC {d[12].get('icMedio')} (t {d[12].get('tEntreCoortes')}, Q5−Q1 {d[12].get('spreadQuintil')})"
              f"   36m IC {d[36].get('icMedio')} (t {d[36].get('tEntreCoortes')}, Q5−Q1 {d[36].get('spreadQuintil')})")

    args.saida.write_text(json.dumps(output, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"\ngravado {args.saida}")


if __name__ == "__main__":
    main()

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
   Porta 0 omite o corte, e `tool/backtest_valuation.dart` grava o potencial
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
``dart run tool/backtest_valuation.dart --montagem aplicativo --com-deslistadas
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

ENTRADA = Path("docs/validacao/backtest_trimestral.json")
SAIDA = Path("docs/validacao/recusas_custo_trimestral.json")
CORTE_LIQUIDEZ = 2_000_000.0


# --------------------------------------------------------------- estatística


def postos(v: list[float]) -> list[float]:
    idx = sorted(range(len(v)), key=lambda i: v[i])
    r = [0.0] * len(v)
    i = 0
    while i < len(idx):
        j = i
        while j + 1 < len(idx) and v[idx[j + 1]] == v[idx[i]]:
            j += 1
        for k in range(i, j + 1):
            r[idx[k]] = (i + j) / 2 + 1
        i = j + 1
    return r


def spearman(a: list[float], b: list[float]) -> float | None:
    if len(a) < 8:
        return None
    ra, rb = postos(a), postos(b)
    ma, mb = st.mean(ra), st.mean(rb)
    num = sum((x - ma) * (y - mb) for x, y in zip(ra, rb))
    den = math.sqrt(sum((x - ma) ** 2 for x in ra) * sum((y - mb) ** 2 for y in rb))
    return num / den if den > 0 else None


def residuo(y: list[float], x: list[float]) -> list[float]:
    """Resíduo de ``y`` contra ``x`` em postos — o que ``y`` ordena além de ``x``."""
    ry, rx = postos(y), postos(x)
    mx, my = st.mean(rx), st.mean(ry)
    sxx = sum((v - mx) ** 2 for v in rx)
    b = sum((u - mx) * (w - my) for u, w in zip(rx, ry)) / sxx if sxx > 0 else 0.0
    return [w - my - b * (u - mx) for u, w in zip(rx, ry)]


def t_newey_west(v: list[float], defasagem: int) -> float | None:
    """`t` da média com Newey-West e núcleo de Bartlett (item C1a).

    A mesma conta de `Regression.neweyWestMean` em `tool/validation/regression.dart`:
    com o fator `k/(k−1)`, defasagem zero é o `t` entre coortes de sempre.
    """
    k = len(v)
    if k < 2:
        return None
    m = sum(v) / k
    lags = min(defasagem, k - 1)

    def gama(j):
        return sum((v[t] - m) * (v[t - j] - m) for t in range(j, k)) / k

    lrv = gama(0) + sum(2 * (1 - j / (lags + 1)) * gama(j) for j in range(1, lags + 1))
    var = lrv / k * k / (k - 1)
    return m / math.sqrt(var) if var > 0 else None


class SplitMix64:
    """O gerador de `SplitMix64` em `tool/validation/regression.dart`, bit a bit."""

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
R3_CAUDA = 0.022750131948179195
_NULAS: dict = {}


def t_sobreposicao(v: list[float], sobreposicao: int) -> float | None:
    """`Regression.overlapAdjustedT`: o t entre coortes vezes √(c/F)."""
    k = len(v)
    if k < 2 or sobreposicao < 0:
        return None
    m = sum(v) / k
    sd = math.sqrt(sum((x - m) ** 2 for x in v) / (k - 1))
    if not sd > 0:
        return None
    l = min(sobreposicao, k - 1)
    soma_c = sum((k - j) * (1 - j / (l + 1)) for j in range(1, l + 1))
    soma_f = sum((1 - j / k) * (1 - j / (l + 1)) for j in range(1, l + 1))
    c = 1 - 2 / (k * (k - 1)) * soma_c
    f = 1 + 2 * soma_f
    if not (c > 0 and f > 0):
        return None
    return m / (sd / math.sqrt(k)) * math.sqrt(c / f)


def nula_sobreposicao(k: int, sobreposicao: int, series: int = 20000, semente: int = 20260915) -> list[float]:
    l = min(sobreposicao, k - 1)
    chave = (k, l, series, semente)
    if chave not in _NULAS:
        g = SplitMix64(semente)
        out = []
        while len(out) < series:
            choques = []
            for _ in range(k + l):
                u = 1 - g.next_double()
                w = g.next_double()
                choques.append(math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * w))
            serie = [sum(choques[t:t + l + 1]) for t in range(k)]
            t = t_sobreposicao(serie, l)
            if t is not None and math.isfinite(t):
                out.append(t)
        _NULAS[chave] = sorted(out)
    return _NULAS[chave]


def critico_sobreposicao(k: int, sobreposicao: int) -> float:
    nula = nula_sobreposicao(k, sobreposicao)
    return nula[min(max(int(math.floor((1 - R3_CAUDA) * len(nula))), 0), len(nula) - 1)]


def data_da_coorte(c) -> dt.date:
    return dt.date(c, 9, 30) if isinstance(c, int) else dt.date.fromisoformat(str(c))


def passo_em_meses(linhas: list[dict]) -> int:
    """O menor intervalo entre coortes da entrada: 12 nas anuais, 3 nas trimestrais."""
    datas = sorted({data_da_coorte(l["coorte"]) for l in linhas})
    passos = [(b.year - a.year) * 12 + b.month - a.month for a, b in zip(datas, datas[1:])]
    return min(passos) if passos else 12


PASSO = 12


def resumo_ic(por_coorte: dict, defasagem: int = 0) -> dict:
    ordenadas = [por_coorte[c] for c in sorted(por_coorte) if por_coorte[c] is not None]
    v = ordenadas
    if not v:
        return {"coortes": 0}
    media = st.mean(v)
    t = None
    if len(v) >= 3 and st.stdev(v) > 0:
        t = media / (st.stdev(v) / math.sqrt(len(v)))
    tnw = t_newey_west(v, defasagem) if len(v) >= 3 else None
    tsob = t_sobreposicao(v, defasagem) if len(v) >= 3 else None
    critico = critico_sobreposicao(len(v), defasagem) if tsob is not None else None
    return {
        "coortes": len(v),
        "icMedio": round(media, 4),
        "tEntreCoortes": None if t is None else round(t, 2),
        "tNeweyWest": None if tnw is None else round(tnw, 2),
        "tSobreposicao": None if tsob is None else round(tsob, 2),
        "criticoSobreposicao": None if critico is None else round(critico, 2),
        "defasagem": min(defasagem, max(len(v) - 1, 0)),
        "positivas": sum(1 for x in v if x > 0),
        "porCoorte": {str(k): round(x, 4) for k, x in sorted(por_coorte.items()) if x is not None},
    }


def spread_quintil(linhas: list[dict], sinal: str, ret: str) -> float | None:
    """Média, entre coortes, do retorno do quintil superior menos o inferior."""
    spreads = []
    por = defaultdict(list)
    for l in linhas:
        if l.get(sinal) is not None and l.get(ret) is not None:
            por[l["coorte"]].append(l)
    for g in por.values():
        if len(g) < 10:
            continue
        g = sorted(g, key=lambda l: l[sinal])
        n = len(g) // 5
        baixo = [l[ret] for l in g[:n]]
        alto = [l[ret] for l in g[-n:]]
        spreads.append(st.mean(alto) - st.mean(baixo))
    return round(st.mean(spreads), 4) if spreads else None


def medir(linhas: list[dict], sinal: str, ret: str, controle: str | None = None) -> dict:
    por = defaultdict(list)
    for l in linhas:
        if l.get(sinal) is None or l.get(ret) is None:
            continue
        if controle is not None and l.get(controle) is None:
            continue
        por[l["coorte"]].append(l)
    ics = {}
    for c, g in por.items():
        s = [l[sinal] for l in g]
        r = [l[ret] for l in g]
        if controle is not None:
            s = residuo(s, [l[controle] for l in g])
        ics[c] = spearman(s, r)
    # A janela de h meses sobrepõe as h/passo − 1 coortes seguintes.
    meses = 36 if ret.startswith("ret36") else 12
    out = resumo_ic(ics, defasagem=max(meses // PASSO - 1, 0))
    out["n"] = sum(len(g) for g in por.values())
    if controle is None:
        out["spreadQuintil"] = spread_quintil(linhas, sinal, ret)
    return out


# ------------------------------------------------------------------ motivos


def motivo(l: dict) -> str:
    m = l.get("recusa")
    if l.get("upside") is not None:
        return "avaliado"
    if m is None:
        return "sem mensagem"
    if m.startswith("Ativo fora do universo analisável"):
        razoes = [r.strip().rstrip(".") for r in m.split(":", 1)[1].split(";")]
        chaves = []
        for r in razoes:
            if r.startswith("liquidez"):
                chaves.append("liquidez")
            elif r.startswith("histórico"):
                chaves.append("histórico curto")
            elif r.startswith("patrimônio"):
                chaves.append("patrimônio não positivo")
            else:
                chaves.append(r)
        if chaves == ["liquidez"]:
            return "Porta 0 — só liquidez"
        if chaves == ["histórico curto"]:
            return "Porta 0 — só histórico curto"
        if chaves == ["patrimônio não positivo"]:
            return "Porta 0 — só patrimônio não positivo"
        return "Porta 0 — mais de um motivo"
    if "não sustenta a via" in m:
        return "estrutura de capital recusada"
    if "capital próprio responde por apenas" in m:
        return "ponte frágil sem via do acionista"
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
    ap.add_argument("--entrada", type=Path, default=ENTRADA)
    ap.add_argument("--saida", type=Path, default=SAIDA)
    # C0b: com as deslistadas na entrada, o grupo diz quais linhas medir — as
    # listadas repetem o C0 na mesma execução, e `todas` é a amostra sem viés.
    ap.add_argument("--grupo", choices=("todas", "listadas", "deslistadas"), default="todas")
    args = ap.parse_args()
    global PASSO
    linhas = json.loads(args.entrada.read_text(encoding="utf-8"))
    PASSO = passo_em_meses(linhas)
    if args.grupo == "listadas":
        linhas = [l for l in linhas if not l.get("deslistada")]
    elif args.grupo == "deslistadas":
        linhas = [l for l in linhas if l.get("deslistada")]
    for l in linhas:
        l["motivo"] = motivo(l)
    grupos = defaultdict(list)
    for l in linhas:
        grupos[l["motivo"]].append(l)
    recusados = [l for l in linhas if l["upside"] is None]

    saida: dict = {"entrada": args.entrada.as_posix(), "grupo": args.grupo,
                   "passoEmMeses": PASSO, "observacoes": len(linhas), "motivos": {}}
    print(f"observações: {len(linhas)}   avaliadas: {len(grupos['avaliado'])}   "
          f"recusadas: {len(recusados)}\n")

    def linha_de(nome: str, g: list[dict]) -> dict:
        liq = [l["liquidez"] for l in g if l.get("liquidez") is not None]
        d = {
            "n": len(g),
            "liquidezMediana": round(st.median(liq)) if liq else None,
            "acimaDoCorte": sum(1 for x in liq if x >= CORTE_LIQUIDEZ),
        }
        for h in (12, 36):
            d[f"bm{h}"] = medir(g, "bookToMarket", f"ret{h}tot")
        return d

    todos = {"avaliado": grupos["avaliado"], "todos os recusados": recusados}
    for k in sorted(grupos):
        if k != "avaliado":
            todos[k] = grupos[k]
    print(f"{'grupo':42s} {'n':>5s} {'liq. med.':>11s} | "
          f"{'IC B/M 12m':>10s} {'t':>6s} {'Q5−Q1':>7s} | {'IC B/M 36m':>10s} {'t':>6s} {'Q5−Q1':>7s}")
    for nome, g in todos.items():
        d = linha_de(nome, g)
        saida["motivos"][nome] = d

        def f(x, p=3):
            return "—" if x is None else f"{x:.{p}f}"

        b12, b36 = d["bm12"], d["bm36"]
        print(f"{nome:42s} {d['n']:5d} {f(d['liquidezMediana'] and d['liquidezMediana'] / 1e6, 2):>9s}mi | "
              f"{f(b12.get('icMedio')):>10s} {f(b12.get('tEntreCoortes'), 2):>6s} {f(b12.get('spreadQuintil')):>7s} | "
              f"{f(b36.get('icMedio')):>10s} {f(b36.get('tEntreCoortes'), 2):>6s} {f(b36.get('spreadQuintil')):>7s}")

    # Liquidez: terciles dentro dos recusados.
    print("\n== B/M nos recusados, por tercil de liquidez ==")
    com_liq = sorted((l for l in recusados if l.get("liquidez") is not None),
                     key=lambda l: l["liquidez"])
    terc = [com_liq[: len(com_liq) // 3], com_liq[len(com_liq) // 3: 2 * len(com_liq) // 3],
            com_liq[2 * len(com_liq) // 3:]]
    saida["tercisDeLiquidez"] = []
    for i, g in enumerate(terc):
        faixa = (g[0]["liquidez"], g[-1]["liquidez"])
        d = {"faixa": [round(faixa[0]), round(faixa[1])], "n": len(g),
             "bm12": medir(g, "bookToMarket", "ret12tot"),
             "bm36": medir(g, "bookToMarket", "ret36tot")}
        saida["tercisDeLiquidez"].append(d)
        print(f"  tercil {i + 1}: R$ {faixa[0] / 1e3:,.0f} mil a R$ {faixa[1] / 1e3:,.0f} mil, n={len(g)}: "
              f"IC 12m {d['bm12'].get('icMedio')} (t {d['bm12'].get('tEntreCoortes')}), "
              f"Q5−Q1 12m {d['bm12'].get('spreadQuintil')}; "
              f"IC 36m {d['bm36'].get('icMedio')} (t {d['bm36'].get('tEntreCoortes')}), "
              f"Q5−Q1 36m {d['bm36'].get('spreadQuintil')}")

    # Contrafactual: o motor sem o corte de liquidez.
    print("\n== Contrafactual: o potencial sem o corte de liquidez ==")
    soltos = [l for l in recusados if l.get("upsideSemLiquidez") is not None]
    so_liq = [l for l in soltos if l["motivo"] == "Porta 0 — só liquidez"]
    for l in soltos:
        l["upsideSolto"] = l["upsideSemLiquidez"]
    for l in grupos["avaliado"]:
        l["upsideSolto"] = l["upside"]
    saida["contrafactual"] = {}
    for nome, g in [("avaliados (referência)", grupos["avaliado"]),
                    ("recusados só por liquidez, soltos", so_liq)]:
        sem = [l["semNegocio"] for l in g if l.get("semNegocio") is not None]
        d = {"n": len(g), "semNegocioMediano": round(st.median(sem), 3) if sem else None}
        print(f"  {nome} (n={len(g)}, pregões sem negócio na janela: "
              f"{d['semNegocioMediano']} na mediana)")
        for sufixo, rotulo in (("", "da data da coorte"), ("Pulo", "começando um mês depois")):
            for h in (12, 36):
                ret = f"ret{h}tot{sufixo}"
                chave = f"{h}{sufixo}"
                d[f"motor{chave}"] = medir(g, "upsideSolto", ret)
                d[f"bm{chave}"] = medir(g, "bookToMarket", ret)
                d[f"motorDadoBm{chave}"] = medir(g, "upsideSolto", ret, controle="bookToMarket")
                print(f"    {h}m {rotulo}: motor IC {d[f'motor{chave}'].get('icMedio')} "
                      f"(t {d[f'motor{chave}'].get('tEntreCoortes')}, Q5−Q1 {d[f'motor{chave}'].get('spreadQuintil')})   "
                      f"B/M IC {d[f'bm{chave}'].get('icMedio')} (t {d[f'bm{chave}'].get('tEntreCoortes')}, "
                      f"Q5−Q1 {d[f'bm{chave}'].get('spreadQuintil')})   motor dado B/M IC "
                      f"{d[f'motorDadoBm{chave}'].get('icMedio')} (t {d[f'motorDadoBm{chave}'].get('tEntreCoortes')}, "
                      f"t_NW {d[f'motorDadoBm{chave}'].get('tNeweyWest')}, t_sob "
                      f"{d[f'motorDadoBm{chave}'].get('tSobreposicao')}/{d[f'motorDadoBm{chave}'].get('criticoSobreposicao')})")
        saida["contrafactual"][nome] = d

    # O mesmo pulo sobre o B/M, por motivo: o spread que sobrevive ao mês.
    print("\n== B/M por motivo, com o retorno começando um mês depois ==")
    saida["bmPulandoUmMes"] = {}
    for nome, g in todos.items():
        d = {h: medir(g, "bookToMarket", f"ret{h}totPulo") for h in (12, 36)}
        saida["bmPulandoUmMes"][nome] = d
        print(f"  {nome:42s} 12m IC {d[12].get('icMedio')} (t {d[12].get('tEntreCoortes')}, Q5−Q1 {d[12].get('spreadQuintil')})"
              f"   36m IC {d[36].get('icMedio')} (t {d[36].get('tEntreCoortes')}, Q5−Q1 {d[36].get('spreadQuintil')})")

    args.saida.write_text(json.dumps(saida, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"\ngravado {args.saida}")


if __name__ == "__main__":
    main()

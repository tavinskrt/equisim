"""C2 — a banda de cenários cobre o que aconteceu?

O motor de referência precisa saber o quanto não sabe (R2): a banda que ele
declara tem de conter o resultado realizado na frequência que diz conter. Esta
ferramenta mede isso fora da amostra, sobre as coortes da montagem do
aplicativo, e testa a recalibragem.

**O que se compara.** O preço justo é valor, e não previsão de preço. A única
leitura observável dele é a que o próprio aplicativo declara: o preço converge
ao valor justo em 36 meses (decisão 26), pelo caminho
``P_h = P_0 · (V / P_0)^(h/36)`` — o mesmo que anualiza o potencial. A banda
entra por esse caminho, borda a borda. O realizado é o **retorno total**
(decisão 89): o valor apurado inclui a distribuição, e o preço depois da data
ex não a inclui.

**As bandas declaradas.**

- Monte Carlo: ``P5–P95``, que a tela apresenta como "pessimista" e
  "otimista" — 90% central. ``P10–P90`` e ``P25–P75`` mostram a forma.
- Cenários discretos: pessimista e otimista, que não declaram frequência; a
  cobertura é informada, e não julgada.

**A recalibragem, fora da amostra.** Para cada coorte de teste, só entram na
calibragem as coortes cujo horizonte já tinha terminado na data dela — em 36
meses, a de 2018 calibra a de 2021. Três formas:

- ``justo``: quantis de ``log(W/V)`` — a banda em torno do preço justo;
- ``convergência parcial``: ``log(W/P0) = a + b·log(V/P0) + e``, com os quantis
  de ``e`` — o motor decide o centro pelo tanto que o preço de fato convergiu;
- ``preço``: quantis de ``log(W/P0)`` — a banda que não usa o motor, como
  referência de largura.

**Com as deslistadas (C2b).** Quando a entrada traz a marca ``deslistada``, a
recalibragem é refeita cruzada: calibrada nas listadas ou em todas, testada em
cada grupo, sempre fora da amostra.

**Coortes por data (C1c, C1d e C3).** A coorte é o ano (saídas anuais antigas)
ou a data ISO (a montagem trimestral na base da data). "O horizonte já tinha
terminado" passa a ser comparado em data: a coorte de 31/03/2019 calibra a de
31/03/2020 em doze meses, e não a de 30/09/2019. ``--so-setembro`` refaz a
medição só com as coortes de 30/09, para comparar com as anuais.

**A forma fixada antes de medir (C2b, quarta rodada).** A §9 de
``docs/validacao/cobertura_banda.md`` registrou, antes de medir, uma sétima
forma e o que fazer com o resultado: a convergência parcial na escala da
volatilidade do papel — ``z = (log(W/P0) − a − b·log(V/P0)) / σ``, com ``σ`` a
volatilidade dos 252 pregões até a data (campo ``volatilidade`` do backtest,
``CalibratedBand.trailingVolatility``). ``forma_fixada`` a mede com as formas de
controle sobre as mesmas observações, e ``regra_do_pacote`` aplica a regra
registrada: passa nos dois horizontes, ou não é pior que a do justo, e vai ao
aplicativo; senão, o aplicativo fica com a do justo.

Entrada: ``docs/validacao/backtest_trimestral.json``, de
``dart run tool/backtest_valuation.dart --montagem aplicativo --com-deslistadas
--trimestral``.

Uso:
    python tool/cobertura_banda.py                       # trimestral, e o pacote
    python tool/cobertura_banda.py --so-setembro --saida docs/validacao/cobertura_banda_setembro.json --sem-pacote
    python tool/cobertura_banda.py --entrada docs/validacao/backtest_aplicativo_deslistadas.json
        --saida docs/validacao/cobertura_banda_deslistadas.json --sem-pacote   # o C2b
"""

from __future__ import annotations

import datetime as dt
import json
import math
import statistics as st
from collections import defaultdict
from pathlib import Path

# A amostra trimestral na base da data, com as deslistadas da ponte ampliada
# (itens C1c, C1d e C3, decisão 97), é a que gera o pacote.
ENTRADA = Path("docs/validacao/backtest_trimestral.json")
SAIDA = Path("docs/validacao/cobertura_banda_trimestral.json")
PACOTE = Path("assets/validacao/banda_calibrada.json")
CONVERGENCIA_MESES = 36
NOMINAIS = (0.9, 0.8, 0.5)


def data_da_coorte(c) -> dt.date:
    """A data da coorte: o ano das saídas anuais é 30/09, a data ISO é ela."""
    if isinstance(c, int):
        return dt.date(c, 9, 30)
    return dt.date.fromisoformat(str(c))


def ano_da_coorte(c) -> int:
    return data_da_coorte(c).year


def terminou(calibra, testa, meses: int) -> bool:
    """O horizonte da coorte ``calibra`` já tinha terminado na data de ``testa``."""
    d = data_da_coorte(calibra)
    total = d.month - 1 + meses
    ano, mes = d.year + total // 12, total % 12 + 1
    ultimo = (dt.date(ano + (mes == 12), mes % 12 + 1, 1) - dt.timedelta(days=1)).day
    return dt.date(ano, mes, min(d.day, ultimo)) <= data_da_coorte(testa)


def quantil(v: list[float], p: float) -> float:
    v = sorted(v)
    x = p * (len(v) - 1)
    i = int(math.floor(x))
    j = min(i + 1, len(v) - 1)
    f = x - i
    return v[i] * (1 - f) + v[j] * f


def postos(v):
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


def spearman(a, b):
    ra, rb = postos(a), postos(b)
    ma, mb = st.mean(ra), st.mean(rb)
    num = sum((x - ma) * (y - mb) for x, y in zip(ra, rb))
    den = math.sqrt(sum((x - ma) ** 2 for x in ra) * sum((y - mb) ** 2 for y in rb))
    return num / den if den > 0 else 0.0


def mqo(x, y):
    mx, my = st.mean(x), st.mean(y)
    sxx = sum((u - mx) ** 2 for u in x)
    b = sum((u - mx) * (w - my) for u, w in zip(x, y)) / sxx
    return my - b * mx, b


def no_horizonte(p0: float, v: float, h: int) -> float:
    """A borda da banda levada ao horizonte pelo caminho da decisão 26."""
    if v <= 0:
        return 0.0
    return p0 * (v / p0) ** (h / CONVERGENCIA_MESES)


def pct(x):
    return None if x is None else round(100 * x, 1)


def cruzada(linhas: list[dict]) -> dict:
    """C2b — a faixa calibrada com e sem as deslistadas, fora da amostra.

    Calibra com as listadas — a faixa que o aplicativo mostrava — ou com todas,
    e testa em cada grupo. A pergunta do C2b é a primeira coluna: a faixa dos
    sobreviventes cobre o mundo que inclui quem quebrou?
    """
    out: dict = {}
    for h in (12, 36):
        k = f"ret{h}tot"
        base = [l for l in linhas
                if l.get("upside") is not None and l.get("justo") and l["justo"] > 0
                and l.get(k) is not None]

        def residuo(l):
            return math.log(l["preco"] * (1 + l[k]) / l["justo"])

        grupos = {
            "listadas": [l for l in base if not l.get("deslistada")],
            "deslistadas": [l for l in base if l.get("deslistada")],
            "todas": base,
        }
        H: dict = {"n": {g: len(v) for g, v in grupos.items()}}
        print(f"\n===== C2b, {h} meses — " + ", ".join(f"{g} {len(v)}" for g, v in grupos.items()) + " =====")
        for g, v in grupos.items():
            if len(v) < 10:
                continue
            r = [residuo(l) for l in v]
            H.setdefault("realizadoSobreJusto", {})[g] = {
                "p5": round(math.exp(quantil(r, 0.05)), 3),
                "mediana": round(math.exp(quantil(r, 0.5)), 3),
                "p95": round(math.exp(quantil(r, 0.95)), 3),
            }
            print(f"  {g}: realizado ÷ justo P5 {math.exp(quantil(r, .05)):.3f}, "
                  f"mediana {math.exp(quantil(r, .5)):.3f}, P95 {math.exp(quantil(r, .95)):.3f}")
        for cal_nome in ("listadas", "todas"):
            cal_por = defaultdict(list)
            for l in grupos[cal_nome]:
                cal_por[l["coorte"]].append(residuo(l))
            for teste_nome in ("listadas", "deslistadas", "todas"):
                teste_por = defaultdict(list)
                for l in grupos[teste_nome]:
                    teste_por[l["coorte"]].append(residuo(l))
                cob = {nom: [0, 0] for nom in NOMINAIS}
                for c in sorted(teste_por):
                    cal = [x for cc, v in cal_por.items() if terminou(cc, c, h) for x in v]
                    if len(cal) < 30:
                        continue
                    for nom in NOMINAIS:
                        lo, hi = quantil(cal, (1 - nom) / 2), quantil(cal, 1 - (1 - nom) / 2)
                        cob[nom][0] += sum(1 for x in teste_por[c] if lo <= x <= hi)
                        cob[nom][1] += len(teste_por[c])
                chave = f"calibrada em {cal_nome}, testada em {teste_nome}"
                H.setdefault("foraDaAmostra", {})[chave] = {
                    "nTeste": cob[0.9][1],
                    "cobertura": {f"{nom:.0%}": pct(x / n) for nom, (x, n) in cob.items() if n},
                }
                if cob[0.9][1]:
                    print(f"  {chave}: n={cob[0.9][1]}, "
                          + ", ".join(f"{nom:.0%} → {x / n:.1%}" for nom, (x, n) in cob.items() if n))
        out[str(h)] = H
    return out


FORMA_FIXADA = "convergência na escala da volatilidade"
FORMAS_DE_CONTROLE = ("justo", "convergência parcial")
FOLGA_PP = 5.0


def _desvio_maximo(cob: dict) -> float | None:
    lidas = [abs(100 * x / n - 100 * nom) for nom, (x, n) in cob.items() if n]
    return round(max(lidas), 1) if lidas else None


def dispersao_entre_coortes(linhas: list[dict], h: int) -> dict:
    """O que a §9 leu antes de fixar a forma: nível e dispersão de log(W/V) por coorte.

    Descritivo, sem cobertura de forma nenhuma: o desvio da mediana entre coortes
    contra o desvio médio dentro delas, e o P5 e o P95 de cada coorte.
    """
    k = f"ret{h}tot"
    por = defaultdict(list)
    for l in linhas:
        if l.get("upside") is not None and l.get("justo") and l["justo"] > 0 and l.get(k) is not None:
            por[l["coorte"]].append(math.log(l["preco"] * (1 + l[k]) / l["justo"]))
    medianas = [st.median(v) for _, v in sorted(por.items())]
    return {
        "desvioDaMedianaEntreCoortes": round(st.pstdev(medianas), 3) if len(medianas) > 1 else None,
        "desvioMedioDentroDasCoortes": round(st.mean(st.pstdev(v) for v in por.values()), 3) if por else None,
        "porCoorte": {str(c): {"n": len(v), "mediana": round(st.median(v), 3),
                               "p5": round(quantil(v, 0.05), 3), "p95": round(quantil(v, 0.95), 3)}
                      for c, v in sorted(por.items())},
    }


def forma_fixada(linhas: list[dict], h: int) -> dict:
    """A forma da §9 e os controles, fora da amostra, sobre as mesmas observações.

    Só entram observações com preço justo positivo, retorno total no horizonte e
    ``volatilidade`` positiva. A calibragem de cada coorte de teste é a da §8:
    as coortes cujo horizonte já tinha terminado, com 30 observações no mínimo.
    """
    k = f"ret{h}tot"
    elegiveis = [l for l in linhas
                 if l.get("upside") is not None and l.get("justo") and l["justo"] > 0
                 and l.get(k) is not None]
    com_sigma = [l for l in elegiveis if (l.get("volatilidade") or 0) > 0]
    por = defaultdict(list)
    for l in com_sigma:
        u = math.log(l["justo"] / l["preco"])
        r = math.log(l["preco"] * (1 + l[k]) / l["preco"])
        por[l["coorte"]].append((u, r, l["volatilidade"], bool(l.get("deslistada"))))
    coortes = sorted(por)
    todos_u = sorted(u for g in por.values() for u, *_ in g)
    c1, c2 = (quantil(todos_u, 1 / 3), quantil(todos_u, 2 / 3)) if todos_u else (0, 0)
    formas = (FORMA_FIXADA, *FORMAS_DE_CONTROLE)
    cob = {f: {nom: [0, 0] for nom in NOMINAIS} for f in formas}
    por_coorte = {f: defaultdict(dict) for f in formas}
    tercil = {f: [[0, 0], [0, 0], [0, 0]] for f in formas}
    grupo = {f: {"listadas": [0, 0], "deslistadas": [0, 0]} for f in formas}
    abaixo = {f: 0 for f in formas}
    for c in coortes:
        cal = [x for cc, g in por.items() if terminou(cc, c, h) for x in g]
        if len(cal) < 30:
            continue
        a, b = mqo([u for u, *_ in cal], [r for _, r, *_ in cal])
        escores = {
            "justo": lambda u, r, s: r - u,
            "convergência parcial": lambda u, r, s: r - (a + b * u),
            FORMA_FIXADA: lambda u, r, s: (r - (a + b * u)) / s,
        }
        for f in formas:
            res = [escores[f](u, r, s) for u, r, s, _ in cal]
            for nom in NOMINAIS:
                lo, hi = quantil(res, (1 - nom) / 2), quantil(res, 1 - (1 - nom) / 2)
                dentro = 0
                for u, r, s, desl in por[c]:
                    e = escores[f](u, r, s)
                    ok = lo <= e <= hi
                    dentro += ok
                    if nom == 0.9:
                        t = 0 if u < c1 else (1 if u < c2 else 2)
                        tercil[f][t][0] += ok
                        tercil[f][t][1] += 1
                        g = grupo[f]["deslistadas" if desl else "listadas"]
                        g[0] += ok
                        g[1] += 1
                        abaixo[f] += e < lo
                cob[f][nom][0] += dentro
                cob[f][nom][1] += len(por[c])
                por_coorte[f][str(c)][f"{nom:.0%}"] = pct(dentro / len(por[c]))
    out: dict = {
        "observacoesElegiveis": len(elegiveis),
        "semVolatilidade": len(elegiveis) - len(com_sigma),
        "nTeste": cob[FORMA_FIXADA][0.9][1],
        "formas": {},
    }
    for f in formas:
        n90 = cob[f][0.9][1]
        out["formas"][f] = {
            "cobertura": {f"{nom:.0%}": pct(x / n) for nom, (x, n) in cob[f].items() if n},
            "desvioMaximoPp": _desvio_maximo(cob[f]),
            "abaixoDa90": pct(abaixo[f] / n90) if n90 else None,
            "porTercilDePotencial90": [pct(x / n) if n else None for x, n in tercil[f]],
            "porGrupo90": {g: pct(x / n) if n else None for g, (x, n) in grupo[f].items()},
            "porCoorte": dict(por_coorte[f]),
        }
        print(f"  [{h}m] {f}: n={n90}, "
              + ", ".join(f"{nom:.0%} → {x / n:.1%}" for nom, (x, n) in cob[f].items() if n)
              + f"; desvio máximo {_desvio_maximo(cob[f])} p.p.; tercis {out['formas'][f]['porTercilDePotencial90']}; "
              f"grupos {out['formas'][f]['porGrupo90']}")
    return out


def pacote_da_forma_fixada(linhas: list[dict], h: int, medida: dict) -> list[dict]:
    """As faixas da forma fixada, com todas as coortes cujo horizonte terminou."""
    k = f"ret{h}tot"
    obs = [(math.log(l["justo"] / l["preco"]), math.log(1 + l[k]), l["volatilidade"], l["coorte"])
           for l in linhas
           if l.get("upside") is not None and l.get("justo") and l["justo"] > 0
           and l.get(k) is not None and (l.get("volatilidade") or 0) > 0]
    a, b = mqo([u for u, *_ in obs], [r for _, r, *_ in obs])
    z = [(r - (a + b * u)) / s for u, r, s, _ in obs]
    coortes = sorted({c for *_, c in obs})
    faixas = []
    for nom in NOMINAIS:
        fora = medida["formas"][FORMA_FIXADA]["cobertura"].get(f"{nom:.0%}")
        faixas.append({
            "meses": h,
            "nominal": nom,
            "a": round(a, 6),
            "b": round(b, 6),
            "zInferior": round(quantil(z, (1 - nom) / 2), 6),
            "zSuperior": round(quantil(z, 1 - (1 - nom) / 2), 6),
            "observacoes": len(obs),
            "primeiraCoorte": ano_da_coorte(coortes[0]),
            "ultimaCoorte": ano_da_coorte(coortes[-1]),
            "coberturaForaDaAmostra": None if fora is None else round(fora / 100, 3),
            "observacoesForaDaAmostra": medida["nTeste"],
        })
    return faixas


def regra_do_pacote(medidas: dict) -> tuple[str, str]:
    """A regra registrada na §9: qual forma vai ao aplicativo, e por quê."""
    fixada = [medidas[h]["formas"][FORMA_FIXADA] for h in ("12", "36")]
    justo = [medidas[h]["formas"]["justo"] for h in ("12", "36")]
    if all(m["desvioMaximoPp"] is not None and m["desvioMaximoPp"] <= FOLGA_PP for m in fixada):
        return FORMA_FIXADA, "passa a até 5 p.p. nos dois horizontes"
    # Horizonte sem coorte de teste não tem desvio, e conta como o pior.
    pior_fixada = max(math.inf if m["desvioMaximoPp"] is None else m["desvioMaximoPp"] for m in fixada)
    pior_justo = max(math.inf if m["desvioMaximoPp"] is None else m["desvioMaximoPp"] for m in justo)
    if pior_fixada <= pior_justo:
        return FORMA_FIXADA, (f"não passa, e o maior desvio dela ({pior_fixada} p.p.) não é maior "
                              f"que o da forma em torno do justo ({pior_justo} p.p.)")
    return "justo", (f"não passa, e o maior desvio dela ({pior_fixada} p.p.) é maior que o da "
                     f"forma em torno do justo ({pior_justo} p.p.)")


def main() -> None:
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--entrada", type=Path, default=ENTRADA)
    ap.add_argument("--saida", type=Path, default=SAIDA)
    ap.add_argument("--pacote", type=Path, default=PACOTE)
    ap.add_argument("--sem-pacote", action="store_true")
    ap.add_argument("--so-setembro", action="store_true")
    args = ap.parse_args()
    entrada, saida_arq, pacote = args.entrada, args.saida, args.pacote
    linhas = json.loads(entrada.read_text(encoding="utf-8"))
    if args.so_setembro:
        linhas = [l for l in linhas if data_da_coorte(l["coorte"]).month == 9]
    saida: dict = {"entrada": entrada.as_posix(), "convergenciaMeses": CONVERGENCIA_MESES, "horizontes": {}}
    faixas: list[dict] = []
    if any("deslistada" in l for l in linhas):
        saida["c2b"] = cruzada(linhas)

    for h in (12, 36):
        k = f"ret{h}tot"
        amostra = [
            l for l in linhas
            if l.get("upside") is not None and l.get("justo") and l["justo"] > 0
            and l.get(k) is not None and l.get("mcQuantis")
        ]
        coortes = sorted({l["coorte"] for l in amostra})
        H: dict = {"n": len(amostra), "coortes": coortes}
        print(f"\n===== {h} meses — {len(amostra)} observações com Monte Carlo, coortes {coortes[0]} a {coortes[-1]} =====")

        def W(l, ret=k):
            return l["preco"] * (1 + l[ret])

        # --- 1. As bandas declaradas ---------------------------------------
        declaradas = {}
        for lo, hi, nom in ((5, 95, 0.9), (10, 90, 0.8), (25, 75, 0.5)):
            dentro = abaixo = 0
            por_coorte = defaultdict(lambda: [0, 0])
            for l in amostra:
                q = l["mcQuantis"]
                a = no_horizonte(l["preco"], q[lo], h)
                b = no_horizonte(l["preco"], q[hi], h)
                w = W(l)
                ok = a <= w <= b
                dentro += ok
                abaixo += w < a
                por_coorte[l["coorte"]][0] += ok
                por_coorte[l["coorte"]][1] += 1
            declaradas[f"P{lo}-P{hi}"] = {
                "nominal": nom,
                "cobertura": pct(dentro / len(amostra)),
                "abaixo": pct(abaixo / len(amostra)),
                "acima": pct((len(amostra) - dentro - abaixo) / len(amostra)),
                "porCoorte": {str(c): pct(x / n) for c, (x, n) in sorted(por_coorte.items())},
            }
            print(f"  Monte Carlo P{lo}–P{hi} (nominal {nom:.0%}): cobre {dentro / len(amostra):.1%}, "
                  f"abaixo {abaixo / len(amostra):.1%}, acima {(len(amostra) - dentro - abaixo) / len(amostra):.1%}")
        disc = [l for l in amostra if l.get("pessimista") is not None and l.get("otimista") is not None]
        dd = sum(1 for l in disc
                 if no_horizonte(l["preco"], l["pessimista"], h) <= W(l) <= no_horizonte(l["preco"], l["otimista"], h))
        declaradas["discreta"] = {"nominal": None, "n": len(disc), "cobertura": pct(dd / len(disc))}
        print(f"  Cenários discretos, pessimista a otimista: cobre {dd / len(disc):.1%} (n={len(disc)})")

        # Variantes de leitura: retorno de preço, e o valor justo capitalizado
        # pelo custo do capital próprio até o horizonte.
        preco = [l for l in amostra if l.get(f"ret{h}") is not None]
        dp = sum(1 for l in preco
                 if no_horizonte(l["preco"], l["mcQuantis"][5], h) <= W(l, f"ret{h}")
                 <= no_horizonte(l["preco"], l["mcQuantis"][95], h))
        ke = [l for l in amostra if l.get("ke")]
        dk = 0
        for l in ke:
            f = (1 + l["ke"]) ** (h / 12)
            a = no_horizonte(l["preco"], l["mcQuantis"][5] * f ** (CONVERGENCIA_MESES / h), h)
            b = no_horizonte(l["preco"], l["mcQuantis"][95] * f ** (CONVERGENCIA_MESES / h), h)
            dk += a <= W(l) <= b
        declaradas["P5-P95 retorno de preço"] = {"n": len(preco), "cobertura": pct(dp / len(preco))}
        declaradas["P5-P95 com Ke acumulado"] = {"n": len(ke), "cobertura": pct(dk / len(ke))}
        print(f"  P5–P95 sobre o retorno de preço: {dp / len(preco):.1%};  "
              f"com o justo capitalizado pelo Ke até o horizonte: {dk / len(ke):.1%}")
        H["declaradas"] = declaradas

        # --- 2. Por que: nível, largura e convergência ----------------------
        logWV = [math.log(W(l) / l["mcQuantis"][50]) for l in amostra]
        u = [math.log(l["justo"] / l["preco"]) for l in amostra]
        r = [math.log(W(l) / l["preco"]) for l in amostra]
        largura_mc = [math.log(l["mcQuantis"][95] / l["mcQuantis"][5]) for l in amostra]
        centro = st.median(logWV)
        a_c, b_c = mqo(u, r)
        esperado_b = h / CONVERGENCIA_MESES
        b_por_coorte = {}
        por = defaultdict(list)
        for l, uu, rr in zip(amostra, u, r):
            por[l["coorte"]].append((uu, rr))
        for c, g in sorted(por.items()):
            b_por_coorte[str(c)] = round(mqo([x for x, _ in g], [y for _, y in g])[1], 3)
        info = spearman(largura_mc, [abs(x - centro) for x in logWV])
        H["diagnostico"] = {
            "medianaLogWsobreMediana": round(centro, 3),
            "fatorMediano": round(math.exp(centro), 2),
            "larguraMcMediana": round(math.exp(st.median(largura_mc)), 3),
            "larguraRealizada90": round(math.exp(quantil(logWV, 0.95) - quantil(logWV, 0.05)), 1),
            "desvioLogVsobreP0": round(st.pstdev(u), 3),
            "desvioLogWsobreP0": round(st.pstdev(r), 3),
            "convergencia": {"a": round(a_c, 3), "b": round(b_c, 3), "bDaDecisao26": round(esperado_b, 3),
                             "bPorCoorte": b_por_coorte},
            "larguraMcContraErroAbsoluto": round(info, 3),
        }
        print(f"  realizado ÷ mediana da distribuição: {math.exp(centro):.2f}× na mediana")
        print(f"  largura mediana da banda P95/P5: {math.exp(st.median(largura_mc)):.3f}×; "
              f"a de 90% do realizado em torno do justo: {math.exp(quantil(logWV, .95) - quantil(logWV, .05)):.1f}×")
        print(f"  convergência: log(W/P0) = {a_c:.3f} + {b_c:.3f}·log(V/P0); a decisão 26 diz b = {esperado_b:.3f}; "
              f"por coorte {b_por_coorte}")
        print(f"  a largura da banda sabe de algo? Spearman com o erro absoluto: {info:+.3f}")

        # --- 3. Recalibragem fora da amostra --------------------------------
        # Toda avaliação com preço justo entra, e não só as que têm cenários:
        # a combinação das duas vias (decisão 38) tira a banda de cenários,
        # mas o preço justo continua sendo o que a tela mostra.
        recal = {}
        todos = [l for l in linhas
                 if l.get("upside") is not None and l.get("justo") and l["justo"] > 0
                 and l.get(k) is not None]
        por = defaultdict(list)
        for l in todos:
            por[l["coorte"]].append((math.log(l["justo"] / l["preco"]), math.log(W(l) / l["preco"])))
        coortes_recal = sorted(por)
        tercis = sorted(uu for g in por.values() for uu, _ in g)
        c1, c2 = quantil(tercis, 1 / 3), quantil(tercis, 2 / 3)
        for forma in ("justo", "convergência parcial", "preço"):
            cob = {nom: [0, 0] for nom in NOMINAIS}
            cob_coorte = defaultdict(dict)
            cob_tercil = [[0, 0], [0, 0], [0, 0]]
            larguras = []
            for c in coortes_recal:
                cal = [(uu, rr) for cc, g in por.items() if terminou(cc, c, h) for uu, rr in g]
                if len(cal) < 30:
                    continue
                if forma == "justo":
                    a, b = 0.0, 1.0
                elif forma == "preço":
                    a, b = 0.0, 0.0
                else:
                    a, b = mqo([x for x, _ in cal], [y for _, y in cal])
                res = [rr - (a + b * uu) for uu, rr in cal]
                for nom in NOMINAIS:
                    lo, hi = quantil(res, (1 - nom) / 2), quantil(res, 1 - (1 - nom) / 2)
                    teste = por[c]
                    n_ok = sum(1 for uu, rr in teste if lo <= rr - (a + b * uu) <= hi)
                    cob[nom][0] += n_ok
                    cob[nom][1] += len(teste)
                    cob_coorte[str(c)][f"{nom:.0%}"] = pct(n_ok / len(teste))
                    if nom == 0.9:
                        larguras.append(math.exp(hi - lo))
                        for uu, rr in teste:
                            t = 0 if uu < c1 else (1 if uu < c2 else 2)
                            cob_tercil[t][0] += lo <= rr - (a + b * uu) <= hi
                            cob_tercil[t][1] += 1
            n_teste = cob[0.9][1]
            recal[forma] = {
                "nTeste": n_teste,
                "cobertura": {f"{nom:.0%}": pct(x / n) for nom, (x, n) in cob.items() if n},
                "desvioMaximoPp": round(max(abs(100 * x / n - 100 * nom) for nom, (x, n) in cob.items() if n), 1)
                if n_teste else None,
                "porCoorte": dict(cob_coorte),
                "porTercilDePotencial90": [pct(x / n) if n else None for x, n in cob_tercil],
                "fatorDaLargura90": [round(x, 1) for x in larguras],
            }
            print(f"  recalibrada — {forma}: n={n_teste}, "
                  + ", ".join(f"{nom:.0%} → {x / n:.1%}" for nom, (x, n) in cob.items() if n)
                  + f"; largura 90% {[round(x, 1) for x in larguras]}×; tercis de potencial "
                  f"{[pct(x / n) if n else None for x, n in cob_tercil]}")
        H["recalibrada"] = recal
        # --- 3b. A forma fixada antes de medir (§9 do documento) -------------
        H["dispersaoEntreCoortes"] = dispersao_entre_coortes(linhas, h)
        if any("volatilidade" in l for l in linhas):
            H["formaFixada"] = forma_fixada(linhas, h)
        saida["horizontes"][str(h)] = H

        # --- 4. O pacote do aplicativo --------------------------------------
        # A faixa em torno do justo, com todas as coortes cujo horizonte já
        # terminou. A cobertura declarada é a fora da amostra, medida acima.
        todas = [rr - uu for g in por.values() for uu, rr in g]
        for nom in NOMINAIS:
            lo, hi = quantil(todas, (1 - nom) / 2), quantil(todas, 1 - (1 - nom) / 2)
            fora = recal["justo"]["cobertura"].get(f"{nom:.0%}")
            faixas.append({
                "meses": h,
                "nominal": nom,
                "fatorInferior": round(math.exp(lo), 4),
                "fatorSuperior": round(math.exp(hi), 4),
                "observacoes": len(todas),
                "primeiraCoorte": ano_da_coorte(coortes_recal[0]),
                "ultimaCoorte": ano_da_coorte(coortes_recal[-1]),
                "coberturaForaDaAmostra": None if fora is None else round(fora / 100, 3),
                "observacoesForaDaAmostra": recal["justo"]["nTeste"],
            })

    conteudo_do_pacote = {"versao": 1, "fonte": entrada.as_posix(), "faixas": faixas}
    medidas = {h: H["formaFixada"] for h, H in saida["horizontes"].items() if "formaFixada" in H}
    if len(medidas) == 2:
        forma, razao = regra_do_pacote(medidas)
        saida["regraDoPacote"] = {"forma": forma, "razao": razao}
        print(f"\nregra da §9: o aplicativo recebe a forma '{forma}' — {razao}")
        if forma == FORMA_FIXADA:
            conteudo_do_pacote = {
                "versao": 2,
                "fonte": entrada.as_posix(),
                "forma": "convergenciaNaVolatilidade",
                "faixas": [f for h in (12, 36) for f in pacote_da_forma_fixada(linhas, h, medidas[str(h)])],
            }
    saida_arq.write_text(json.dumps(saida, ensure_ascii=False, indent=1), encoding="utf-8")
    if args.sem_pacote:
        print(f"gravado {saida_arq}")
        return
    pacote.parent.mkdir(parents=True, exist_ok=True)
    pacote.write_text(json.dumps(conteudo_do_pacote, ensure_ascii=False), encoding="utf-8")
    print(f"gravado {saida_arq} e {pacote}")


if __name__ == "__main__":
    main()

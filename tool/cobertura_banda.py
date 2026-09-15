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

Entrada: ``docs/validacao/backtest_aplicativo.json``, de
``dart run tool/backtest_valuation.dart --montagem aplicativo``.

Uso:
    python tool/cobertura_banda.py
"""

from __future__ import annotations

import json
import math
import statistics as st
from collections import defaultdict
from pathlib import Path

ENTRADA = Path("docs/validacao/backtest_aplicativo.json")
SAIDA = Path("docs/validacao/cobertura_banda.json")
PACOTE = Path("assets/validacao/banda_calibrada.json")
CONVERGENCIA_MESES = 36
NOMINAIS = (0.9, 0.8, 0.5)


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
        while j + 1 < len(idx) and v[idx[j + 1]] == v[idx[i]]:
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


def main() -> None:
    linhas = json.loads(ENTRADA.read_text(encoding="utf-8"))
    saida: dict = {"entrada": ENTRADA.as_posix(), "convergenciaMeses": CONVERGENCIA_MESES, "horizontes": {}}
    faixas: list[dict] = []

    for h in (12, 36):
        k = f"ret{h}tot"
        amostra = [
            l for l in linhas
            if l.get("upside") is not None and l.get("justo") and l["justo"] > 0
            and l.get(k) is not None and l.get("mcQuantis")
        ]
        coortes = sorted({l["coorte"] for l in amostra})
        H: dict = {"n": len(amostra), "coortes": coortes}
        print(f"\n===== {h} meses — {len(amostra)} observações, coortes {coortes[0]} a {coortes[-1]} =====")

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
        anos = h // 12
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
                cal = [(uu, rr) for cc, g in por.items() if cc + anos <= c for uu, rr in g]
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
                "primeiraCoorte": coortes_recal[0],
                "ultimaCoorte": coortes_recal[-1],
                "coberturaForaDaAmostra": None if fora is None else round(fora / 100, 3),
                "observacoesForaDaAmostra": recal["justo"]["nTeste"],
            })

    SAIDA.write_text(json.dumps(saida, ensure_ascii=False, indent=1), encoding="utf-8")
    PACOTE.parent.mkdir(parents=True, exist_ok=True)
    PACOTE.write_text(json.dumps({"versao": 1, "fonte": ENTRADA.as_posix(), "faixas": faixas},
                                 ensure_ascii=False), encoding="utf-8")
    print(f"gravado {SAIDA} e {PACOTE}")


if __name__ == "__main__":
    main()

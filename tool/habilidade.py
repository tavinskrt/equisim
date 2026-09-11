"""A cascata se paga? O motor contra os fatores ingênuos.

O cabeçalho de ``tool/backtest_valuation.dart`` declara o critério desde que
foi escrito: *"se o motor não os supera, a cascata inteira está cobrando um
custo de complexidade que não entrega."* Este script executa esse teste.

Três medidas, em ordem de severidade:

1. **IC bruto** — o potencial ordena o retorno futuro melhor que ``PL/VM`` e
   ``lucro/VM``?
2. **IC incremental** — condicionado ao book-to-market, o motor acrescenta
   alguma coisa? É o teste que decide, e o único que responde à pergunta do
   cabeçalho.
3. **Diagnóstico** — se não acrescenta, por quê: o potencial já é um fator de
   valor? o sinal é lento? é o provento? são as ressalvas?

Entrada: ``docs/validacao/backtest_valuation.json``, produzido por
``dart run tool/backtest_valuation.dart``.

Uso:
    python tool/habilidade.py
"""

from __future__ import annotations

import json
import math
import random
import statistics as st
from pathlib import Path

SEMENTE = 20260911
ENTRADA = Path("docs/validacao/backtest_valuation.json")
SAIDA = Path("docs/validacao/habilidade.json")


# --------------------------------------------------------------- estatística


def postos(v: list[float]) -> list[float]:
    """Postos com média nos empates."""
    idx = sorted(range(len(v)), key=lambda i: v[i])
    r = [0.0] * len(v)
    i = 0
    while i < len(idx):
        j = i
        while j + 1 < len(idx) and v[idx[j + 1]] == v[idx[i]]:
            j += 1
        medio = (i + j) / 2 + 1
        for k in range(i, j + 1):
            r[idx[k]] = medio
        i = j + 1
    return r


def spearman(a: list[float], b: list[float]) -> float | None:
    if len(a) < 4:
        return None
    ra, rb = postos(a), postos(b)
    ma, mb = sum(ra) / len(ra), sum(rb) / len(rb)
    num = sum((x - ma) * (y - mb) for x, y in zip(ra, rb))
    da = math.sqrt(sum((x - ma) ** 2 for x in ra))
    db = math.sqrt(sum((y - mb) ** 2 for y in rb))
    return None if da == 0 or db == 0 else num / (da * db)


def z_posto(v: list[float]) -> list[float]:
    """Posto reescalado para [-1, 1] — padronização transversal robusta."""
    n = len(v)
    if n < 2:
        return [0.0] * n
    return [2 * (x - 1) / (n - 1) - 1 for x in postos(v)]


def ols(X: list[list[float]], y: list[float]):
    """Mínimos quadrados com intercepto. Devolve (coef, erro-padrão, resíduos).

    Equações normais com eliminação de Gauss e pivotamento parcial. O núcleo
    Dart tem a versão conferida contra o ``statsmodels``; aqui basta o
    suficiente para um `t` de três regressores.
    """
    k = len(X[0])
    n = len(y)
    linhas = [[1.0] + list(x) for x in X]
    A = [[0.0] * (k + 1) for _ in range(k + 1)]
    b = [0.0] * (k + 1)
    for i in range(n):
        for a in range(k + 1):
            b[a] += linhas[i][a] * y[i]
            for c in range(k + 1):
                A[a][c] += linhas[i][a] * linhas[i][c]

    def resolver(M, largura):
        for col in range(k + 1):
            p = max(range(col, k + 1), key=lambda r: abs(M[r][col]))
            if abs(M[p][col]) < 1e-12:
                return None
            M[col], M[p] = M[p], M[col]
            piv = M[col][col]
            for c in range(largura):
                M[col][c] /= piv
            for r in range(k + 1):
                if r == col:
                    continue
                f = M[r][col]
                for c in range(largura):
                    M[r][c] -= f * M[col][c]
        return M

    M = resolver([A[i][:] + [b[i]] for i in range(k + 1)], k + 2)
    if M is None:
        return None
    beta = [M[i][k + 1] for i in range(k + 1)]

    res = [y[i] - sum(beta[a] * linhas[i][a] for a in range(k + 1)) for i in range(n)]
    s2 = sum(e * e for e in res) / (n - k - 1)

    ident = [[1.0 if i == j else 0.0 for j in range(k + 1)] for i in range(k + 1)]
    M2 = resolver([A[i][:] + ident[i] for i in range(k + 1)], 2 * (k + 1))
    if M2 is None:
        return None
    se = [math.sqrt(max(s2 * M2[i][k + 1 + i], 0.0)) for i in range(k + 1)]
    return beta, se, res


# ------------------------------------------------------------------- leitura


def carregar():
    if not ENTRADA.exists():
        raise SystemExit(
            f"{ENTRADA} não existe. Rode antes:\n"
            f"  dart run tool/backtest_valuation.dart"
        )
    return json.loads(ENTRADA.read_text(encoding="utf-8"))


PREDITORES = [
    ("potencial (motor)", "upside"),
    ("book-to-market", "bookToMarket"),
    ("earnings yield", "earningsYield"),
]


def amostra_comum(d, h):
    """Só as linhas em que os três preditores e o retorno existem."""
    return [
        r
        for r in d
        if r.get(h) is not None and all(r.get(k) is not None for _, k in PREDITORES)
    ]


# ------------------------------------------------------------------- medidas


def ic_bruto(d, saida):
    print("== 1. IC bruto: o motor contra os ingênuos ==\n")
    for h in ["ret12", "ret36", "ret12aj", "ret36aj"]:
        s = amostra_comum(d, h)
        if len(s) < 30:
            continue
        y = [r[h] for r in s]
        linha = {"n": len(s)}
        txt = []
        for nome, k in PREDITORES:
            ic = spearman([r[k] for r in s], y)
            linha[k] = ic
            txt.append(f"{nome.split()[0]} {ic:+.4f}")
        saida[h] = linha
        print(f"  {h:8s} n={len(s):4d}   " + "   ".join(txt))
    print(
        "\n  (as séries 'aj' incluem provento e erram 9,1% na mediana —\n"
        "   limitacoes §1.2; são checagem de robustez, não medida preferida)\n"
    )


def ic_incremental(d, saida):
    print("\n== 2. IC incremental: o motor acrescenta ao book-to-market? ==\n")
    saida["regressaoCondicional"] = {}
    for h in ["ret12", "ret36"]:
        s = amostra_comum(d, h)
        # Padroniza DENTRO de cada coorte: é seção transversal, não painel cru.
        X, Y = [], []
        for c in sorted({r["coorte"] for r in s}):
            g = [r for r in s if r["coorte"] == c]
            if len(g) < 10:
                continue
            zs = [z_posto([r[k] for r in g]) for _, k in PREDITORES]
            zy = z_posto([r[h] for r in g])
            for i in range(len(g)):
                X.append([zs[0][i], zs[1][i], zs[2][i]])
                Y.append(zy[i])

        out = ols(X, Y)
        if out is None:
            print(f"  {h}: sistema singular")
            continue
        beta, se, _ = out
        nomes = ["intercepto"] + [n for n, _ in PREDITORES]
        print(f"  --- {h}, n={len(Y)} ---")
        print("    preditor              coef      e.p.        t")
        reg = {"n": len(Y)}
        for i, nm in enumerate(nomes):
            t = beta[i] / se[i] if se[i] > 0 else float("nan")
            print(f"    {nm:19s} {beta[i]:+7.4f}   {se[i]:6.4f}   {t:+7.2f}")
            if i > 0:
                reg[PREDITORES[i - 1][1]] = {"coef": beta[i], "t": t}

        so_motor = ols([[x[0]] for x in X], Y)
        t_so = so_motor[0][1] / so_motor[1][1]
        print(f"    motor sozinho:      {so_motor[0][1]:+7.4f}   "
              f"{so_motor[1][1]:6.4f}   {t_so:+7.2f}")
        reg["motorSozinho"] = {"coef": so_motor[0][1], "t": t_so}

        # O que sobra do motor depois de remover o B/M.
        ortog = ols([[x[1]] for x in X], [x[0] for x in X])
        ic_ort = spearman(ortog[2], Y)
        reg["icOrtogonalizado"] = ic_ort
        print(f"    IC do motor ORTOGONALIZADO contra B/M: {ic_ort:+.4f}\n")
        saida["regressaoCondicional"][h] = reg


def diagnostico(d, saida):
    print("\n== 3. Diagnóstico ==\n")
    s = [r for r in d if r.get("upside") is not None
         and r.get("bookToMarket") is not None]

    print("  (a) O potencial já é um fator de valor?")
    cb = spearman([r["upside"] for r in s], [r["bookToMarket"] for r in s])
    se_ = [r for r in s if r.get("earningsYield") is not None]
    ce = spearman([r["upside"] for r in se_], [r["earningsYield"] for r in se_])
    print(f"      Spearman(potencial, B/M) = {cb:+.4f}   n={len(s)}")
    print(f"      Spearman(potencial, E/P) = {ce:+.4f}   n={len(se_)}")
    saida["correlacaoDoPotencialComOsIngenuos"] = {
        "bookToMarket": cb, "earningsYield": ce, "n": len(s)
    }

    print("\n  (b) O sinal é lento? Autocorrelação de posto entre coortes:")
    por_ticker: dict[str, dict[int, float]] = {}
    for r in s:
        por_ticker.setdefault(r["ticker"], {})[r["coorte"]] = r["upside"]
    auto = []
    anos = sorted({r["coorte"] for r in s})
    for c in anos[:-1]:
        a, b = [], []
        for v in por_ticker.values():
            if c in v and c + 1 in v:
                a.append(v[c])
                b.append(v[c + 1])
        if len(a) >= 20:
            ic = spearman(a, b)
            auto.append({"de": c, "para": c + 1, "spearman": ic, "n": len(a)})
            print(f"      {c} para {c+1}: {ic:+.3f}   n={len(a)}")
    if auto:
        print(f"      mediana: {st.median([x['spearman'] for x in auto]):+.3f}")
    saida["autocorrelacaoDoPotencial"] = auto

    print("\n  (c) São as ressalvas? IC por presença de ressalva:")
    for h in ["ret12", "ret36"]:
        for nome, cond in [("sem ressalva", lambda n: n == 0),
                           ("com ressalva", lambda n: n > 0)]:
            g = [r for r in s if r.get(h) is not None
                 and r.get("ressalvas") is not None
                 and cond(len(r["ressalvas"]))]
            if len(g) < 20:
                continue
            im = spearman([r["upside"] for r in g], [r[h] for r in g])
            ib = spearman([r["bookToMarket"] for r in g], [r[h] for r in g])
            print(f"      {h} {nome:14s} motor {im:+.3f}   B/M {ib:+.3f}   n={len(g)}")

    print("\n  (d) Por via:")
    for h in ["ret12", "ret36"]:
        for mod in ["dcfFcff", "dcfEarnings"]:
            g = [r for r in s if r.get(h) is not None and r.get("modelo") == mod]
            if len(g) < 20:
                continue
            im = spearman([r["upside"] for r in g], [r[h] for r in g])
            ib = spearman([r["bookToMarket"] for r in g], [r[h] for r in g])
            print(f"      {h} {mod:12s}  motor {im:+.3f}   B/M {ib:+.3f}   n={len(g)}")


def quintis(d):
    """Quintil superior contra inferior, na AMOSTRA COMUM.

    Medir cada preditor no universo em que ele existe seria comparação
    injusta: o ``bookToMarket`` também existe nos ativos que o motor
    **recusou** — 1.945 linhas contra 730 —, e ali ele não tem contra quem
    competir. A amostra comum é a única em que os três respondem à mesma
    pergunta sobre os mesmos ativos.
    """
    print("\n\n== 4. Quintil superior contra inferior (amostra comum) ==\n")
    for h in ["ret12", "ret36"]:
        base = amostra_comum(d, h)
        print(f"  --- {h}, n={len(base)} ---")
        for nome, k in PREDITORES:
            s = sorted(base, key=lambda r: r[k])
            q = len(s) // 5
            if q < 3:
                continue
            baixo = st.median([r[h] for r in s[:q]])
            alto = st.median([r[h] for r in s[-q:]])
            print(f"    {nome:18s} Q1 {baixo*100:+7.1f}%   Q5 {alto*100:+7.1f}%   "
                  f"spread {(alto-baixo)*100:+6.1f} p.p.")
        # O que o motor recusa não é sorteio: vale registrar o contraste.
        recusados = [r for r in d if r.get(h) is not None
                     and r.get("upside") is None
                     and r.get("bookToMarket") is not None]
        if len(recusados) >= 25:
            rs = sorted(recusados, key=lambda r: r["bookToMarket"])
            q = len(rs) // 5
            baixo = st.median([r[h] for r in rs[:q]])
            alto = st.median([r[h] for r in rs[-q:]])
            rotulo = "B/M nos recusados"
            print(f"    {rotulo:18s} Q1 {baixo*100:+7.1f}%   Q5 {alto*100:+7.1f}%"
                  f"   spread {(alto-baixo)*100:+6.1f} p.p.   n={len(rs)}")
        print()


def main() -> None:
    random.seed(SEMENTE)
    d = carregar()
    saida = {
        "medidoEm": "2026-09-11",
        "fonte": str(ENTRADA),
        "observacoes": len(d),
    }
    ic_bruto(d, saida)
    ic_incremental(d, saida)
    diagnostico(d, saida)
    quintis(d)
    SAIDA.write_text(
        json.dumps(saida, indent=1, ensure_ascii=False), encoding="utf-8"
    )
    print(f"  gravado {SAIDA}")


if __name__ == "__main__":
    main()

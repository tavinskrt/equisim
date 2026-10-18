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
``CalibratedBand.trailingVolatility``). ``fixed_form`` a mede com as formas de
controle sobre as mesmas observações, e ``package_rule`` aplica a regra
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
INPUT = Path("docs/validacao/backtest_trimestral.json")
OUTPUT = Path("docs/validacao/cobertura_banda_trimestral.json")
PACKAGE = Path("assets/validacao/banda_calibrada.json")
CONVERGENCE_MONTHS = 36
NOMINALS = (0.9, 0.8, 0.5)


def cohort_date(c) -> dt.date:
    """A data da coorte: o ano das saídas anuais é 30/09, a data ISO é ela."""
    if isinstance(c, int):
        return dt.date(c, 9, 30)
    return dt.date.fromisoformat(str(c))


def cohort_year(c) -> int:
    return cohort_date(c).year


def finished(calibration, test_set, months: int) -> bool:
    """O horizonte da coorte ``calibration`` já tinha terminado na data de ``test_set``."""
    d = cohort_date(calibration)
    total = d.month - 1 + months
    year, month = d.year + total // 12, total % 12 + 1
    last = (dt.date(year + (month == 12), month % 12 + 1, 1) - dt.timedelta(days=1)).day
    return dt.date(year, month, min(d.day, last)) <= cohort_date(test_set)


def quantile(v: list[float], p: float) -> float:
    v = sorted(v)
    x = p * (len(v) - 1)
    i = int(math.floor(x))
    j = min(i + 1, len(v) - 1)
    f = x - i
    return v[i] * (1 - f) + v[j] * f


def ranks(v):
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
    ra, rb = ranks(a), ranks(b)
    ma, mb = st.mean(ra), st.mean(rb)
    num = sum((x - ma) * (y - mb) for x, y in zip(ra, rb))
    den = math.sqrt(sum((x - ma) ** 2 for x in ra) * sum((y - mb) ** 2 for y in rb))
    return num / den if den > 0 else 0.0


def ols_fit(x, y):
    mx, my = st.mean(x), st.mean(y)
    sxx = sum((u - mx) ** 2 for u in x)
    b = sum((u - mx) * (w - my) for u, w in zip(x, y)) / sxx
    return my - b * mx, b


def at_horizon(p0: float, v: float, h: int) -> float:
    """A borda da banda levada ao horizonte pelo caminho da decisão 26."""
    if v <= 0:
        return 0.0
    return p0 * (v / p0) ** (h / CONVERGENCE_MONTHS)


def pct(x):
    return None if x is None else round(100 * x, 1)


def cross(lines: list[dict]) -> dict:
    """C2b — a faixa calibrada com e sem as deslistadas, fora da amostra.

    Calibra com as listadas — a faixa que o aplicativo mostrava — ou com todas,
    e testa em cada grupo. A pergunta do C2b é a primeira coluna: a faixa dos
    sobreviventes cobre o mundo que inclui quem quebrou?
    """
    out: dict = {}
    for h in (12, 36):
        k = f"ret{h}tot"
        base = [l for l in lines
                if l.get("upside") is not None and l.get("justo") and l["justo"] > 0
                and l.get(k) is not None]

        def residual(l):
            return math.log(l["preco"] * (1 + l[k]) / l["justo"])

        groups = {
            "listadas": [l for l in base if not l.get("deslistada")],
            "deslistadas": [l for l in base if l.get("deslistada")],
            "todas": base,
        }
        H: dict = {"n": {g: len(v) for g, v in groups.items()}}
        print(f"\n===== C2b, {h} meses — " + ", ".join(f"{g} {len(v)}" for g, v in groups.items()) + " =====")
        for g, v in groups.items():
            if len(v) < 10:
                continue
            r = [residual(l) for l in v]
            H.setdefault("realizadoSobreJusto", {})[g] = {
                "p5": round(math.exp(quantile(r, 0.05)), 3),
                "mediana": round(math.exp(quantile(r, 0.5)), 3),
                "p95": round(math.exp(quantile(r, 0.95)), 3),
            }
            print(f"  {g}: realizado ÷ justo P5 {math.exp(quantile(r, .05)):.3f}, "
                  f"mediana {math.exp(quantile(r, .5)):.3f}, P95 {math.exp(quantile(r, .95)):.3f}")
        for cal_name in ("listadas", "todas"):
            cal_by = defaultdict(list)
            for l in groups[cal_name]:
                cal_by[l["coorte"]].append(residual(l))
            for test_name in ("listadas", "deslistadas", "todas"):
                test_by = defaultdict(list)
                for l in groups[test_name]:
                    test_by[l["coorte"]].append(residual(l))
                coverage = {nominal: [0, 0] for nominal in NOMINALS}
                for c in sorted(test_by):
                    cal_set = [x for cc, v in cal_by.items() if finished(cc, c, h) for x in v]
                    if len(cal_set) < 30:
                        continue
                    for nominal in NOMINALS:
                        lo, hi = quantile(cal_set, (1 - nominal) / 2), quantile(cal_set, 1 - (1 - nominal) / 2)
                        coverage[nominal][0] += sum(1 for x in test_by[c] if lo <= x <= hi)
                        coverage[nominal][1] += len(test_by[c])
                key = f"calibrada em {cal_name}, testada em {test_name}"
                H.setdefault("foraDaAmostra", {})[key] = {
                    "nTeste": coverage[0.9][1],
                    "cobertura": {f"{nominal:.0%}": pct(x / n) for nominal, (x, n) in coverage.items() if n},
                }
                if coverage[0.9][1]:
                    print(f"  {key}: n={coverage[0.9][1]}, "
                          + ", ".join(f"{nominal:.0%} → {x / n:.1%}" for nominal, (x, n) in coverage.items() if n))
        out[str(h)] = H
    return out


FIXED_FORM = "convergência na escala da volatilidade"
CONTROL_FORMS = ("justo", "convergência parcial")
SLACK_PP = 5.0


def _max_deviation(coverage: dict) -> float | None:
    deviations = [abs(100 * x / n - 100 * nominal) for nominal, (x, n) in coverage.items() if n]
    return round(max(deviations), 1) if deviations else None


def dispersion_across_cohorts(lines: list[dict], h: int) -> dict:
    """O que a §9 leu antes de fixar a forma: nível e dispersão de log(W/V) por coorte.

    Descritivo, sem cobertura de forma nenhuma: o desvio da mediana entre coortes
    contra o desvio médio dentro delas, e o P5 e o P95 de cada coorte.
    """
    k = f"ret{h}tot"
    by_group = defaultdict(list)
    for l in lines:
        if l.get("upside") is not None and l.get("justo") and l["justo"] > 0 and l.get(k) is not None:
            by_group[l["coorte"]].append(math.log(l["preco"] * (1 + l[k]) / l["justo"]))
    medians = [st.median(v) for _, v in sorted(by_group.items())]
    return {
        "desvioDaMedianaEntreCoortes": round(st.pstdev(medians), 3) if len(medians) > 1 else None,
        "desvioMedioDentroDasCoortes": round(st.mean(st.pstdev(v) for v in by_group.values()), 3) if by_group else None,
        "porCoorte": {str(c): {"n": len(v), "mediana": round(st.median(v), 3),
                               "p5": round(quantile(v, 0.05), 3), "p95": round(quantile(v, 0.95), 3)}
                      for c, v in sorted(by_group.items())},
    }


def fixed_form(lines: list[dict], h: int) -> dict:
    """A forma da §9 e os controles, fora da amostra, sobre as mesmas observações.

    Só entram observações com preço justo positivo, retorno total no horizonte e
    ``volatilidade`` positiva. A calibragem de cada coorte de teste é a da §8:
    as coortes cujo horizonte já tinha terminado, com 30 observações no mínimo.
    """
    k = f"ret{h}tot"
    eligible = [l for l in lines
                 if l.get("upside") is not None and l.get("justo") and l["justo"] > 0
                 and l.get(k) is not None]
    with_sigma = [l for l in eligible if (l.get("volatilidade") or 0) > 0]
    by_group = defaultdict(list)
    for l in with_sigma:
        u = math.log(l["justo"] / l["preco"])
        r = math.log(l["preco"] * (1 + l[k]) / l["preco"])
        by_group[l["coorte"]].append((u, r, l["volatilidade"], bool(l.get("deslistada"))))
    cohorts = sorted(by_group)
    all_upsides = sorted(u for g in by_group.values() for u, *_ in g)
    c1, c2 = (quantile(all_upsides, 1 / 3), quantile(all_upsides, 2 / 3)) if all_upsides else (0, 0)
    forms = (FIXED_FORM, *CONTROL_FORMS)
    coverage = {f: {nominal: [0, 0] for nominal in NOMINALS} for f in forms}
    by_cohort = {f: defaultdict(dict) for f in forms}
    tercile = {f: [[0, 0], [0, 0], [0, 0]] for f in forms}
    group = {f: {"listadas": [0, 0], "deslistadas": [0, 0]} for f in forms}
    below = {f: 0 for f in forms}
    for c in cohorts:
        cal_set = [x for cc, g in by_group.items() if finished(cc, c, h) for x in g]
        if len(cal_set) < 30:
            continue
        a, b = ols_fit([u for u, *_ in cal_set], [r for _, r, *_ in cal_set])
        scores = {
            "justo": lambda u, r, s: r - u,
            "convergência parcial": lambda u, r, s: r - (a + b * u),
            FIXED_FORM: lambda u, r, s: (r - (a + b * u)) / s,
        }
        for f in forms:
            res = [scores[f](u, r, s) for u, r, s, _ in cal_set]
            for nominal in NOMINALS:
                lo, hi = quantile(res, (1 - nominal) / 2), quantile(res, 1 - (1 - nominal) / 2)
                inside = 0
                for u, r, s, delisted in by_group[c]:
                    e = scores[f](u, r, s)
                    ok = lo <= e <= hi
                    inside += ok
                    if nominal == 0.9:
                        t = 0 if u < c1 else (1 if u < c2 else 2)
                        tercile[f][t][0] += ok
                        tercile[f][t][1] += 1
                        g = group[f]["deslistadas" if delisted else "listadas"]
                        g[0] += ok
                        g[1] += 1
                        below[f] += e < lo
                coverage[f][nominal][0] += inside
                coverage[f][nominal][1] += len(by_group[c])
                by_cohort[f][str(c)][f"{nominal:.0%}"] = pct(inside / len(by_group[c]))
    out: dict = {
        "observacoesElegiveis": len(eligible),
        "semVolatilidade": len(eligible) - len(with_sigma),
        "nTeste": coverage[FIXED_FORM][0.9][1],
        "formas": {},
    }
    for f in forms:
        n90 = coverage[f][0.9][1]
        out["formas"][f] = {
            "cobertura": {f"{nominal:.0%}": pct(x / n) for nominal, (x, n) in coverage[f].items() if n},
            "desvioMaximoPp": _max_deviation(coverage[f]),
            "abaixoDa90": pct(below[f] / n90) if n90 else None,
            "porTercilDePotencial90": [pct(x / n) if n else None for x, n in tercile[f]],
            "porGrupo90": {g: pct(x / n) if n else None for g, (x, n) in group[f].items()},
            "porCoorte": dict(by_cohort[f]),
        }
        print(f"  [{h}m] {f}: n={n90}, "
              + ", ".join(f"{nominal:.0%} → {x / n:.1%}" for nominal, (x, n) in coverage[f].items() if n)
              + f"; desvio máximo {_max_deviation(coverage[f])} p.p.; tercis {out['formas'][f]['porTercilDePotencial90']}; "
              f"grupos {out['formas'][f]['porGrupo90']}")
    return out


def fixed_form_package(lines: list[dict], h: int, measure: dict) -> list[dict]:
    """As faixas da forma fixada, com todas as coortes cujo horizonte terminou."""
    k = f"ret{h}tot"
    obs = [(math.log(l["justo"] / l["preco"]), math.log(1 + l[k]), l["volatilidade"], l["coorte"])
           for l in lines
           if l.get("upside") is not None and l.get("justo") and l["justo"] > 0
           and l.get(k) is not None and (l.get("volatilidade") or 0) > 0]
    a, b = ols_fit([u for u, *_ in obs], [r for _, r, *_ in obs])
    z = [(r - (a + b * u)) / s for u, r, s, _ in obs]
    cohorts = sorted({c for *_, c in obs})
    ranges = []
    for nominal in NOMINALS:
        outside = measure["formas"][FIXED_FORM]["cobertura"].get(f"{nominal:.0%}")
        ranges.append({
            "meses": h,
            "nominal": nominal,
            "a": round(a, 6),
            "b": round(b, 6),
            "zInferior": round(quantile(z, (1 - nominal) / 2), 6),
            "zSuperior": round(quantile(z, 1 - (1 - nominal) / 2), 6),
            "observacoes": len(obs),
            "primeiraCoorte": cohort_year(cohorts[0]),
            "ultimaCoorte": cohort_year(cohorts[-1]),
            "coberturaForaDaAmostra": None if outside is None else round(outside / 100, 3),
            "observacoesForaDaAmostra": measure["nTeste"],
        })
    return ranges


def package_rule(measures: dict) -> tuple[str, str]:
    """A regra registrada na §9: qual forma vai ao aplicativo, e por quê."""
    fixed_forms = [measures[h]["formas"][FIXED_FORM] for h in ("12", "36")]
    fair = [measures[h]["formas"]["justo"] for h in ("12", "36")]
    if all(m["desvioMaximoPp"] is not None and m["desvioMaximoPp"] <= SLACK_PP for m in fixed_forms):
        return FIXED_FORM, "passa a até 5 p.p. nos dois horizontes"
    # Horizonte sem coorte de teste não tem desvio, e conta como o pior.
    worst_fixed = max(math.inf if m["desvioMaximoPp"] is None else m["desvioMaximoPp"] for m in fixed_forms)
    worst_fair = max(math.inf if m["desvioMaximoPp"] is None else m["desvioMaximoPp"] for m in fair)
    if worst_fixed <= worst_fair:
        return FIXED_FORM, (f"não passa, e o maior desvio dela ({worst_fixed} p.p.) não é maior "
                              f"que o da forma em torno do justo ({worst_fair} p.p.)")
    return "justo", (f"não passa, e o maior desvio dela ({worst_fixed} p.p.) é maior que o da "
                     f"forma em torno do justo ({worst_fair} p.p.)")


def main() -> None:
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--entrada", type=Path, default=INPUT)
    ap.add_argument("--saida", type=Path, default=OUTPUT)
    ap.add_argument("--pacote", type=Path, default=PACKAGE)
    ap.add_argument("--sem-pacote", action="store_true")
    ap.add_argument("--so-setembro", action="store_true")
    args = ap.parse_args()
    entry, output_file, package = args.entrada, args.saida, args.pacote
    lines = json.loads(entry.read_text(encoding="utf-8"))
    if args.so_setembro:
        lines = [l for l in lines if cohort_date(l["coorte"]).month == 9]
    output: dict = {"entrada": entry.as_posix(), "convergenciaMeses": CONVERGENCE_MONTHS, "horizontes": {}}
    ranges: list[dict] = []
    if any("deslistada" in l for l in lines):
        output["c2b"] = cross(lines)

    for h in (12, 36):
        k = f"ret{h}tot"
        sample = [
            l for l in lines
            if l.get("upside") is not None and l.get("justo") and l["justo"] > 0
            and l.get(k) is not None and l.get("mcQuantis")
        ]
        cohorts = sorted({l["coorte"] for l in sample})
        H: dict = {"n": len(sample), "coortes": cohorts}
        print(f"\n===== {h} meses — {len(sample)} observações com Monte Carlo, coortes {cohorts[0]} a {cohorts[-1]} =====")

        def W(l, ret=k):
            return l["preco"] * (1 + l[ret])

        # --- 1. As bandas declaradas ---------------------------------------
        declared_map = {}
        for lo, hi, nominal in ((5, 95, 0.9), (10, 90, 0.8), (25, 75, 0.5)):
            inside = below = 0
            by_cohort = defaultdict(lambda: [0, 0])
            for l in sample:
                q = l["mcQuantis"]
                a = at_horizon(l["preco"], q[lo], h)
                b = at_horizon(l["preco"], q[hi], h)
                w = W(l)
                ok = a <= w <= b
                inside += ok
                below += w < a
                by_cohort[l["coorte"]][0] += ok
                by_cohort[l["coorte"]][1] += 1
            declared_map[f"P{lo}-P{hi}"] = {
                "nominal": nominal,
                "cobertura": pct(inside / len(sample)),
                "abaixo": pct(below / len(sample)),
                "acima": pct((len(sample) - inside - below) / len(sample)),
                "porCoorte": {str(c): pct(x / n) for c, (x, n) in sorted(by_cohort.items())},
            }
            print(f"  Monte Carlo P{lo}–P{hi} (nominal {nominal:.0%}): cobre {inside / len(sample):.1%}, "
                  f"abaixo {below / len(sample):.1%}, acima {(len(sample) - inside - below) / len(sample):.1%}")
        discordant = [l for l in sample if l.get("pessimista") is not None and l.get("otimista") is not None]
        dd = sum(1 for l in discordant
                 if at_horizon(l["preco"], l["pessimista"], h) <= W(l) <= at_horizon(l["preco"], l["otimista"], h))
        declared_map["discreta"] = {"nominal": None, "n": len(discordant), "cobertura": pct(dd / len(discordant))}
        print(f"  Cenários discretos, pessimista a otimista: cobre {dd / len(discordant):.1%} (n={len(discordant)})")

        # Variantes de leitura: retorno de preço, e o valor justo capitalizado
        # pelo custo do capital próprio até o horizonte.
        price = [l for l in sample if l.get(f"ret{h}") is not None]
        dp = sum(1 for l in price
                 if at_horizon(l["preco"], l["mcQuantis"][5], h) <= W(l, f"ret{h}")
                 <= at_horizon(l["preco"], l["mcQuantis"][95], h))
        ke = [l for l in sample if l.get("ke")]
        dk = 0
        for l in ke:
            f = (1 + l["ke"]) ** (h / 12)
            a = at_horizon(l["preco"], l["mcQuantis"][5] * f ** (CONVERGENCE_MONTHS / h), h)
            b = at_horizon(l["preco"], l["mcQuantis"][95] * f ** (CONVERGENCE_MONTHS / h), h)
            dk += a <= W(l) <= b
        declared_map["P5-P95 retorno de preço"] = {"n": len(price), "cobertura": pct(dp / len(price))}
        declared_map["P5-P95 com Ke acumulado"] = {"n": len(ke), "cobertura": pct(dk / len(ke))}
        print(f"  P5–P95 sobre o retorno de preço: {dp / len(price):.1%};  "
              f"com o justo capitalizado pelo Ke até o horizonte: {dk / len(ke):.1%}")
        H["declaradas"] = declared_map

        # --- 2. Por que: nível, largura e convergência ----------------------
        logWV = [math.log(W(l) / l["mcQuantis"][50]) for l in sample]
        u = [math.log(l["justo"] / l["preco"]) for l in sample]
        r = [math.log(W(l) / l["preco"]) for l in sample]
        mc_width = [math.log(l["mcQuantis"][95] / l["mcQuantis"][5]) for l in sample]
        center = st.median(logWV)
        a_c, b_c = ols_fit(u, r)
        expected_b = h / CONVERGENCE_MONTHS
        b_by_cohort = {}
        by_group = defaultdict(list)
        for l, uu, rr in zip(sample, u, r):
            by_group[l["coorte"]].append((uu, rr))
        for c, g in sorted(by_group.items()):
            b_by_cohort[str(c)] = round(ols_fit([x for x, _ in g], [y for _, y in g])[1], 3)
        info = spearman(mc_width, [abs(x - center) for x in logWV])
        H["diagnostico"] = {
            "medianaLogWsobreMediana": round(center, 3),
            "fatorMediano": round(math.exp(center), 2),
            "larguraMcMediana": round(math.exp(st.median(mc_width)), 3),
            "larguraRealizada90": round(math.exp(quantile(logWV, 0.95) - quantile(logWV, 0.05)), 1),
            "desvioLogVsobreP0": round(st.pstdev(u), 3),
            "desvioLogWsobreP0": round(st.pstdev(r), 3),
            "convergencia": {"a": round(a_c, 3), "b": round(b_c, 3), "bDaDecisao26": round(expected_b, 3),
                             "bPorCoorte": b_by_cohort},
            "larguraMcContraErroAbsoluto": round(info, 3),
        }
        print(f"  realizado ÷ mediana da distribuição: {math.exp(center):.2f}× na mediana")
        print(f"  largura mediana da banda P95/P5: {math.exp(st.median(mc_width)):.3f}×; "
              f"a de 90% do realizado em torno do justo: {math.exp(quantile(logWV, .95) - quantile(logWV, .05)):.1f}×")
        print(f"  convergência: log(W/P0) = {a_c:.3f} + {b_c:.3f}·log(V/P0); a decisão 26 diz b = {expected_b:.3f}; "
              f"por coorte {b_by_cohort}")
        print(f"  a largura da banda sabe de algo? Spearman com o erro absoluto: {info:+.3f}")

        # --- 3. Recalibragem fora da amostra --------------------------------
        # Toda avaliação com preço justo entra, e não só as que têm cenários:
        # a combinação das duas vias (decisão 38) tira a banda de cenários,
        # mas o preço justo continua sendo o que a tela mostra.
        recal = {}
        all_rows = [l for l in lines
                 if l.get("upside") is not None and l.get("justo") and l["justo"] > 0
                 and l.get(k) is not None]
        by_group = defaultdict(list)
        for l in all_rows:
            by_group[l["coorte"]].append((math.log(l["justo"] / l["preco"]), math.log(W(l) / l["preco"])))
        recal_cohorts = sorted(by_group)
        terciles = sorted(uu for g in by_group.values() for uu, _ in g)
        c1, c2 = quantile(terciles, 1 / 3), quantile(terciles, 2 / 3)
        for form in ("justo", "convergência parcial", "preço"):
            coverage = {nominal: [0, 0] for nominal in NOMINALS}
            cohort_coverage = defaultdict(dict)
            tercile_coverage = [[0, 0], [0, 0], [0, 0]]
            widths = []
            for c in recal_cohorts:
                cal_set = [(uu, rr) for cc, g in by_group.items() if finished(cc, c, h) for uu, rr in g]
                if len(cal_set) < 30:
                    continue
                if form == "justo":
                    a, b = 0.0, 1.0
                elif form == "preço":
                    a, b = 0.0, 0.0
                else:
                    a, b = ols_fit([x for x, _ in cal_set], [y for _, y in cal_set])
                res = [rr - (a + b * uu) for uu, rr in cal_set]
                for nominal in NOMINALS:
                    lo, hi = quantile(res, (1 - nominal) / 2), quantile(res, 1 - (1 - nominal) / 2)
                    test = by_group[c]
                    n_ok = sum(1 for uu, rr in test if lo <= rr - (a + b * uu) <= hi)
                    coverage[nominal][0] += n_ok
                    coverage[nominal][1] += len(test)
                    cohort_coverage[str(c)][f"{nominal:.0%}"] = pct(n_ok / len(test))
                    if nominal == 0.9:
                        widths.append(math.exp(hi - lo))
                        for uu, rr in test:
                            t = 0 if uu < c1 else (1 if uu < c2 else 2)
                            tercile_coverage[t][0] += lo <= rr - (a + b * uu) <= hi
                            tercile_coverage[t][1] += 1
            n_test = coverage[0.9][1]
            recal[form] = {
                "nTeste": n_test,
                "cobertura": {f"{nominal:.0%}": pct(x / n) for nominal, (x, n) in coverage.items() if n},
                "desvioMaximoPp": round(max(abs(100 * x / n - 100 * nominal) for nominal, (x, n) in coverage.items() if n), 1)
                if n_test else None,
                "porCoorte": dict(cohort_coverage),
                "porTercilDePotencial90": [pct(x / n) if n else None for x, n in tercile_coverage],
                "fatorDaLargura90": [round(x, 1) for x in widths],
            }
            print(f"  recalibrada — {form}: n={n_test}, "
                  + ", ".join(f"{nominal:.0%} → {x / n:.1%}" for nominal, (x, n) in coverage.items() if n)
                  + f"; largura 90% {[round(x, 1) for x in widths]}×; tercis de potencial "
                  f"{[pct(x / n) if n else None for x, n in tercile_coverage]}")
        H["recalibrada"] = recal
        # --- 3b. A forma fixada antes de medir (§9 do documento) -------------
        H["dispersaoEntreCoortes"] = dispersion_across_cohorts(lines, h)
        if any("volatilidade" in l for l in lines):
            H["formaFixada"] = fixed_form(lines, h)
        output["horizontes"][str(h)] = H

        # --- 4. O pacote do aplicativo --------------------------------------
        # A faixa em torno do justo, com todas as coortes cujo horizonte já
        # terminou. A cobertura declarada é a fora da amostra, medida acima.
        all_diffs = [rr - uu for g in by_group.values() for uu, rr in g]
        for nominal in NOMINALS:
            lo, hi = quantile(all_diffs, (1 - nominal) / 2), quantile(all_diffs, 1 - (1 - nominal) / 2)
            outside = recal["justo"]["cobertura"].get(f"{nominal:.0%}")
            ranges.append({
                "meses": h,
                "nominal": nominal,
                "fatorInferior": round(math.exp(lo), 4),
                "fatorSuperior": round(math.exp(hi), 4),
                "observacoes": len(all_diffs),
                "primeiraCoorte": cohort_year(recal_cohorts[0]),
                "ultimaCoorte": cohort_year(recal_cohorts[-1]),
                "coberturaForaDaAmostra": None if outside is None else round(outside / 100, 3),
                "observacoesForaDaAmostra": recal["justo"]["nTeste"],
            })

    package_content = {"versao": 1, "fonte": entry.as_posix(), "faixas": ranges}
    measures = {h: H["formaFixada"] for h, H in output["horizontes"].items() if "formaFixada" in H}
    if len(measures) == 2:
        form, ratio = package_rule(measures)
        output["regraDoPacote"] = {"forma": form, "razao": ratio}
        print(f"\nregra da §9: o aplicativo recebe a forma '{form}' — {ratio}")
        if form == FIXED_FORM:
            package_content = {
                "versao": 2,
                "fonte": entry.as_posix(),
                "forma": "convergenciaNaVolatilidade",
                "faixas": [f for h in (12, 36) for f in fixed_form_package(lines, h, measures[str(h)])],
            }
    output_file.write_text(json.dumps(output, ensure_ascii=False, indent=1), encoding="utf-8")
    if args.sem_pacote:
        print(f"gravado {output_file}")
        return
    package.parent.mkdir(parents=True, exist_ok=True)
    package.write_text(json.dumps(package_content, ensure_ascii=False), encoding="utf-8")
    print(f"gravado {output_file} e {package}")


if __name__ == "__main__":
    main()

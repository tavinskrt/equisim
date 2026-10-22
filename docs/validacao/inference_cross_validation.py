"""
Conferência cruzada das primitivas estatísticas do núcleo.

Por que este arquivo existe
---------------------------
O argumento que sustenta a estatística deste trabalho é que o Dart não tem
NumPy nem SciPy, e por isso tudo que foi implementado à mão é recalculado em
Python e comparado. O `cross_validation.py` fazia isso para as métricas de
risco — volatilidade, drawdown, beta, Sortino.

Ele não cobria `inference.dart`, que chegou com a decisão 25 trazendo OLS, erro
-padrão Newey-West com núcleo de Bartlett, quantil da t de Student, R² crítico
e MAD escalado. Os quantis e o R² crítico batiam contra tabela publicada nos
testes de unidade; o **HAC não tinha conferência alguma** fora do próprio
código. Este arquivo fecha esse buraco.

Como funciona
-------------
O Dart grava os dados sintéticos **junto** dos resultados que produziu. O
Python lê os mesmos números e recalcula com `statsmodels` e `scipy.stats`.
Nenhum gerador pseudoaleatório é compartilhado entre os dois lados: se cada um
gerasse a própria amostra, a comparação dependeria de duas sequências
coincidirem, o que é frágil e não prova nada sobre as fórmulas.

Uso
---
    dart run tool/validate.dart inferencia
    pip install numpy scipy statsmodels
    python docs/validacao/inference_cross_validation.py

Saída
-----
    conferencia_inferencia.md   — relatório comparativo
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

try:
    import numpy as np
    import statsmodels.api as sm
    from scipy import stats
except ImportError:
    sys.exit("Instale as dependências: pip install numpy scipy statsmodels")

BASE = Path(__file__).parent
INPUT = BASE / "inferencia_nucleo.json"

# Tolerância relativa. Mais frouxa que a de 1e-4 das métricas de risco porque a
# t de Student do núcleo é obtida por bisseção sobre a beta incompleta, com
# critério de parada declarado — não se espera igualdade em ponto flutuante com
# a implementação do SciPy, e sim concordância dentro do erro do método.
TOLERANCE = 1e-6
T_TOLERANCE = 1e-5


def bartlett_lag(n: int) -> int:
    """Defasagem de Newey-West, na mesma regra do núcleo."""
    return int(math.floor(4 * (n / 100) ** (2 / 9)))


def compare(name: str, dart, python, tol: float = TOLERANCE) -> tuple[str, bool]:
    """Compara e devolve (linha formatada, passou)."""
    if dart is None or python is None:
        return (f"| {name} | — | — | — | ⚪ sem dado |", True)
    scale = max(abs(dart), abs(python), 1e-12)
    deviation = abs(dart - python) / scale
    passed = deviation < tol
    mark = "✅" if passed else "❌"
    return (f"| {name} | {dart:.10f} | {python:.10f} | {deviation:.2e} | {mark} |", passed)


def check_regressions(cases: list[dict]) -> tuple[list[str], int, int]:
    lines: list[str] = []
    total = approved = 0
    for case in cases:
        x = np.asarray(case["x"], dtype=float)
        y = np.asarray(case["y"], dtype=float)
        d = case["dart"]

        X = sm.add_constant(x)
        ols = sm.OLS(y, X).fit()
        intercept, slope = ols.params
        slope_error = ols.bse[1]

        n = len(x)
        L = bartlett_lag(n)
        # `maxlags=0` é degenerado no statsmodels; com L = 0 o HAC recai no erro
        # homocedástico, que é exatamente o que o núcleo faz.
        if L > 0:
            hac = sm.OLS(y, X).fit(
                cov_type="HAC", cov_kwds={"maxlags": L, "use_correction": False}
            )
            hac_error = hac.bse[1]
            # O núcleo aplica a correção de amostra pequena n/(n-2) sobre a
            # variância; o statsmodels sem `use_correction` não aplica nenhuma.
            hac_error = hac_error * math.sqrt(n / (n - 2))
        else:
            hac_error = None

        sxx = float(((x - x.mean()) ** 2).sum())
        residual = float(np.sqrt(ols.ssr / (n - 2)))

        comparisons = [
            ("inclinação", d["slope"], float(slope)),
            ("intercepto", d["intercept"], float(intercept)),
            ("R²", d["r2"], float(ols.rsquared)),
            ("erro-padrão da inclinação", d["slopeStdError"], float(slope_error)),
            ("erro-padrão do resíduo", d["residualStdError"], residual),
            ("Sxx", d["sxx"], sxx),
            (
                f"erro-padrão HAC (L={L})",
                d.get("hacSlopeStdError"),
                None if hac_error is None else float(hac_error),
            ),
        ]

        lines.append(f"\n### Regressão — {case['nome']} (n = {n})\n")
        lines.append("| Grandeza | Equisim (Dart) | Python | Desvio relativo | |")
        lines.append("|---|---|---|---|---|")
        for name, a, b in comparisons:
            line, passed = compare(name, a, b)
            lines.append(line)
            if a is not None and b is not None:
                total += 1
                approved += int(passed)
    return lines, total, approved


def check_robustness(cases: list[dict]) -> tuple[list[str], int, int]:
    lines = ["\n### Mediana e MAD escalado\n"]
    lines.append("| Amostra | Grandeza | Equisim (Dart) | Python | Desvio | |")
    lines.append("|---|---|---|---|---|---|")
    total = approved = 0
    for case in cases:
        v = np.asarray(case["valores"], dtype=float)
        d = case["dart"]
        median = float(np.median(v))
        mad = float(1.4826 * np.median(np.abs(v - median)))
        for name, a, b in [
            ("mediana", d["mediana"], median),
            ("MAD escalado", d["madEscalado"], mad),
        ]:
            line, passed = compare(f"{case['nome']} | {name}", a, b)
            lines.append(f"| {line[2:]}")
            if a is not None and b is not None:
                total += 1
                approved += int(passed)
    return lines, total, approved


def check_quantiles(cases: list[dict]) -> tuple[list[str], int, int]:
    lines = ["\n### Quantil da t de Student\n"]
    lines.append("| p | gl | Equisim (Dart) | SciPy | Desvio relativo | |")
    lines.append("|---|---|---|---|---|---|")
    total = approved = 0
    for case in cases:
        p, df = case["p"], case["df"]
        expected = float(stats.t.ppf(p, df))
        line, passed = compare(f"{p} | {df}", case["dart"], expected, T_TOLERANCE)
        lines.append(f"| {line[2:]}")
        total += 1
        approved += int(passed)
    return lines, total, approved


def check_r2_critical(cases: list[dict]) -> tuple[list[str], int, int]:
    lines = ["\n### R² crítico\n"]
    lines.append("| n | α | Equisim (Dart) | SciPy | Desvio relativo | |")
    lines.append("|---|---|---|---|---|---|")
    total = approved = 0
    for case in cases:
        n, alpha = case["n"], case["alpha"]
        # R²_crit = t² / (t² + n − 2), com t bicaudal a (1 − α).
        t = float(stats.t.ppf(1 - alpha / 2, n - 2))
        expected = t * t / (t * t + n - 2)
        line, passed = compare(f"{n} | {alpha}", case["dart"], expected, T_TOLERANCE)
        lines.append(f"| {line[2:]}")
        total += 1
        approved += int(passed)
    return lines, total, approved


def main() -> None:
    if not INPUT.exists():
        sys.exit(
            f"Arquivo não encontrado: {INPUT}\n"
            "Rode antes: dart run tool/validate.dart inferencia"
        )
    data = json.loads(INPUT.read_text(encoding="utf-8"))

    lines: list[str] = []
    total = approved = 0
    for checker, key in [
        (check_regressions, "regressoes"),
        (check_robustness, "robustez"),
        (check_quantiles, "quantis_t"),
        (check_r2_critical, "r2_critico"),
    ]:
        part, t, a = checker(data[key])
        lines += part
        total += t
        approved += a

    header_lines = [
        "# Conferência cruzada — primitivas estatísticas do núcleo",
        "",
        "As grandezas da coluna *Python* foram recalculadas de forma "
        "independente com `statsmodels` e `scipy.stats`, sobre **os mesmos "
        "dados** que o Dart usou — exportados por "
        "`tool/validation/inference_export.dart`. Nenhum gerador "
        "pseudoaleatório é compartilhado entre os dois lados.",
        "",
        f"Tolerância: {TOLERANCE:.0e} nas regressões e na robustez, "
        f"{T_TOLERANCE:.0e} nos quantis — a t do núcleo vem de bisseção sobre "
        "a beta incompleta, e concordância dentro do erro do método é o que se "
        "espera, não igualdade em ponto flutuante.",
        "",
        "O erro-padrão HAC do núcleo aplica correção de amostra pequena "
        "`n/(n−2)` sobre a variância; a coluna do Python reproduz essa correção "
        "sobre o resultado do `statsmodels` com `use_correction=False`, para "
        "comparar a mesma grandeza.",
        "",
        f"**Resultado: {approved} de {total} comparações dentro da tolerância.**",
    ]

    destination = BASE / "conferencia_inferencia.md"
    destination.write_text("\n".join(header_lines + lines) + "\n", encoding="utf-8")

    print(f"{approved}/{total} comparações dentro da tolerância.")
    print(f"-> {destination}")
    if approved < total:
        sys.exit(1)


if __name__ == "__main__":
    main()

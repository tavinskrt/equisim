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
ENTRADA = BASE / "inferencia_nucleo.json"

# Tolerância relativa. Mais frouxa que a de 1e-4 das métricas de risco porque a
# t de Student do núcleo é obtida por bisseção sobre a beta incompleta, com
# critério de parada declarado — não se espera igualdade em ponto flutuante com
# a implementação do SciPy, e sim concordância dentro do erro do método.
TOLERANCIA = 1e-6
TOLERANCIA_T = 1e-5


def bartlett_lag(n: int) -> int:
    """Defasagem de Newey-West, na mesma regra do núcleo."""
    return int(math.floor(4 * (n / 100) ** (2 / 9)))


def comparar(nome: str, dart, python, tol: float = TOLERANCIA) -> tuple[str, bool]:
    """Compara e devolve (linha formatada, passou)."""
    if dart is None or python is None:
        return (f"| {nome} | — | — | — | ⚪ sem dado |", True)
    escala = max(abs(dart), abs(python), 1e-12)
    desvio = abs(dart - python) / escala
    passou = desvio < tol
    marca = "✅" if passou else "❌"
    return (f"| {nome} | {dart:.10f} | {python:.10f} | {desvio:.2e} | {marca} |", passou)


def conferir_regressoes(casos: list[dict]) -> tuple[list[str], int, int]:
    linhas: list[str] = []
    total = aprovados = 0
    for caso in casos:
        x = np.asarray(caso["x"], dtype=float)
        y = np.asarray(caso["y"], dtype=float)
        d = caso["dart"]

        X = sm.add_constant(x)
        ols = sm.OLS(y, X).fit()
        intercepto, inclinacao = ols.params
        erro_inclinacao = ols.bse[1]

        n = len(x)
        L = bartlett_lag(n)
        # `maxlags=0` é degenerado no statsmodels; com L = 0 o HAC recai no erro
        # homocedástico, que é exatamente o que o núcleo faz.
        if L > 0:
            hac = sm.OLS(y, X).fit(
                cov_type="HAC", cov_kwds={"maxlags": L, "use_correction": False}
            )
            erro_hac = hac.bse[1]
            # O núcleo aplica a correção de amostra pequena n/(n-2) sobre a
            # variância; o statsmodels sem `use_correction` não aplica nenhuma.
            erro_hac = erro_hac * math.sqrt(n / (n - 2))
        else:
            erro_hac = None

        sxx = float(((x - x.mean()) ** 2).sum())
        residuo = float(np.sqrt(ols.ssr / (n - 2)))

        comparacoes = [
            ("inclinação", d["slope"], float(inclinacao)),
            ("intercepto", d["intercept"], float(intercepto)),
            ("R²", d["r2"], float(ols.rsquared)),
            ("erro-padrão da inclinação", d["slopeStdError"], float(erro_inclinacao)),
            ("erro-padrão do resíduo", d["residualStdError"], residuo),
            ("Sxx", d["sxx"], sxx),
            (
                f"erro-padrão HAC (L={L})",
                d.get("hacSlopeStdError"),
                None if erro_hac is None else float(erro_hac),
            ),
        ]

        linhas.append(f"\n### Regressão — {caso['nome']} (n = {n})\n")
        linhas.append("| Grandeza | Equisim (Dart) | Python | Desvio relativo | |")
        linhas.append("|---|---|---|---|---|")
        for nome, a, b in comparacoes:
            linha, passou = comparar(nome, a, b)
            linhas.append(linha)
            if a is not None and b is not None:
                total += 1
                aprovados += int(passou)
    return linhas, total, aprovados


def conferir_robustez(casos: list[dict]) -> tuple[list[str], int, int]:
    linhas = ["\n### Mediana e MAD escalado\n"]
    linhas.append("| Amostra | Grandeza | Equisim (Dart) | Python | Desvio | |")
    linhas.append("|---|---|---|---|---|---|")
    total = aprovados = 0
    for caso in casos:
        v = np.asarray(caso["valores"], dtype=float)
        d = caso["dart"]
        mediana = float(np.median(v))
        mad = float(1.4826 * np.median(np.abs(v - mediana)))
        for nome, a, b in [
            ("mediana", d["mediana"], mediana),
            ("MAD escalado", d["madEscalado"], mad),
        ]:
            linha, passou = comparar(f"{caso['nome']} | {nome}", a, b)
            linhas.append(f"| {linha[2:]}")
            if a is not None and b is not None:
                total += 1
                aprovados += int(passou)
    return linhas, total, aprovados


def conferir_quantis(casos: list[dict]) -> tuple[list[str], int, int]:
    linhas = ["\n### Quantil da t de Student\n"]
    linhas.append("| p | gl | Equisim (Dart) | SciPy | Desvio relativo | |")
    linhas.append("|---|---|---|---|---|---|")
    total = aprovados = 0
    for caso in casos:
        p, df = caso["p"], caso["df"]
        esperado = float(stats.t.ppf(p, df))
        linha, passou = comparar(f"{p} | {df}", caso["dart"], esperado, TOLERANCIA_T)
        linhas.append(f"| {linha[2:]}")
        total += 1
        aprovados += int(passou)
    return linhas, total, aprovados


def conferir_r2_critico(casos: list[dict]) -> tuple[list[str], int, int]:
    linhas = ["\n### R² crítico\n"]
    linhas.append("| n | α | Equisim (Dart) | SciPy | Desvio relativo | |")
    linhas.append("|---|---|---|---|---|---|")
    total = aprovados = 0
    for caso in casos:
        n, alpha = caso["n"], caso["alpha"]
        # R²_crit = t² / (t² + n − 2), com t bicaudal a (1 − α).
        t = float(stats.t.ppf(1 - alpha / 2, n - 2))
        esperado = t * t / (t * t + n - 2)
        linha, passou = comparar(f"{n} | {alpha}", caso["dart"], esperado, TOLERANCIA_T)
        linhas.append(f"| {linha[2:]}")
        total += 1
        aprovados += int(passou)
    return linhas, total, aprovados


def main() -> None:
    if not ENTRADA.exists():
        sys.exit(
            f"Arquivo não encontrado: {ENTRADA}\n"
            "Rode antes: dart run tool/validate.dart inferencia"
        )
    dados = json.loads(ENTRADA.read_text(encoding="utf-8"))

    linhas: list[str] = []
    total = aprovados = 0
    for conferidor, chave in [
        (conferir_regressoes, "regressoes"),
        (conferir_robustez, "robustez"),
        (conferir_quantis, "quantis_t"),
        (conferir_r2_critico, "r2_critico"),
    ]:
        parte, t, a = conferidor(dados[chave])
        linhas += parte
        total += t
        aprovados += a

    cabecalho = [
        "# Conferência cruzada — primitivas estatísticas do núcleo",
        "",
        "As grandezas da coluna *Python* foram recalculadas de forma "
        "independente com `statsmodels` e `scipy.stats`, sobre **os mesmos "
        "dados** que o Dart usou — exportados por "
        "`tool/validation/inference_export.dart`. Nenhum gerador "
        "pseudoaleatório é compartilhado entre os dois lados.",
        "",
        f"Tolerância: {TOLERANCIA:.0e} nas regressões e na robustez, "
        f"{TOLERANCIA_T:.0e} nos quantis — a t do núcleo vem de bisseção sobre "
        "a beta incompleta, e concordância dentro do erro do método é o que se "
        "espera, não igualdade em ponto flutuante.",
        "",
        "O erro-padrão HAC do núcleo aplica correção de amostra pequena "
        "`n/(n−2)` sobre a variância; a coluna do Python reproduz essa correção "
        "sobre o resultado do `statsmodels` com `use_correction=False`, para "
        "comparar a mesma grandeza.",
        "",
        f"**Resultado: {aprovados} de {total} comparações dentro da tolerância.**",
    ]

    destino = BASE / "conferencia_inferencia.md"
    destino.write_text("\n".join(cabecalho + linhas) + "\n", encoding="utf-8")

    print(f"{aprovados}/{total} comparações dentro da tolerância.")
    print(f"-> {destino}")
    if aprovados < total:
        sys.exit(1)


if __name__ == "__main__":
    main()

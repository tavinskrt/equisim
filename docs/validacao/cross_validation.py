"""
Conferência cruzada das métricas do Equisim.

Por que este arquivo existe
---------------------------
O Dart não tem ecossistema científico maduro: não há NumPy nem SciPy. Toda a
estatística do trabalho foi implementada à mão, dentro de `equisim_core`.
Afirmar que está correta sem conferência externa seria pedir confiança.

Este script lê as séries exportadas pelo executor de validação e **recalcula
tudo de forma independente**, com bibliotecas consagradas, reportando a
diferença. Uma divergência acima da tolerância indica defeito no motor.

Uso
---
    dart run tool/validate.dart exportar
    pip install pandas numpy
    python docs/validacao/cross_validation.py

Escopo — e o que fica de fora
-----------------------------
Este arquivo cobre as **métricas de risco**: volatilidade, drawdown, CAGR, beta,
correlação, semidesvio e Sortino.

As primitivas estatísticas de `inference.dart` — OLS, Newey-West HAC, quantil da
t de Student, R² crítico e MAD escalado, todas introduzidas pela decisão 25 —
são conferidas por `inference_cross_validation.py`, que roda contra `statsmodels`
e `scipy.stats`. Os dois juntos é que fecham o argumento; nenhum deles sozinho.

Saída
-----
    conferencia_python.md   — relatório comparativo
"""

from __future__ import annotations

import sys
from pathlib import Path

try:
    import numpy as np
    import pandas as pd
except ImportError:
    sys.exit("Instale as dependências: pip install pandas numpy")

BASE = Path(__file__).parent
RELATIVE_TOLERANCE = 1e-6
SESSIONS_PER_YEAR = 252


def load_parameters() -> dict[str, str]:
    path = BASE / "parametros.csv"
    if not path.exists():
        sys.exit(f"Arquivo ausente: {path}. Rode 'dart run tool/validate.dart exportar'.")
    df = pd.read_csv(path)
    return dict(zip(df["parametro"], df["valor"]))


def daily_returns(index: pd.Series) -> pd.Series:
    """Retornos simples de uma série de índice de retorno total."""
    return index.dropna().pct_change().dropna()


def annual_volatility(returns: pd.Series) -> float:
    """Desvio-padrão AMOSTRAL (ddof=1) anualizado — mesma convenção do motor."""
    return float(returns.std(ddof=1) * np.sqrt(SESSIONS_PER_YEAR))


def max_drawdown(index: pd.Series) -> float:
    series = index.dropna()
    peak = series.cummax()
    return float(((series - peak) / peak).min())


def cagr(index: pd.Series, calendar_days: float) -> float:
    series = index.dropna()
    if len(series) < 2 or calendar_days <= 0:
        return 0.0
    years = calendar_days / 365.25
    return float((series.iloc[-1] / series.iloc[0]) ** (1 / years) - 1)


def beta_and_correlation(asset_index: pd.Series, market_index: pd.Series) -> tuple[float, float, int]:
    """Beta = Cov(Ra, Rm) / Var(Rm).

    Convencao de pareamento: os retornos sao calculados entre datas em que
    AMBAS as series negociaram. Parear retornos calculados sobre calendarios
    proprios mediria intervalos diferentes de cada lado -- se o ativo nao
    negociou num dia, seu retorno seguinte cobre dois dias enquanto o do
    mercado cobre um. O beta resultante mistura co-movimento com ruido de
    calendario.
    """
    levels = pd.concat([asset_index, market_index], axis=1, join="inner").dropna()
    if len(levels) < 31:
        return (float("nan"), float("nan"), len(levels))
    paired = levels.pct_change().dropna()
    ra = paired.iloc[:, 0]
    rm = paired.iloc[:, 1]
    covariance = float(np.cov(ra, rm, ddof=1)[0, 1])
    variance = float(np.var(rm, ddof=1))
    beta = covariance / variance if variance > 0 else float("nan")
    correlation = float(np.corrcoef(ra, rm)[0, 1])
    return (beta, correlation, len(paired))


def annual_semideviation(returns: pd.Series, target: float = 0.0) -> float:
    """Semidesvio de Sortino e Satchell.

        DD = sqrt( (1/N) * soma( min(r - alvo, 0)^2 ) )

    O divisor e o total de observacoes, nao a contagem de negativos, e os
    desvios sao medidos a partir do alvo, nao da media dos negativos.
    """
    shortfall = np.minimum(returns.to_numpy() - target, 0.0)
    if len(shortfall) < 2:
        return 0.0
    variance = float(np.sum(shortfall**2) / len(shortfall))
    return float(np.sqrt(variance) * np.sqrt(SESSIONS_PER_YEAR))


def sortino(returns: pd.Series, cagr_value: float, risk_free: float) -> float:
    deviation = annual_semideviation(returns)
    return (cagr_value - risk_free) / deviation if deviation > 0 else 0.0


def compare(name: str, dart: float, python: float) -> tuple[str, bool]:
    """Compara e devolve (linha formatada, passou)."""
    if pd.isna(dart) or pd.isna(python):
        return (f"| {name} | {dart} | {python} | — | ⚪ sem dado |", True)
    scale = max(abs(dart), abs(python), 1e-9)
    deviation = abs(dart - python) / scale
    passed = deviation < 1e-4
    mark = "✅" if passed else "❌"
    return (
        f"| {name} | {dart:.8f} | {python:.8f} | {deviation:.2e} | {mark} |",
        passed,
    )


def main() -> None:
    parameters = load_parameters()
    risk_free = float(parameters["taxa_livre_risco_anual"])

    prices = pd.read_csv(BASE / "precos.csv", parse_dates=["date"]).set_index("date")
    dart_metrics = pd.read_csv(BASE / "metricas_equisim.csv").set_index("ticker")

    if "IBOV" not in prices.columns:
        sys.exit("precos.csv não contém a coluna IBOV; refaça a exportação.")
    market_index = prices["IBOV"].dropna()

    lines: list[str] = []
    total = 0
    approved = 0

    for ticker in prices.columns:
        if ticker not in dart_metrics.index:
            continue

        # Indice de preco em base 1,0 no primeiro pregao da janela. Era o
        # `retorno_total.csv` que entrava aqui, construido pelo motor de
        # retorno total; ele saiu com a decisao 023, e a trajetoria de um
        # ativo passou a ser a propria serie de fechamentos.
        series = prices[ticker].dropna()
        if len(series) < 30 or series.iloc[0] <= 0:
            continue
        index = series / series.iloc[0]

        returns = daily_returns(index)
        days = (index.index[-1] - index.index[0]).days

        py_total_return = float(index.iloc[-1] / index.iloc[0] - 1)
        py_cagr = cagr(index, days)
        py_vol = annual_volatility(returns)
        py_mdd = max_drawdown(index)
        py_sharpe = (py_cagr - risk_free) / py_vol if py_vol > 0 else 0.0
        py_sortino = sortino(returns, py_cagr, risk_free)
        py_beta, py_corr, py_obs = beta_and_correlation(index, market_index)

        d = dart_metrics.loc[ticker]
        comparisons = [
            ("retorno total", float(d["retorno_total"]), py_total_return),
            ("CAGR", float(d["cagr"]), py_cagr),
            ("volatilidade", float(d["volatilidade_anual"]), py_vol),
            ("max drawdown", float(d["max_drawdown"]), py_mdd),
            ("Sharpe", float(d["sharpe"]), py_sharpe),
            ("Sortino", float(d["sortino"]), py_sortino),
            ("beta", float(d["beta"]) if pd.notna(d["beta"]) else float("nan"), py_beta),
            (
                "correlação",
                float(d["correlacao_ibov"]) if pd.notna(d["correlacao_ibov"]) else float("nan"),
                py_corr,
            ),
        ]

        lines.append(f"\n### {ticker}\n")
        lines.append("| Métrica | Equisim (Dart) | Python | Desvio relativo | |")
        lines.append("|---|---|---|---|---|")
        for name, dart_value, python_value in comparisons:
            line, passed = compare(name, dart_value, python_value)
            lines.append(line)
            if not (pd.isna(dart_value) or pd.isna(python_value)):
                total += 1
                approved += int(passed)

    header_lines = [
        "# Conferência cruzada — Equisim × Python",
        "",
        f"Janela: {parameters['janela_inicio']} a {parameters['janela_fim']}  ",
        f"Taxa livre de risco: {risk_free:.4%} a.a. (CDI observado)  ",
        f"Desvio-padrão: {parameters['desvio_padrao']}  ",
        f"Pregões por ano: {parameters['pregoes_por_ano']}",
        "",
        "As métricas da coluna *Python* foram recalculadas de forma independente "
        "com `pandas` e `numpy` a partir das séries exportadas. Um desvio "
        "relativo acima de 1e-4 indica divergência entre as implementações.",
        "",
        f"**Resultado: {approved} de {total} comparações dentro da tolerância.**",
    ]

    output = "\n".join(header_lines + lines) + "\n"
    destination = BASE / "conferencia_python.md"
    destination.write_text(output, encoding="utf-8")

    print(f"{approved}/{total} comparações dentro da tolerância.")
    print(f"-> {destination}")
    if approved < total:
        sys.exit(1)


if __name__ == "__main__":
    main()

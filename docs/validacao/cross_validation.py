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
TOLERANCIA_RELATIVA = 1e-6
PREGOES_POR_ANO = 252


def carregar_parametros() -> dict[str, str]:
    caminho = BASE / "parametros.csv"
    if not caminho.exists():
        sys.exit(f"Arquivo ausente: {caminho}. Rode 'dart run tool/validate.dart exportar'.")
    df = pd.read_csv(caminho)
    return dict(zip(df["parametro"], df["valor"]))


def retornos_diarios(indice: pd.Series) -> pd.Series:
    """Retornos simples de uma série de índice de retorno total."""
    return indice.dropna().pct_change().dropna()


def volatilidade_anual(retornos: pd.Series) -> float:
    """Desvio-padrão AMOSTRAL (ddof=1) anualizado — mesma convenção do motor."""
    return float(retornos.std(ddof=1) * np.sqrt(PREGOES_POR_ANO))


def max_drawdown(indice: pd.Series) -> float:
    serie = indice.dropna()
    pico = serie.cummax()
    return float(((serie - pico) / pico).min())


def cagr(indice: pd.Series, dias_corridos: float) -> float:
    serie = indice.dropna()
    if len(serie) < 2 or dias_corridos <= 0:
        return 0.0
    anos = dias_corridos / 365.25
    return float((serie.iloc[-1] / serie.iloc[0]) ** (1 / anos) - 1)


def beta_e_correlacao(indice_ativo: pd.Series, indice_mercado: pd.Series) -> tuple[float, float, int]:
    """Beta = Cov(Ra, Rm) / Var(Rm).

    Convencao de pareamento: os retornos sao calculados entre datas em que
    AMBAS as series negociaram. Parear retornos calculados sobre calendarios
    proprios mediria intervalos diferentes de cada lado -- se o ativo nao
    negociou num dia, seu retorno seguinte cobre dois dias enquanto o do
    mercado cobre um. O beta resultante mistura co-movimento com ruido de
    calendario.
    """
    niveis = pd.concat([indice_ativo, indice_mercado], axis=1, join="inner").dropna()
    if len(niveis) < 31:
        return (float("nan"), float("nan"), len(niveis))
    pareado = niveis.pct_change().dropna()
    ra = pareado.iloc[:, 0]
    rm = pareado.iloc[:, 1]
    covariancia = float(np.cov(ra, rm, ddof=1)[0, 1])
    variancia = float(np.var(rm, ddof=1))
    beta = covariancia / variancia if variancia > 0 else float("nan")
    correlacao = float(np.corrcoef(ra, rm)[0, 1])
    return (beta, correlacao, len(pareado))


def semidesvio_anual(retornos: pd.Series, alvo: float = 0.0) -> float:
    """Semidesvio de Sortino e Satchell.

        DD = sqrt( (1/N) * soma( min(r - alvo, 0)^2 ) )

    O divisor e o total de observacoes, nao a contagem de negativos, e os
    desvios sao medidos a partir do alvo, nao da media dos negativos.
    """
    shortfall = np.minimum(retornos.to_numpy() - alvo, 0.0)
    if len(shortfall) < 2:
        return 0.0
    variancia = float(np.sum(shortfall**2) / len(shortfall))
    return float(np.sqrt(variancia) * np.sqrt(PREGOES_POR_ANO))


def sortino(retornos: pd.Series, cagr_valor: float, taxa_livre: float) -> float:
    desvio = semidesvio_anual(retornos)
    return (cagr_valor - taxa_livre) / desvio if desvio > 0 else 0.0


def comparar(nome: str, dart: float, python: float) -> tuple[str, bool]:
    """Compara e devolve (linha formatada, passou)."""
    if pd.isna(dart) or pd.isna(python):
        return (f"| {nome} | {dart} | {python} | — | ⚪ sem dado |", True)
    escala = max(abs(dart), abs(python), 1e-9)
    desvio = abs(dart - python) / escala
    passou = desvio < 1e-4
    marca = "✅" if passou else "❌"
    return (
        f"| {nome} | {dart:.8f} | {python:.8f} | {desvio:.2e} | {marca} |",
        passou,
    )


def main() -> None:
    parametros = carregar_parametros()
    taxa_livre = float(parametros["taxa_livre_risco_anual"])

    retorno_total = pd.read_csv(BASE / "retorno_total.csv", parse_dates=["date"]).set_index("date")
    precos = pd.read_csv(BASE / "precos.csv", parse_dates=["date"]).set_index("date")
    metricas_dart = pd.read_csv(BASE / "metricas_equisim.csv").set_index("ticker")

    if "IBOV" not in precos.columns:
        sys.exit("precos.csv não contém a coluna IBOV; refaça a exportação.")
    indice_mercado = precos["IBOV"].dropna()

    linhas: list[str] = []
    total = 0
    aprovados = 0

    for ticker in retorno_total.columns:
        if ticker not in metricas_dart.index:
            continue

        indice = retorno_total[ticker].dropna()
        if len(indice) < 30:
            continue

        retornos = retornos_diarios(indice)
        dias = (indice.index[-1] - indice.index[0]).days

        py_retorno_total = float(indice.iloc[-1] / indice.iloc[0] - 1)
        py_cagr = cagr(indice, dias)
        py_vol = volatilidade_anual(retornos)
        py_mdd = max_drawdown(indice)
        py_sharpe = (py_cagr - taxa_livre) / py_vol if py_vol > 0 else 0.0
        py_sortino = sortino(retornos, py_cagr, taxa_livre)
        py_beta, py_corr, py_obs = beta_e_correlacao(indice, indice_mercado)

        d = metricas_dart.loc[ticker]
        comparacoes = [
            ("retorno total", float(d["retorno_total"]), py_retorno_total),
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

        linhas.append(f"\n### {ticker}\n")
        linhas.append("| Métrica | Equisim (Dart) | Python | Desvio relativo | |")
        linhas.append("|---|---|---|---|---|")
        for nome, valor_dart, valor_python in comparacoes:
            linha, passou = comparar(nome, valor_dart, valor_python)
            linhas.append(linha)
            if not (pd.isna(valor_dart) or pd.isna(valor_python)):
                total += 1
                aprovados += int(passou)

    cabecalho = [
        "# Conferência cruzada — Equisim × Python",
        "",
        f"Janela: {parametros['janela_inicio']} a {parametros['janela_fim']}  ",
        f"Taxa livre de risco: {taxa_livre:.4%} a.a. (CDI observado)  ",
        f"Desvio-padrão: {parametros['desvio_padrao']}  ",
        f"Pregões por ano: {parametros['pregoes_por_ano']}",
        "",
        "As métricas da coluna *Python* foram recalculadas de forma independente "
        "com `pandas` e `numpy` a partir das séries exportadas. Um desvio "
        "relativo acima de 1e-4 indica divergência entre as implementações.",
        "",
        f"**Resultado: {aprovados} de {total} comparações dentro da tolerância.**",
    ]

    saida = "\n".join(cabecalho + linhas) + "\n"
    destino = BASE / "conferencia_python.md"
    destino.write_text(saida, encoding="utf-8")

    print(f"{aprovados}/{total} comparações dentro da tolerância.")
    print(f"-> {destino}")
    if aprovados < total:
        sys.exit(1)


if __name__ == "__main__":
    main()

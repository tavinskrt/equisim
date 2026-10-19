"""O efeito do point-in-time por versão sobre as coortes (item B8).

Compara duas execuções do backtest trimestral, observação por observação:

- **sem versões**: a ingestão com a última versão de cada documento — o que o
  backtest fazia até 22/09/2026, e o que ele faz sem `data/cvm_versoes.json`;
- **com versões**: cada coorte lendo a versão que era pública na data dela.

A execução sem versões não é versionada (são 15 MB); ela se refaz tirando
`data/cvm_versoes.json` do lugar e rodando o backtest. Este script recebe os
dois arquivos e grava só o resumo da comparação.

Uso:
    python tool/reapresentacao_efeito.py SEM.json COM.json
"""

from __future__ import annotations

import json
import statistics as st
import sys
from pathlib import Path


def read(path: str) -> dict:
    return {(o["coorte"], o["ticker"]): o
            for o in json.loads(Path(path).read_text(encoding="utf-8"))}


def q(xs: list[float], p: float) -> float | None:
    xs = sorted(xs)
    return xs[int(p * (len(xs) - 1))] if xs else None


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    without_restatement, with_restatement = read(sys.argv[1]), read(sys.argv[2])
    common = without_restatement.keys() & with_restatement.keys()

    started_evaluating = [k for k in common
                        if without_restatement[k].get("upside") is None and with_restatement[k].get("upside") is not None]
    stopped_evaluating = [k for k in common
                         if without_restatement[k].get("upside") is not None and with_restatement[k].get("upside") is None]
    both = [k for k in common
             if without_restatement[k].get("upside") is not None and with_restatement[k].get("upside") is not None]
    fiscal_year_changed = [k for k in common
                       if without_restatement[k].get("fimDoExercicio") != with_restatement[k].get("fimDoExercicio")]

    fair_move, upside_move, moved = [], [], []
    for k in both:
        js, jc = without_restatement[k].get("justo"), with_restatement[k].get("justo")
        if js and jc and js > 0:
            r = jc / js - 1
            if abs(r) > 1e-9:
                moved.append(k)
                fair_move.append(abs(r))
        upside_move.append(abs(with_restatement[k]["upside"] - without_restatement[k]["upside"]))

    bm_changed = [k for k in common
                if without_restatement[k].get("bookToMarket") is not None
                and with_restatement[k].get("bookToMarket") is not None
                and abs(without_restatement[k]["bookToMarket"] - with_restatement[k]["bookToMarket"]) > 1e-9]

    by_cohort: dict[str, list[int]] = {}
    for k in common:
        c = by_cohort.setdefault(k[0], [0, 0])
        c[0] += 1
        if k in moved or k in started_evaluating or k in stopped_evaluating:
            c[1] += 1

    largest = sorted(
        ((abs(with_restatement[k]["justo"] / without_restatement[k]["justo"] - 1), k) for k in moved),
        reverse=True)[:10]
    summary = {
        "observacoesSemVersoes": len(without_restatement),
        "observacoesComVersoes": len(with_restatement),
        "emComum": len(common),
        "avaliadasNasDuas": len(both),
        "passaramASerAvaliadas": len(started_evaluating),
        "deixaramDeSerAvaliadas": len(stopped_evaluating),
        "exercicioMaisRecenteMudou": len(fiscal_year_changed),
        "precoJustoMudou": len(moved),
        "fracaoDasAvaliadasQueMudou": len(moved) / len(both) if both else None,
        "movimentoDoJustoEntreAsQueMudaram": {
            "mediana": q(fair_move, .5), "p90": q(fair_move, .9),
            "maximo": max(fair_move) if fair_move else None},
        "movimentoDoPotencialEmTodasAsAvaliadas": {
            "mediana": q(upside_move, .5), "p90": q(upside_move, .9)},
        "bookToMarketMudou": len(bm_changed),
        "coorteComMaisMudanca": max(
            ((c, v[1] / v[0]) for c, v in by_cohort.items() if v[0]),
            key=lambda x: x[1]) if by_cohort else None,
        "maioresMovimentos": [
            {"coorte": k[0], "ticker": k[1], "movimento": round(m, 4),
             "justoSem": without_restatement[k]["justo"], "justoCom": with_restatement[k]["justo"]}
            for m, k in largest],
    }
    Path("docs/validacao/reapresentacao_efeito.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=1), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())

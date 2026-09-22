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


def ler(caminho: str) -> dict:
    return {(o["coorte"], o["ticker"]): o
            for o in json.loads(Path(caminho).read_text(encoding="utf-8"))}


def q(xs: list[float], p: float) -> float | None:
    xs = sorted(xs)
    return xs[int(p * (len(xs) - 1))] if xs else None


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    sem, com = ler(sys.argv[1]), ler(sys.argv[2])
    comuns = sem.keys() & com.keys()

    passou_a_avaliar = [k for k in comuns
                        if sem[k].get("upside") is None and com[k].get("upside") is not None]
    deixou_de_avaliar = [k for k in comuns
                         if sem[k].get("upside") is not None and com[k].get("upside") is None]
    ambos = [k for k in comuns
             if sem[k].get("upside") is not None and com[k].get("upside") is not None]
    exercicio_mudou = [k for k in comuns
                       if sem[k].get("fimDoExercicio") != com[k].get("fimDoExercicio")]

    mov_justo, mov_upside, movidos = [], [], []
    for k in ambos:
        js, jc = sem[k].get("justo"), com[k].get("justo")
        if js and jc and js > 0:
            r = jc / js - 1
            if abs(r) > 1e-9:
                movidos.append(k)
                mov_justo.append(abs(r))
        mov_upside.append(abs(com[k]["upside"] - sem[k]["upside"]))

    bm_mudou = [k for k in comuns
                if sem[k].get("bookToMarket") is not None
                and com[k].get("bookToMarket") is not None
                and abs(sem[k]["bookToMarket"] - com[k]["bookToMarket"]) > 1e-9]

    por_coorte: dict[str, list[int]] = {}
    for k in comuns:
        c = por_coorte.setdefault(k[0], [0, 0])
        c[0] += 1
        if k in movidos or k in passou_a_avaliar or k in deixou_de_avaliar:
            c[1] += 1

    maiores = sorted(
        ((abs(com[k]["justo"] / sem[k]["justo"] - 1), k) for k in movidos),
        reverse=True)[:10]
    resumo = {
        "observacoesSemVersoes": len(sem),
        "observacoesComVersoes": len(com),
        "emComum": len(comuns),
        "avaliadasNasDuas": len(ambos),
        "passaramASerAvaliadas": len(passou_a_avaliar),
        "deixaramDeSerAvaliadas": len(deixou_de_avaliar),
        "exercicioMaisRecenteMudou": len(exercicio_mudou),
        "precoJustoMudou": len(movidos),
        "fracaoDasAvaliadasQueMudou": len(movidos) / len(ambos) if ambos else None,
        "movimentoDoJustoEntreAsQueMudaram": {
            "mediana": q(mov_justo, .5), "p90": q(mov_justo, .9),
            "maximo": max(mov_justo) if mov_justo else None},
        "movimentoDoPotencialEmTodasAsAvaliadas": {
            "mediana": q(mov_upside, .5), "p90": q(mov_upside, .9)},
        "bookToMarketMudou": len(bm_mudou),
        "coorteComMaisMudanca": max(
            ((c, v[1] / v[0]) for c, v in por_coorte.items() if v[0]),
            key=lambda x: x[1]) if por_coorte else None,
        "maioresMovimentos": [
            {"coorte": k[0], "ticker": k[1], "movimento": round(m, 4),
             "justoSem": sem[k]["justo"], "justoCom": com[k]["justo"]}
            for m, k in maiores],
    }
    Path("docs/validacao/reapresentacao_efeito.json").write_text(
        json.dumps(resumo, ensure_ascii=False, indent=1), encoding="utf-8")
    print(json.dumps(resumo, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())

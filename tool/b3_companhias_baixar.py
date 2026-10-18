"""Baixa o registro de cada emissor na B3: contagem de ações e eventos.

A página de empresas listadas da B3 é servida por um endpoint que devolve, por
emissor, a **quantidade de ações por classe** e os **eventos societários** —
desdobramento, grupamento e bonificação, com fator, data-com e ISIN — além dos
proventos em dinheiro. É o registro que o item A3.1 do plano pede: o fator
declarado, e não inferido do preço.

O emissor é o código de quatro letras do ticker (PETR para PETR3 e PETR4). A
consulta é por emissor, com pausa entre requisições.

Uso:
    python tool/b3_companhias_baixar.py            # emissores do universo
    python tool/b3_companhias_baixar.py PETR VALE  # emissores específicos
"""

from __future__ import annotations

import base64
import datetime as dt
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ENDPOINT = (
    "https://sistemaswebb3-listados.b3.com.br/listedCompaniesProxy/"
    "CompanyCall/GetListedSupplementCompany/"
)
DESTINATION = Path("data/b3/companhias")
PAUSE = 0.6


def query(issuer: str) -> object | None:
    load = json.dumps({"issuingCompany": issuer, "language": "pt-br"})
    url = ENDPOINT + base64.b64encode(load.encode()).decode()
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=60) as r:
                return json.load(r)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
            print(f"  {issuer}: tentativa {attempt + 1} falhou ({e})")
            time.sleep(3 * (attempt + 1))
    return None


def main() -> int:
    if len(sys.argv) > 1:
        issuers = sorted({a.upper()[:4] for a in sys.argv[1:]})
    else:
        universe = json.loads(Path("docs/validacao/universo.json").read_text(encoding="utf-8"))
        issuers = sorted({e["ticker"][:4] for e in universe})

    DESTINATION.mkdir(parents=True, exist_ok=True)
    failures, empty = [], []
    for i, issuer in enumerate(issuers, 1):
        payload = query(issuer)
        if payload is None:
            failures.append(issuer)
        elif not payload:
            empty.append(issuer)
        else:
            record = {"consultadoEm": dt.date.today().isoformat(), "resposta": payload}
            (DESTINATION / f"{issuer}.json").write_text(
                json.dumps(record, ensure_ascii=False), encoding="utf-8"
            )
        if i % 25 == 0:
            print(f"  {i}/{len(issuers)}")
        time.sleep(PAUSE)

    print(f"\n{len(issuers) - len(failures) - len(empty)} emissores gravados em {DESTINATION}")
    if empty:
        print("sem registro na B3: " + " ".join(empty))
    if failures:
        print("!! FALHARAM: " + " ".join(failures))
    return 0


if __name__ == "__main__":
    sys.exit(main())

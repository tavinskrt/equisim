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
DESTINO = Path("data/b3/companhias")
PAUSA = 0.6


def consultar(emissor: str) -> object | None:
    carga = json.dumps({"issuingCompany": emissor, "language": "pt-br"})
    url = ENDPOINT + base64.b64encode(carga.encode()).decode()
    for tentativa in range(3):
        try:
            with urllib.request.urlopen(url, timeout=60) as r:
                return json.load(r)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
            print(f"  {emissor}: tentativa {tentativa + 1} falhou ({e})")
            time.sleep(3 * (tentativa + 1))
    return None


def main() -> int:
    if len(sys.argv) > 1:
        emissores = sorted({a.upper()[:4] for a in sys.argv[1:]})
    else:
        universo = json.loads(Path("docs/validacao/universo.json").read_text(encoding="utf-8"))
        emissores = sorted({e["ticker"][:4] for e in universo})

    DESTINO.mkdir(parents=True, exist_ok=True)
    falhas, vazios = [], []
    for i, emissor in enumerate(emissores, 1):
        dado = consultar(emissor)
        if dado is None:
            falhas.append(emissor)
        elif not dado:
            vazios.append(emissor)
        else:
            registro = {"consultadoEm": dt.date.today().isoformat(), "resposta": dado}
            (DESTINO / f"{emissor}.json").write_text(
                json.dumps(registro, ensure_ascii=False), encoding="utf-8"
            )
        if i % 25 == 0:
            print(f"  {i}/{len(emissores)}")
        time.sleep(PAUSA)

    print(f"\n{len(emissores) - len(falhas) - len(vazios)} emissores gravados em {DESTINO}")
    if vazios:
        print("sem registro na B3: " + " ".join(vazios))
    if falhas:
        print("!! FALHARAM: " + " ".join(falhas))
    return 0


if __name__ == "__main__":
    sys.exit(main())

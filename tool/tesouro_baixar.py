"""Baixa as taxas diárias do Tesouro Direto (Tesouro Transparente).

Arquivo único, de 2004 até o dia útil anterior, com a taxa e o preço de cada
título. É dele que sai a curva nominal do item A2 — o *Tesouro Prefixado*
(LTN, cupom zero) e o *Prefixado com Juros Semestrais* (NTN-F).

Aberto, sem cadastro. O endereço vem do catálogo CKAN, e não fica fixo aqui:
o identificador do recurso muda quando o Tesouro republica o conjunto.

Uso:
    python tool/tesouro_baixar.py
"""

from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

CATALOG = (
    "https://www.tesourotransparente.gov.br/ckan/api/3/action/package_show"
    "?id=taxas-dos-titulos-ofertados-pelo-tesouro-direto"
)
DESTINATION = Path("data/tesouro/precotaxatesourodireto.csv")
# O download do CSV já respondeu 429 (26/10/2026). O agente de navegador é o
# mesmo dos scripts da B3, que recusam o User-Agent padrão do urllib.
HEADER = {"User-Agent": "Mozilla/5.0 (equisim)"}
# Espera, em segundos, antes de cada nova tentativa depois de um 429 ou 503,
# quando o servidor não diz quanto esperar (Retry-After).
BACKOFF = (15, 30, 60, 120)


def fetch(url: str, timeout: int) -> bytes:
    """O corpo de [url], tentando de novo quando o servidor pede para esperar."""
    for attempt in range(len(BACKOFF) + 1):
        try:
            request = urllib.request.Request(url, headers=HEADER)
            with urllib.request.urlopen(request, timeout=timeout) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code not in (429, 503) or attempt == len(BACKOFF):
                raise
            after = e.headers.get("Retry-After", "")
            wait = int(after) if after.isdigit() else BACKOFF[attempt]
            print(f"  HTTP {e.code}; nova tentativa em {wait} s")
            time.sleep(wait)
    raise AssertionError("inalcançável")


def main() -> int:
    package = json.loads(fetch(CATALOG, timeout=60))
    csv = [
        rec["url"]
        for rec in package["result"]["resources"]
        if (rec.get("format") or "").upper() == "CSV"
    ]
    if not csv:
        print("o catálogo não lista CSV — conferir o conjunto no Tesouro")
        return 2
    DESTINATION.parent.mkdir(parents=True, exist_ok=True)
    DESTINATION.write_bytes(fetch(csv[0], timeout=300))
    print(f"{DESTINATION}: {DESTINATION.stat().st_size / 1e6:.1f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())

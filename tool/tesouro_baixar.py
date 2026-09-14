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
import urllib.request
from pathlib import Path

CATALOGO = (
    "https://www.tesourotransparente.gov.br/ckan/api/3/action/package_show"
    "?id=taxas-dos-titulos-ofertados-pelo-tesouro-direto"
)
DESTINO = Path("data/tesouro/precotaxatesourodireto.csv")


def main() -> int:
    with urllib.request.urlopen(CATALOGO, timeout=60) as r:
        pacote = json.load(r)
    csv = [
        rec["url"]
        for rec in pacote["result"]["resources"]
        if (rec.get("format") or "").upper() == "CSV"
    ]
    if not csv:
        print("o catálogo não lista CSV — conferir o conjunto no Tesouro")
        return 2
    DESTINO.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(csv[0], timeout=300) as r:
        DESTINO.write_bytes(r.read())
    print(f"{DESTINO}: {DESTINO.stat().st_size / 1e6:.1f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())

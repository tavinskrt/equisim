"""Baixa o COTAHIST anual da B3 e grava só o mercado à vista, em CSV compacto.

O COTAHIST é o arquivo histórico oficial da B3: todo papel negociado em cada
ano, **inclusive os que depois deixaram de existir**, com fechamento bruto, o
`DISMES` (número de distribuição) e o ISIN. É a metade de preço da amostra sem
viés de sobrevivência (item A3.2 do plano, pré-requisito do C1b).

**Por que compacto.** O arquivo de 2024 tem 650 MB descompactado; de 2010 a
2026 passariam de 5 GB, quase tudo opção, termo e leilão. O ZIP é lido em
fluxo, sem ir a disco descompactado, e só o registro à vista em lote padrão é
gravado — com os campos que a ponte e o ajuste por evento precisam.

Layout do registro `01` (posições da B3, base 1): data 3–10, BDI 11–12, ticker
13–24, mercado 25–27, nome 28–39, especificação 40–49, fechamento 109–121 (duas
casas), volume 171–188 (duas casas), fator de cotação 211–217, ISIN 231–242,
`DISMES` 243–245.

Uso:
    python tool/b3_baixar.py                 # 2010 até o ano corrente
    python tool/b3_baixar.py --de 2018 --ate 2020
"""

from __future__ import annotations

import argparse
import datetime as dt
import io
import sys
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

RAIZ = "https://bvmf.bmfbovespa.com.br/InstDados/SerHist"
CABECALHO = "data;ticker;isin;especificacao;nome;fechamento;fatorCotacao;distribuicao;volume\n"


def baixar(ano: int, destino: Path) -> tuple[int, int] | None:
    """Baixa um ano e grava `avista_{ano}.csv`. Devolve (linhas, bytes do ZIP)."""
    url = f"{RAIZ}/COTAHIST_A{ano}.ZIP"
    # O servidor da B3 devolve 403 ao User-Agent padrão do urllib.
    pedido = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (equisim)"})
    try:
        with urllib.request.urlopen(pedido, timeout=600) as r:
            bruto = r.read()
    except urllib.error.HTTPError as e:
        if e.code == 404:
            print(f"  {ano}: NÃO PUBLICADO (404)")
            return None
        raise

    destino.mkdir(parents=True, exist_ok=True)
    saida = destino / f"avista_{ano}.csv"
    n = 0
    with zipfile.ZipFile(io.BytesIO(bruto)) as z, saida.open("w", encoding="utf-8") as out:
        out.write(CABECALHO)
        nome = next(x for x in z.namelist() if x.upper().endswith(".TXT"))
        with z.open(nome) as f:
            for linha in io.TextIOWrapper(f, encoding="latin-1"):
                if not linha.startswith("01") or len(linha) < 245:
                    continue
                if linha[24:27] != "010" or linha[10:12] != "02":
                    continue
                data = f"{linha[2:6]}-{linha[6:8]}-{linha[8:10]}"
                campos = (
                    data,
                    linha[12:24].strip(),
                    linha[230:242].strip(),
                    linha[39:49].strip(),
                    linha[27:39].strip().replace(";", ","),
                    str(int(linha[108:121])),
                    str(int(linha[210:217])),
                    str(int(linha[242:245])),
                    str(int(linha[170:188])),
                )
                out.write(";".join(campos) + "\n")
                n += 1
    print(f"  {ano}: {n} pregões à vista, ZIP de {len(bruto) / 1e6:.1f} MB")
    return (n, len(bruto))


def main() -> int:
    hoje = dt.date.today()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--de", type=int, default=2010)
    ap.add_argument("--ate", type=int, default=hoje.year)
    ap.add_argument("--destino", type=Path, default=Path("data/b3"))
    a = ap.parse_args()

    ausentes = []
    total = 0
    for ano in range(a.de, a.ate + 1):
        r = baixar(ano, a.destino)
        if r is None:
            ausentes.append(ano)
        else:
            total += r[0]
    print(f"\n{total} pregões à vista em {a.destino}")
    if ausentes:
        print("!! ANOS NÃO PUBLICADOS: " + ", ".join(map(str, ausentes)))
    return 0


if __name__ == "__main__":
    sys.exit(main())

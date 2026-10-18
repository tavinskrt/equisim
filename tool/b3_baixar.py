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

ROOT = "https://bvmf.bmfbovespa.com.br/InstDados/SerHist"
HEADER = "data;ticker;isin;especificacao;nome;fechamento;fatorCotacao;distribuicao;volume\n"
# Máxima e mínima do pregão, para a estimativa de spread de Corwin e Schultz
# (item C4). Arquivo à parte, e não colunas a mais em `avista_*.csv`: os
# leitores de lá são posicionais, e baixar de novo por cima misturaria uma
# revisão eventual da fonte à medição que estiver em curso.
EXTREMES_HEADER = "data;ticker;isin;maxima;minima;fechamento;fatorCotacao\n"


def download(year: int, destination: Path, extremes: bool = False) -> tuple[int, int] | None:
    """Baixa um ano e grava `avista_{ano}.csv` — ou `extremos_{ano}.csv`, com
    [extremes]. Devolve (linhas, bytes do ZIP)."""
    url = f"{ROOT}/COTAHIST_A{year}.ZIP"
    # O servidor da B3 devolve 403 ao User-Agent padrão do urllib.
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (equisim)"})
    try:
        with urllib.request.urlopen(request, timeout=600) as r:
            raw = r.read()
    except urllib.error.HTTPError as e:
        if e.code == 404:
            print(f"  {year}: NÃO PUBLICADO (404)")
            return None
        raise

    destination.mkdir(parents=True, exist_ok=True)
    output = destination / (f"extremos_{year}.csv" if extremes else f"avista_{year}.csv")
    n = 0
    with zipfile.ZipFile(io.BytesIO(raw)) as z, output.open("w", encoding="utf-8") as out:
        out.write(EXTREMES_HEADER if extremes else HEADER)
        name = next(x for x in z.namelist() if x.upper().endswith(".TXT"))
        with z.open(name) as f:
            for line in io.TextIOWrapper(f, encoding="latin-1"):
                if not line.startswith("01") or len(line) < 245:
                    continue
                if line[24:27] != "010" or line[10:12] != "02":
                    continue
                date = f"{line[2:6]}-{line[6:8]}-{line[8:10]}"
                if extremes:
                    out.write(";".join((
                        date,
                        line[12:24].strip(),
                        line[230:242].strip(),
                        str(int(line[69:82])),   # PREMAX, em centavos
                        str(int(line[82:95])),   # PREMIN
                        str(int(line[108:121])),
                        str(int(line[210:217])),
                    )) + "\n")
                    n += 1
                    continue
                fields = (
                    date,
                    line[12:24].strip(),
                    line[230:242].strip(),
                    line[39:49].strip(),
                    line[27:39].strip().replace(";", ","),
                    str(int(line[108:121])),
                    str(int(line[210:217])),
                    str(int(line[242:245])),
                    str(int(line[170:188])),
                )
                out.write(";".join(fields) + "\n")
                n += 1
    print(f"  {year}: {n} pregões à vista, ZIP de {len(raw) / 1e6:.1f} MB")
    return (n, len(raw))


def main() -> int:
    today = dt.date.today()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--de", type=int, default=2010)
    ap.add_argument("--ate", type=int, default=today.year)
    ap.add_argument("--destino", type=Path, default=Path("data/b3"))
    ap.add_argument("--extremos", action="store_true",
                    help="grava máxima e mínima em extremos_{ano}.csv (item C4)")
    a = ap.parse_args()

    missing = []
    total = 0
    for year in range(a.de, a.ate + 1):
        r = download(year, a.destino, extremes=a.extremos)
        if r is None:
            missing.append(year)
        else:
            total += r[0]
    print(f"\n{total} pregões à vista em {a.destino}")
    if missing:
        print("!! ANOS NÃO PUBLICADOS: " + ", ".join(map(str, missing)))
    return 0


if __name__ == "__main__":
    sys.exit(main())

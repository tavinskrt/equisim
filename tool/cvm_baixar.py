"""Baixa e extrai os arquivos anuais da CVM.

A CVM não é API de tempo real — é publicação anual em massa. Por isso o
download é ferramenta, e não camada de dados do aplicativo: roda quando se
quer atualizar a base, não a cada avaliação.

**Baixar todos os anos é o que fecha o viés de sobrevivência (§1.3).** O
arquivo de cada ano contém as companhias que existiam *naquele* ano; uma que
fechou capital em 2019 está no arquivo de 2019 e não no de 2024. Confiar no
universo de hoje é o que produz o viés.

Uso:
    python tool/cvm_baixar.py                    # 2010 até o ano corrente
    python tool/cvm_baixar.py --de 2020 --ate 2024
    python tool/cvm_baixar.py --destino data/cvm
    python tool/cvm_baixar.py --docs FRE --destino data/cvm/fre
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

RAIZ = "https://dados.cvm.gov.br/dados/CIA_ABERTA/DOC"

# Só o que o motor consome. DMPL e DVA somam 400 MB por ano e nada usa.
INTERESSAM = (
    "_BPA_con_", "_BPA_ind_",
    "_BPP_con_", "_BPP_ind_",
    "_DRE_con_", "_DRE_ind_",
    "_DFC_MI_con_", "_DFC_MI_ind_",
    "_composicao_capital_",
    "_valor_mobiliario_",
    # Formulário de Referência: contagem de ações e eventos por data, para as
    # companhias que já não estão na B3 (item A3.4), e o prazo das outorgas
    # no quadro de intangíveis (item A6).
    "_capital_social_",
    "_ativo_intangivel_",
    # FCA geral: o setor de atividade que a companhia declara, por ano — o
    # recuo da classificação da B3 para as deslistadas que o portal não
    # responde (item C1b).
    "_geral_",
)


def _e_metadado(nome: str, doc: str) -> bool:
    """O CSV de metadados é `{doc}_cia_aberta_{ano}.csv`, sem sufixo."""
    return nome.lower() == f"{doc.lower()}_cia_aberta_{nome[-8:-4]}.csv"


def baixar(doc: str, ano: int, destino: Path) -> tuple[int, int] | None:
    """Baixa um zip e extrai os CSVs de interesse.

    Devolve (extraídos, bytes), ou ``None`` quando a fonte não publica o ano.
    """
    url = f"{RAIZ}/{doc}/DADOS/{doc.lower()}_cia_aberta_{ano}.zip"
    try:
        with urllib.request.urlopen(url, timeout=180) as r:
            bruto = r.read()
    except urllib.error.HTTPError as e:
        if e.code == 404:
            print(f"  {doc} {ano}: NÃO PUBLICADO pela CVM (404)")
            return None
        raise

    n = 0
    with zipfile.ZipFile(io.BytesIO(bruto)) as z:
        for nome in z.namelist():
            if not nome.lower().endswith(".csv"):
                continue
            if not (any(s in nome for s in INTERESSAM) or _e_metadado(nome, doc)):
                continue
            destino.mkdir(parents=True, exist_ok=True)
            (destino / nome).write_bytes(z.read(nome))
            n += 1
    print(f"  {doc} {ano}: {n} arquivo(s), {len(bruto)/1e6:.1f} MB baixados")
    return (n, len(bruto))


def main() -> int:
    hoje = dt.date.today()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--de", type=int, default=2010)
    ap.add_argument("--ate", type=int, default=hoje.year)
    ap.add_argument("--destino", type=Path, default=Path("data/cvm"))
    ap.add_argument(
        "--docs",
        default="DFP,ITR,FCA",
        help="documentos a baixar, separados por vírgula",
    )
    a = ap.parse_args()

    docs = [d.strip().upper() for d in a.docs.split(",") if d.strip()]
    total_arq = total_bytes = 0
    ausentes: list[str] = []
    for ano in range(a.de, a.ate + 1):
        print(f"{ano}:")
        for doc in docs:
            r = baixar(doc, ano, a.destino)
            if r is None:
                ausentes.append(f"{doc} {ano}")
                continue
            total_arq += r[0]
            total_bytes += r[1]

    print(
        f"\n{total_arq} arquivos, {total_bytes/1e6:.0f} MB baixados "
        f"para {a.destino}"
    )
    print(
        "Os anos antigos trazem companhias que já não existem — é o que "
        "remove o viés de sobrevivência."
    )
    # O ano corrente da DFP ainda não existe e é esperado; qualquer outro
    # ausente é lacuna da fonte, e tem de ser dito — em 14/09/2026 a CVM não
    # publicava o ITR de 2025, e a série trimestral saiu com buraco por isso.
    esperados = {f"DFP {hoje.year}"}
    lacunas = [x for x in ausentes if x not in esperados]
    if lacunas:
        print()
        print("!! LACUNAS NA FONTE — anos que a CVM não publica:")
        for x in lacunas:
            print(f"!!   {x}")
        print("!! A série trimestral recua para DFP onde houver buraco "
              "(decisão 73).")
    return 0


if __name__ == "__main__":
    sys.exit(main())

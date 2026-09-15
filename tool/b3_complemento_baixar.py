"""Baixa, por emissor, a classificação setorial e o histórico de proventos da B3.

Duas consultas do mesmo portal de empresas listadas que o
`b3_companhias_baixar.py` já usa, e que ele não cobre:

- **`GetDetail`** devolve a classificação setorial oficial da B3 —
  `Setor / Subsetor / Segmento` —, por emissor. É a fonte do item A5.
- **`GetListedCashDividends`** devolve o histórico de proventos em dinheiro, com
  data-ex, valor por ação, rótulo e preço antes da data-ex, desde o começo da
  série da B3. É a fonte do item A4. O registro do `GetListedSupplementCompany`
  só traz os últimos doze meses: em 14/09/2026, o provento mais antigo dos
  1.082 que ele listava era de 12/09/2025.

Lê o `codeCVM` e o `tradingName` de `data/b3/companhias/`, que tem de existir
antes. O nome de pregão entra sem espaços, que é como a consulta o aceita.

**As deslistadas também.** A consulta de proventos é por nome de pregão, e
responde para companhia que já saiu da bolsa — CIELO e SOUZACRUZ trazem o
histórico inteiro. O nome vem do COTAHIST, papel a papel, para as companhias da
ponte de `b3_ponte.py` (item A3.4).

Uso:
    python tool/b3_complemento_baixar.py               # emissores já baixados
    python tool/b3_complemento_baixar.py PETR VALE     # emissores específicos
    python tool/b3_complemento_baixar.py --deslistadas # proventos das deslistadas
    python tool/b3_complemento_baixar.py --deslistadas-classificacao
                                                       # setor das deslistadas (C1b)
    python tool/b3_complemento_baixar.py --deslistadas --so-faltantes
    python tool/b3_complemento_baixar.py --deslistadas-classificacao --so-faltantes
                                                       # só as que a ponte ganhou (C1d)

``--so-faltantes`` consulta só a companhia sem arquivo — ou, na classificação, sem
detalhe gravado. Sem ele, ``--deslistadas`` regrava o arquivo inteiro e apaga o
detalhe que a classificação tinha gravado nele.
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

RAIZ = "https://sistemaswebb3-listados.b3.com.br/listedCompaniesProxy/CompanyCall/"
ORIGEM = Path("data/b3/companhias")
DESTINO = Path("data/b3/complemento")
PAUSA = 0.6
POR_PAGINA = 120
# O portal recusa pedido sem agente de navegador (403), como o COTAHIST.
CABECALHO = {"User-Agent": "Mozilla/5.0"}


def consultar(metodo: str, carga: dict) -> object | None:
    url = RAIZ + metodo + "/" + base64.b64encode(json.dumps(carga).encode()).decode()
    for tentativa in range(3):
        try:
            pedido = urllib.request.Request(url, headers=CABECALHO)
            with urllib.request.urlopen(pedido, timeout=60) as r:
                return json.load(r)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
            print(f"  {metodo}: tentativa {tentativa + 1} falhou ({e})")
            time.sleep(3 * (tentativa + 1))
    return None


def proventos(nome_pregao: str) -> list | None:
    """Todas as páginas; `None` se alguma falhar — série parcial não é série."""
    pagina, total, linhas = 1, None, []
    while total is None or pagina <= total:
        dado = consultar(
            "GetListedCashDividends",
            {
                "language": "pt-br",
                "pageNumber": pagina,
                "pageSize": POR_PAGINA,
                "tradingName": nome_pregao,
            },
        )
        if not isinstance(dado, dict):
            return None
        total = (dado.get("page") or {}).get("totalPages") or 0
        linhas.extend(dado.get("results") or [])
        pagina += 1
        time.sleep(PAUSA)
    return linhas


def nomes_de_pregao(tickers: set[str]) -> dict[str, str]:
    """Último nome resumido do emissor no COTAHIST, por ticker."""
    nomes: dict[str, str] = {}
    for arquivo in sorted(Path("data/b3").glob("avista_*.csv")):
        with arquivo.open(encoding="utf-8", errors="replace") as f:
            next(f, None)
            for linha in f:
                c = linha.split(";")
                if len(c) > 4 and c[1] in tickers:
                    nomes[c[1]] = c[4].strip()
    return nomes


def deslistadas(so_faltantes: bool = False) -> int:
    ponte = json.loads(Path("data/b3/ponte_deslistadas.json").read_text(encoding="utf-8"))
    tickers = {t for c in ponte.values() for t in c["papeis"]}
    nomes = nomes_de_pregao(tickers)
    destino = Path("data/b3/complemento_deslistadas")
    destino.mkdir(parents=True, exist_ok=True)
    falhas, sem_nome = [], []
    for i, (cnpj, c) in enumerate(sorted(ponte.items()), 1):
        if so_faltantes and (destino / (cnpj.replace(".", "").replace("/", "").replace("-", "") + ".json")).exists():
            continue
        candidatos = {nomes[t] for t in c["papeis"] if t in nomes}
        if not candidatos:
            sem_nome.append(cnpj)
            continue
        registros = []
        for nome in sorted(candidatos):
            historico = proventos(nome.replace(" ", ""))
            if historico is None:
                falhas.append(f"{cnpj} {nome}")
                continue
            registros.append({"nomePregao": nome, "proventos": historico})
        arquivo = destino / (cnpj.replace(".", "").replace("/", "").replace("-", "") + ".json")
        arquivo.write_text(
            json.dumps(
                {
                    "consultadoEm": dt.date.today().isoformat(),
                    "cnpj": cnpj,
                    "tickers": sorted(c["papeis"]),
                    "consultas": registros,
                },
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )
        if i % 25 == 0:
            print(f"  {i}/{len(ponte)}")
    print(f"\n{len(ponte) - len(sem_nome)} companhias consultadas em {destino}")
    if sem_nome:
        print("sem nome de pregão no COTAHIST: " + " ".join(sem_nome))
    if falhas:
        print("!! FALHARAM: " + " ".join(falhas))
    return 0


def codigos_cvm(cnpjs: set[str]) -> dict[str, str]:
    """Código CVM de cada CNPJ, do índice anual da FCA — o último declarado."""
    codigos: dict[str, str] = {}
    for arquivo in sorted(Path("data/cvm").glob("fca_cia_aberta_20[0-9][0-9].csv")):
        with arquivo.open(encoding="latin-1") as f:
            next(f, None)
            for linha in f:
                c = linha.split(";")
                if len(c) > 4 and c[0] in cnpjs and c[4].strip().isdigit():
                    codigos[c[0]] = str(int(c[4]))
    return codigos


def classificacao_deslistadas(so_faltantes: bool = False) -> int:
    """Classificação setorial da B3 das deslistadas (item C1b).

    O ``GetDetail`` responde para boa parte das companhias que saíram da bolsa,
    e é a mesma taxonomia que a decisão 87 usa nas listadas. Grava o detalhe no
    arquivo de proventos de cada companhia, que já existe; resposta vazia fica
    registrada como vazia, e não inventada.
    """
    destino = Path("data/b3/complemento_deslistadas")
    ponte = json.loads(Path("data/b3/ponte_deslistadas.json").read_text(encoding="utf-8"))
    codigos = codigos_cvm(set(ponte))
    sem_codigo, vazias, falhas, com = [], [], [], 0
    for i, cnpj in enumerate(sorted(ponte), 1):
        arquivo = destino / (cnpj.replace(".", "").replace("/", "").replace("-", "") + ".json")
        if not arquivo.exists():
            continue
        registro = json.loads(arquivo.read_text(encoding="utf-8"))
        if so_faltantes and "detalhe" in registro:
            continue
        codigo = codigos.get(cnpj)
        if codigo is None:
            sem_codigo.append(cnpj)
            continue
        detalhe = consultar("GetDetail", {"codeCVM": codigo, "language": "pt-br"})
        time.sleep(PAUSA)
        if detalhe is None:
            falhas.append(cnpj)
            continue
        registro["codigoCvm"] = codigo
        registro["detalhe"] = detalhe
        registro["detalheConsultadoEm"] = dt.date.today().isoformat()
        arquivo.write_text(json.dumps(registro, ensure_ascii=False), encoding="utf-8")
        if isinstance(detalhe, dict) and (detalhe.get("industryClassification") or "").strip():
            com += 1
        else:
            vazias.append(cnpj)
        if i % 25 == 0:
            print(f"  {i}/{len(ponte)}")
    print(f"\n{com} com classificação; {len(vazias)} sem; {len(sem_codigo)} sem código CVM")
    if vazias:
        print("sem classificação: " + " ".join(vazias))
    if falhas:
        print("!! FALHARAM: " + " ".join(falhas))
    return 0


def main() -> int:
    so_faltantes = "--so-faltantes" in sys.argv[1:]
    if "--deslistadas-classificacao" in sys.argv[1:]:
        return classificacao_deslistadas(so_faltantes)
    if "--deslistadas" in sys.argv[1:]:
        return deslistadas(so_faltantes)
    pedidos = {a.upper()[:4] for a in sys.argv[1:] if not a.startswith("--")}
    arquivos = sorted(ORIGEM.glob("*.json"))
    if pedidos:
        arquivos = [a for a in arquivos if a.stem in pedidos]

    DESTINO.mkdir(parents=True, exist_ok=True)
    falhas, sem_nome = [], []
    for i, arquivo in enumerate(arquivos, 1):
        resposta = json.loads(arquivo.read_text(encoding="utf-8")).get("resposta") or []
        if not resposta:
            continue
        emissor = arquivo.stem
        codigo_cvm = (resposta[0].get("codeCVM") or "").strip()
        nome_pregao = (resposta[0].get("tradingName") or "").replace(" ", "")
        if not codigo_cvm or not nome_pregao:
            sem_nome.append(emissor)
            continue

        detalhe = consultar("GetDetail", {"codeCVM": codigo_cvm, "language": "pt-br"})
        time.sleep(PAUSA)
        historico = proventos(nome_pregao)
        if detalhe is None or historico is None:
            falhas.append(emissor)
            continue

        registro = {
            "consultadoEm": dt.date.today().isoformat(),
            "detalhe": detalhe,
            "proventos": historico,
        }
        (DESTINO / f"{emissor}.json").write_text(
            json.dumps(registro, ensure_ascii=False), encoding="utf-8"
        )
        if i % 25 == 0:
            print(f"  {i}/{len(arquivos)}")

    print(f"\n{len(arquivos) - len(falhas) - len(sem_nome)} emissores gravados em {DESTINO}")
    if sem_nome:
        print("sem código CVM ou nome de pregão: " + " ".join(sem_nome))
    if falhas:
        print("!! FALHARAM: " + " ".join(falhas))
    return 0


if __name__ == "__main__":
    sys.exit(main())

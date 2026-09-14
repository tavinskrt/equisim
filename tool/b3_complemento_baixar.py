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


def deslistadas() -> int:
    ponte = json.loads(Path("data/b3/ponte_deslistadas.json").read_text(encoding="utf-8"))
    tickers = {t for c in ponte.values() for t in c["papeis"]}
    nomes = nomes_de_pregao(tickers)
    destino = Path("data/b3/complemento_deslistadas")
    destino.mkdir(parents=True, exist_ok=True)
    falhas, sem_nome = [], []
    for i, (cnpj, c) in enumerate(sorted(ponte.items()), 1):
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


def main() -> int:
    if "--deslistadas" in sys.argv[1:]:
        return deslistadas()
    pedidos = {a.upper()[:4] for a in sys.argv[1:]}
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

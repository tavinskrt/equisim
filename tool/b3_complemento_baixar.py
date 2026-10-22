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
antes. O nome de pregão entra sem espaços e sem barra, que é como a consulta o aceita.

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

ROOT = "https://sistemaswebb3-listados.b3.com.br/listedCompaniesProxy/CompanyCall/"
ORIGIN = Path("data/b3/companhias")
DESTINATION = Path("data/b3/complemento")
PAUSE = 0.6
PER_PAGE = 120
# O portal recusa pedido sem agente de navegador (403), como o COTAHIST.
HEADER = {"User-Agent": "Mozilla/5.0"}


def query(method: str, load: dict) -> object | None:
    url = ROOT + method + "/" + base64.b64encode(json.dumps(load).encode()).decode()
    for attempt in range(3):
        try:
            request = urllib.request.Request(url, headers=HEADER)
            with urllib.request.urlopen(request, timeout=60) as r:
                return json.load(r)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
            print(f"  {method}: tentativa {attempt + 1} falhou ({e})")
            time.sleep(3 * (attempt + 1))
    return None


def query_name(trading_name: str) -> str:
    """O nome de pregão como a consulta de proventos o aceita: sem espaços e sem barra.

    Com a barra, a consulta volta vazia sem erro: `AMBEVS/A` devolvia zero
    proventos, e `AMBEVSA` devolve os 40 da Ambev S.A. (item B44). Os nove
    emissores com barra no nome — Ambev, Klabin, Cury, Light, IMC, Ourofino,
    Embpar, Haga e Wetzel — tinham ficado sem histórico. Sem a barra, o nome
    não se confunde com outro: `AMBEV` sozinho é a antiga Companhia de Bebidas,
    incorporada em 2013.
    """
    return trading_name.replace(" ", "").replace("/", "")


def dividends(trading_name: str) -> list | None:
    """Todas as páginas; `None` se alguma falhar — série parcial não é série."""
    page, total, lines = 1, None, []
    while total is None or page <= total:
        payload = query(
            "GetListedCashDividends",
            {
                "language": "pt-br",
                "pageNumber": page,
                "pageSize": PER_PAGE,
                "tradingName": trading_name,
            },
        )
        if not isinstance(payload, dict):
            return None
        total = (payload.get("page") or {}).get("totalPages") or 0
        lines.extend(payload.get("results") or [])
        page += 1
        time.sleep(PAUSE)
    return lines


def trading_names(tickers: set[str]) -> dict[str, str]:
    """Último nome resumido do emissor no COTAHIST, por ticker."""
    names: dict[str, str] = {}
    for file in sorted(Path("data/b3").glob("avista_*.csv")):
        with file.open(encoding="utf-8", errors="replace") as f:
            next(f, None)
            for line in f:
                c = line.split(";")
                if len(c) > 4 and c[1] in tickers:
                    names[c[1]] = c[4].strip()
    return names


def delisted_list(only_missing: bool = False) -> int:
    bridge = json.loads(Path("data/b3/ponte_deslistadas.json").read_text(encoding="utf-8"))
    tickers = {t for c in bridge.values() for t in c["papeis"]}
    names = trading_names(tickers)
    destination = Path("data/b3/complemento_deslistadas")
    destination.mkdir(parents=True, exist_ok=True)
    failures, without_name = [], []
    for i, (cnpj, c) in enumerate(sorted(bridge.items()), 1):
        if only_missing and (destination / (cnpj.replace(".", "").replace("/", "").replace("-", "") + ".json")).exists():
            continue
        candidates = {names[t] for t in c["papeis"] if t in names}
        if not candidates:
            without_name.append(cnpj)
            continue
        records = []
        for name in sorted(candidates):
            history = dividends(query_name(name))
            if history is None:
                failures.append(f"{cnpj} {name}")
                continue
            records.append({"nomePregao": name, "proventos": history})
        file = destination / (cnpj.replace(".", "").replace("/", "").replace("-", "") + ".json")
        file.write_text(
            json.dumps(
                {
                    "consultadoEm": dt.date.today().isoformat(),
                    "cnpj": cnpj,
                    "tickers": sorted(c["papeis"]),
                    "consultas": records,
                },
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )
        if i % 25 == 0:
            print(f"  {i}/{len(bridge)}")
    print(f"\n{len(bridge) - len(without_name)} companhias consultadas em {destination}")
    if without_name:
        print("sem nome de pregão no COTAHIST: " + " ".join(without_name))
    if failures:
        print("!! FALHARAM: " + " ".join(failures))
    return 0


def cvm_codes(cnpjs: set[str]) -> dict[str, str]:
    """Código CVM de cada CNPJ, do índice anual da FCA — o último declarado."""
    codes: dict[str, str] = {}
    for file in sorted(Path("data/cvm").glob("fca_cia_aberta_20[0-9][0-9].csv")):
        with file.open(encoding="latin-1") as f:
            next(f, None)
            for line in f:
                c = line.split(";")
                if len(c) > 4 and c[0] in cnpjs and c[4].strip().isdigit():
                    codes[c[0]] = str(int(c[4]))
    return codes


def delisted_classification(only_missing: bool = False) -> int:
    """Classificação setorial da B3 das deslistadas (item C1b).

    O ``GetDetail`` responde para boa parte das companhias que saíram da bolsa,
    e é a mesma taxonomia que a decisão 87 usa nas listadas. Grava o detalhe no
    arquivo de proventos de cada companhia, que já existe; resposta vazia fica
    registrada como vazia, e não inventada.
    """
    destination = Path("data/b3/complemento_deslistadas")
    bridge = json.loads(Path("data/b3/ponte_deslistadas.json").read_text(encoding="utf-8"))
    codes = cvm_codes(set(bridge))
    without_code, empty_list, failures, found = [], [], [], 0
    for i, cnpj in enumerate(sorted(bridge), 1):
        file = destination / (cnpj.replace(".", "").replace("/", "").replace("-", "") + ".json")
        if not file.exists():
            continue
        record = json.loads(file.read_text(encoding="utf-8"))
        if only_missing and "detalhe" in record:
            continue
        code = codes.get(cnpj)
        if code is None:
            without_code.append(cnpj)
            continue
        detail = query("GetDetail", {"codeCVM": code, "language": "pt-br"})
        time.sleep(PAUSE)
        if detail is None:
            failures.append(cnpj)
            continue
        record["codigoCvm"] = code
        record["detalhe"] = detail
        record["detalheConsultadoEm"] = dt.date.today().isoformat()
        file.write_text(json.dumps(record, ensure_ascii=False), encoding="utf-8")
        if isinstance(detail, dict) and (detail.get("industryClassification") or "").strip():
            found += 1
        else:
            empty_list.append(cnpj)
        if i % 25 == 0:
            print(f"  {i}/{len(bridge)}")
    print(f"\n{found} com classificação; {len(empty_list)} sem; {len(without_code)} sem código CVM")
    if empty_list:
        print("sem classificação: " + " ".join(empty_list))
    if failures:
        print("!! FALHARAM: " + " ".join(failures))
    return 0


def main() -> int:
    only_missing = "--so-faltantes" in sys.argv[1:]
    if "--deslistadas-classificacao" in sys.argv[1:]:
        return delisted_classification(only_missing)
    if "--deslistadas" in sys.argv[1:]:
        return delisted_list(only_missing)
    requests = {a.upper()[:4] for a in sys.argv[1:] if not a.startswith("--")}
    files = sorted(ORIGIN.glob("*.json"))
    if requests:
        files = [a for a in files if a.stem in requests]

    DESTINATION.mkdir(parents=True, exist_ok=True)
    failures, without_name = [], []
    for i, file in enumerate(files, 1):
        response = json.loads(file.read_text(encoding="utf-8")).get("resposta") or []
        if not response:
            continue
        issuer = file.stem
        cvm_code = (response[0].get("codeCVM") or "").strip()
        trading_name = query_name(response[0].get("tradingName") or "")
        if not cvm_code or not trading_name:
            without_name.append(issuer)
            continue

        detail = query("GetDetail", {"codeCVM": cvm_code, "language": "pt-br"})
        time.sleep(PAUSE)
        history = dividends(trading_name)
        if detail is None or history is None:
            failures.append(issuer)
            continue

        record = {
            "consultadoEm": dt.date.today().isoformat(),
            "detalhe": detail,
            "proventos": history,
        }
        (DESTINATION / f"{issuer}.json").write_text(
            json.dumps(record, ensure_ascii=False), encoding="utf-8"
        )
        if i % 25 == 0:
            print(f"  {i}/{len(files)}")

    print(f"\n{len(files) - len(failures) - len(without_name)} emissores gravados em {DESTINATION}")
    if without_name:
        print("sem código CVM ou nome de pregão: " + " ".join(without_name))
    if failures:
        print("!! FALHARAM: " + " ".join(failures))
    return 0


if __name__ == "__main__":
    sys.exit(main())

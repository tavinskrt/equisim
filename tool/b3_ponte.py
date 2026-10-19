"""Liga as companhias da CVM fora do universo de hoje aos papéis do COTAHIST.

**Por que existe (item A3.2).** A amostra sem viés de sobrevivência (C1b) precisa
das duas pontas de cada companhia que deixou de existir: a demonstração, que a
ingestão da CVM já tem, e o preço, que está no COTAHIST. As duas não se
conhecem — a CVM identifica por CNPJ, o COTAHIST por ticker e ISIN.

**Duas pontes, em ordem de confiança.**

1. **Código declarado.** A FCA da CVM traz o código de negociação de cada
   valor mobiliário — **mas só de 2018 em diante**: de 2010 a 2017 a coluna vem
   vazia em todas as linhas (conferido em 14/09/2026). O código liga ao ticker
   do COTAHIST, e o ISIN dele ao emissor, que traz as outras classes.
2. **Nome, com sobreposição de anos.** Para a companhia que a FCA marca com
   ação *em bolsa* e sem código, o nome resumido do emissor no COTAHIST tem de
   ser prefixo do nome empresarial — atual ou anterior, que a FCA guarda — e
   os anos de DFP e de pregão têm de se tocar. Mais de um candidato é ambíguo,
   e fica de fora.

A companhia sem ação em bolsa na FCA — emissora de dívida, concessionária
fechada — não entra: ela não tem preço, e não pertence à amostra de retorno.

**O que o item C1d acrescentou (15/09/2026)**, depois de levantar as 128 que
ficavam sem ponte:

- **Viva é quem está nas coortes, e não na lista de hoje.** A ponte excluía a
  companhia com ticker em ``universo.json``; a coorte, porém, só tem a listada
  que a fonte de preços devolve. A BRF (BRFS3) e a Petz (PETZ3) saíram da bolsa
  por incorporação em 2025 e ficavam sem as duas pontas; a Tupy (TUPY3) e a
  Sequoia (SEQL3) estão listadas e a fonte não as traz. O universo vivo passa a
  ser ``docs/validacao/universo_coortes.json``, que o backtest grava.
- **Código de emissor.** Parte da FCA declara as quatro letras do emissor em vez
  do ticker — SJOS, OBTC —, e o COTAHIST as tem no ISIN.
- **Nome contido e nome curto.** O nome do COTAHIST dentro do nome empresarial,
  com seis letras ou mais — SCHLOSSER em CIA INDUSTRIAL SCHLOSSER —, ou nome de
  três a quatro letras que também é a raiz do ISIN — RAIA, TAM, AMIL. Com um
  candidato só e anos que se tocam, como a regra do nome.
- **O registro de quem fica fora**, companhia a companhia, em
  ``docs/validacao/ponte_deslistadas_registro.json``.

Uso:
    python tool/b3_baixar.py
    python tool/b3_ponte.py
Grava data/b3/ponte_deslistadas.json e docs/validacao/ponte_deslistadas_registro.json.
"""

from __future__ import annotations

import collections
import csv
import glob
import json
import re
import sys
import unicodedata
from pathlib import Path

OUTPUT = Path("data/b3/ponte_deslistadas.json")
REGISTRY = Path("docs/validacao/ponte_deslistadas_registro.json")
COHORT_UNIVERSE = Path("docs/validacao/universo_coortes.json")
SUFFIXES = (
    " S A", " SA", " CIA", " COMPANHIA", " EM RECUPERACAO JUDICIAL",
    " RECUPERACAO JUDICIAL", " EM LIQUIDACAO", " PARTICIPACOES", " PART", " HOLDING",
)


def normalize(s: str) -> str:
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().upper()
    s = re.sub(r"[^A-Z0-9 ]", " ", s)
    for w in SUFFIXES:
        s = s.replace(w, " ")
    return "".join(s.split())


def main() -> int:
    # Viva é a companhia que as coortes já observam como listada. Sem o arquivo
    # do backtest, recua para a lista de hoje.
    if COHORT_UNIVERSE.exists():
        universe = set(json.loads(COHORT_UNIVERSE.read_text(encoding="utf-8"))["tickers"])
    else:
        universe = {e["ticker"] for e in json.loads(Path("docs/validacao/universo.json").read_text(encoding="utf-8"))}
    documents = json.loads(Path("data/cvm_exercicios.json").read_text(encoding="utf-8"))

    companies: dict[str, dict] = collections.defaultdict(lambda: {"nome": "", "anos": set(), "tickers": set()})
    for d in documents:
        if d["documento"] != "DFP":
            continue
        c = companies[d["cnpj"]]
        c["nome"] = d["nome"]
        c["anos"].add(int(d["fimDoExercicio"][:4]))
        c["tickers"].update(d["tickers"] or [])

    listed: set[str] = set()
    codes: dict[str, set[str]] = collections.defaultdict(set)
    names: dict[str, set[str]] = collections.defaultdict(set)
    markets: dict[str, set[str]] = collections.defaultdict(set)
    for f in glob.glob("data/cvm/fca_cia_aberta_valor_mobiliario_*.csv"):
        with open(f, encoding="latin-1") as h:
            for r in csv.DictReader(h, delimiter=";"):
                cnpj = r["CNPJ_Companhia"]
                if (r.get("Valor_Mobiliario") or "").startswith("A") and (r.get("Mercado") or "").strip() == "Bolsa":
                    listed.add(cnpj)
                cod = (r.get("Codigo_Negociacao") or "").strip().upper()
                if cod:
                    codes[cnpj].add(cod)
                if r.get("Nome_Empresarial"):
                    names[cnpj].add(r["Nome_Empresarial"])
                if (r.get("Valor_Mobiliario") or "").startswith("A") and (r.get("Mercado") or "").strip():
                    markets[cnpj].add(r["Mercado"].strip())

    securities: dict[str, dict] = {}
    issuers: dict[str, dict] = collections.defaultdict(lambda: {"nomes": set(), "anos": set(), "tickers": set()})
    for f in sorted(glob.glob("data/b3/avista_*.csv")):
        year = int(f[-8:-4])
        with open(f, encoding="utf-8") as h:
            next(h)
            for line in h:
                date, tk, isin, _kind, name = line.split(";")[:5]
                p = securities.setdefault(tk, {"isin": isin, "primeiro": date, "ultimo": date})
                p["ultimo"] = max(p["ultimo"], date)
                p["primeiro"] = min(p["primeiro"], date)
                if isin.startswith("BR") and len(isin) == 12:
                    e = issuers[isin[2:6]]
                    e["nomes"].add(name)
                    e["anos"].add(year)
                    e["tickers"].add(tk)

    if not securities:
        print("sem COTAHIST em data/b3 — rodar tool/b3_baixar.py")
        return 2

    alive = {cnpj for cnpj, c in companies.items() if c["tickers"] & universe}
    live_issuers = {t[:4] for t in universe}
    bridge: dict[str, dict] = {}

    def overlap_years(dfp_years: set[int], trading_years: set[int]) -> bool:
        return bool(dfp_years & (trading_years | {a - 1 for a in trading_years}))

    # 1. Código declarado
    for cnpj, c in companies.items():
        if cnpj in alive:
            continue
        declared = c["tickers"] | codes.get(cnpj, set())
        issuer_lane = {tk for x in declared if len(x) >= 5 for tk in issuers.get(x[:4], {}).get("tickers", ())}
        tickers = sorted({x for x in declared if x in securities} | issuer_lane)
        if tickers:
            bridge[cnpj] = {"via": "codigo", "tickers": tickers}
            continue
        # 1b. As quatro letras do emissor no lugar do ticker, com os anos tocando.
        roots = {x for x in declared if len(x) == 4 and x.isalpha() and x in issuers and overlap_years(c["anos"], issuers[x]["anos"])}
        if len(roots) == 1:
            bridge[cnpj] = {"via": "emissor", "tickers": sorted(issuers[roots.pop()]["tickers"])}

    # 2. Nome, para quem tinha ação em bolsa e nenhum código
    linked = {tk[:4] for p in bridge.values() for tk in p["tickers"]} | live_issuers
    free = {cod: e for cod, e in issuers.items() if cod not in linked}
    ambiguous = 0
    for cnpj, c in companies.items():
        if cnpj in alive or cnpj in bridge or cnpj not in listed:
            continue
        name_candidates = {normalize(c["nome"])} | {normalize(n) for n in names.get(cnpj, ())}
        findings = set()
        for cod, e in free.items():
            if not any(len(normalize(n)) >= 5 and any(cn.startswith(normalize(n)) for cn in name_candidates) for n in e["nomes"]):
                continue
            if overlap_years(c["anos"], e["anos"]):
                findings.add(cod)
        if len(findings) == 1:
            cod = findings.pop()
            bridge[cnpj] = {"via": "nome", "tickers": sorted(free[cod]["tickers"])}
            continue
        if len(findings) > 1:
            ambiguous += 1
            continue
        # 2b. Nome contido, com seis letras ou mais, ou nome curto que também é a
        #     raiz do ISIN. Um candidato só, e os anos tocando.
        relaxed = set()
        for cod, e in free.items():
            if not overlap_years(c["anos"], e["anos"]):
                continue
            for n in e["nomes"]:
                nn = normalize(n)
                contained = len(nn) >= 6 and any(nn in cn for cn in name_candidates)
                short = 3 <= len(nn) < 5 and any(cn.startswith(nn) and (cod.startswith(nn) or nn.startswith(cod)) for cn in name_candidates)
                if contained or short:
                    relaxed.add(cod)
        if len(relaxed) == 1:
            cod = relaxed.pop()
            bridge[cnpj] = {"via": "nomeRelaxado", "tickers": sorted(free[cod]["tickers"])}
        elif len(relaxed) > 1:
            ambiguous += 1

    output = {}
    for cnpj, p in bridge.items():
        c = companies[cnpj]
        output[cnpj] = {
            "nome": c["nome"],
            "via": p["via"],
            "anosDfp": sorted(c["anos"]),
            "papeis": {tk: {"isin": securities[tk]["isin"], "primeiro": securities[tk]["primeiro"], "ultimo": securities[tk]["ultimo"]} for tk in p["tickers"]},
        }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(output, ensure_ascii=False, indent=1), encoding="utf-8")

    outside = [cnpj for cnpj in companies if cnpj not in alive]
    with_exchange = [cnpj for cnpj in outside if cnpj in listed or companies[cnpj]["tickers"] or codes.get(cnpj)]
    by_lane = collections.Counter(p["via"] for p in output.values())

    # O registro de quem ficou sem ponte, companhia a companhia (item C1d).
    record = []
    cotahist_tickers = set(securities)
    for cnpj in with_exchange:
        if cnpj in output:
            continue
        c = companies[cnpj]
        declared = sorted(c["tickers"] | codes.get(cnpj, set()))
        valid = [x for x in declared if re.fullmatch(r"[A-Z]{4}\d{1,2}", x)]
        if max(c["anos"]) < 2017:
            reason = "ultimoDfpAntesDaJanela"
        elif any(x in cotahist_tickers for x in declared):
            reason = "codigoNoCotahistForaDaPonte"
        elif valid:
            reason = "codigoSemPregaoAVista"
        elif declared:
            reason = "codigoDeclaradoInvalido"
        else:
            reason = "semCodigoENomeSemCandidato"
        record.append({
            "cnpj": cnpj,
            "nome": c["nome"],
            "anosDfp": [min(c["anos"]), max(c["anos"])],
            "codigosDeclarados": declared,
            "mercados": sorted(markets.get(cnpj, set())),
            "motivo": reason,
        })
    record.sort(key=lambda r: (r["motivo"], -r["anosDfp"][1], r["nome"]))
    REGISTRY.write_text(json.dumps({
        "geradoPor": "tool/b3_ponte.py",
        "motivos": {
            "ultimoDfpAntesDaJanela": "o último DFP é anterior a 2017: a companhia não chega à primeira coorte, de 2018",
            "codigoNoCotahistForaDaPonte": "o código tem pregão, e a companhia ficou fora por outro motivo — a conferir",
            "codigoSemPregaoAVista": "o código declarado não tem pregão à vista de lote padrão de 2010 em diante",
            "codigoDeclaradoInvalido": "a FCA declara algo que não é ticker nem raiz de emissor com pregão",
            "semCodigoENomeSemCandidato": "sem código na FCA e nenhum emissor do COTAHIST com o nome e os anos",
        },
        "companhias": record,
    }, ensure_ascii=False, indent=1), encoding="utf-8")
    fiscal_years = collections.Counter()
    for cnpj, p in output.items():
        price_years = set()
        for info in p["papeis"].values():
            price_years.update(range(int(info["primeiro"][:4]), int(info["ultimo"][:4]) + 1))
        fiscal_years[p["via"]] += sum(1 for a in companies[cnpj]["anos"] if a + 1 in price_years)

    print(f"companhias com DFP: {len(companies)}   no universo de hoje: {len(alive)}   fora dele: {len(outside)}")
    print(f"fora do universo e com ação em bolsa (FCA ou código): {len(with_exchange)}")
    for lane in ("codigo", "emissor", "nome", "nomeRelaxado"):
        print(f"  ligadas por {lane}: {by_lane[lane]} companhias, {fiscal_years[lane]} exercícios com pregão no ano seguinte")
    print(f"  ambíguas por nome, fora da ponte: {ambiguous}")
    print(f"  sem ponte: {len(record)}  {dict(collections.Counter(r['motivo'] for r in record))}")
    print(f"gravado {REGISTRY}")
    print(f"gravado {OUTPUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

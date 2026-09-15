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

SAIDA = Path("data/b3/ponte_deslistadas.json")
REGISTRO = Path("docs/validacao/ponte_deslistadas_registro.json")
UNIVERSO_COORTES = Path("docs/validacao/universo_coortes.json")
SUFIXOS = (
    " S A", " SA", " CIA", " COMPANHIA", " EM RECUPERACAO JUDICIAL",
    " RECUPERACAO JUDICIAL", " EM LIQUIDACAO", " PARTICIPACOES", " PART", " HOLDING",
)


def normalizar(s: str) -> str:
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().upper()
    s = re.sub(r"[^A-Z0-9 ]", " ", s)
    for w in SUFIXOS:
        s = s.replace(w, " ")
    return "".join(s.split())


def main() -> int:
    # Viva é a companhia que as coortes já observam como listada. Sem o arquivo
    # do backtest, recua para a lista de hoje.
    if UNIVERSO_COORTES.exists():
        universo = set(json.loads(UNIVERSO_COORTES.read_text(encoding="utf-8"))["tickers"])
    else:
        universo = {e["ticker"] for e in json.loads(Path("docs/validacao/universo.json").read_text(encoding="utf-8"))}
    documentos = json.loads(Path("data/cvm_exercicios.json").read_text(encoding="utf-8"))

    cias: dict[str, dict] = collections.defaultdict(lambda: {"nome": "", "anos": set(), "tickers": set()})
    for d in documentos:
        if d["documento"] != "DFP":
            continue
        c = cias[d["cnpj"]]
        c["nome"] = d["nome"]
        c["anos"].add(int(d["fimDoExercicio"][:4]))
        c["tickers"].update(d["tickers"] or [])

    em_bolsa: set[str] = set()
    codigos: dict[str, set[str]] = collections.defaultdict(set)
    nomes: dict[str, set[str]] = collections.defaultdict(set)
    mercados: dict[str, set[str]] = collections.defaultdict(set)
    for f in glob.glob("data/cvm/fca_cia_aberta_valor_mobiliario_*.csv"):
        with open(f, encoding="latin-1") as h:
            for r in csv.DictReader(h, delimiter=";"):
                cnpj = r["CNPJ_Companhia"]
                if (r.get("Valor_Mobiliario") or "").startswith("A") and (r.get("Mercado") or "").strip() == "Bolsa":
                    em_bolsa.add(cnpj)
                cod = (r.get("Codigo_Negociacao") or "").strip().upper()
                if cod:
                    codigos[cnpj].add(cod)
                if r.get("Nome_Empresarial"):
                    nomes[cnpj].add(r["Nome_Empresarial"])
                if (r.get("Valor_Mobiliario") or "").startswith("A") and (r.get("Mercado") or "").strip():
                    mercados[cnpj].add(r["Mercado"].strip())

    papeis: dict[str, dict] = {}
    emissores: dict[str, dict] = collections.defaultdict(lambda: {"nomes": set(), "anos": set(), "tickers": set()})
    for f in sorted(glob.glob("data/b3/avista_*.csv")):
        ano = int(f[-8:-4])
        with open(f, encoding="utf-8") as h:
            next(h)
            for linha in h:
                data, tk, isin, _esp, nome = linha.split(";")[:5]
                p = papeis.setdefault(tk, {"isin": isin, "primeiro": data, "ultimo": data})
                p["ultimo"] = max(p["ultimo"], data)
                p["primeiro"] = min(p["primeiro"], data)
                if isin.startswith("BR") and len(isin) == 12:
                    e = emissores[isin[2:6]]
                    e["nomes"].add(nome)
                    e["anos"].add(ano)
                    e["tickers"].add(tk)

    if not papeis:
        print("sem COTAHIST em data/b3 — rodar tool/b3_baixar.py")
        return 2

    vivos = {cnpj for cnpj, c in cias.items() if c["tickers"] & universo}
    emissores_vivos = {t[:4] for t in universo}
    ponte: dict[str, dict] = {}

    def tocam(anos_dfp: set[int], anos_pregao: set[int]) -> bool:
        return bool(anos_dfp & (anos_pregao | {a - 1 for a in anos_pregao}))

    # 1. Código declarado
    for cnpj, c in cias.items():
        if cnpj in vivos:
            continue
        declarados = c["tickers"] | codigos.get(cnpj, set())
        via_emissor = {tk for x in declarados if len(x) >= 5 for tk in emissores.get(x[:4], {}).get("tickers", ())}
        tickers = sorted({x for x in declarados if x in papeis} | via_emissor)
        if tickers:
            ponte[cnpj] = {"via": "codigo", "tickers": tickers}
            continue
        # 1b. As quatro letras do emissor no lugar do ticker, com os anos tocando.
        raizes = {x for x in declarados if len(x) == 4 and x.isalpha() and x in emissores and tocam(c["anos"], emissores[x]["anos"])}
        if len(raizes) == 1:
            ponte[cnpj] = {"via": "emissor", "tickers": sorted(emissores[raizes.pop()]["tickers"])}

    # 2. Nome, para quem tinha ação em bolsa e nenhum código
    ligados = {tk[:4] for p in ponte.values() for tk in p["tickers"]} | emissores_vivos
    livres = {cod: e for cod, e in emissores.items() if cod not in ligados}
    ambiguos = 0
    for cnpj, c in cias.items():
        if cnpj in vivos or cnpj in ponte or cnpj not in em_bolsa:
            continue
        candidatos_nome = {normalizar(c["nome"])} | {normalizar(n) for n in nomes.get(cnpj, ())}
        achados = set()
        for cod, e in livres.items():
            if not any(len(normalizar(n)) >= 5 and any(cn.startswith(normalizar(n)) for cn in candidatos_nome) for n in e["nomes"]):
                continue
            if tocam(c["anos"], e["anos"]):
                achados.add(cod)
        if len(achados) == 1:
            cod = achados.pop()
            ponte[cnpj] = {"via": "nome", "tickers": sorted(livres[cod]["tickers"])}
            continue
        if len(achados) > 1:
            ambiguos += 1
            continue
        # 2b. Nome contido, com seis letras ou mais, ou nome curto que também é a
        #     raiz do ISIN. Um candidato só, e os anos tocando.
        relaxados = set()
        for cod, e in livres.items():
            if not tocam(c["anos"], e["anos"]):
                continue
            for n in e["nomes"]:
                nn = normalizar(n)
                contido = len(nn) >= 6 and any(nn in cn for cn in candidatos_nome)
                curto = 3 <= len(nn) < 5 and any(cn.startswith(nn) and (cod.startswith(nn) or nn.startswith(cod)) for cn in candidatos_nome)
                if contido or curto:
                    relaxados.add(cod)
        if len(relaxados) == 1:
            cod = relaxados.pop()
            ponte[cnpj] = {"via": "nomeRelaxado", "tickers": sorted(livres[cod]["tickers"])}
        elif len(relaxados) > 1:
            ambiguos += 1

    saida = {}
    for cnpj, p in ponte.items():
        c = cias[cnpj]
        saida[cnpj] = {
            "nome": c["nome"],
            "via": p["via"],
            "anosDfp": sorted(c["anos"]),
            "papeis": {tk: {"isin": papeis[tk]["isin"], "primeiro": papeis[tk]["primeiro"], "ultimo": papeis[tk]["ultimo"]} for tk in p["tickers"]},
        }
    SAIDA.parent.mkdir(parents=True, exist_ok=True)
    SAIDA.write_text(json.dumps(saida, ensure_ascii=False, indent=1), encoding="utf-8")

    fora = [cnpj for cnpj in cias if cnpj not in vivos]
    com_bolsa = [cnpj for cnpj in fora if cnpj in em_bolsa or cias[cnpj]["tickers"] or codigos.get(cnpj)]
    por_via = collections.Counter(p["via"] for p in saida.values())

    # O registro de quem ficou sem ponte, companhia a companhia (item C1d).
    registro = []
    tickers_cotahist = set(papeis)
    for cnpj in com_bolsa:
        if cnpj in saida:
            continue
        c = cias[cnpj]
        declarados = sorted(c["tickers"] | codigos.get(cnpj, set()))
        validos = [x for x in declarados if re.fullmatch(r"[A-Z]{4}\d{1,2}", x)]
        if max(c["anos"]) < 2017:
            motivo = "ultimoDfpAntesDaJanela"
        elif any(x in tickers_cotahist for x in declarados):
            motivo = "codigoNoCotahistForaDaPonte"
        elif validos:
            motivo = "codigoSemPregaoAVista"
        elif declarados:
            motivo = "codigoDeclaradoInvalido"
        else:
            motivo = "semCodigoENomeSemCandidato"
        registro.append({
            "cnpj": cnpj,
            "nome": c["nome"],
            "anosDfp": [min(c["anos"]), max(c["anos"])],
            "codigosDeclarados": declarados,
            "mercados": sorted(mercados.get(cnpj, set())),
            "motivo": motivo,
        })
    registro.sort(key=lambda r: (r["motivo"], -r["anosDfp"][1], r["nome"]))
    REGISTRO.write_text(json.dumps({
        "geradoPor": "tool/b3_ponte.py",
        "motivos": {
            "ultimoDfpAntesDaJanela": "o último DFP é anterior a 2017: a companhia não chega à primeira coorte, de 2018",
            "codigoNoCotahistForaDaPonte": "o código tem pregão, e a companhia ficou fora por outro motivo — a conferir",
            "codigoSemPregaoAVista": "o código declarado não tem pregão à vista de lote padrão de 2010 em diante",
            "codigoDeclaradoInvalido": "a FCA declara algo que não é ticker nem raiz de emissor com pregão",
            "semCodigoENomeSemCandidato": "sem código na FCA e nenhum emissor do COTAHIST com o nome e os anos",
        },
        "companhias": registro,
    }, ensure_ascii=False, indent=1), encoding="utf-8")
    exercicios = collections.Counter()
    for cnpj, p in saida.items():
        anos_preco = set()
        for info in p["papeis"].values():
            anos_preco.update(range(int(info["primeiro"][:4]), int(info["ultimo"][:4]) + 1))
        exercicios[p["via"]] += sum(1 for a in cias[cnpj]["anos"] if a + 1 in anos_preco)

    print(f"companhias com DFP: {len(cias)}   no universo de hoje: {len(vivos)}   fora dele: {len(fora)}")
    print(f"fora do universo e com ação em bolsa (FCA ou código): {len(com_bolsa)}")
    for via in ("codigo", "emissor", "nome", "nomeRelaxado"):
        print(f"  ligadas por {via}: {por_via[via]} companhias, {exercicios[via]} exercícios com pregão no ano seguinte")
    print(f"  ambíguas por nome, fora da ponte: {ambiguos}")
    print(f"  sem ponte: {len(registro)}  {dict(collections.Counter(r['motivo'] for r in registro))}")
    print(f"gravado {REGISTRO}")
    print(f"gravado {SAIDA}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

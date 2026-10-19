"""Baixa do RAD as versões antigas dos documentos da CVM (item B8).

**Por que existe.** Os CSVs anuais da CVM (`cvm_baixar.py`) trazem, nos
demonstrativos, **só a última versão** de cada documento — o índice
`{doc}_cia_aberta_{ano}.csv` lista todas as versões com a data de recebimento,
mas as contas de uma DFP reapresentada chegam só com os números corrigidos.
Uma coorte de 2019 que usasse a DFP de 2018 reapresentada em 2021 lia números
que ninguém tinha em 2019.

A versão original existe, e é pública: o RAD entrega o pacote de cada versão
pelo `ID_DOC` que o próprio índice traz. Dentro dele, `InfoFinaDFin.xml` tem as
contas com o mesmo código, a mesma escala e os mesmos valores dos CSVs — a
conferência de 22/09/2026 sobre a DFP e o ITR da WEG de 2019 bateu conta a
conta, nos oito demonstrativos que o motor lê.

**O que baixa.** Só a versão que estava **vigente em alguma data de coorte** e
não é a última: a de recebimento mais recente até a data. Reapresentação feita
em semanas, sem coorte no meio, não muda nenhuma observação e não é baixada. O
universo é o das coortes — a ponte de hoje (`docs/validacao/ponte_cvm.json`)
mais as deslistadas (`data/b3/ponte_deslistadas.json`).

**O que grava.** Os demonstrativos no layout dos CSVs da CVM, com a coluna
`VERSAO` da versão baixada, em `data/cvm/versoes/` — para que a ingestão os leia
com o mesmo leitor dos anuais. O pacote bruto não é guardado: tem o PDF das
demonstrações, e passa de 5 MB por documento.

Uso:
    python tool/cvm_versoes_baixar.py            # retoma de onde parou
    python tool/cvm_versoes_baixar.py --contar   # só diz quantas faltam
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import io
import json
import re
import sys
import time
import urllib.error
import urllib.request
import zipfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

RAD = ("https://www.rad.cvm.gov.br/ENETCONSULTA/frmDownloadDocumento.aspx"
       "?CodigoInstituicao=1&NumeroSequencialDocumento={id}")

# As coortes de `tool/backtest_valuation.dart --trimestral`: o último dia de
# cada trimestre, de 31/03/2018 a 30/09/2025. Mudar lá exige mudar aqui.
COHORTS = [
    dt.date(year, month, day).isoformat()
    for year in range(2018, 2026)
    for month, day in ((3, 31), (6, 30), (9, 30), (12, 31))
    if dt.date(year, month, day) <= dt.date(2025, 9, 30)
]

# Código do demonstrativo no `InfoFinaDFin.xml` → sufixo do CSV da CVM.
# Conferido contra os CSVs em 22/09/2026 (docstring do módulo).
STATEMENT = {"2": "BPA", "3": "BPP", "4": "DRE", "7": "DFC_MI"}
INFORMATION = {"1": "ind", "2": "con"}
SCALE = {"1": "UNIDADE", "2": "MIL"}
BALANCE_SHEET = {"BPA", "BPP"}

_destination = "data/cvm/versoes"

FIELDS = ["CNPJ_CIA", "DT_REFER", "VERSAO", "DENOM_CIA", "ESCALA_MOEDA",
          "ORDEM_EXERC", "DT_INI_EXERC", "DT_FIM_EXERC", "CD_CONTA",
          "DS_CONTA", "VL_CONTA"]
CAPITAL_FIELDS = ["CNPJ_CIA", "DT_REFER", "VERSAO", "DENOM_CIA",
                  "QT_ACAO_TOTAL_CAP_INTEGR", "QT_ACAO_TOTAL_TESOURO"]


def _tag(block: str, name: str) -> str | None:
    m = re.search(rf"<{name}>([^<]*)</{name}>", block)
    return m.group(1) if m else None


def _without_form(xml: str) -> str:
    """Tira o `FormularioDemonstracaoFinanceira` que o RAD repete em todo bloco."""
    return re.sub(
        r"<FormularioDemonstracaoFinanceira>.*?</FormularioDemonstracaoFinanceira>",
        "", xml, flags=re.S)


def index(cvm: Path, cnpjs: set[str]) -> dict:
    """Versões de cada documento: (cnpj, refer, doc) → [(versao, receb, id, nome)]."""
    out: dict = {}
    for f in sorted(cvm.glob("*_cia_aberta_20??.csv")):
        doc = f.name[:3].upper()
        if doc not in ("DFP", "ITR"):
            continue
        with f.open(encoding="latin-1", newline="") as h:
            for r in csv.DictReader(h, delimiter=";"):
                if r["CNPJ_CIA"] not in cnpjs:
                    continue
                out.setdefault((r["CNPJ_CIA"], r["DT_REFER"], doc), []).append(
                    (int(r["VERSAO"] or 1), r["DT_RECEB"][:10], r["ID_DOC"],
                     r["DENOM_CIA"]))
    return out


def old_in_force(versions: dict) -> list:
    """As versões que não são a última e estavam vigentes em alguma coorte."""
    target = set()
    for k, vs in versions.items():
        vs = sorted(set(vs))
        if len(vs) < 2:
            continue
        latest = max(vs, key=lambda v: (v[1], v[0]))
        for c in COHORTS:
            before = [v for v in vs if v[1] <= c]
            if not before:
                continue
            v = max(before, key=lambda v: (v[1], v[0]))
            if v != latest:
                target.add((k, v))
    return sorted(target)


def convert(package: bytes, cnpj: str, refer: str, version: int, name: str):
    """Do pacote do RAD para linhas no layout dos CSVs da CVM.

    Devolve ``(linhas por demonstrativo, linha de capital, motivo)``; o motivo
    é ``None`` quando deu certo.
    """
    z = zipfile.ZipFile(io.BytesIO(package))
    internal = [n for n in z.namelist() if n.lower().endswith((".dfp", ".itr"))]
    if not internal:
        # A partir de 2023 o pacote traz um XML único no lugar do .dfp/.itr.
        single = [n for n in z.namelist()
                 if re.fullmatch(r"\d+(DFP|ITR)[\d-]+v\d+\.xml", n)]
        if single:
            return convert_single_xml(z.read(single[0]), cnpj, refer, version,
                                       name)
        return None, None, "pacote sem .dfp/.itr"
    z2 = zipfile.ZipFile(io.BytesIO(z.read(internal[0])))
    names = set(z2.namelist())
    if "InfoFinaDFin.xml" not in names:
        return None, None, "sem InfoFinaDFin.xml"

    form = next((n for n in names if n.startswith("FormularioDemonstracao")), None)
    scale = SCALE.get(_tag(z2.read(form).decode("utf-8", "replace"),
                             "CodigoEscalaMoeda") or "") if form else None
    if scale is None:
        return None, None, "escala desconhecida"

    # Coluna N do XML é o período N declarado no pacote.
    periods = {}
    pxml = _without_form(
        z2.read("PeriodoDemonstracaoFinanceira.xml").decode("utf-8", "replace"))
    for b in pxml.split("<PeriodoDemonstracaoFinanceira>")[1:]:
        n = _tag(b, "NumeroIdentificacaoPeriodo")
        start = (_tag(b, "DataInicioPeriodo") or "")[:10]
        end = (_tag(b, "DataFimPeriodo") or "")[:10]
        if n and end and not end.startswith("0001"):
            periods[int(n)] = (start, end)
    ref_year = int(refer[:4])
    previous = f"{ref_year - 1}{refer[4:]}"
    # No ITR, dois períodos terminam na data: o trimestre e o acumulado. O
    # saldo do balanço está na coluna do primeiro; a DFC só tem o acumulado,
    # que é o de início mais cedo.
    balance = min((n for n, p in periods.items() if p[1] == refer), default=None)
    accumulated = {
        end: min(p[0] for p in periods.values() if p[1] == end)
        for end in (refer, previous)
        if any(p[1] == end for p in periods.values())
    }

    lines: dict[str, list] = {}
    xml = z2.read("InfoFinaDFin.xml").decode("utf-8", "replace")
    for b in xml.split("<InfoFinaDFin>")[1:]:
        b = re.sub(r"<PeriodoDemonstracaoFinanceira>.*?</PeriodoDemonstracaoFinanceira>",
                   "", b, flags=re.S)
        statement = STATEMENT.get(_tag(b, "CodigoTipoDemonstracaoFinanceira") or "")
        inf = INFORMATION.get(_tag(b, "CodigoTipoInformacaoFinanceira") or "")
        account = _tag(b, "NumeroConta")
        if statement is None or inf is None or not account:
            continue
        label = _tag(b, "DescricaoConta1") or ""
        for n, (start, end) in periods.items():
            raw = _tag(b, f"ValorConta{n}")
            if raw is None:
                continue
            if statement in BALANCE_SHEET:
                # A ingestão lê do balanço só o saldo na data do documento; o
                # comparativo não é gravado.
                if n != balance:
                    continue
                order, start_csv = "ÚLTIMO", ""
            else:
                if statement == "DFC_MI" and start != accumulated.get(end):
                    continue
                if end == refer:
                    order = "ÚLTIMO"
                elif end == previous:
                    order = "PENÚLTIMO"
                else:
                    continue
                start_csv = start
            lines.setdefault(f"{statement}_{inf}", []).append({
                "CNPJ_CIA": cnpj, "DT_REFER": refer, "VERSAO": version,
                "DENOM_CIA": name, "ESCALA_MOEDA": scale,
                "ORDEM_EXERC": order, "DT_INI_EXERC": start_csv,
                "DT_FIM_EXERC": end, "CD_CONTA": account, "DS_CONTA": label,
                "VL_CONTA": raw,
            })

    capital = None
    cap = next((n for n in names if n.startswith("ComposicaoCapitalSocial")), None)
    if cap:
        c = _without_form(z2.read(cap).decode("utf-8", "replace"))
        tot = _tag(c, "QuantidadeTotalAcaoCapitalIntegralizado")
        treasury = _tag(c, "QuantidadeTotalAcaoTesouraria")
        if tot:
            capital = {"CNPJ_CIA": cnpj, "DT_REFER": refer, "VERSAO": version,
                       "DENOM_CIA": name, "QT_ACAO_TOTAL_CAP_INTEGR": tot,
                       "QT_ACAO_TOTAL_TESOURO": treasury or "0"}
    return lines, capital, None


# Formato do XML único (2023 em diante): seção → demonstrativo, e a coluna de
# cada valor → (ordem, início, fim) em função das datas do cabeçalho.
SECTION = {"BalancoPatrimonialAtivo": "BPA", "BalancoPatrimonialPassivo": "BPP",
         "DemonstracaoResultado": "DRE", "DemonstracaoFluxoCaixa": "DFC_MI"}
BLOCK = {"DfIndividuais": "ind", "DfConsolidadas": "con"}


def _number_br(text: str | None) -> str | None:
    """«19.976.556» e «-1.234,5» para o texto que os CSVs da CVM usam."""
    if text is None or not text.strip():
        return None
    return text.strip().replace(".", "").replace(",", ".")


def _zero_text(value: str) -> bool:
    """O texto é um zero («0», «-0», «0.0000»)? Pelo texto, e não por `float`."""
    return re.fullmatch(r"[+-]?0*(\.0*)?", value.strip()) is not None


def _date_br(text: str | None) -> str:
    if not text or len(text) < 10:
        return ""
    d, m, a = text[:10].split("/")
    return f"{a}-{m}-{d}"


def _year_before(iso: str) -> str:
    return f"{int(iso[:4]) - 1}{iso[4:]}" if iso else ""


def convert_single_xml(raw: bytes, cnpj: str, refer: str, version: int,
                        name: str):
    """O XML único do RAD, de 2023 em diante, para o layout dos CSVs."""
    x = raw.decode("utf-8", "replace")
    x = re.sub(r"<ImagemObjetoArquivoPdf>.*?</ImagemObjetoArquivoPdf>", "", x,
               flags=re.S)
    scale = SCALE.get(_tag(x, "EscalaMoeda") or "")
    if scale is None:
        return None, None, "escala desconhecida"
    ref = _date_br(_tag(x, "DataReferencia"))
    if ref != refer:
        return None, None, f"data de referência {ref} ≠ {refer}"
    ref_ant = _year_before(refer)
    if "<DadosDFP>" in x:
        start_last = _date_br(_tag(x, "DtInicioUltimoExercicioSocial"))
        start_prev = _date_br(_tag(x, "DtInicioPenultimoExercicioSocial"))
        end_prev = _date_br(_tag(x, "DtFimPenultimoExercicioSocial"))
        balance_sheet = {"UltimoExercicio": refer}
        flow = {"UltimoExercicio": ("ÚLTIMO", start_last, refer),
                 "PenultimoExercicio": ("PENÚLTIMO", start_prev, end_prev)}
        dfc_flow = flow
    else:
        start_quarter = _date_br(_tag(x, "DtInicioTrimestreAtual"))
        start_fiscal_year = _date_br(_tag(x, "DtInicioExercicioSocialCurso"))
        start_prior_year = _date_br(_tag(x, "DtInicioExercicioSocialAnterior"))
        balance_sheet = {"TrimestreAtual": refer}
        flow = {
            "TrimestreAtual": ("ÚLTIMO", start_quarter, refer),
            "AcumuladoExercicioAtual": ("ÚLTIMO", start_fiscal_year, refer),
            "TrimestreAnterior": ("PENÚLTIMO", _year_before(start_quarter), ref_ant),
            "AcumuladoExercicioAnterior": ("PENÚLTIMO", start_prior_year, ref_ant),
        }
        dfc_flow = {
            "AcumuladoAtualExercicio": ("ÚLTIMO", start_fiscal_year, refer),
            "AcumuladoExercicioAnterior": ("PENÚLTIMO", start_prior_year, ref_ant),
        }

    lines: dict[str, list] = {}
    for block, inf in BLOCK.items():
        mb = re.search(rf"<{block}>(.*?)</{block}>", x, flags=re.S)
        if not mb:
            continue
        for section, statement in SECTION.items():
            ms = re.search(rf"<{section}>(.*?)</{section}>", mb.group(1), flags=re.S)
            if not ms:
                continue
            for c in re.findall(r"<Conta>(.*?)</Conta>", ms.group(1), flags=re.S):
                account = _tag(c, "CodigoConta")
                if not account:
                    continue
                if statement == "DFC_MI" and (_tag(c, "Metodo") or "").lower() == "direto":
                    continue
                columns = (
                    {k: ("ÚLTIMO", "", v) for k, v in balance_sheet.items()}
                    if statement in ("BPA", "BPP")
                    else (dfc_flow if statement == "DFC_MI" else flow))
                # O XML traz o plano de contas inteiro, com as linhas não
                # usadas vazias ou zeradas e sem descrição; o CSV da CVM traz a
                # conta descrita sempre (zerada, se fixa e vazia) e omite a
                # zerada sem descrição. Conferido conta a conta na WEG de 2023 e 2024.
                fixed = (_tag(c, "ContaFixa") or "").lower() == "true"
                label = _tag(c, "DescricaoConta") or ""
                for column, (order, start, end) in columns.items():
                    value = _number_br(_tag(c, column))
                    if value is None and fixed:
                        value = "0"
                    if value is None or (not label and _zero_text(value)):
                        continue
                    lines.setdefault(f"{statement}_{inf}", []).append({
                        "CNPJ_CIA": cnpj, "DT_REFER": refer, "VERSAO": version,
                        "DENOM_CIA": name, "ESCALA_MOEDA": scale,
                        "ORDEM_EXERC": order, "DT_INI_EXERC": start,
                        "DT_FIM_EXERC": end, "CD_CONTA": account,
                        "DS_CONTA": label,
                        "VL_CONTA": value,
                    })

    capital = None
    paid_in = re.search(r"<CaptalIntegralizado>(.*?)</CaptalIntegralizado>", x, re.S)
    mt = re.search(r"<Tesouraria>(.*?)</Tesouraria>", x, re.S)
    tot = _number_br(_tag(paid_in.group(1), "QtdeTotalAcoes")) if paid_in else None
    if tot:
        capital = {"CNPJ_CIA": cnpj, "DT_REFER": refer, "VERSAO": version,
                   "DENOM_CIA": name, "QT_ACAO_TOTAL_CAP_INTEGR": tot,
                   "QT_ACAO_TOTAL_TESOURO":
                       (_number_br(_tag(mt.group(1), "QtdeTotalAcoes"))
                        if mt else None) or "0"}
    if not lines:
        return None, None, "XML único sem demonstrativo"
    return lines, capital, None


def download(doc_id: str, attempts: int = 5) -> bytes | None:
    request = urllib.request.Request(RAD.format(id=doc_id),
                                    headers={"User-Agent": "Mozilla/5.0"})
    for i in range(attempts):
        try:
            with urllib.request.urlopen(request, timeout=300) as r:
                body = r.read()
            if body[:2] != b"PK":
                return None  # o RAD devolveu página, e não pacote
            zipfile.ZipFile(io.BytesIO(body))  # truncado não abre
            return body
        except (urllib.error.URLError, TimeoutError, ConnectionError,
                zipfile.BadZipFile, OSError):
            time.sleep(5 * (i + 1))
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cvm", default="data/cvm")
    ap.add_argument("--contar", action="store_true")
    ap.add_argument("--pausa", type=float, default=1.0)
    ap.add_argument("--conexoes", type=int, default=3)
    a = ap.parse_args()

    cvm = Path(a.cvm)
    bridge = Path("docs/validacao/ponte_cvm.json")
    delisted_list = Path("data/b3/ponte_deslistadas.json")
    for p in (bridge, delisted_list):
        if not p.exists():
            print(f"{p} não existe — rode antes a sequência do item C5.",
                  file=sys.stderr)
            return 2
    cnpjs = set(json.loads(bridge.read_text(encoding="utf-8"))["ponte"].values())
    cnpjs |= set(json.loads(delisted_list.read_text(encoding="utf-8")).keys())

    target = old_in_force(index(cvm, cnpjs))
    global _destination
    destination = cvm / "versoes"
    destination.mkdir(parents=True, exist_ok=True)
    _destination = str(destination)
    done_file = destination / "baixados.json"
    done = (json.loads(done_file.read_text(encoding="utf-8"))
              if done_file.exists() else {})
    # Download que falhou volta à fila; pacote que não converte, não.
    still_missing = [x for x in target
              if done.get(x[1][2], {}).get("motivo", "download falhou")
              == "download falhou"]
    print(f"== Versões antigas vigentes em coorte: {len(target)} "
          f"({len(target) - len(still_missing)} já baixadas, {len(still_missing)} faltam) ==")
    if a.contar:
        return 0

    def fetch(item):
        (cnpj, refer, doc), (version, received, doc_id, name) = item
        time.sleep(a.pausa)
        package = download(doc_id)
        if package is None:
            return item, (None, None, "download falhou")
        try:
            return item, convert(package, cnpj, refer, version, name)
        except (zipfile.BadZipFile, KeyError, ValueError) as e:
            return item, (None, None, f"conversão falhou: {e}")

    # Poucas conexões ao mesmo tempo: o RAD reseta a transferência longa, e o
    # pacote passa de 15 MB por causa do PDF. A escrita fica neste fio.
    with ThreadPoolExecutor(max_workers=a.conexoes) as pool:
        results = pool.map(fetch, still_missing)
        for i, (item, (lines, capital, reason)) in enumerate(results):
            (cnpj, refer, doc), (version, received, doc_id, name) = item
            register(doc, lines, capital)
            done[doc_id] = {"cnpj": cnpj, "refer": refer, "doc": doc,
                              "versao": version, "recebidoEm": received,
                              "motivo": reason or "ok"}
            done_file.write_text(
                json.dumps(done, ensure_ascii=False, indent=0),
                encoding="utf-8")
            print(f"  [{i + 1}/{len(still_missing)}] {doc} {refer} v{version} "
                  f"{name[:30]}: {reason or 'ok'}", flush=True)
    return 0


def register(doc: str, lines, capital) -> None:
    """Acrescenta as linhas de uma versão aos CSVs de `data/cvm/versoes/`."""
    destination = Path(_destination)
    if lines:
        for statement, rows in lines.items():
            out_path = destination / f"{doc.lower()}_cia_aberta_{statement}_versoes.csv"
            new = not out_path.exists()
            with out_path.open("a", encoding="latin-1", errors="replace",
                          newline="") as h:
                w = csv.DictWriter(h, fieldnames=FIELDS, delimiter=";")
                if new:
                    w.writeheader()
                w.writerows(rows)
        if capital:
            out_path = destination / f"{doc.lower()}_cia_aberta_composicao_capital_versoes.csv"
            new = not out_path.exists()
            with out_path.open("a", encoding="latin-1", errors="replace",
                          newline="") as h:
                w = csv.DictWriter(h, fieldnames=CAPITAL_FIELDS, delimiter=";")
                if new:
                    w.writeheader()
                w.writerow(capital)


if __name__ == "__main__":
    sys.exit(main())

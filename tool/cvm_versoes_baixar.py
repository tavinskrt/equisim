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
COORTES = [
    dt.date(ano, mes, dia).isoformat()
    for ano in range(2018, 2026)
    for mes, dia in ((3, 31), (6, 30), (9, 30), (12, 31))
    if dt.date(ano, mes, dia) <= dt.date(2025, 9, 30)
]

# Código do demonstrativo no `InfoFinaDFin.xml` → sufixo do CSV da CVM.
# Conferido contra os CSVs em 22/09/2026 (docstring do módulo).
DEMONSTRATIVO = {"2": "BPA", "3": "BPP", "4": "DRE", "7": "DFC_MI"}
INFORMACAO = {"1": "ind", "2": "con"}
ESCALA = {"1": "UNIDADE", "2": "MIL"}
BALANCO = {"BPA", "BPP"}

_destino = "data/cvm/versoes"

CAMPOS = ["CNPJ_CIA", "DT_REFER", "VERSAO", "DENOM_CIA", "ESCALA_MOEDA",
          "ORDEM_EXERC", "DT_INI_EXERC", "DT_FIM_EXERC", "CD_CONTA",
          "DS_CONTA", "VL_CONTA"]
CAMPOS_CAPITAL = ["CNPJ_CIA", "DT_REFER", "VERSAO", "DENOM_CIA",
                  "QT_ACAO_TOTAL_CAP_INTEGR", "QT_ACAO_TOTAL_TESOURO"]


def _tag(bloco: str, nome: str) -> str | None:
    m = re.search(rf"<{nome}>([^<]*)</{nome}>", bloco)
    return m.group(1) if m else None


def _sem_formulario(xml: str) -> str:
    """Tira o `FormularioDemonstracaoFinanceira` que o RAD repete em todo bloco."""
    return re.sub(
        r"<FormularioDemonstracaoFinanceira>.*?</FormularioDemonstracaoFinanceira>",
        "", xml, flags=re.S)


def indice(cvm: Path, cnpjs: set[str]) -> dict:
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


def vigentes_antigas(versoes: dict) -> list:
    """As versões que não são a última e estavam vigentes em alguma coorte."""
    alvo = set()
    for k, vs in versoes.items():
        vs = sorted(set(vs))
        if len(vs) < 2:
            continue
        ultima = max(vs, key=lambda v: (v[1], v[0]))
        for c in COORTES:
            antes = [v for v in vs if v[1] <= c]
            if not antes:
                continue
            v = max(antes, key=lambda v: (v[1], v[0]))
            if v != ultima:
                alvo.add((k, v))
    return sorted(alvo)


def converter(pacote: bytes, cnpj: str, refer: str, versao: int, nome: str):
    """Do pacote do RAD para linhas no layout dos CSVs da CVM.

    Devolve ``(linhas por demonstrativo, linha de capital, motivo)``; o motivo
    é ``None`` quando deu certo.
    """
    z = zipfile.ZipFile(io.BytesIO(pacote))
    interno = [n for n in z.namelist() if n.lower().endswith((".dfp", ".itr"))]
    if not interno:
        # A partir de 2023 o pacote traz um XML único no lugar do .dfp/.itr.
        unico = [n for n in z.namelist()
                 if re.fullmatch(r"\d+(DFP|ITR)[\d-]+v\d+\.xml", n)]
        if unico:
            return converter_xml_unico(z.read(unico[0]), cnpj, refer, versao,
                                       nome)
        return None, None, "pacote sem .dfp/.itr"
    z2 = zipfile.ZipFile(io.BytesIO(z.read(interno[0])))
    nomes = set(z2.namelist())
    if "InfoFinaDFin.xml" not in nomes:
        return None, None, "sem InfoFinaDFin.xml"

    form = next((n for n in nomes if n.startswith("FormularioDemonstracao")), None)
    escala = ESCALA.get(_tag(z2.read(form).decode("utf-8", "replace"),
                             "CodigoEscalaMoeda") or "") if form else None
    if escala is None:
        return None, None, "escala desconhecida"

    # Coluna N do XML é o período N declarado no pacote.
    periodos = {}
    pxml = _sem_formulario(
        z2.read("PeriodoDemonstracaoFinanceira.xml").decode("utf-8", "replace"))
    for b in pxml.split("<PeriodoDemonstracaoFinanceira>")[1:]:
        n = _tag(b, "NumeroIdentificacaoPeriodo")
        ini = (_tag(b, "DataInicioPeriodo") or "")[:10]
        fim = (_tag(b, "DataFimPeriodo") or "")[:10]
        if n and fim and not fim.startswith("0001"):
            periodos[int(n)] = (ini, fim)
    ano_ref = int(refer[:4])
    anterior = f"{ano_ref - 1}{refer[4:]}"
    # No ITR, dois períodos terminam na data: o trimestre e o acumulado. O
    # saldo do balanço está na coluna do primeiro; a DFC só tem o acumulado,
    # que é o de início mais cedo.
    saldo = min((n for n, p in periodos.items() if p[1] == refer), default=None)
    acumulado = {
        fim: min(p[0] for p in periodos.values() if p[1] == fim)
        for fim in (refer, anterior)
        if any(p[1] == fim for p in periodos.values())
    }

    linhas: dict[str, list] = {}
    xml = z2.read("InfoFinaDFin.xml").decode("utf-8", "replace")
    for b in xml.split("<InfoFinaDFin>")[1:]:
        b = re.sub(r"<PeriodoDemonstracaoFinanceira>.*?</PeriodoDemonstracaoFinanceira>",
                   "", b, flags=re.S)
        dem = DEMONSTRATIVO.get(_tag(b, "CodigoTipoDemonstracaoFinanceira") or "")
        inf = INFORMACAO.get(_tag(b, "CodigoTipoInformacaoFinanceira") or "")
        conta = _tag(b, "NumeroConta")
        if dem is None or inf is None or not conta:
            continue
        rotulo = _tag(b, "DescricaoConta1") or ""
        for n, (ini, fim) in periodos.items():
            bruto = _tag(b, f"ValorConta{n}")
            if bruto is None:
                continue
            if dem in BALANCO:
                # A ingestão lê do balanço só o saldo na data do documento; o
                # comparativo não é gravado.
                if n != saldo:
                    continue
                ordem, ini_csv = "ÚLTIMO", ""
            else:
                if dem == "DFC_MI" and ini != acumulado.get(fim):
                    continue
                if fim == refer:
                    ordem = "ÚLTIMO"
                elif fim == anterior:
                    ordem = "PENÚLTIMO"
                else:
                    continue
                ini_csv = ini
            linhas.setdefault(f"{dem}_{inf}", []).append({
                "CNPJ_CIA": cnpj, "DT_REFER": refer, "VERSAO": versao,
                "DENOM_CIA": nome, "ESCALA_MOEDA": escala,
                "ORDEM_EXERC": ordem, "DT_INI_EXERC": ini_csv,
                "DT_FIM_EXERC": fim, "CD_CONTA": conta, "DS_CONTA": rotulo,
                "VL_CONTA": bruto,
            })

    capital = None
    cap = next((n for n in nomes if n.startswith("ComposicaoCapitalSocial")), None)
    if cap:
        c = _sem_formulario(z2.read(cap).decode("utf-8", "replace"))
        tot = _tag(c, "QuantidadeTotalAcaoCapitalIntegralizado")
        tes = _tag(c, "QuantidadeTotalAcaoTesouraria")
        if tot:
            capital = {"CNPJ_CIA": cnpj, "DT_REFER": refer, "VERSAO": versao,
                       "DENOM_CIA": nome, "QT_ACAO_TOTAL_CAP_INTEGR": tot,
                       "QT_ACAO_TOTAL_TESOURO": tes or "0"}
    return linhas, capital, None


# Formato do XML único (2023 em diante): seção → demonstrativo, e a coluna de
# cada valor → (ordem, início, fim) em função das datas do cabeçalho.
SECAO = {"BalancoPatrimonialAtivo": "BPA", "BalancoPatrimonialPassivo": "BPP",
         "DemonstracaoResultado": "DRE", "DemonstracaoFluxoCaixa": "DFC_MI"}
BLOCO = {"DfIndividuais": "ind", "DfConsolidadas": "con"}


def _numero_br(texto: str | None) -> str | None:
    """«19.976.556» e «-1.234,5» para o texto que os CSVs da CVM usam."""
    if texto is None or not texto.strip():
        return None
    return texto.strip().replace(".", "").replace(",", ".")


def _texto_zero(valor: str) -> bool:
    """O texto é um zero («0», «-0», «0.0000»)? Pelo texto, e não por `float`."""
    return re.fullmatch(r"[+-]?0*(\.0*)?", valor.strip()) is not None


def _data_br(texto: str | None) -> str:
    if not texto or len(texto) < 10:
        return ""
    d, m, a = texto[:10].split("/")
    return f"{a}-{m}-{d}"


def _ano_antes(iso: str) -> str:
    return f"{int(iso[:4]) - 1}{iso[4:]}" if iso else ""


def converter_xml_unico(bruto: bytes, cnpj: str, refer: str, versao: int,
                        nome: str):
    """O XML único do RAD, de 2023 em diante, para o layout dos CSVs."""
    x = bruto.decode("utf-8", "replace")
    x = re.sub(r"<ImagemObjetoArquivoPdf>.*?</ImagemObjetoArquivoPdf>", "", x,
               flags=re.S)
    escala = ESCALA.get(_tag(x, "EscalaMoeda") or "")
    if escala is None:
        return None, None, "escala desconhecida"
    ref = _data_br(_tag(x, "DataReferencia"))
    if ref != refer:
        return None, None, f"data de referência {ref} ≠ {refer}"
    ref_ant = _ano_antes(refer)
    if "<DadosDFP>" in x:
        ini_ult = _data_br(_tag(x, "DtInicioUltimoExercicioSocial"))
        ini_pen = _data_br(_tag(x, "DtInicioPenultimoExercicioSocial"))
        fim_pen = _data_br(_tag(x, "DtFimPenultimoExercicioSocial"))
        balanco = {"UltimoExercicio": refer}
        fluxo = {"UltimoExercicio": ("ÚLTIMO", ini_ult, refer),
                 "PenultimoExercicio": ("PENÚLTIMO", ini_pen, fim_pen)}
        fluxo_dfc = fluxo
    else:
        ini_tri = _data_br(_tag(x, "DtInicioTrimestreAtual"))
        ini_exe = _data_br(_tag(x, "DtInicioExercicioSocialCurso"))
        ini_ant = _data_br(_tag(x, "DtInicioExercicioSocialAnterior"))
        balanco = {"TrimestreAtual": refer}
        fluxo = {
            "TrimestreAtual": ("ÚLTIMO", ini_tri, refer),
            "AcumuladoExercicioAtual": ("ÚLTIMO", ini_exe, refer),
            "TrimestreAnterior": ("PENÚLTIMO", _ano_antes(ini_tri), ref_ant),
            "AcumuladoExercicioAnterior": ("PENÚLTIMO", ini_ant, ref_ant),
        }
        fluxo_dfc = {
            "AcumuladoAtualExercicio": ("ÚLTIMO", ini_exe, refer),
            "AcumuladoExercicioAnterior": ("PENÚLTIMO", ini_ant, ref_ant),
        }

    linhas: dict[str, list] = {}
    for bloco, inf in BLOCO.items():
        mb = re.search(rf"<{bloco}>(.*?)</{bloco}>", x, flags=re.S)
        if not mb:
            continue
        for secao, dem in SECAO.items():
            ms = re.search(rf"<{secao}>(.*?)</{secao}>", mb.group(1), flags=re.S)
            if not ms:
                continue
            for c in re.findall(r"<Conta>(.*?)</Conta>", ms.group(1), flags=re.S):
                conta = _tag(c, "CodigoConta")
                if not conta:
                    continue
                if dem == "DFC_MI" and (_tag(c, "Metodo") or "").lower() == "direto":
                    continue
                colunas = (
                    {k: ("ÚLTIMO", "", v) for k, v in balanco.items()}
                    if dem in ("BPA", "BPP")
                    else (fluxo_dfc if dem == "DFC_MI" else fluxo))
                # O XML traz o plano de contas inteiro, com as linhas não
                # usadas vazias ou zeradas e sem descrição; o CSV da CVM traz a
                # conta descrita sempre (zerada, se fixa e vazia) e omite a
                # zerada sem descrição. Conferido conta a conta na WEG de 2023 e 2024.
                fixa = (_tag(c, "ContaFixa") or "").lower() == "true"
                rotulo = _tag(c, "DescricaoConta") or ""
                for coluna, (ordem, ini, fim) in colunas.items():
                    valor = _numero_br(_tag(c, coluna))
                    if valor is None and fixa:
                        valor = "0"
                    if valor is None or (not rotulo and _texto_zero(valor)):
                        continue
                    linhas.setdefault(f"{dem}_{inf}", []).append({
                        "CNPJ_CIA": cnpj, "DT_REFER": refer, "VERSAO": versao,
                        "DENOM_CIA": nome, "ESCALA_MOEDA": escala,
                        "ORDEM_EXERC": ordem, "DT_INI_EXERC": ini,
                        "DT_FIM_EXERC": fim, "CD_CONTA": conta,
                        "DS_CONTA": rotulo,
                        "VL_CONTA": valor,
                    })

    capital = None
    mi = re.search(r"<CaptalIntegralizado>(.*?)</CaptalIntegralizado>", x, re.S)
    mt = re.search(r"<Tesouraria>(.*?)</Tesouraria>", x, re.S)
    tot = _numero_br(_tag(mi.group(1), "QtdeTotalAcoes")) if mi else None
    if tot:
        capital = {"CNPJ_CIA": cnpj, "DT_REFER": refer, "VERSAO": versao,
                   "DENOM_CIA": nome, "QT_ACAO_TOTAL_CAP_INTEGR": tot,
                   "QT_ACAO_TOTAL_TESOURO":
                       (_numero_br(_tag(mt.group(1), "QtdeTotalAcoes"))
                        if mt else None) or "0"}
    if not linhas:
        return None, None, "XML único sem demonstrativo"
    return linhas, capital, None


def baixar(id_doc: str, tentativas: int = 5) -> bytes | None:
    pedido = urllib.request.Request(RAD.format(id=id_doc),
                                    headers={"User-Agent": "Mozilla/5.0"})
    for i in range(tentativas):
        try:
            with urllib.request.urlopen(pedido, timeout=300) as r:
                corpo = r.read()
            if corpo[:2] != b"PK":
                return None  # o RAD devolveu página, e não pacote
            zipfile.ZipFile(io.BytesIO(corpo))  # truncado não abre
            return corpo
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
    ponte = Path("docs/validacao/ponte_cvm.json")
    deslistadas = Path("data/b3/ponte_deslistadas.json")
    for p in (ponte, deslistadas):
        if not p.exists():
            print(f"{p} não existe — rode antes a sequência do item C5.",
                  file=sys.stderr)
            return 2
    cnpjs = set(json.loads(ponte.read_text(encoding="utf-8"))["ponte"].values())
    cnpjs |= set(json.loads(deslistadas.read_text(encoding="utf-8")).keys())

    alvo = vigentes_antigas(indice(cvm, cnpjs))
    global _destino
    destino = cvm / "versoes"
    destino.mkdir(parents=True, exist_ok=True)
    _destino = str(destino)
    feitos_arq = destino / "baixados.json"
    feitos = (json.loads(feitos_arq.read_text(encoding="utf-8"))
              if feitos_arq.exists() else {})
    # Download que falhou volta à fila; pacote que não converte, não.
    faltam = [x for x in alvo
              if feitos.get(x[1][2], {}).get("motivo", "download falhou")
              == "download falhou"]
    print(f"== Versões antigas vigentes em coorte: {len(alvo)} "
          f"({len(alvo) - len(faltam)} já baixadas, {len(faltam)} faltam) ==")
    if a.contar:
        return 0

    def buscar(item):
        (cnpj, refer, doc), (versao, receb, id_doc, nome) = item
        time.sleep(a.pausa)
        pacote = baixar(id_doc)
        if pacote is None:
            return item, (None, None, "download falhou")
        try:
            return item, converter(pacote, cnpj, refer, versao, nome)
        except (zipfile.BadZipFile, KeyError, ValueError) as e:
            return item, (None, None, f"conversão falhou: {e}")

    # Poucas conexões ao mesmo tempo: o RAD reseta a transferência longa, e o
    # pacote passa de 15 MB por causa do PDF. A escrita fica neste fio.
    with ThreadPoolExecutor(max_workers=a.conexoes) as pool:
        resultados = pool.map(buscar, faltam)
        for i, (item, (linhas, capital, motivo)) in enumerate(resultados):
            (cnpj, refer, doc), (versao, receb, id_doc, nome) = item
            registrar(doc, linhas, capital)
            feitos[id_doc] = {"cnpj": cnpj, "refer": refer, "doc": doc,
                              "versao": versao, "recebidoEm": receb,
                              "motivo": motivo or "ok"}
            feitos_arq.write_text(
                json.dumps(feitos, ensure_ascii=False, indent=0),
                encoding="utf-8")
            print(f"  [{i + 1}/{len(faltam)}] {doc} {refer} v{versao} "
                  f"{nome[:30]}: {motivo or 'ok'}", flush=True)
    return 0


def registrar(doc: str, linhas, capital) -> None:
    """Acrescenta as linhas de uma versão aos CSVs de `data/cvm/versoes/`."""
    destino = Path(_destino)
    if linhas:
        for dem, rows in linhas.items():
            arq = destino / f"{doc.lower()}_cia_aberta_{dem}_versoes.csv"
            novo = not arq.exists()
            with arq.open("a", encoding="latin-1", errors="replace",
                          newline="") as h:
                w = csv.DictWriter(h, fieldnames=CAMPOS, delimiter=";")
                if novo:
                    w.writeheader()
                w.writerows(rows)
        if capital:
            arq = destino / f"{doc.lower()}_cia_aberta_composicao_capital_versoes.csv"
            novo = not arq.exists()
            with arq.open("a", encoding="latin-1", errors="replace",
                          newline="") as h:
                w = csv.DictWriter(h, fieldnames=CAMPOS_CAPITAL, delimiter=";")
                if novo:
                    w.writeheader()
                w.writerow(capital)


if __name__ == "__main__":
    sys.exit(main())

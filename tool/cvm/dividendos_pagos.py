"""Dividendos e juros sobre capital próprio pagos, por companhia e exercício, das DFPs da CVM.

**Por que existe.** O crescimento fundamental `g = ROE × (1 − payout)` pede o
payout em dinheiro. A fonte de preços não o tem por exercício, e os proventos
da B3 vêm por ação, na base de ações de cada data — somá-los exige a contagem de
cada dia, que erra de escala (item B43). O fluxo de caixa da DFP traz o valor
pago no ano, em reais, no grupo de financiamento (6.03).

**O que se soma.** No exercício corrente (`ÚLTIMO`), as linhas 6.03.* cuja
descrição é de pagamento de dividendo ou de juro sobre capital próprio. Fica de
fora:

- o que é **recebido** (`Dividendos recebidos`, de coligadas);
- o que é pago a **não controladores**: o payout é o do acionista da
  companhia, e a parte do minoritário da controlada não sai do lucro dele;
- a linha **filha** de outra que já casou, para não somar duas vezes.

O descritivo varia por companhia (`Dividendos pagos`, `Pgto de
Dividendos/Juros s/ Capital Próprio`, `Juros sobre o capital próprio e
dividendos pagos`...), e é por ele que se reconhece a linha: os códigos abaixo
de 6.03 não são padronizados. Vale o consolidado; sem linha de financiamento
no consolidado, o individual. De cada DFP, a última versão.

Uso, da raiz do repositório:

    python tool/cvm/dividendos_pagos.py

Grava `data/cvm/dividendos_pagos.json` (ignorado pelo git): por CNPJ, por ano,
o pago em reais, com a fonte (`con` ou `ind`).
"""
import csv
import json
import re
from pathlib import Path

FOLDER = Path('data/cvm')
OUTPUT = FOLDER / 'dividendos_pagos.json'

_DIVIDEND = re.compile(
    r'divid|jcp|juros\s+s(obre|/)?\.?\s*(o\s+)?cap'
    # «Pagamento de Proventos» (B3); «proventos» sozinho é ambíguo — «Proventos
    # de Empréstimos» é captação —, e só casa junto de pagamento.
    r'|(pag|distribu)\w*\s+(de\s+)?provent|provent\w*\s+pag'
    r'|distribui\w*\s+de\s+lucro'
    r'|remunera\w*\s+(paga\s+)?a(os)?\s+acionista',
    re.I)
_OUTSIDE = re.compile(
    r'receb|n[aã~�]o[\s-]*controlador|minorit|baseada\s+em\s+a|emprést|emprest',
    re.I)
_SCALE = {'MIL': 1000.0, 'UNIDADE': 1.0}


def _matches(description: str) -> bool:
    return bool(_DIVIDEND.search(description)) and not _OUTSIDE.search(description)


def read(file: Path) -> dict:
    """Por (CNPJ, ano): {'versao': v, 'linhas': {codigo: valor}, 'financiamento': bool}."""
    out: dict = {}
    with file.open(encoding='latin-1', newline='') as h:
        for x in csv.DictReader(h, delimiter=';'):
            order = x.get('ORDEM_EXERC') or ''
            if not (order.startswith('Ú') or order.startswith('\xda') or order.upper().startswith('ÚLTIMO')
                    or order.startswith('�')):
                continue
            code = x.get('CD_CONTA') or ''
            if not code.startswith('6.03'):
                continue
            cnpj = x['CNPJ_CIA']
            year = int((x.get('DT_REFER') or '0000')[:4])
            version = int(x.get('VERSAO') or 1)
            key = (cnpj, year)
            current = out.get(key)
            if current is not None and version < current['versao']:
                continue
            if current is None or version > current['versao']:
                current = out[key] = {'versao': version, 'linhas': {}, 'financiamento': False}
            current['financiamento'] = True
            if code == '6.03' or not _matches(x.get('DS_CONTA') or ''):
                continue
            try:
                value = float(x.get('VL_CONTA') or 0) * _SCALE.get(
                    (x.get('ESCALA_MOEDA') or 'MIL').strip().upper(), 1000.0)
            except ValueError:
                continue
            current['linhas'][code] = value
    return out


def paid(lines: dict) -> float:
    """Soma das saídas das linhas casadas, sem a filha de outra casada."""
    total = 0.0
    for code, value in lines.items():
        parts = code.split('.')
        matched_parent = any('.'.join(parts[:k]) in lines for k in range(3, len(parts)))
        if matched_parent or value >= 0:
            continue
        total += -value
    return total


def main() -> None:
    result: dict = {}
    for file in sorted(FOLDER.glob('dfp_cia_aberta_DFC_MI_con_*.csv')):
        file_year = file.stem.rsplit('_', 1)[-1]
        individual = FOLDER / f'dfp_cia_aberta_DFC_MI_ind_{file_year}.csv'
        consolidated = read(file)
        ind = read(individual) if individual.exists() else {}
        for key in set(consolidated) | set(ind):
            cnpj, year = key
            if key in consolidated and consolidated[key]['financiamento']:
                source, payload = 'con', consolidated[key]
            elif key in ind:
                source, payload = 'ind', ind[key]
            else:
                continue
            result.setdefault(cnpj, {})[str(year)] = {
                'pago': round(paid(payload['linhas']), 2),
                'fonte': source,
                'linhas': len(payload['linhas']),
            }
        print(f'{file.name}: {len(consolidated)} consolidados, {len(ind)} individuais')
    OUTPUT.write_text(json.dumps({
        'fonte': 'CVM, DFP, demonstração do fluxo de caixa (método indireto), grupo 6.03',
        'companhias': result,
    }, ensure_ascii=False), encoding='utf-8')
    print(f'gravado {OUTPUT}: {len(result)} companhias')


if __name__ == '__main__':
    main()

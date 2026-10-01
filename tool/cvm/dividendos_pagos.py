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

PASTA = Path('data/cvm')
SAIDA = PASTA / 'dividendos_pagos.json'

_DIVIDENDO = re.compile(
    r'divid|jcp|juros\s+s(obre|/)?\.?\s*(o\s+)?cap'
    # «Pagamento de Proventos» (B3); «proventos» sozinho é ambíguo — «Proventos
    # de Empréstimos» é captação —, e só casa junto de pagamento.
    r'|(pag|distribu)\w*\s+(de\s+)?provent|provent\w*\s+pag'
    r'|distribui\w*\s+de\s+lucro'
    r'|remunera\w*\s+(paga\s+)?a(os)?\s+acionista',
    re.I)
_FORA = re.compile(
    r'receb|n[aã~�]o[\s-]*controlador|minorit|baseada\s+em\s+a|emprést|emprest',
    re.I)
_ESCALA = {'MIL': 1000.0, 'UNIDADE': 1.0}


def _casa(descricao: str) -> bool:
    return bool(_DIVIDENDO.search(descricao)) and not _FORA.search(descricao)


def ler(arquivo: Path) -> dict:
    """Por (CNPJ, ano): {'versao': v, 'linhas': {codigo: valor}, 'financiamento': bool}."""
    out: dict = {}
    with arquivo.open(encoding='latin-1', newline='') as h:
        for x in csv.DictReader(h, delimiter=';'):
            ordem = x.get('ORDEM_EXERC') or ''
            if not (ordem.startswith('Ú') or ordem.startswith('\xda') or ordem.upper().startswith('ÚLTIMO')
                    or ordem.startswith('�')):
                continue
            codigo = x.get('CD_CONTA') or ''
            if not codigo.startswith('6.03'):
                continue
            cnpj = x['CNPJ_CIA']
            ano = int((x.get('DT_REFER') or '0000')[:4])
            versao = int(x.get('VERSAO') or 1)
            chave = (cnpj, ano)
            atual = out.get(chave)
            if atual is not None and versao < atual['versao']:
                continue
            if atual is None or versao > atual['versao']:
                atual = out[chave] = {'versao': versao, 'linhas': {}, 'financiamento': False}
            atual['financiamento'] = True
            if codigo == '6.03' or not _casa(x.get('DS_CONTA') or ''):
                continue
            try:
                valor = float(x.get('VL_CONTA') or 0) * _ESCALA.get(
                    (x.get('ESCALA_MOEDA') or 'MIL').strip().upper(), 1000.0)
            except ValueError:
                continue
            atual['linhas'][codigo] = valor
    return out


def pago(linhas: dict) -> float:
    """Soma das saídas das linhas casadas, sem a filha de outra casada."""
    total = 0.0
    for codigo, valor in linhas.items():
        partes = codigo.split('.')
        pai_casado = any('.'.join(partes[:k]) in linhas for k in range(3, len(partes)))
        if pai_casado or valor >= 0:
            continue
        total += -valor
    return total


def main() -> None:
    resultado: dict = {}
    for arquivo in sorted(PASTA.glob('dfp_cia_aberta_DFC_MI_con_*.csv')):
        ano_arquivo = arquivo.stem.rsplit('_', 1)[-1]
        individual = PASTA / f'dfp_cia_aberta_DFC_MI_ind_{ano_arquivo}.csv'
        con = ler(arquivo)
        ind = ler(individual) if individual.exists() else {}
        for chave in set(con) | set(ind):
            cnpj, ano = chave
            if chave in con and con[chave]['financiamento']:
                fonte, dado = 'con', con[chave]
            elif chave in ind:
                fonte, dado = 'ind', ind[chave]
            else:
                continue
            resultado.setdefault(cnpj, {})[str(ano)] = {
                'pago': round(pago(dado['linhas']), 2),
                'fonte': fonte,
                'linhas': len(dado['linhas']),
            }
        print(f'{arquivo.name}: {len(con)} consolidados, {len(ind)} individuais')
    SAIDA.write_text(json.dumps({
        'fonte': 'CVM, DFP, demonstração do fluxo de caixa (método indireto), grupo 6.03',
        'companhias': resultado,
    }, ensure_ascii=False), encoding='utf-8')
    print(f'gravado {SAIDA}: {len(resultado)} companhias')


if __name__ == '__main__':
    main()

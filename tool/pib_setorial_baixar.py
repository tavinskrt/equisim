"""Baixa o valor adicionado a preços correntes por atividade (IBGE) para data/indices/.

**Por que existe.** Medir um crescimento pelo PIB nominal do setor de cada
ativo, no lugar do crescimento da economia inteira, pede o valor adicionado de
cada atividade em reais correntes. As Contas Nacionais Trimestrais do IBGE o
publicam desde 1996 na tabela 1846 do SIDRA, por setor e subsetor:
agropecuária, indústrias extrativas, de transformação, eletricidade e gás com
água e saneamento, construção, comércio, transporte, informação e comunicação,
atividades financeiras, imobiliárias, outros serviços e administração pública.

Uso, da raiz do repositório:

    python tool/pib_setorial_baixar.py

Grava `data/indices/pib_setorial.json`: por atividade, uma lista de
`[AAAATT, milhões de reais]`, com o trimestre como o IBGE o codifica (`201904`
é o quarto de 2019). É dado público e pequeno, e `data/indices/` não está no
`.gitignore` (ao contrário de `data/cvm/` e `data/b3/`).
"""
import json
import time
import urllib.request
from pathlib import Path

TABELA = 1846
SAIDA = Path('data/indices/pib_setorial.json')
URL = (f'https://apisidra.ibge.gov.br/values/t/{TABELA}/n1/all/v/all/p/all'
       '/c11255/all?formato=json')


def baixar() -> list:
    for tentativa in range(4):
        try:
            with urllib.request.urlopen(URL, timeout=120) as r:
                return json.loads(r.read().decode('utf-8'))
        except Exception as e:  # rede instável: repete com espera crescente
            if tentativa == 3:
                raise RuntimeError(f'SIDRA {TABELA}: {e}') from e
            time.sleep(3 * (tentativa + 1))
    return []


def main() -> None:
    linhas = baixar()
    if not linhas or not isinstance(linhas, list):
        raise RuntimeError(f'SIDRA {TABELA}: resposta vazia')
    # A primeira linha é o cabeçalho: os nomes de cada coluna `D1C`, `V`...
    cabecalho, dados = linhas[0], linhas[1:]
    coluna_atividade = next(k for k, v in cabecalho.items()
                            if v.startswith('Setores e subsetores') and k.endswith('N'))
    coluna_trimestre = next(k for k, v in cabecalho.items()
                            if v.startswith('Trimestre') and k.endswith('C'))
    atividades: dict[str, list] = {}
    vazios = 0
    for l in dados:
        valor = l.get('V')
        # O SIDRA marca valor ausente com '-', '..' ou 'X': sem valor não há
        # ponto, e inventar um mediria outra coisa.
        try:
            v = float(valor)
        except (TypeError, ValueError):
            vazios += 1
            continue
        atividades.setdefault(l[coluna_atividade], []).append(
            [l[coluna_trimestre], v])
    for serie in atividades.values():
        serie.sort(key=lambda p: p[0])
        trimestres = [p[0] for p in serie]
        if len(trimestres) != len(set(trimestres)):
            raise RuntimeError('trimestres repetidos na série baixada')
    SAIDA.parent.mkdir(parents=True, exist_ok=True)
    SAIDA.write_text(json.dumps({
        'fonte': f'IBGE, SIDRA tabela {TABELA} (Contas Nacionais Trimestrais, '
                 'valores a preços correntes, milhões de reais)',
        'atividades': atividades,
    }, ensure_ascii=False), encoding='utf-8')
    for nome, serie in sorted(atividades.items()):
        print(f'{nome}: {len(serie)} trimestres, {serie[0][0]} a {serie[-1][0]}')
    if vazios:
        print(f'{vazios} valores ausentes ignorados')
    print(f'gravado {SAIDA}')


if __name__ == '__main__':
    main()

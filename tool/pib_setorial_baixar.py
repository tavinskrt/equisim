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

TABLE = 1846
OUTPUT = Path('data/indices/pib_setorial.json')
URL = (f'https://apisidra.ibge.gov.br/values/t/{TABLE}/n1/all/v/all/p/all'
       '/c11255/all?formato=json')


def download() -> list:
    for attempt in range(4):
        try:
            with urllib.request.urlopen(URL, timeout=120) as r:
                return json.loads(r.read().decode('utf-8'))
        except Exception as e:  # rede instável: repete com espera crescente
            if attempt == 3:
                raise RuntimeError(f'SIDRA {TABLE}: {e}') from e
            time.sleep(3 * (attempt + 1))
    return []


def main() -> None:
    lines = download()
    if not lines or not isinstance(lines, list):
        raise RuntimeError(f'SIDRA {TABLE}: resposta vazia')
    # A primeira linha é o cabeçalho: os nomes de cada coluna `D1C`, `V`...
    header_lines, data = lines[0], lines[1:]
    activity_column = next(k for k, v in header_lines.items()
                            if v.startswith('Setores e subsetores') and k.endswith('N'))
    quarter_column = next(k for k, v in header_lines.items()
                            if v.startswith('Trimestre') and k.endswith('C'))
    activities: dict[str, list] = {}
    empty = 0
    for l in data:
        value = l.get('V')
        # O SIDRA marca valor ausente com '-', '..' ou 'X': sem valor não há
        # ponto, e inventar um mediria outra coisa.
        try:
            v = float(value)
        except (TypeError, ValueError):
            empty += 1
            continue
        activities.setdefault(l[activity_column], []).append(
            [l[quarter_column], v])
    for series in activities.values():
        series.sort(key=lambda p: p[0])
        quarters = [p[0] for p in series]
        if len(quarters) != len(set(quarters)):
            raise RuntimeError('trimestres repetidos na série baixada')
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps({
        'fonte': f'IBGE, SIDRA tabela {TABLE} (Contas Nacionais Trimestrais, '
                 'valores a preços correntes, milhões de reais)',
        'atividades': activities,
    }, ensure_ascii=False), encoding='utf-8')
    for name, series in sorted(activities.items()):
        print(f'{name}: {len(series)} trimestres, {series[0][0]} a {series[-1][0]}')
    if empty:
        print(f'{empty} valores ausentes ignorados')
    print(f'gravado {OUTPUT}')


if __name__ == '__main__':
    main()

"""Baixa o Ibovespa diário do SGS do Banco Central (série 7) para data/indices/.

**Por que existe.** A série do Ibovespa que a brapi entrega começa dez anos
antes de hoje (23/09/2016 na consulta de 28/09/2026). Medir um prêmio de risco
histórico numa coorte de 2018 com janela de dez anos pede o índice desde 2008,
e o SGS 7 tem o fechamento diário desde muito antes disso — até 30/09/2019,
quando a série foi descontinuada. As duas se sobrepõem de 2016 a 2019, e é na
sobreposição que `tool/validation/ibovespa_longo.dart` confere a emenda.

Uso, da raiz do repositório:

    python tool/ibovespa_sgs_baixar.py

Grava `data/indices/ibovespa_sgs7.json`: uma lista de `[AAAA-MM-DD,
fechamento]`. É dado público e pequeno, e `data/indices/` não está no
`.gitignore` (ao contrário de `data/cvm/` e `data/b3/`). Consulta ano a ano,
porque a API do SGS limita a janela de uma série diária por requisição.
"""
import json
import time
import urllib.request
from pathlib import Path

SERIES = 7
FIRST_YEAR = 2000
LAST_YEAR = 2019
OUTPUT = Path('data/indices/ibovespa_sgs7.json')
URL = ('https://api.bcb.gov.br/dados/serie/bcdata.sgs.{serie}/dados'
       '?formato=json&dataInicial=01/01/{ano}&dataFinal=31/12/{ano}')


def download_year(year: int) -> list:
    url = URL.format(serie=SERIES, ano=year)
    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=60) as r:
                data = json.loads(r.read().decode('utf-8'))
            if isinstance(data, dict):
                # O SGS responde {"erro": ...} quando o ano não tem valor.
                return []
            return data
        except Exception as e:  # rede instável: repete com espera crescente
            if attempt == 3:
                raise RuntimeError(f'SGS {SERIES}, ano {year}: {e}') from e
            time.sleep(2 * (attempt + 1))
    return []


def main() -> None:
    points = []
    for year in range(FIRST_YEAR, LAST_YEAR + 1):
        lines = download_year(year)
        empty = 0
        for l in lines:
            # O SGS devolve alguns dias com valor nulo ou vazio: sem fechamento
            # não há ponto, e inventar um (zero, repetir o anterior) mediria
            # outra coisa.
            value = l.get('valor')
            if value in (None, ''):
                empty += 1
                continue
            day, month, a = l['data'].split('/')
            points.append([f'{a}-{month}-{day}', float(value)])
        print(f'{year}: {len(lines) - empty} pregões'
              f'{f", {empty} sem valor" if empty else ""}')
    points.sort(key=lambda p: p[0])
    dates = [p[0] for p in points]
    if len(dates) != len(set(dates)):
        raise RuntimeError('datas repetidas na série baixada')
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps({
        'fonte': f'Banco Central, SGS {SERIES} (Ibovespa, fechamento diário)',
        'primeiro': dates[0],
        'ultimo': dates[-1],
        'pontos': points,
    }), encoding='utf-8')
    print(f'gravado {OUTPUT}: {len(points)} pregões, {dates[0]} a {dates[-1]}')


if __name__ == '__main__':
    main()

"""Baixa o Ibovespa diário do SGS do Banco Central (série 7) para data/indices/.

**Por que existe.** A série do Ibovespa que a brapi entrega começa dez anos
antes de hoje (23/09/2016 na consulta de 28/09/2026). Medir um prêmio de risco
histórico numa coorte de 2018 com janela de dez anos pede o índice desde 2008,
e o SGS 7 tem o fechamento diário desde muito antes disso — até 30/09/2019,
quando a série foi descontinuada. As duas se sobrepõem de 2016 a 2019, e é na
sobreposição que `tool/validation/ibovespa_longo.dart` confere a emenda.

Uso, da raiz do repositório:

    python tool/ibovespa_sgs_baixar.py

Grava `data/indices/ibovespa_sgs7.json` (ignorado pelo git, como o resto de
`data/`): uma lista de `[AAAA-MM-DD, fechamento]`. Consulta ano a ano, porque a
API do SGS limita a janela de uma série diária por requisição.
"""
import json
import time
import urllib.request
from pathlib import Path

SERIE = 7
PRIMEIRO_ANO = 2000
ULTIMO_ANO = 2019
SAIDA = Path('data/indices/ibovespa_sgs7.json')
URL = ('https://api.bcb.gov.br/dados/serie/bcdata.sgs.{serie}/dados'
       '?formato=json&dataInicial=01/01/{ano}&dataFinal=31/12/{ano}')


def baixar_ano(ano: int) -> list:
    url = URL.format(serie=SERIE, ano=ano)
    for tentativa in range(4):
        try:
            with urllib.request.urlopen(url, timeout=60) as r:
                dados = json.loads(r.read().decode('utf-8'))
            if isinstance(dados, dict):
                # O SGS responde {"erro": ...} quando o ano não tem valor.
                return []
            return dados
        except Exception as e:  # rede instável: repete com espera crescente
            if tentativa == 3:
                raise RuntimeError(f'SGS {SERIE}, ano {ano}: {e}') from e
            time.sleep(2 * (tentativa + 1))
    return []


def main() -> None:
    pontos = []
    for ano in range(PRIMEIRO_ANO, ULTIMO_ANO + 1):
        linhas = baixar_ano(ano)
        vazios = 0
        for l in linhas:
            # O SGS devolve alguns dias com valor nulo ou vazio: sem fechamento
            # não há ponto, e inventar um (zero, repetir o anterior) mediria
            # outra coisa.
            valor = l.get('valor')
            if valor in (None, ''):
                vazios += 1
                continue
            dia, mes, a = l['data'].split('/')
            pontos.append([f'{a}-{mes}-{dia}', float(valor)])
        print(f'{ano}: {len(linhas) - vazios} pregões'
              f'{f", {vazios} sem valor" if vazios else ""}')
    pontos.sort(key=lambda p: p[0])
    datas = [p[0] for p in pontos]
    if len(datas) != len(set(datas)):
        raise RuntimeError('datas repetidas na série baixada')
    SAIDA.parent.mkdir(parents=True, exist_ok=True)
    SAIDA.write_text(json.dumps({
        'fonte': f'Banco Central, SGS {SERIE} (Ibovespa, fechamento diário)',
        'primeiro': datas[0],
        'ultimo': datas[-1],
        'pontos': pontos,
    }), encoding='utf-8')
    print(f'gravado {SAIDA}: {len(pontos)} pregões, {datas[0]} a {datas[-1]}')


if __name__ == '__main__':
    main()

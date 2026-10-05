"""Baixa o prêmio-país do Brasil (EMBI+ Risco-Brasil) do IPEADATA para data/indices/.

**Por que existe (item B46).** O lambda de Damodaran mede quanto cada companhia
está exposta ao risco do país: a sensibilidade do retorno da ação à variação do
prêmio-país, comparada à das outras. A pergunta do item é se as estatais estão
mais expostas que as privadas, e o prêmio-país diário é a outra ponta da
regressão.

**A série.** O EMBI+ Risco-Brasil, do J.P. Morgan: o spread, em pontos-base,
dos títulos da dívida externa brasileira sobre os do Tesouro americano de prazo
equivalente. O IPEADATA o republica, aberto e sem cadastro, pelo código
`JPM366_EMBI366`.

Uso, da raiz do repositório:

    python tool/risco_pais_baixar.py

Grava `data/indices/embi_brasil.json`: uma lista de `[AAAA-MM-DD, pontos-base]`.
É dado público e pequeno, e `data/indices/` não está no `.gitignore`.
"""
import json
import urllib.request
from pathlib import Path

SERIE = 'JPM366_EMBI366'
URL = ('http://www.ipeadata.gov.br/api/odata4/'
       f"ValoresSerie(SERCODIGO='{SERIE}')")
SAIDA = Path('data/indices/embi_brasil.json')


def main() -> int:
    with urllib.request.urlopen(URL, timeout=120) as r:
        dados = json.loads(r.read().decode('utf-8'))
    pontos = []
    for v in dados.get('value', []):
        valor = v.get('VALVALOR')
        data = (v.get('VALDATA') or '')[:10]
        if valor is None or len(data) != 10:
            continue
        pontos.append([data, float(valor)])
    pontos.sort()
    if not pontos:
        print('o IPEADATA não devolveu valor para', SERIE)
        return 2
    SAIDA.parent.mkdir(parents=True, exist_ok=True)
    SAIDA.write_text(json.dumps(pontos), encoding='utf-8')
    print(f'{SAIDA}: {len(pontos)} dias, de {pontos[0][0]} a {pontos[-1][0]}; '
          f'último {pontos[-1][1]:.0f} pontos-base')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

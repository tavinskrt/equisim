# Risco-país e tamanho no custo de capital — item B4

> **Medido em 21/09/2026**, sobre a entrada congelada do gabarito da cascata.
>
> ```bash
> dart run tool/gabarito_cascata.dart        # congela a entrada
> dart run tool/premio_de_mercado.dart       # a varredura do prêmio
> dart run tool/tamanho.dart                 # grava tamanho.json
> ```
>
> Montagem conferida contra o gabarito ativo a ativo: **zero divergências**.
>
> **Remedido depois da [decisão 119](../decisoes/119-a-rota-derivada-tambem-remunera-o-caixa-pela-taxa-livre-de-risco.md)**,
> que estendeu à rota derivada a separação do caixa que a decisão 113 fez no
> WACC. O preço justo caiu em 73 dos 97 e dois ativos saíram; os números abaixo
> são os de depois.

## 0. A acusação do item

«Não há prêmio de risco-país, nem ajuste por tamanho, nem qualquer fator além do
beta. Um CAPM de fator único é defensável num artigo e é fraco como motor de
referência.»

São duas perguntas, e as duas têm resposta medida.

## 1. Risco-país: já está no desconto, e somá-lo seria contar duas vezes

**A taxa livre de risco deste motor é brasileira, em reais.** Não é o Treasury
com um spread por cima — é o CDI e a curva do Tesouro Nacional, que já
**precificam** o risco de crédito soberano e a inflação local.

| | nominal | real (Fisher, IPCA de 4,5%) |
|---|---:|---:|
| `R_f` corrente | 14,15% | **9,23%** |
| `R_f` terminal (estrutural) | 9,40% | **4,69%** |

Um juro real de 9,23% ao ano, contra um real americano de longo prazo da ordem de
2%. **Os sete pontos de diferença são exatamente a compensação que um prêmio de
risco-país serve para introduzir**, e ela já está dentro do desconto — em toda
avaliação, em todo ano da projeção, e também no terminal, onde o real cai para
4,69%.

A forma mais comum do ajuste — `ERP = ERP_maduro + CRP`, com prêmio maduro de
~4,3% e prêmio-país brasileiro de ~3,5% — daria um prêmio total perto de **8%**.
A varredura do B3 já mediu o que isso faz sobre um `R_f` brasileiro
([premio_de_mercado.md](premio_de_mercado.md)):

| prêmio | avaliados | potencial mediano | preço justo vs 5,5% |
|---:|---:|---:|---:|
| 5,50% | 97 | −44,73% | — |
| 8,00% | 93 | **−51,07%** | **−13,29%** |

**Quatro ativos a menos e 13% de preço justo a menos, para introduzir um risco que
o `R_f` já cobra.** O ajuste não é omissão: é dupla contagem recusada.

**A forma correta de introduzi-lo seria outra**, e ela não se aplica aqui:
converter a avaliação para dólar, descontar ao Treasury e somar o prêmio-país.
Esse caminho existe para quem avalia emergente em moeda forte; este motor avalia
companhia brasileira em reais, contra preço em reais.

## 2. Tamanho: o beta já cobra, e cobra na magnitude certa

Nos 97 avaliados, com o valor de mercado da fonte usado **só para ordenar**:

| postos de `log`(valor de mercado) contra | |
|---|---:|
| beta | **−0,327** |
| taxa de desconto | −0,184 |
| potencial | −0,111 |

**Empresa menor tem beta maior, e a relação não é fraca.** Por tercil:

| tercil | n | valor de mercado mediano | beta mediano | desconto mediano | potencial mediano |
|---|---:|---:|---:|---:|---:|
| menor | 32 | R$ 2,25 bi | **1,387** | 18,91% | −34,04% |
| meio | 32 | R$ 8,87 bi | 1,013 | 18,05% | −55,10% |
| maior | 33 | R$ 94,11 bi | **0,876** | 17,89% | −42,16% |

A diferença de beta entre o tercil menor e o maior é de **0,511**. Ao prêmio de
5,5%, isso é **2,81 pontos percentuais** de custo do capital próprio a mais para
os menores.

**Dois pontos é a ordem de grandeza do prêmio por tamanho da literatura de
fatores, e o beta cobra quase três.** O motor já cobra, pelo beta, **mais** do
que um ajuste explícito somaria.

### E somar por cima faz o que se esperaria

Dois pontos percentuais somados ao prêmio **só do tercil menor**:

| | |
|---|---:|
| preço justo no tercil menor | **−11,64%** (p25 −14,81%, p75 −9,35%) |
| preço justo no universo | 0,00% |
| postos do potencial | **0,9920** |
| deixam de ser avaliáveis | 0 |

**A ordenação não muda** — e é ela que a §0 do plano acusa. O que muda é o nível
de um terço do universo, para baixo, **justamente no tercil cujo potencial é o
menos negativo** (−34,04% contra −55,10% do meio). Somar o prêmio afastaria o
motor do mercado, e não o aproximaria.

## 3. O que se decidiu

[Decisão 117](../decisoes/117-risco-pais-e-tamanho-sao-recusados-com-medicao.md):
**os dois são recusados, com medição.**

- **Risco-país**, porque o `R_f` brasileiro já o contém — 9,23% de juro real —, e
  somá-lo custaria 13% de preço justo e quatro avaliações para contar duas vezes
  a mesma coisa.
- **Tamanho**, porque o beta já cobra **2,81 p.p.** a mais do tercil menor —
  acima da magnitude do ajuste —, e porque somá-lo não move a ordenação (postos
  de 0,992) e afasta o nível.

**A recusa é do ajuste, e não da crítica.** O CAPM continua sendo de fator único,
e isso continua sendo limitação declarada — o que esta medição estabelece é que
os dois fatores nomeados pelo item **já estão dentro dele por outro caminho**.

## 4. O que isto não diz

- **Não mede retorno realizado por tamanho.** Se pequenos brasileiros de fato
  renderam mais, é pergunta de coorte, e depende da base bruta (item C5). O que
  está medido é o que o motor já **cobra**, e o que um ajuste mudaria.
- **Não testa outros fatores.** Valor, momento, qualidade e liquidez estão fora,
  e a §0 do plano já mostrou que o book-to-market ordena mais que o potencial —
  o que é assunto do B1 e do C1, e não do custo de capital.
- **O valor de mercado usado é o da fonte**, que erra em alguns tickers (decisão
  83). Ele entra **só na ordenação** por tamanho, onde um erro de escala não
  troca tercil; nenhuma conta de dinheiro depende dele aqui.
- **O beta maior dos pequenos pode ser ruído de liquidez**, e não risco. A
  [decisão 108](../decisoes/108-a-recusa-por-liquidez-fica-e-o-beta-corrigido-fecha-um-terco-da-distancia.md)
  mediu o viés de negociação não sincrônica e manteve a recusa por liquidez; aqui
  a leitura é sobre os que **passam** no corte, onde o viés é menor — mas não é
  zero, e isso empurra na direção de o beta dos pequenos estar **subestimado**,
  não superestimado.

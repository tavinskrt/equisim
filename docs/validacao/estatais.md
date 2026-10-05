# O controle estatal na taxa de desconto — item B46

> **Medido em 02/10/2026**, sobre a entrada congelada de 14/09/2026 e as
> coortes do backtest, por `tool/estatais.dart`,
> `tool/backtest_valuation.dart --premio-estatal` e `tool/estatais_backtest.py`.
> Dados em [estatais.json](estatais.json) e
> [backtest_estatais.json](backtest_estatais.json).
> A ressalva de controle estatal entrou no motor pela
> [decisão 145](../decisoes/145-a-avaliacao-declara-o-controle-estatal-sem-mudar-o-preco.md);
> **cobrar um prêmio a mais das estatais não está decidido**.

## 1. A pergunta

O usuário, em 02/10/2026: «ainda sim achamos que o preço das estatais está um
pouco inflado pois a taxa de desconto para essas empresas, na teoria, deveria
ser um pouco maior do que para as demais. Existe alguma forma de fazermos com
que a taxa de desconto se ajuste para esses casos se agarrando em alguma teoria
financeira?» Autorizou quatro passos e o download do prêmio-país.

## 2. O que a teoria diz

| Teoria | O que afirma | Onde entraria |
|---|---|---|
| **Agência e governança** (Jensen e Meckling, 1976; Shleifer e Vishny, 1994; La Porta e outros, 2002; Musacchio e Lazzarini, 2014) | o controlador público persegue objetivos além do lucro — preço de combustível, tarifa, crédito direcionado, indicação política —, e o minoritário paga. É o "desconto de estatal" | **no fluxo**: o que o minoritário pode esperar receber |
| **CAPM** | só o risco que anda com o mercado muda a taxa | a parte da interferência que anda com a economia já estaria no beta |
| **Lambda de Damodaran** (2003) | cada companhia tem exposição própria ao risco do país: `Ke = Rf + β × prêmio + λ × prêmio-país` | **na taxa**: aqui o prêmio-país já está no prefixado para todas (decisão 117), e só o excesso de λ acima de 1 entraria |

A prática recomenda **não somar à taxa um prêmio específico que a medição não
sustente** (Damodaran; Brealey, Myers e Allen). Por isso a pergunta foi
respondida medindo: o beta e o lambda são os dois lugares em que a taxa poderia
cobrar o risco do controle.

## 3. Quem é estatal, e em que data

O Formulário Cadastral da CVM traz, todo ano, a espécie do controle acionário
(`Especie_Controle_Acionario`). O histórico de cada companhia sai dos
formulários de 2010 a 2026, com a data da mudança tirada da coluna
`Data_Especie_Controle_Acionario` quando ela cai entre os dois formulários
(`tool/controle_empacotar.dart`, `assets/cvm/controle.json`).

- **Em 14/09/2026, 17 dos 293 emissores do universo são estatais**: Banco do
  Brasil, BB Seguridade, Caixa Seguridade, Petrobras, Cemig, Copasa, Sanepar,
  Banrisul, Banestes, Banese, Banco da Amazônia, Banco do Nordeste, BRB,
  Celesc, CEB, Telebras e SPTuris.
- **As privatizações saem datadas**: Eletrobras em 17/06/2022, Copel em
  11/08/2023, Sabesp em 22/07/2024, EMAE em 02/10/2024, BR Distribuidora em
  27/06/2019. A CEEE-D, sem data plausível declarada, muda em 01/01/2022 (foi
  privatizada em julho de 2021).
- **Dez papéis de oito estatais são avaliados** na entrada congelada; as
  outras nove companhias são recusadas pela liquidez. A Copasa só entrou depois
  de corrigido, na mesma rodada, o defeito que a recusava como insolvente com
  R$ 8,6 bilhões de patrimônio (item B47,
  [decisão 146](../decisoes/146-sem-o-par-vpa-e-contagem-a-base-e-o-pl-da-demonstracao.md)).

## 4. O potencial que o motor dá às estatais

| | Estatais | Privadas |
|---|---:|---:|
| Avaliadas em 14/09/2026 | 10 | 100 |
| Potencial mediano | **−5,0%** | **−41,6%** |
| Com potencial acima de zero | 5 | 23 |

**Dentro do mesmo setor a diferença continua**: no financeiro, Banco do Brasil
+78%, Banrisul +36%, BB Seguridade +9% e Caixa Seguridade −41%, contra −34% na
mediana das 20 privadas; em utilidade pública, Sanepar +33% e +38%, Cemig −22%
e Copasa −76%, contra −37% nas 11 privadas.

**Nas coortes do backtest**, de 2018 a 2025, o motor deu às estatais potencial
maior que o das privadas em quase todas: 28 de 30 em 12 meses e 21 de 22 em
36, com 38 e 44 pontos de diferença na mediana. E as estatais **renderam
mais**: 14 pontos acima das privadas em 12 meses (19 de 30 coortes) e 32 em 36
(17 de 22). Mas renderam um pouco menos do que o potencial as ordenava: a
posição delas no retorno ficou, em média, 6 pontos percentuais abaixo da
posição no potencial em 12 meses e 2 em 36. São 12 companhias, com classes que
andam juntas, e as coortes se sobrepõem.

## 5. Medição 1 — o beta

O motor encolhe o beta medido em direção à mediana do setor, e o setor é quase
todo de privadas. Se o encolhimento puxasse o beta das estatais para baixo, a
correção caberia no CAPM puro.

| | Companhias | Beta medido (mediana) | Beta encolhido (mediana) | Encolhido − medido |
|---|---:|---:|---:|---:|
| Estatais | 17 | 0,46 | 0,46 | +0,001 |
| Privadas | 275 | 0,91 | 0,92 | −0,000 |
| Estatais avaliadas (passam a liquidez) | 8 | 0,83 | — | — |
| Privadas avaliadas | 92 | 1,00 | — | — |

**O encolhimento não é o problema**: ele quase não mexe no beta de ninguém (o
peso mediano da medida é 0,98). **O beta das estatais é que é menor**: 0,33
abaixo da mediana das privadas do mesmo setor. Parte disso é a baixa liquidez
dos bancos regionais — papel parado tem beta medido baixo —, mas mesmo entre as
avaliadas, que passam o corte de liquidez, a diferença fica: 0,83 contra 1,00
(`t` de Welch de −4,3). **Pelo beta, a taxa das estatais deveria ser menor, e
não maior.**

## 6. Medição 2 — o lambda

A sensibilidade do retorno semanal de cada companhia à queda do risco soberano,
em cinco anos, por duas séries independentes: o **EMBI+ Risco-Brasil**, do J.P.
Morgan pelo IPEADATA (`tool/risco_pais_baixar.py`), de 30/07/2019 a 30/07/2024,
quando o índice foi descontinuado; e o **prefixado de dez anos** da curva do
Tesouro, de 14/09/2021 a 14/09/2026, que é o risco soberano em reais. O lambda
de cada grupo é a sensibilidade mediana dele dividida pela do universo. Entra
quem teve a mesma espécie de controle na janela inteira.

| | EMBI+ (2019–2024) | Prefixado de 10 anos (2021–2026) |
|---|---:|---:|
| λ das estatais | **0,71** (17) | **0,70** (16) |
| λ das privadas | 1,04 (191) | 1,03 (244) |
| `t` de Welch, estatal − privada | −3,40 | −4,76 |
| Além do Ibovespa, estatal − privada | +0,09 na mediana; `t` 0,53 | −0,41 na mediana; `t` −1,18 |
| λ das estatais avaliadas | 0,74 (8) | 0,76 (8) |
| Além do Ibovespa, só as avaliadas | `t` 0,28 | `t` −1,88 |

**As estatais são menos sensíveis ao risco soberano**, e não mais. Além do que
o Ibovespa já explica, a diferença não se distingue de zero. **Pelo lambda,
`(λ − 1) × prêmio-país` dá −0,66 ponto** (prêmio-país de 2,28%, o último EMBI+):
a taxa também sairia menor.

Os casos grandes são mistos: Petrobras e Banco do Brasil têm λ acima de 1 pelo
EMBI+ (1,44 a 1,56 e 1,09) e abaixo de 1 pelo prefixado (0,64 a 0,67 e 0,90).

## 7. Medição 3 — o efeito de cobrar um prêmio a mais

O prêmio a mais entra somado ao do mercado na proporção do beta
(`β × (prêmio + x ÷ β) = β × prêmio + x`), o que é exato no custo do capital
próprio de hoje; no caminho realavancado ano a ano, o acréscimo anda com a
alavancagem.

**No preço de hoje**, nas dez estatais avaliadas:

| Prêmio a mais no Ke | Potencial mediano das estatais |
|---|---:|
| nenhum | −5,0% |
| +0,5 ponto | −8,3% |
| +1 ponto | −11,3% |
| +2 pontos | −16,9% |
| +3 pontos | −21,9% |
| beta sem encolhimento | −4,4% |
| *privadas, sem mudança* | *−41,6%* |

| Papel | Beta medido | λ (EMBI+) | λ (prefixado) | Potencial | +1 ponto | +2 pontos | +3 pontos |
|---|---:|---:|---:|---:|---:|---:|---:|
| BBAS3 | 0,98 | 1,09 | 0,90 | +78% | +65% | +53% | +43% |
| SAPR4 | 0,61 | 0,62 | 0,72 | +38% | +29% | +21% | +13% |
| BRSR6 | 0,86 | 0,71 | 0,74 | +36% | +26% | +18% | +10% |
| SAPR11 | 0,66 | 0,70 | 0,76 | +33% | +22% | +13% | +4% |
| BBSE3 | 0,46 | 0,56 | 0,25 | +9% | +2% | −4% | −10% |
| PETR4 | 0,88 | 1,44 | 0,67 | −19% | −25% | −29% | −34% |
| CMIG4 | 0,91 | 0,88 | 1,07 | −22% | −28% | −34% | −39% |
| PETR3 | 0,92 | 1,56 | 0,64 | −28% | −33% | −37% | −41% |
| CXSE3 | 0,69 | 0,87 | 0,70 | −41% | −45% | −48% | −51% |
| CSMG3 | 0,79 | 0,78 | 0,80 | −76% | −78% | −81% | −83% |

O primeiro ponto tira cerca de 6 pontos do potencial mediano das estatais, e
cada ponto seguinte, um pouco menos. **Fechar a diferença para as privadas
pediria mais de seis pontos**, um prêmio que nenhuma das duas medições
sustenta.

**No backtest**, cada observação de estatal na data foi avaliada de novo com
cada prêmio a mais (`--premio-estatal`), e a fila de cada coorte foi refeita com
o potencial novo delas (`tool/estatais_backtest.py`):

| Prêmio a mais no Ke | IC médio, 12 meses | IC médio, 36 meses | Posição das estatais no retorno − no potencial, 12 meses | Idem, 36 meses |
|---|---:|---:|---:|---:|
| nenhum | **0,056** | **0,086** | −0,059 | −0,022 |
| +0,5 ponto | 0,054 | 0,084 | −0,046 | −0,010 |
| +1 ponto | 0,053 | 0,081 | −0,033 | +0,003 |
| +2 pontos | 0,051 | 0,081 | −0,014 | +0,018 |
| +3 pontos | 0,048 | 0,077 | +0,009 | +0,041 |

**A posição média das estatais se acerta com um prêmio pequeno** — cerca de 1
ponto em 36 meses e de 2,5 em 12 —, **mas a ordenação do universo piora com
qualquer prêmio**, nos dois horizontes. As estatais renderam mais que as
privadas, e empurrá-las para baixo na fila desalinha mais do que alinha. As
diferenças de IC são pequenas e estão dentro do ruído da amostra; o sentido é
que é o mesmo em todas as linhas.

## 8. Medição 4 — a ressalva

A avaliação de uma estatal passa a levar a ressalva **controle estatal** e um
aviso que diz o que foi medido; o preço justo não muda
([decisão 145](../decisoes/145-a-avaliacao-declara-o-controle-estatal-sem-mudar-o-preco.md)).
A montagem do aplicativo nas ferramentas — a entrada congelada, o gabarito e o
backtest — leva a mesma ressalva, pela espécie na data.

## 9. O que isto quer dizer

1. **A intuição tem base, e o motor de fato acha as estatais mais baratas que
   as privadas** — hoje e em todas as coortes, dentro do mesmo setor também.
2. **Mas as duas teorias que poriam esse risco na taxa dizem o contrário.** O
   beta das estatais é menor que o das privadas, e o lambda de Damodaran fica
   em 0,7: pelo CAPM e pela exposição ao risco do país, a taxa delas sairia
   **menor**. O risco do controlador público não anda com o mercado nem com o
   risco soberano; pela teoria de agência, ele está no fluxo que o minoritário
   pode esperar receber.
3. **O mercado cobra esse risco, e cobrou caro demais na amostra.** O desconto
   de estatal existe — elas negociam barato contra o fluxo que o motor
   projeta —, e nas coortes de 2018 a 2025 elas renderam acima das privadas,
   parte disso pelas privatizações, quando o desconto some de uma vez.
4. **Cobrar um prêmio na taxa pioraria a ordenação.** Ele acerta a posição
   média das estatais com 1 a 2,5 pontos, mas o IC do universo cai com
   qualquer prêmio. E fechar a diferença de nível para as privadas pediria mais
   de seis pontos, que nada sustenta.
5. **O que foi feito**: a ressalva de controle estatal, que diz o que o motor
   não cobra e por quê (decisão 145). **O que fica para decidir**, com o
   orientador: se o risco do controle deve entrar no **fluxo** — por exemplo,
   pela distribuição que o minoritário recebeu no passado, contra a das
   privadas —, que é onde a teoria o põe e que esta medição não testou.

## 10. O que isto não diz

- **O EMBI+ termina em 30/07/2024.** A janela dele não é a do prefixado, e o
  prêmio-país usado na conta do lambda tem dois anos. As duas séries dão o
  mesmo lambda, o que é o que dá confiança a ele.
- **Onze companhias.** Três bancos, duas classes da Cemig e três papéis da
  Sanepar andam juntos; a diferença entre grupos tem pouco poder, e o `t` das
  coortes não foi corrigido pela sobreposição.
- **O beta e o lambda medem o risco que anda com o mercado e com o risco
  soberano.** O risco do controle que não anda com nada — a decisão política de
  um ano — não aparece em nenhum dos dois; a teoria de agência diz que ele está
  no fluxo esperado, e o fluxo esperado do minoritário não foi medido aqui.
- **A data da privatização** sai do formulário; quando ele não a declara de
  forma plausível, a mudança vale de 1º de janeiro do primeiro formulário novo.

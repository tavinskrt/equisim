# O prêmio de risco medido do Ibovespa

Medido em 29/09/2026, a pedido do orientador: o prêmio de mercado do CAPM pode
ser **capturado** do mercado, em vez de fixado em 5,5%? Esta é a forma mais
direta de capturá-lo, a histórica: quanto o Ibovespa rendeu acima do CDI na
mesma janela. **É medição: nada foi ligado no motor.**

Reproduz-se com:

```bash
python tool/ibovespa_sgs_baixar.py
```

```bash
dart run tool/premio_historico.dart
```

O resultado completo está em [premio_historico.json](premio_historico.json).

---

## 1. Como o prêmio é medido

```
prêmio = (1 + crescimento anual do Ibovespa) ÷ (1 + crescimento anual do CDI) − 1
```

- As duas taxas saem da **mesma janela** terminada na data, com as regras que o
  aplicativo já usa nas âncoras de mercado (`ResolveMarketAnchors`): o Ibovespa
  entre as médias de 63 pregões das duas pontas (decisão 60), o CDI composto dia
  a dia.
- É Fisher, e não subtração, como na decisão 116.
- O erro-padrão é `volatilidade anual do índice ÷ √anos`.

**A série do Ibovespa.** A brapi entrega só os últimos dez anos (desde
23/09/2016). Para janelas mais longas e para as datas das coortes, o índice
antes disso vem do Banco Central (SGS 7, fechamento diário até 30/09/2019). Nos
744 pregões em que as duas séries existem, a razão mediana entre elas é
1,000000 ([ibovespa_longo.dart](../../tool/validation/ibovespa_longo.dart)).

---

## 2. Hoje (entrada congelada de 14/09/2026): o número depende da janela

| Janela | Ibovespa ao ano | CDI ao ano | **Prêmio** | Erro-padrão | Intervalo de 95% |
|---:|---:|---:|---:|---:|---|
| 5 anos | 10,63% | 12,59% | **−1,75%** | 7,85 p.p. | −17,1% a +13,6% |
| 10 anos | 11,41% | 9,39% | **+1,85%** | 7,17 p.p. | −12,2% a +15,9% |
| 15 anos | 8,02% | 9,84% | **−1,66%** | 5,96 p.p. | −13,3% a +10,0% |
| 20 anos | 7,80% | 10,19% | **−2,17%** | 5,79 p.p. | −13,5% a +9,2% |

(As âncoras congeladas do aplicativo, com a série da brapi, dão 1,88% em dez
anos; a diferença para 1,85% é a série do Banco Central nas pontas.)

**Só a janela de dez anos dá prêmio positivo.** Com 5, 15 ou 20 anos, o
Ibovespa rendeu **menos** que o CDI. E em todas as janelas o intervalo de 95%
vai de −12% a +16%: o dado não distingue um prêmio de −5% de um de +10%.

**Correção de registro.** A decisão 116 mediu o prêmio de cinco anos em +0,39%,
comparando o Ibovespa de **cinco** anos com o CDI de **dez** anos (as âncoras
congeladas). Na mesma janela, o prêmio de cinco anos é −1,75%. A conclusão
daquela decisão — o histórico é ruído — não muda; o número muda.

---

## 3. O que cada prêmio faz ao aplicativo

O universo inteiro reavaliado sobre a entrada congelada, com o prêmio de cada
janela no lugar dos 5,5%:

| Prêmio | Avaliados | Upside mediano | Upside acima de zero | Preço justo, na mediana | Postos contra 5,5% |
|---|---:|---:|---:|---:|---:|
| 5,5% fixo | 97 | −45,4% | 15 de 97 | — | 1,000 |
| 10 anos (+1,85%) | 107 | −38,3% | 25 de 107 | +28,5% | 0,985 |
| 5 anos (−1,75%) | 108 | −22,0% | 37 de 108 | +71,8% | 0,940 |
| 15 anos (−1,66%) | 108 | −22,7% | 37 de 108 | +70,4% | 0,942 |
| 20 anos (−2,17%) | 109 | −18,2% | 42 de 109 | +79,5% | 0,931 |

Os cinco casos do guia de estudo:

| Prêmio | WEGE3 | ITUB4 | VALE3 | SAPR11 | RENT3 |
|---|---:|---:|---:|---:|---|
| 5,5% fixo | R$ 12,53 | R$ 21,76 | R$ 70,25 | R$ 36,74 | recusada |
| 10 anos (+1,85%) | R$ 15,53 | R$ 27,82 | R$ 85,46 | R$ 44,44 | recusada |
| 5 anos (−1,75%) | R$ 20,50 | R$ 37,79 | R$ 107,54 | R$ 55,04 | recusada |
| 20 anos (−2,17%) | R$ 21,32 | R$ 39,40 | R$ 110,83 | R$ 56,56 | recusada |
| **Preço de mercado** | R$ 50,74 | R$ 42,35 | R$ 75,48 | R$ 34,74 | R$ 35,59 |

**O prêmio aproxima o motor do mercado, mas não fecha a distância**, e só chega
perto quando é negativo. A ordem entre as ações quase não muda com o de dez
anos (0,985) e muda um pouco com os negativos (0,93 a 0,94).

---

## 4. Nas datas das coortes: negativo quase sempre

O prêmio de cada data do backtest, só com dado até ela:

| | Janela de 10 anos | Janela de 5 anos |
|---|---|---|
| Faixa | de −7,71% a +2,35% | de −4,15% a +11,75% |
| Mediana | −1,77% | +0,89% |
| **Datas com prêmio negativo** | **25 de 31** | **14 de 31** |
| Erro-padrão típico | 7 a 9 p.p. | 8 a 12 p.p. |

A janela de dez anos só fica positiva a partir do fim de 2023; a de cinco anos
passa de +11% em 2020 e 2021 (depois da alta de 2016 a 2019) e volta a negativa
em 2024 e 2025. A tabela data a data está no JSON (`porCoorte`).

---

## 5. O que isto quer dizer

1. **No Brasil, o Ibovespa rendeu menos que o CDI na maior parte das janelas
   recentes.** Com prêmio histórico, o motor usaria prêmio negativo em 25 de 31
   datas.
2. **Prêmio negativo não é premissa defensável no CAPM.** Ele diz que o
   investidor aceita, de antemão, render menos que a renda fixa para carregar
   risco — e que a ação mais arriscada (beta alto) é a que exige **menos**
   retorno. O prêmio do CAPM é uma expectativa, e o histórico é o que aconteceu;
   num período de juro real alto e bolsa fraca, os dois se separam.
3. **A janela vira o novo número fixado.** Entre 5, 10, 15 e 20 anos o prêmio de
   hoje vai de −2,2% a +1,9%, e a escolha da janela decide o resultado.
4. **O efeito é de nível, não de ordem**, como a decisão 116 já tinha medido.

## 6. O que não foi feito, e por quê

**O backtest inteiro com o prêmio de cada coorte não foi rodado.** Com o prêmio
de dez anos negativo em 25 das 31 coortes, ele mediria um CAPM em que o beta alto
barateia o capital, que nenhuma teoria sustenta. Fica disponível se o usuário
quiser ver o efeito sobre a faixa calibrada e a habilidade mesmo assim, ou com
uma regra (por exemplo, prêmio com piso em zero), o que já seria outra premissa.

**A alternativa que resta para capturar o prêmio do mercado é o prêmio
implícito do índice** (a taxa que iguala o preço do Ibovespa ao dinheiro que ele
distribui, pelo método de Damodaran), que olha para a frente em vez de para
trás. Não foi medido aqui: está em [premio_implicito.md](premio_implicito.md),
medido no mesmo dia. A média de cinco ou de dez anos dele fica positiva em
todas as coortes, entre 0,1% e 2,0%, e hoje em 1,55% e 1,23%, perto do
histórico de dez anos.

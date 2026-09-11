# O retorno por ativo mede o dinheiro, não o ativo

Medido em 11/09/2026.

```bash
dart run tool/retorno_por_ativo.dart   # grava retorno_por_ativo.json
```

---

## 0. A proposta

A lente `metodo` apontou, como achado **local**:

> Modificar `AssetPerformance` para receber e calcular um *Time-Weighted
> Return* individual ou XIRR específico, em substituição à razão simples do
> capital em `totalReturn`. […] isoladas do cronograma de aporte.

A carteira reporta três retornos — TWR, XIRR e o CAGR derivado do TWR. Cada
ativo reporta um só:

```
totalReturn = (valor final + caixa − aportado) ÷ aportado
```

que é razão de capital acumulado, sem dimensão de tempo.

## 1. O canal que a lente teme está fechado — duas vezes

A preocupação é que ativos com históricos de tamanhos diferentes fiquem
incomparáveis. **Isso não pode acontecer.**

`PortfolioBacktest.run` recua o início efetivo para o **mais tardio** dos
primeiros pregões da carteira, e avisa. Medido: dois ativos, um listado 60
meses depois do outro, produzem

```
período efetivo 01/01/2024 a 01/12/2025
aviso: Período encurtado […]: nem todos os ativos possuem histórico desde o
       início solicitado.
VALE4 20.8%   NOVO3 20.8%   — medidos na mesma janela
```

E `backtestComparisonProvider` faz o mesmo **entre as duas carteiras**, com o
início comum calculado sobre a união dos tickers de Principal e Reserva antes
de qualquer execução. O comentário lá já registra a razão.

Todo ativo é medido na mesma janela que todos os outros, das duas carteiras.

## 2. O canal que resta, e o tamanho dele

Com janela comum e cronograma comum, `totalReturn` **ainda** difere do retorno
de preço, porque o aporte mensal interage com a trajetória de cada ativo.

**Isolado.** Dois ativos que partem de 100 e voltam a 100 — retorno de preço
**zero para ambos** —, um em vale e outro em pico:

| ativo | trajetória | retorno de preço | `totalReturn` |
|---|---|---:|---:|
| VALE4 | cai e volta | 0,0% | **+37,2%** |
| PICO4 | sobe e volta | 0,0% | **−19,2%** |

**56,5 pontos percentuais** entre dois ativos cujo preço não saiu do lugar.

**Numa carteira real** de 15 ativos, aporte inicial de R$ 10.000 e mensal de
R$ 1.000, de 30/09/2019 a 04/09/2026:

| ticker | `totalReturn` | retorno de preço | posto tR | posto preço |
|---|---:|---:|---:|---:|
| ALOS3 | +39,1% | −0,0% | 1 | 6 |
| ABCB4 | +31,1% | +37,3% | 2 | 3 |
| ALPK3 | +27,6% | −52,9% | 3 | 9 |
| ALUP3 | +25,4% | +18,2% | 4 | 4 |
| ALUP11 | +22,9% | +38,3% | 5 | 2 |
| ALUP4 | +16,8% | +44,3% | 6 | 1 |
| ABEV3 | +10,7% | −18,2% | 7 | 7 |
| ALPA4 | +7,2% | −47,6% | 8 | 8 |
| AFLT3 | −9,6% | −57,8% | 9 | 11 |
| ALPA3 | −14,9% | −56,2% | 10 | 10 |
| AGRO3 | −21,5% | +8,3% | 11 | 5 |
| ALLD3 | −39,6% | −69,8% | 12 | 12 |
| AALR3 | −61,9% | −82,9% | 13 | 13 |
| AMAR3 | −62,5% | −95,8% | 14 | 14 |
| AERI3 | −75,7% | −97,9% | 15 | 15 |

**Spearman entre as duas medidas: 0,7571. Maior deslocamento: 6 postos de 15.**

TWR da carteira −22,2%, XIRR −2,4%.

## 3. Qual das duas é a certa

**As duas, para perguntas diferentes** — e a que está no lugar é a certa para a
pergunta que a tela faz.

O cartão de desempenho por ativo existe para uma decisão: **trocar o pior ativo
da Principal pelo melhor candidato da Reserva.** Essa decisão é sobre dinheiro
que de fato seguiu aquele cronograma de aportes. A ALOS3 rendeu +39,1% ao
investidor mensal ainda que o preço não tenha andado, e isso não é ilusão
contábil: é o resultado de comprar durante a queda. Trocá-la por um TWR de
−0,0% descreveria o ativo e **esconderia o que aconteceu com o capital**.

O glossário da tela já dizia o certo — *"quanto o **capital destinado** àquele
ativo rendeu"* —, e agora traz também a ressalva com o tamanho medido, porque
um leitor que compare o número ao gráfico do ativo encontra até 56,5 p.p. de
diferença e precisa saber por quê.

## 4. Conclusão

**A conta fica; o rótulo ganhou a ressalva.** A proposta de substituir
`totalReturn` por TWR por ativo é recusada: ela responderia pior à pergunta que
o cartão faz.

O que sobra como dívida, e não foi feito: a tela **não oferece** a leitura
independente de cronograma. Quem quiser saber como o ativo andou, e não como o
dinheiro dele andou, precisa olhar o gráfico. Acrescentar uma segunda coluna
resolveria — e é acréscimo de interface, não correção de defeito.

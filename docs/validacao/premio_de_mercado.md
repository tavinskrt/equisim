# O prêmio de risco de mercado — item B3

> **Medido em 21/09/2026**, sobre a entrada congelada do gabarito da cascata.
>
> ```bash
> dart run tool/gabarito_cascata.dart      # congela a entrada
> dart run tool/premio_de_mercado.dart     # grava premio_de_mercado.json
> ```
>
> Montagem de 5,5% conferida contra o gabarito ativo a ativo: **zero
> divergências**.
>
> **Remedido depois da [decisão 119](../decisoes/119-a-rota-derivada-tambem-remunera-o-caixa-pela-taxa-livre-de-risco.md)**,
> que estendeu à rota derivada a separação do caixa que a decisão 113 fez no
> WACC. O preço justo caiu em 73 dos 97 e dois ativos saíram; os números abaixo
> são os de depois.

## 0. A pergunta

O prêmio é **5,5% fixo**, ponto médio de uma faixa de 5–6% adotada por
convenção. O item B3 nomeia duas saídas: **histórico com encolhimento**, ou
**implícito**. Esta medição roda as duas.

## 1. O histórico: 0,39%, e a barra de erro engole tudo

Ibovespa contra CDI, na janela que a entrada congelada guarda:

| | |
|---|---:|
| janela | 5,00 anos (1.248 pregões) |
| Ibovespa, CAGR | 9,81% |
| CDI, CAGR | 9,39% |
| **prêmio (Fisher)** | **0,39%** |
| volatilidade anual do índice | 17,55% |
| **erro-padrão do prêmio** | **7,85%** |
| intervalo de 95% | **−15,00% a +15,77%** |

**Anos de série para um erro-padrão de 1 p.p.: 308.**

A janela de dez anos das âncoras do projeto (`MarketAnchors.fallback2026`) diz o
mesmo com outro número: Ibovespa 11,26%, CDI 9,40%, prêmio de **1,70%** — e o
erro-padrão a dez anos ainda é de 5,5 p.p.

**Não é que o prêmio brasileiro seja baixo. É que ele não é estimável com a
série que existe.** Um intervalo de trinta pontos de largura não escolhe entre
5,5% e 0,39% — nem entre 5,5% e qualquer outro número.

## 2. O encolhimento devolve o parâmetro

É a segunda saída que o item nomeia, e ela se resolve sozinha. O peso do
estimador amostral é `τ² ÷ (τ² + σ²)`:

| dispersão a priori `τ` | peso da amostra | prêmio encolhido |
|---:|---:|---:|
| 0,25% | 0,10% | **5,49%** |
| 0,50% | 0,40% | 5,48% |
| 1,00% | 1,60% | 5,42% |
| 2,00% | 6,10% | 5,19% |

**Com uma faixa a priori quatro vezes mais larga que a declarada, o encolhimento
ainda devolve 5,19%.** O histórico não carrega informação suficiente para mover
o parâmetro, e dizer isso com o número ao lado é mais forte do que adotar 5,5%
por convenção.

## 3. O implícito: −3,9%, e é o achado da medição

O universo inteiro reavaliado em cada prêmio, e a busca pelo prêmio que põe o
potencial mediano em zero:

| prêmio | avaliados | potencial mediano | acima de zero | preço justo vs 5,5% | postos |
|---:|---:|---:|---:|---:|---:|
| −6,00% | 97 | +33,44% | 60 de 97 | +168,33% | 0,783 |
| −4,00% | 108 | +0,69% | 55 de 108 | +117,79% | 0,873 |
| **−3,94%** | | **0** | | | |
| −2,00% | 110 | −19,53% | 40 de 110 | +75,70% | 0,934 |
| 0,00% | 108 | −29,86% | 33 de 108 | +48,12% | 0,969 |
| 2,00% | 108 | −38,72% | 25 de 108 | +27,38% | 0,987 |
| 4,00% | 101 | −42,58% | 18 de 101 | +10,02% | 0,998 |
| **5,50%** | **97** | **−44,73%** | 15 de 97 | — | 1,000 |
| 7,00% | 96 | −48,93% | 11 de 96 | −8,37% | 0,996 |
| 10,00% | 87 | −53,72% | 5 de 87 | −21,64% | 0,981 |

**O prêmio implícito é −3,9%**: o acionista teria de exigir quase quatro pontos
**abaixo do CDI** para que o motor concordasse com o preço da ação mediana. É absurdo
econômico, e é exatamente por isso que interessa.

### O que isso resolve

**O desacordo de nível entre o motor e o mercado não é do prêmio.** A §0 do
plano mediu o potencial mediano em −38%, e a pergunta implícita desde então era
se o custo de capital estava alto demais. **Não está — ou, se está, não é pelo
prêmio.** Zerar o prêmio move o potencial mediano de −44,7% para −29,9%: dois
terços do desacordo sobrevivem a um prêmio de risco **nulo**.

O desacordo mora em outro lugar, e as rodadas anteriores já mostraram onde: o
terminal neutro carrega um déficit perpétuo porque a rentabilidade das abertas
brasileiras vive abaixo do custo de capital delas
([decisão 112](../decisoes/112-a-rentabilidade-reverte-a-mediana-do-mercado-e-nao-ao-custo-de-capital.md)).

## 4. E o prêmio quase não mexe na ordenação

Correlação de postos do potencial contra a montagem de 5,5%: **0,996 ou mais
entre 4% e 7%**, e ainda 0,97 com prêmio zero. Só abaixo de −2% a ordenação
começa a se desmanchar —
e lá a cascata já está avaliando outro conjunto de ativos.

**O prêmio é botão de nível, não de ordenação.** Era a previsão da §3 do plano, e
está medida.

**Mas ele mexe na cobertura:** 87 avaliados a 10%, 97 a 5,5%, 110 a −2%. Prêmio
maior recusa mais, porque o capital próprio desaparece dentro da projeção em mais
ativos.

## 5. O que se decidiu

[Decisão 116](../decisoes/116-o-premio-de-mercado-fica-em-5-5-por-cento-por-medicao-das-duas-alternativas.md):
**5,5% fica**, e deixa de ser convenção.

- O histórico não estima: 0,39% com intervalo de trinta pontos de largura.
- O encolhimento — a saída que o item pedia — **devolve 5,49%**.
- O implícito é −3,9%, absurdo, e o absurdo é informação: o desacordo de nível
  não é do prêmio.

## 6. O que isto não diz

- **A janela é de cinco anos**, que é o que a entrada congelada guarda do
  Ibovespa. Uma série desde 1995 daria outro número, e ainda assim com
  erro-padrão de 3 p.p.
- **O prêmio implícito foi buscado pela mediana do potencial**, e não pelo
  agregado ponderado pelo valor de mercado — ponderar exigiria a contagem de
  papéis, que é a grandeza que a ponte arbitra (decisão 83), e o resultado
  passaria a depender dela.
- **Não mede prêmio variável no tempo.** O prêmio implícito de Damodaran é
  recalculado a cada data e varia com o ciclo; aqui há uma data só, e a
  conclusão é sobre o nível, não sobre a dinâmica.

# 5. Bancos e outras financeiras: por que a conta é outra

> **Para que serve este capítulo.** Um banco não é uma fábrica. O que é dívida
> para uma indústria é matéria-prima para um banco. Este capítulo explica por
> que o Equisim avalia bancos por outro caminho, e mostra, lado a lado, quais
> contas são feitas para bancos e quais para as demais empresas.
>
> Tempo de leitura: 40 minutos. Pré-requisito: capítulo 4.
> O [caso ITUB4](casos/itub4.md) mostra cada conta com números reais.

---

## 5.1 A dívida do banco é o produto dele

Uma siderúrgica pega empréstimo para comprar um alto-forno. O empréstimo é
**financiamento**: uma decisão sobre como pagar pela operação, separada da
operação em si.

Um banco capta dinheiro (depósitos, CDBs, letras) e empresta esse dinheiro mais
caro. A captação **é a operação**. Não dá para separar "quanto o banco lucra
operando" de "como o banco se financia": uma coisa é a outra.

Isso quebra três peças da via da firma:

1. **Não existe EBIT de banco.** Juro pago é o custo da mercadoria vendida, não
   uma despesa financeira abaixo do resultado operacional. A CVM nem publica
   EBIT para instituição financeira.
2. **Não existe "dívida líquida" de banco no sentido de estrutura de capital.**
   Subtrair os depósitos do valor do banco trataria o estoque de matéria-prima
   como dívida, e o resultado seria um valor negativo sem sentido.
3. **O WACC não faz sentido.** Não há uma "parte dívida" do financiamento para
   ponderar: o custo da captação já está dentro do lucro.

---

## 5.2 A saída: avaliar direto o dinheiro do acionista

Para bancos, o Equisim pula a firma e vai direto ao acionista (Porta 1 da
cascata, capítulo 4, seção 4.2). A lógica é a mesma do capítulo 4, com três
trocas:

| No lugar de… | usa-se… | porque… |
|---|---|---|
| NOPAT | **lucro líquido por papel** | é o que sobra ao sócio depois de pagar a captação e o imposto |
| capital investido | **patrimônio líquido** | é o capital do sócio, e é ele que o regulador exige |
| ROIC | **ROE** (lucro ÷ PL de abertura) | é o retorno do capital do sócio |
| WACC | **Ke** | o único custo a descontar é o do sócio |

E o crescimento vem do patrimônio: um banco só empresta mais se tiver mais
capital (o Banco Central limita a alavancagem pelo índice de Basileia), e
capital novo vem do lucro retido. É a mesma relação `g = b × ROE`.

---

## 5.3 As contas, lado a lado

Esta é a tabela para responder à pergunta "que contas são feitas para bancos, e
quais para não bancos?". Cada linha é um passo do motor, na ordem em que ele
acontece. Os números de exemplo vêm dos casos de 14/09/2026.

| Passo | Não banco (via da firma) — WEGE3 | Banco (via do acionista) — ITUB4 |
|---|---|---|
| **Porta 0** | liquidez ≥ R$ 2 mi/dia, ≥ 8 exercícios, PL positivo | igual |
| **Contagem de papéis** | contagem oficial da B3, líquida de tesouraria | igual |
| **Porta 1** | não é financeira → segue | é financeira → **via do acionista** |
| **Porta 3** | NOPAT positivo em ≥ 60% dos anos → via da firma | não se aplica |
| **Alíquota** | mediana das efetivas, até 34% → aplicada ao EBIT | não se usa: o lucro líquido já vem tributado |
| **Lucro de partida** | NOPAT = EBIT × (1 − alíquota) | lucro líquido ÷ papéis (LPA) |
| **Base de capital** | capital investido = PL + dívida líquida | patrimônio líquido |
| **Retorno** | ROIC = NOPAT ÷ capital de abertura | ROE = lucro ÷ PL de abertura |
| **Normalização** | mesmas três guardas, sobre o ROIC | mesmas três guardas, sobre o ROE |
| **Crescimento `g`** | mediana do crescimento do capital investido | mediana do crescimento do PL |
| **Beta** | medido e encolhido para o setor; **desalavancado** (Hamada) | medido e encolhido; **não se desalavanca** |
| **Taxa livre de risco** | forward de cada ano da curva | igual |
| **Custo do capital próprio** | Ke recalculado ano a ano com a dívida projetada (ponto fixo) | Ke = forward do ano + β × 5,5%, com o beta medido |
| **Custo da dívida** | Rf + prêmio sintético (alavancagem, cobertura) | não existe |
| **WACC** | calculado; é o **alvo** para onde o ROIC converge | não existe; o ROE converge para o Ke |
| **Projeção** | NOPAT cresce `g_t`; retenção `g_t ÷ ROIC_t` | LPA cresce `g_t`; retenção `g_t ÷ ROE_t` |
| **Fluxo de cada ano** | fluxo da firma − serviço da dívida = fluxo do acionista | LPA × (1 − retenção) = "dividendo implícito" |
| **Desconto** | ao Ke do ano, com meio de ano | ao Ke do ano, com meio de ano |
| **Valor terminal** | neutro, com moat ou de concessão — da firma, convertido ao acionista | neutro ou com moat, direto no LPA |
| **Minoritários** | subtraídos | já fora do lucro da controladora |
| **Dívida** | sai do fluxo, ano a ano | não há ponte de dívida |
| **Resultado** | capital próprio ÷ papéis | a soma já é por papel |
| **Múltiplos de pares** | P/L, P/VP e EV/EBITDA | P/L e P/VP; **EV/EBITDA recusado** |
| **Ressalva "ponte frágil"** | pode aparecer | não se aplica |

---

## 5.4 O "dividendo implícito"

Na via do acionista, o fluxo de cada ano é:

```
fluxo_t = LPA_t × (1 − b_t)        com b_t = g_t ÷ ROE_t
```

Isso tem a forma de um modelo de desconto de dividendos, mas o dividendo **não
é o dividendo publicado**: é o que o banco *poderia* distribuir mantendo o
crescimento projetado. O projeto decidiu não ler proventos na avaliação
(decisões 23 e 89) — o dividendo que um banco de fato paga depende de política,
de regulador e de juros sobre capital próprio, e não é o valor econômico do
lucro.

---

## 5.5 E o imposto de 45% dos bancos?

Bancos pagam CSLL maior que as demais empresas (a soma de IRPJ e CSLL chega a
45%). O motor usa 34% como alíquota legal no escudo fiscal do WACC — **mas o
banco não passa pelo WACC nem pelo NOPAT**: a via do acionista parte do lucro
líquido, que já saiu depois do imposto efetivamente pago. A diferença de
alíquota, portanto, não entra em nenhuma conta dos bancos (limitação declarada
nas [limitações](../validacao/limitacoes.md), sem efeito medido).

---

## 5.6 Não bancos que também vão para a via do acionista

A via do acionista não é só de bancos. Uma empresa não financeira cujo
resultado operacional é negativo em mais de 40% dos anos (Porta 3) também vai
para ela: o NOPAT não sustenta uma projeção, mas o lucro líquido pode sustentar
(uma holding com resultado de participações, por exemplo). Diferente do banco,
ela **tem** dívida de estrutura de capital, e por isso o motor recalcula o Ke
ano a ano com a alavancagem projetada, como faz na via da firma (decisão 46).
Em 14/09/2026 era um único caso entre os 97 avaliados.

---

## 5.7 O que muda no resultado de um banco

- **O desconto é mais alto.** Sem o custo mais baixo da dívida para diluir, a
  taxa é o próprio Ke: no Itaú, 19,0% no ano 1, contra um WACC de 18,1% na WEG.
- **O retorno raramente supera o custo.** Com Ke perto de 19–20%, um ROE de 18%
  (a mediana do Itaú) fica abaixo do custo. Na conta do motor, crescer não cria
  valor para esse banco, e a vantagem competitiva residual é barrada ("sem
  excedente").
- **Com retorno abaixo do custo, mais crescimento vale menos.** Em 10 dos 19
  bancos e financeiras avaliados em 14/09/2026, o cenário "só crescimento +3
  pontos" dá um preço justo **menor** (item B38).

## Para estudar mais

- **Damodaran, *Valuation***, capítulo sobre "Valuing financial service firms"
  — a referência para avaliar banco pelo fluxo do acionista e pelo ROE.
- **Koller et al. (McKinsey), *Valuation***, capítulo "Banks".
- **Banco Central do Brasil**, "Relatório de Estabilidade Financeira" — explica
  capital regulatório e Basileia.

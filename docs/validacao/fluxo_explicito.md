# O nível do fluxo explícito

Auditado em 10/09/2026, sobre os 122 ativos que a cascata avalia.

```bash
dart run tool/fluxo_explicito.dart   # grava fluxo_explicito.json
```

---

## 0. A pergunta

O [DCF reverso](dcf_reverso.md) mediu que, depois de o terminal e a taxa de
desconto saírem como explicação, sobra um multiplicador mediano de **1,74×**
entre o fluxo que o motor desconta e o que o preço de mercado capitaliza.
Nenhuma instrumentação isolava esse resíduo, e o suspeito nomeado — o freio de
reinvestimento — era hipótese.

---

## 1. Desenho

O valor por unidade de fluxo-base é homogêneo de grau 1, então o efeito de
qualquer premissa sobre o valor da firma é um multiplicador `m` independente da
escala do ativo. Para cada contrafactual mede-se `m` contra o `m` **necessário**
para alcançar o preço:

```
EV por papel   = justo / s                s = participação do capital próprio
m necessário   = 1 + s · (preço/justo − 1)
fração fechada = (m_contrafactual − 1) / (m_necessário − 1)
```

**A projeção contrafactual é escrita no utilitário e conferida contra a
produção antes de ser usada.** Dois dos quatro contrafactuais mexem na forma da
retenção, não em um campo de `DcfAssumptions`, e para esses não há alternativa
a um laço próprio. O laço só vale se reproduzir a cascata no caso base:

| conferência contra `DcfCalculator` | mediana | máximo |
|---|---:|---:|
| erro relativo, 122 ativos | **0,0** | **0,0** |

Zero exato, não "dentro da tolerância" — o laço percorre a mesma aritmética na
mesma ordem.

---

## 2. O que o freio custa

| | ano 1 | ano N |
|---|---:|---:|
| retenção mediana | **47,8%** | 50,5% |

**Vinte dos 122 estão no teto de 95% já no primeiro ano**, e 30 acima de 80%.
No teto, 95% do lucro operacional é retido e 5% chega ao fluxo.

A causa é aritmética: `b = g/ROIC`, e o **ROIC da base tem mediana de 11,2%**,
com **30 dos 122 abaixo do crescimento nominal da economia de 6,86%**. Uma
empresa que rende 6% ao ano não financia crescimento de 6,86% sem consumir
tudo. O freio não está errado — está dizendo isso.

---

## 3. Os contrafactuais

Medidos antes da correção, contra o multiplicador necessário mediano de 1,74×:

| Contrafactual | `m` | fecha do vão | fecha tudo em |
|---|---:|---:|---:|
| freio desligado | 1,43× | 29,7% | 33 de 122 |
| freio só no crescimento **real** | 1,33× | 22,4% | 26 de 122 |
| sem convergência do ROIC | 0,96× | **−4,8%** | 2 de 122 |
| **alíquota efetiva** | **1,18×** | **13,3%** | 19 de 122 |
| alíquota + crescimento real | 1,55× | 51,1% | 44 de 122 |

Nenhum fecha sozinho. E os quatro não têm o mesmo estatuto:

**O freio não é defeito.** `b = g/ROIC` é a identidade que diz quanto capital
novo um crescimento exige, e desligá-lo reintroduz exatamente o que a
[decisão 25](../decisoes/025-reconstrucao-do-motor-de-avaliacao.md) corrigiu:
fluxo crescendo sem nada retido para financiá-lo. Cobrar só o crescimento
**real** é defensável — crescer ao lado da inflação pede reposição a preço
maior, não investimento líquido — mas a depreciação a custo histórico que já
está dentro do NOPAT subestima a reposição, e cobrar o nominal é a leitura
conservadora dessa ambiguidade. **É escolha de método, e mudá-la para fechar o
vão seria ajustar o motor ao mercado**, que a
[decisão 35](../decisoes/035-dcf-reverso-e-regressao-condicional.md) veda.

**A convergência do ROIC ajuda o valor**, e desligá-la o piora em 4%. Ela não
é candidata a nada.

**A alíquota é defeito.** É o único dos quatro em que o motor usa um número
que não é o da empresa.

---

## 4. A alíquota: o defeito

A fonte publica `NOPAT = EBIT × 0,66` — a alíquota estatutária brasileira
aplicada a **toda** empresa, em 4.572 de 4.572 exercícios do cache. Medido:

| | valor |
|---|---:|
| alíquota efetiva mediana do universo | **22,1%** |
| p10 / p25 / p75 / p90 | 9,4% / 14,5% / 26,5% / 32,0% |
| abaixo da estatutária | **112 de 122** |
| acima da estatutária | 10 |

JCP, incentivo regional, lucro presumido e prejuízo fiscal compensado não são
exceção no Brasil.

### É regime, não evento — e isso foi medido

O que separa incentivo estrutural de um ano atípico é a **estabilidade dentro
da empresa**:

| | valor |
|---|---:|
| dispersão robusta da alíquota dentro da empresa | **7,5 p.p.** |
| exercícios por empresa | 15 (mediana) |
| estáveis abaixo de 10 p.p. de dispersão | **82 de 120** |

Uma alíquota baixa que se repete por quinze exercícios é regime tributário. É o
que autoriza projetá-la, e é por isso que a estrutural é a **mediana** dos
exercícios e não a do último: prejuízo fiscal compensado num ano move a
alíquota daquele ano e não a mediana de quinze.

---

## 5. A correção, e o que ela move

Implementada pela [decisão 37](../decisoes/037-aliquota-estrutural-no-fluxo-da-firma.md).

**A alíquota entra na série e no fluxo-base ao mesmo tempo.** Mudar só o fluxo
deixaria o ROIC na convenção antiga, e o freio `b = g/ROIC` passaria a cobrar
reinvestimento de um retorno que não é o do fluxo descontado — o mesmo defeito
que a [decisão 31](../decisoes/031-escala-do-preco-tributo-e-invariancia-das-guardas.md)
mediu em 17% na AZZA3. Por isso o efeito **compõe**: NOPAT maior sobre a mesma
base de capital é ROIC maior, ROIC maior é retenção menor, e retenção menor é
fluxo maior de novo.

**O escudo fiscal do WACC continua na estatutária**, e deve continuar: a
dedutibilidade do juro vale na margem, e a margem é a alíquota cheia. As duas
alíquotas medem coisas diferentes e só coincidiam por acidente da fonte.

### O efeito medido

| | antes | depois |
|---|---:|---:|
| multiplicador necessário, mediana | 1,74× | **1,53×** |
| multiplicador necessário, p25 | 1,14× | **1,01×** |
| potencial mediano | −45,7% | **−42,3%** |
| potencial p75 | −19,6% | **−0,9%** |
| potenciais positivos | 15 | **28** |
| preços justos alterados além de 0,5% | — | **80 de 122** |
| variação mediana do preço justo | — | **+16,2%** |

O quartil superior da distribuição praticamente encostou no zero, e o número de
ativos que o motor considera baratos quase dobrou. **O vão não fechou** — a
mediana continua a −42,3%, e restam 1,53× de multiplicador a explicar.

---

## 6. O que a correção revelou, e é um segundo defeito

Nove ativos **caíram** mais de 5%, alguns brutalmente: VBBR3 de R$ 33,71 para
R$ 2,65, PRIO3 de R$ 53,88 para R$ 7,46. Um imposto menor não pode reduzir
valor.

**Os nove são troca de via, e são todos os que caíram.** Dez ativos mudaram de
via, todos de `dcfEarnings` para `dcfFcff`:

| Ativo | justo antes | justo depois | variação |
|---|---:|---:|---:|
| VBBR3 | 33,71 | 2,65 | **−92,1%** |
| PRIO3 | 53,88 | 7,46 | −86,2% |
| AGRO3 | 8,99 | 1,72 | −80,9% |
| SBFG3 | 6,14 | 1,51 | −75,4% |
| MULT3 | 6,25 | 2,19 | −65,0% |
| KLBN3 | 1,33 | 0,52 | −60,9% |
| HYPE3 | 10,32 | 4,08 | −60,5% |
| KLBN4 | 1,29 | 0,52 | −59,7% |
| KLBN11 | 6,71 | 2,76 | −58,9% |
| YDUQ3 | 2,44 | 5,57 | +128,3% |

O mecanismo: o NOPAT maior eleva o valor da firma, a participação do capital
próprio cruza os 20% da pós-condição da
[decisão 34](../decisoes/034-fronteira-das-vias-medida-na-taxa-estrutural.md), a
migração deixa de disparar, e o ativo **fica** na via da firma — que para ele
devolve muito menos.

**A correção não criou isso: ela o expôs.** Antes, esses nove estavam na via do
acionista porque o valor da firma estava artificialmente deprimido por uma
alíquota que não era a deles. Com a alíquota certa, a participação está
genuinamente acima de 20% e a regra da decisão 34 os manda para a via da firma.
O que aparece é a **discordância entre as duas vias**, que a própria decisão 34
registrou como assunto de outra decisão: na VBBR3 elas diferem por 12,7×.

### A superfície exposta

| Participação do capital próprio | Ativos na via da firma |
|---|---:|
| entre 20% e 25% | 3 |
| entre 25% e 35% | 4 |
| entre 35% e 50% | 15 |
| abaixo de 20% (migraram) | 36 |

**Treze ativos estão a menos de 10 p.p. acima do corte** — AGRO3, HYPE3,
KLBN11, KLBN3, KLBN4, MOTV3, MULT3, MYPK3, PRIO3, QUAL3, SBFG3, VBBR3 e
YDUQ3 —, e para eles um limiar decide entre dois números que diferem por
múltiplos.

É defeito da mesma família dos dois já removidos: o degrau da vantagem
competitiva ([decisão 36](../decisoes/036-decaimento-medido-do-excedente-na-perpetuidade.md))
e a travessia induzida pelo ciclo monetário (decisão 34). **Não é corrigido
aqui**, porque conciliar as duas vias é mudança de método com decisão própria,
e bundlá-la nesta esconderia qual das duas produziu qual efeito.

---

## 7. O que fica em aberto

1. **A discordância entre as vias é a pendência de maior efeito medido.**
   Treze ativos na faixa de exposição, e um deles com fator de 12,7× entre as
   duas rotas.
2. **Restam 1,53× de multiplicador.** O freio explica boa parte e é método, não
   defeito. O que sobra depois dele não tem candidato nomeado.
3. ~~**A alíquota efetiva usa `|despesa| ÷ lucro antes`.**~~ **Fechado na §8**,
   e por um caminho diferente do esperado: a fonte grava a despesa com sinal
   negativo, e a correção é negar em vez de modular.
4. **O teto de retenção em 95% cria uma região hipersensível.** Dos vinte
   ativos nele, quinze continuam nele depois da correção; nos que saíram, o
   preço justo se move muito com pouca variação de ROIC.

---

## 8. O sinal da despesa tributária, e um achado do conselheiro que estava meio certo

A §7.3 registrava como limitação aberta que `effectiveTaxRate` usava
`|despesa| ÷ lucro antes`, transformando crédito tributário em alíquota
positiva. A lente `nucleo` do conselheiro apontou o mesmo, e propôs remover o
`.abs()` deixando o `clamp(0, 0,5)` conter o negativo.

**A proposta foi implementada, medida e desfeita: ela piorava tudo.** Com o
`.abs()` fora, a alíquota mediana do universo foi a **0,0%** e 98 dos 122
preços justos se moveram.

A causa está na convenção da fonte, que ninguém tinha conferido. **A brapi
grava a despesa tributária com sinal negativo**, e a identidade contábil no
cache prova:

| AALR3 | lucro antes | `incomeTaxExpense` | lucro líquido |
|---|---:|---:|---:|
| exercício normal | 34.619 | **−5.852** | 28.767 |
| exercício de crédito | −7.923 | **+22.563** | 14.640 |

`lucro líquido = lucro antes + incomeTaxExpense` nos dois. A despesa **soma**,
e um campo positivo é **crédito**.

Ou seja: o `.abs()` acertava o caso comum pelo motivo errado, e o conselheiro
acertou o sintoma pelo diagnóstico errado. Remover o módulo sem negar o sinal
inverteria o universo inteiro.

**A correção é negar, não modular:** `alíquota = −despesa ÷ lucro antes`,
confinada em `[0; 0,5]`. O caso comum sai idêntico; o crédito produz razão
negativa e o piso de zero faz o que sempre prometeu.

### O efeito

| | antes | depois |
|---|---:|---:|
| alíquota estrutural mediana | 22,1% | **18,9%** |
| potencial mediano | −40,0% | **−38,6%** |
| potenciais positivos | 28 | **30** |
| preços justos alterados além de 0,5% | — | **33 de 122** |

As maiores altas são de quem tinha exercícios de crédito contados como imposto
pago: BEEF3 +63,0% (alíquota de 18,7% para 0,0%), RANI3 +30,4%, ANIM3 +30,3%.

**Três testes passavam por causa do erro.** Dois fixtures do núcleo e um da
interface gravavam a despesa positiva, e `effectiveTaxRate` tirava o módulo —
os dois erros se cancelavam, e o cancelamento escondia o tratamento do crédito.
Corrigidos os fixtures, a identidade contábil deles passou a fechar.

**A limitação da §7.3 está fechada.**

---

## 9. D4 — o resíduo, remedido pela cascata (10/09/2026)

### 9.1 O arnês não media o motor

Os contrafactuais das §§2 e 3 rodavam num laço próprio, escrito neste
utilitário para replicar `DcfCalculator._project`. A conferência que o
acompanhava — `erroConferencia` — comparava esse laço contra
`DcfCalculator.firm` **com as mesmas premissas**, e por isso só provava que o
laço somava certo. Ela não podia ver o que estava errado:

| | o laço usava | a cascata usa |
|---|---|---|
| crescimento perpétuo | o teto da economia, **em 78 dos 120** | `min(g, teto)` |
| taxa de desconto | reinterpolação de dois pontos | o **caminho resolvido** (decisão 41) |
| rota do capital próprio | ponte `EV − D` | a **rota derivada** (decisão 43) |

Três motores de diferença. O número que a §3 publicou — 1,74× de multiplicador
mediano, e as frações fechadas por cada contrafactual — media um motor que já
não existia.

**A correção é estrutural: o contrafactual passa a ser imposto à cascata.**
`ValuationInputs` ganhou `reinvestmentOverride` e `cashTimingOverride`,
declarados como as outras costuras de diagnóstico, e o utilitário deixou de ter
projeção própria. O que ele mede agora atravessa as duas vias, a rota derivada
e o ponto fixo.

**A medida também mudou de unidade, e ficou mais simples.** Antes o vão era
convertido em multiplicador do valor da **firma** por `m = 1 + s·(preço/justo −
1)`, o que trazia a amplificação `1/s` para dentro da própria medida. Agora é
`preço ÷ justo`: quanto o preço justo teria de subir.

### 9.2 O vão, agora

| | valor |
|---|---:|
| p25 | 0,92× |
| **mediana** | **1,42×** |
| p75 | 2,97× |
| já acima do preço de mercado | **36 de 120** |
| mediana **entre os 84 com vão** | 2,19× |

**Trinta e seis dos 120 já não têm vão a fechar.** Medir a mediana com eles
dentro elogia qualquer contrafactual, e por isso os contrafactuais abaixo são
medidos só nos 84 restantes.

### 9.3 Os contrafactuais, pela cascata real

| Contrafactual | `m` | fecha do vão | fecha tudo em |
|---|---:|---:|---:|
| freio desligado | 1,50× | 30,5% | 23 de 84 |
| freio só no crescimento **real** | 1,43× | 27,7% | 22 de 84 |
| sem convergência do ROIC | 0,96× | **−3,1%** | 2 de 84 |
| freio sem o teto de 95% | **1,00×** | **0,0%** | 0 de 84 |

Os dois primeiros continuam com o estatuto que a §3 lhes deu: **escolha de
método, não defeito**. `b = g/ROIC` é a identidade que diz quanto capital novo
um crescimento exige, e afrouxá-la para fechar o vão seria ajustar o motor ao
mercado, que a [decisão 35](../decisoes/035-dcf-reverso-e-regressao-condicional.md)
veda.

O terceiro segue ajudando o valor. **O quarto é novo, e o resultado dele é o
achado do D4.**

---

## 10. O teto de retenção não segurava nada — o crescimento é que não era financiável

Desligar o teto de 95% move **zero** ativos. Isso parece dizer que o teto não
faz nada, e diz o contrário: ele fazia demais, e no lugar errado.

A conta do freio é `b_t = g_t / ROIC_t`, confinada em `[0; 0,95]`. Quando
`g > 0,95·ROIC`, o confinamento corta a **retenção** — e o crescimento
continua inteiro. O resultado é um fluxo que:

- **cresce** à taxa cheia, exercício após exercício;
- **paga** por esse crescimento só 95% do lucro, porque o resto foi truncado.

Os 5% que sobram viram caixa distribuível de uma expansão que ninguém
financiou. Medido em 10/09/2026: **14 dos 116 ativos com retorno utilizável
tinham `g > ROIC`, e os 14 estavam no teto.** Na MOVI3, crescimento de 31,8%
sobre retorno de 13,4%; na FESA4 o freio pedia 6,8 vezes o lucro operacional
antes de ser truncado.

**A correção é aplicar a identidade na premissa, e não na consequência.**
`g = b·ROIC` com `b ≤ 0,95` significa `g ≤ 0,95·ROIC`: o crescimento projetado
passa a ser confinado ao que o próprio retorno financia, ano a ano, e o mesmo
confinamento vale para o crescimento perpétuo contra o retorno terminal.

Feito isso, o teto da retenção deixa de ser alcançável por truncamento: os 15
ativos que ainda aparecem em `b = 0,95` estão lá porque o **crescimento** foi
cortado até exatamente ali, e removê-lo não muda nada — que é o `m = 1,00×` da
tabela acima.

| | antes | depois |
|---|---:|---:|
| retenção mediana no ano N | 51,0% | **38,9%** |
| ativos que perdem valor sem o teto | — | **0** |

---

## 11. O caixa não chega no dia 31 de dezembro

Descontar o fluxo inteiro de um exercício no último dia dele cobra doze meses
de espera por dinheiro que, em média, chegou no sexto. O erro é **sistemático,
sempre na mesma direção, e incide sobre a avaliação inteira** — período
explícito e perpetuidade.

A correção é a convenção de meio de ano: cada fluxo é levantado por
`√(1 + r_t)`, à taxa do próprio ano, e o valor terminal pela taxa de
equilíbrio que o capitaliza.

| | valor |
|---|---:|
| justo(fim de ano) ÷ justo(produção), p10 | 0,87× |
| **mediana** | **0,92×** |
| p90 | 0,94× |
| levantamento p10 / mediana / p90 | +6,6% / **+8,2%** / +15,0% |

A dispersão é a dispersão das taxas: quem desconta a 18% ganha mais do que quem
desconta a 9%, porque meio ano vale mais quando o dinheiro é mais caro.

**Não é ajuste ao mercado.** A direção é conhecida antes de medir — o meio de
ano sempre levanta —, e o tamanho sai da taxa de desconto, não do vão a fechar.
Se fechasse o vão inteiro seria suspeito; fecha um oitavo dele.

**O ponto fixo teve de acompanhar.** `LeveredCostOfCapital` reconstrói o valor
ano a ano por acumulação regressiva para conhecer `D/E`, e essa reconstrução
estava na convenção de fim de ano. Como a dívida **não** é levantada, `D/E`
sairia inflado e o `Ke` com ele. A acumulação passou a seguir a convenção, e a
invariante — o valor que alimenta a alavancagem é o mesmo que sai no preço —
está travada por teste nas duas convenções.

---

## 12. O efeito do bloco no universo

| | pós-decisão 45 | agora |
|---|---:|---:|
| potencial mediano | −36,1% | **−30,3%** |
| potencial p25 | −66,5% | −66,4% |
| **potencial p75** | −0,5% | **+8,2%** |
| potenciais positivos | 30 | **36** |

**O quartil superior deixou de tangenciar o zero e passou a +8,2%.**

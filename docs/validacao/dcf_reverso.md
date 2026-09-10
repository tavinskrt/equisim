# DCF reverso e regressão condicional

Executado em 09/09/2026, sobre os 376 papéis que a fonte devolveu, dos quais
**122 são avaliados** pela cascata.

Reproduz-se com:

```bash
dart run tool/dcf_reverso.dart            # grava dcf_reverso.json
dart run tool/regressao_condicional.dart  # grava regressao_condicional.json
```

O segundo **não vai à rede**: lê o `backtest_valuation.json` que a
[validação preditiva](validacao_preditiva.md) já produziu.

---

## 0. Por que estas duas medições, e por que antes de qualquer conserto

O motor tem dois fatos incômodos medidos e nenhuma explicação medida para
nenhum dos dois:

1. **Viés de nível.** O potencial mediano está em −45,7% nesta execução. A
   cascata afirma que o mercado inteiro está caro.
2. **Redundância possível.** O coeficiente de informação do potencial em 36
   meses é 0,170, contra 0,213 do valor patrimonial sobre preço. O motor
   ordena, e não supera dois fatores de uma linha.

Para o primeiro havia três hipóteses, cada uma com um conserto de semanas:
o **terminal neutro**, a **taxa de desconto** e as **saturações
conservadoras**. Escolher errado custa o mesmo que escolher certo.

Pior que isso: **o conserto do terminal fecharia o vão independentemente da
causa verdadeira.** Um retorno terminal livre tem graus de liberdade de sobra
para absorver um erro de taxa, e o resultado pareceria correto por fora. É a
definição de modelo mal especificado que ajusta bem — e é o que esta medição
existe para impedir.

Para o segundo, correlação isolada não decide nada: três ordenadores
correlacionados entre si podem ter o mesmo IC e conteúdo idêntico.

---

## 1. Desenho do DCF reverso

Para cada ativo avaliado, a cascata **inteira** é varrida em três eixos, um de
cada vez, procurando o valor que iguala o preço justo ao preço de mercado.
Varrer a cascata e não o desconto é deliberado: o roteamento, as guardas, a
saturação e a pós-condição da ponte continuam no lugar, e reimplementar o
fluxo descontado no utilitário mediria outro motor.

| Eixo | O que se varia | Faixa |
|---|---|---|
| `RONIC_∞` | retorno terminal, no lugar do veredito de vantagem competitiva | 0,5% a 200%, log-espaçado, 61 pontos |
| Prêmio de risco | `marketPremium` do CAPM, que viaja para as duas taxas | 0 a 25%, 51 pontos |
| Nível da curva | deslocamento **paralelo** da taxa livre de risco corrente e da de equilíbrio | −13 a +5 p.p., 73 pontos |

O quarto eixo — o **fluxo-base** — sai por identidade em vez de varredura. O
DCF é homogêneo de grau 1 no fluxo, de modo que o multiplicador necessário é
`preço ÷ justo` na via do acionista e, na via da firma, o que a ponte impõe:

```
D por papel = justo · (1 − s)/s          s = participação do capital próprio
k           = (preço + D/N) ÷ (justo + D/N)
```

### Por que o eixo da taxa livre de risco precisou existir

A varredura do prêmio **não mede o nível do custo de capital**, e isso não
estava óbvio antes de rodar. `CostOfCapital.wacc` não deixa o WACC cair abaixo
da própria taxa livre de risco: zerar o prêmio leva o desconto ao CDI e para
ali. Uma varredura só no prêmio não distingue "o prêmio está alto" de "a taxa
livre de risco está alta" — ela esbarra no piso e devolve *inatingível* nos
dois casos.

Deslocar as duas taxas juntas é o que mede o nível. O limite inferior de
−13 p.p. quase zera a taxa de equilíbrio de 9,40%, e é deliberadamente absurdo:
o interesse é saber **se existe** taxa que alcance o preço, não propor uma.

### Grade antes de bissecção, e por quê

Bissecar pressupõe monotonia. A cascata tem migração de via, saturação de
fator e piso de WACC, e qualquer um pode produzir degrau. A grade **mede** a
monotonia em vez de supô-la, e um ativo com mais de um cruzamento é declarado
como tal em vez de receber a primeira raiz encontrada. A bissecção só roda
dentro de um intervalo que já se sabe único.

---

## 2. O resultado do DCF reverso

### 2.1 Quantos ativos cada eixo alcança

| Eixo | raiz única | múltiplas raízes | **inatingível** | já acima do preço |
|---|---:|---:|---:|---:|
| `RONIC_∞` | 45 | 2 | **73** | 2 |
| Prêmio de risco | 46 | 3 | **72** | 1 |
| **Nível da curva** | **99** | 5 | **16** | 2 |

*Inatingível* quer dizer que em nenhum ponto da grade o preço justo alcança o
preço de mercado. No eixo do `RONIC_∞` isso é forte: **nem retorno terminal de
200% ao ano perpétuo** basta para 73 dos 122.

### 2.2 A assimetria que decide

```
ativos em que a TAXA resolve e o TERMINAL é inatingível:   56
ativos em que o TERMINAL resolve e a TAXA é inatingível:    0
```

Não há **um único** ativo cujo vão o terminal explique e a taxa não. A
dominância é estrita, e é a evidência mais limpa da medição inteira.

### 2.3 O terminal não é o culpado — nem a normalização

| Hipótese | Veredito | Medida |
|---|---|---|
| Terminal neutro | **rejeitada** | inatingível em 73 de 122; explicação exclusiva em 0 |
| Saturações da base | **rejeitada** | fator de normalização aplicado tem **mediana 1,00** e fica abaixo de 1 em apenas 27 de 122 |
| Taxa de desconto | **implicada, e insuficiente** | ver 2.4 |

Onde o `RONIC_∞` implícito existe, ele fica em **16,5%** na mediana — 1,32× o
ROIC que a empresa entregou na mediana do ciclo, e acima do ciclo em 29 dos 41
casos comparáveis. Não é absurdo, e é exatamente o que a exceção de vantagem
competitiva já concede a sete ativos. **Mas alcança pouco mais de um terço do
universo.**

### 2.4 A taxa alcança o preço, mas a taxa que ela pede não é uma taxa

O eixo da curva resolve 99 dos 122. O deslocamento mediano é de **−3,4 p.p.**,
e a taxa de equilíbrio implícita fica em **5,98%** contra os 9,40% medidos.

É aqui que a leitura vira:

| Taxa de equilíbrio implícita | Ativos |
|---|---:|
| abaixo do crescimento nominal da economia (6,86%) | **63 de 99** |
| abaixo da âncora de inflação (5,00%) | **44 de 99** |

Uma taxa livre de risco nominal abaixo da inflação esperada é uma taxa real
negativa, e uma taxa livre de risco abaixo do crescimento nominal da economia
faz o valor presente de uma perpetuidade crescente divergir. **Não são taxas
brasileiras, e não são taxas.** O que a medição sustenta é que o desconto do
motor está alto na direção certa — o CDI corrente de 14,09% é um *overnight*
em pico de ciclo, e a taxa de equilíbrio de 9,40% é média histórica, não curva
observada. O que ela **não** sustenta é que trocar a curva feche o vão.

### 2.5 O que sobra fica no fluxo-base

O multiplicador necessário do fluxo, por identidade:

| p25 | mediana | p75 |
|---:|---:|---:|
| 1,14× | **1,64×** | 2,89× |

Acima de 1 em 107 dos 122. O fator de normalização que o motor **aplicou** tem
mediana 1,00 — de modo que o vão não vem de a base ter sido reduzida, e sim de
o fluxo que a base produz ser menor do que o preço capitaliza.

Dezesseis ativos são **inatingíveis nos três eixos** ao mesmo tempo:

> ALPA4, AXIA3, B3SA3, BRAP4, EMBJ3, FESA4, MDNE3, MULT3, RAIL3, RENT4, SAUD3,
> SBSP3, SMFT3, TEND3, TOTS3, UGPA3

Neles o multiplicador vai de 2,55× (FESA4) a 14,09× (EMBJ3), e o peso do
terminal é **baixo** — 0,18 na B3SA3, 0,23 na RAIL3 e na MDNE3. Peso terminal
baixo com vão grande é a assinatura de fluxo explícito insuficiente, não de
perpetuidade mal montada.

O suspeito com mais superfície é o **freio de reinvestimento**: o fluxo
explícito é `NOPAT × (1 − g/ROIC)`, e com `g` convergindo para a âncora e
`ROIC` do fluxo-base, a retenção consome metade ou mais do lucro operacional
em boa parte do universo. O terminal não paga esse pedágio — `VT = NOPAT/WACC`
é o lucro inteiro. A [decisão 31](../decisoes/031-escala-do-preco-tributo-e-invariancia-das-guardas.md)
já havia medido 17% de diferença na AZZA3 por casar `g` de uma série com
`ROIC` de outra. **Isto é hipótese, não medição:** nenhuma instrumentação
atual isola o nível do fluxo explícito, e construí-la é trabalho novo.

### 2.6 Um achado colateral: a não monotonia sobreviveu

| Eixo | ativos não monótonos |
|---|---:|
| `RONIC_∞` | 38 de 122 |
| Prêmio | 40 de 122 |
| Nível da curva | **46 de 122** |

A [decisão 34](../decisoes/034-fronteira-das-vias-medida-na-taxa-estrutural.md)
removeu a travessia de via induzida pelo ciclo monetário medindo a
participação na taxa **estrutural**. Ela resolveu o caso que motivou a
decisão — mover só a taxa corrente —, e **não** o caso geral: deslocar as duas
taxas juntas move também a participação estrutural, e a fronteira volta a ser
cruzada. Em 46 dos 122 o preço justo não é monótono no nível da curva.

Isso não invalida as raízes desta seção — elas saem de intervalos com
cruzamento único, e os múltiplos estão declarados. É pendência registrada, não
corrigida aqui.

---

## 3. A regressão condicional

### 3.1 Desenho

Fama-MacBeth em dois passos, sobre as mesmas coortes da validação preditiva.
Em cada coorte, regressão transversal do retorno realizado nos três
ordenadores; depois, a média dos coeficientes entre coortes, com o `t` do
segundo passo. Tudo em **postos padronizados** — o potencial tem cauda
pesadíssima e regressão de nível sobre ele mediria o extremo, não a relação.

A **IC incremental** é a mesma pergunta por outro caminho: retira-se do
potencial o que o P/B e o L/P explicam, e mede-se a correlação de ordem do
resíduo com o retorno. É o sinal que sobra depois de pagar o que já estava
disponível de graça.

Só coortes com 30 ou mais ativos entram: abaixo disso três regressores em
postos têm erro-padrão maior que o coeficiente por construção.

### 3.2 O resultado em 36 meses

| Coorte | n | IC pot. | IC P/B | IC L/P | coef. pot. condicional | t | IC increm. |
|---|---:|---:|---:|---:|---:|---:|---:|
| 2018 | 70 | 0,168 | 0,135 | 0,161 | 0,113 | 0,46 | 0,033 |
| 2019 | 81 | 0,164 | 0,288 | 0,332 | −0,224 | −1,31 | −0,083 |
| 2020 | 90 | 0,365 | 0,203 | 0,347 | 0,243 | 1,45 | 0,185 |
| 2021 | 108 | 0,149 | 0,250 | 0,168 | 0,043 | 0,32 | 0,022 |
| 2022 | 113 | 0,006 | 0,188 | −0,078 | 0,032 | 0,25 | −0,003 |

Segundo passo:

| Grandeza | média | IC 95% | t | positivas |
|---|---:|---|---:|---:|
| IC do potencial, sozinho | **0,170** | [+0,012; +0,329] | 2,98 | 5/5 |
| IC do P/B | 0,213 | [+0,140; +0,286] | 8,12 | 5/5 |
| IC do L/P | 0,186 | [−0,028; +0,399] | 2,42 | 4/5 |
| **coef. do potencial COM P/B e L/P** | **0,041** | [−0,170; +0,253] | 0,54 | 4/5 |
| coef. do P/B com os outros | 0,145 | [−0,075; +0,365] | 1,83 | 4/5 |
| **IC incremental do potencial** | **0,031** | [−0,090; +0,152] | 0,71 | 3/5 |

**O coeficiente do potencial cai de 0,170 para 0,041 quando o P/B e o L/P
entram na mesma regressão.** A informação que a cascata traz em 36 meses é, em
sua quase totalidade, informação que dois fatores de uma linha já traziam.

O intervalo de 95% da IC incremental, [−0,090; +0,152], **contém zero
folgadamente e exclui o 0,170 do IC bruto**. É o que a amostra permite afirmar:
não que a contribuição própria seja nula, e sim que ela não é a que o IC bruto
sugeria.

### 3.3 Em 12 meses o quadro se inverte, e é curioso

| Grandeza | média | t | positivas |
|---|---:|---:|---:|
| IC do potencial, sozinho | 0,098 | 1,44 | 5/7 |
| coef. do potencial COM P/B e L/P | **0,100** | 1,16 | 5/7 |
| IC incremental | 0,049 | 0,90 | 5/7 |

Em doze meses o coeficiente **não cai** ao entrar com os outros: 0,098 sozinho
contra 0,100 acompanhado. O que o potencial vê em doze meses é ortogonal ao
que o P/B vê — só que é pouco, e o `t` não sustenta afirmação.

A leitura que isso sugere, e que não foi testada: em horizonte longo a cascata
converge para o mesmo que o valor patrimonial mede, porque é disso que o preço
justo é feito; em horizonte curto ela se separa, e ali não tem força. É
hipótese.

### 3.4 A leitura pela série ajustada concorda

Sobre `adjustedClose` — leitura secundária, pela [§1.2](limitacoes.md#12-adjustedclose-diverge-de-forma-material) —
o IC bruto do potencial sobe para 0,191 e o condicional cai para **0,013**. A
conclusão não muda de sinal nem de tamanho.

### 3.5 O que limita esta medição

**Cinco coortes anuais de 36 meses não são cinco observações independentes.**
As janelas se sobrepõem em dois terços, e o `t` do segundo passo superestima a
confiança. Isso vale para os três ordenadores igualmente — inclusive para o
0,213 do P/B.

**A potência é baixa.** Um teste que não rejeita com cinco observações não
prova ausência. O que ele estabelece é que a contribuição própria da cascata
**não é detectável neste tamanho de amostra**, e que o ponto estimado é 0,031
contra um bruto de 0,170.

**Os três vieses da §5 da [validação preditiva](validacao_preditiva.md)
continuam de pé** — sobrevivência, reapresentação e provento — e nenhum deles
foi removido aqui.

---

## 4. O que estas duas medições autorizam decidir

**Autorizam:**

- Descartar o terminal neutro como explicação do viés de nível. Ele é
  inatingível em 73 dos 122 e explicação exclusiva em nenhum. Trocar o degrau
  de vantagem competitiva por decaimento contínuo continua defensável por
  teoria — **não** é o conserto do nível, e não deve ser vendido como tal.
- Descartar a normalização da base como explicação. Mediana de 1,00.
- Implicar o nível da curva de desconto, com ressalva: é o único eixo com
  tração, e ainda assim pede uma taxa de equilíbrio abaixo da inflação em 44
  dos 99 casos que resolve.
- Afirmar que o resíduo mora no **fluxo-base**, e que nenhuma instrumentação
  atual o isola.
- Afirmar que a ordenação da cascata em 36 meses **não sobrevive** ao controle
  por P/B e L/P.

**Não autorizam:**

- Dizer que o motor está errado. Um preço justo abaixo do preço de mercado
  pode ser discordância legítima, e nada aqui arbitra quem tem razão. O que a
  medição mostra é que a discordância é grande demais para caber em qualquer
  premissa isolada.
- Dizer que a cascata não tem informação própria. Diz-se que ela não é
  detectável em cinco coortes sobrepostas.
- Calibrar qualquer parâmetro para fechar o vão. Ajustar o motor até a mediana
  do potencial ir a zero é ajustá-lo ao mercado, e destrói justamente o sinal
  que a [§2.3 da validação preditiva](validacao_preditiva.md) mediu.

---

## 5. Conferência da estatística

`tool/validation/regression.dart` é implementação nova — regressão múltipla
por equações normais, postos com empate, correlação de ordem, segundo passo de
Fama-MacBeth. Ela é conferida em
[`test/tool/regression_test.dart`](../../test/tool/regression_test.dart)
contra `Inference.ols` do núcleo, que por sua vez está conferido contra o
`statsmodels` na ordem de 1e-14 ([conferencia_inferencia.md](conferencia_inferencia.md)).
No caso de um regressor as duas têm de coincidir em inclinação, intercepto,
erro-padrão e R² — e coincidem dentro de 1e-10, por caminhos diferentes
(fórmula fechada contra inversão de `X'X`).

**O que fica sem conferência externa.** A máquina do projeto não tem `numpy`,
`scipy` nem `statsmodels` instalados — verificado em 09/09/2026. A conferência
cruzada em Python que a [§2.10 das limitações](limitacoes.md#210-as-primitivas-estatísticas-do-núcleo-e-sua-conferência-externa)
descreve **não pôde ser estendida** a este arquivo. O caso multivariado com
três regressores é conferido só por recuperação de coeficientes conhecidos e
por ortogonalidade do resíduo, que são condições necessárias e não suficientes.

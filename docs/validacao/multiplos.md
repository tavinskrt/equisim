# A triangulação por múltiplos de pares — item B5

> **Medido em 21/09/2026**, sobre a entrada congelada do gabarito da cascata.
>
> ```bash
> dart run tool/gabarito_cascata.dart       # congela a entrada
> dart run tool/multiplos_empacotar.dart    # grava o pacote versionado
> dart run tool/multiplos.dart              # grava multiplos.json
> ```
>
> **Preço justo idêntico ao do gabarito em todos os avaliados**: a segunda
> leitura não entra no cálculo. Essa conferência é parte da medição — se o
> gabarito divergisse, a triangulação teria vazado para o preço.
>
> **Remedido depois da [decisão 119](../decisoes/119-a-rota-derivada-tambem-remunera-o-caixa-pela-taxa-livre-de-risco.md)**,
> que estendeu à rota derivada a separação do caixa que a decisão 113 fez no
> WACC. O preço justo caiu em 73 dos 97 e dois ativos saíram.
>
> **Remedido em 24/09/2026**, sobre o motor que fecha a Fase 3 — com o juro da
> rota derivada pela curva (B24) e o prêmio de crédito sem despesa financeira
> (B26), que movem o preço justo, e com a cópia única dos insumos
> ([decisão 132](../decisoes/132-a-copia-dos-insumos-passa-por-um-lugar-so.md)),
> que não o move. A cópia usada pela concessão que acaba dentro da projeção
> perdia os múltiplos de pares, e **quatro concessionárias — EGIE3, EQTL3,
> TAEE11 e TAEE4 — ficavam sem a segunda leitura**; agora as quatro recebem as
> três. Os números abaixo são os de depois; os de 21/09 estão no histórico do
> git deste arquivo.

## 0. O que o item pedia

«Nenhuma avaliação profissional entrega DCF sozinho. Um múltiplo de pares —
EV/EBITDA, P/L, P/VP setorial — dá uma segunda leitura e, principalmente, um
teste de sanidade sobre o nível que hoje só a §2.8 discute em prosa.»

## 1. Como a segunda leitura é montada

**As medianas são do universo, e o núcleo não as calcula.** A cascata avalia um
ativo por vez; a mediana é de todos. Quem mede é `tool/multiplos_empacotar.dart`,
que grava pacote versionado; quem carrega é o aplicativo. É o mesmo arranjo do
prior do beta (decisão 40) e do registro da B3 (decisão 82).

**Do universo congelado saem 362 observações** e 33 grupos com alguma mediana:

| | mercado inteiro | pares |
|---|---:|---:|
| P/L | **8,76×** | 274 |
| P/VP | **1,07×** | 324 |
| EV/EBITDA | **5,65×** | 276 |

Por setor econômico, as mesmas três:

| setor | P/L | P/VP | EV/EBITDA |
|---|---:|---:|---:|
| bens industriais | 9,5× | 1,4× | 5,1× |
| consumo cíclico | 6,1× | 0,9× | 4,5× |
| consumo não cíclico | 11,3× | 0,9× | 5,5× |
| financeiro | 8,6× | 1,0× | — |
| materiais básicos | 13,5× | 0,9× | 6,7× |
| petróleo e gás | 11,4× | 1,6× | 7,1× |
| saúde | 13,8× | 1,1× | 5,2× |
| tecnologia | 17,7× | 0,7× | 9,0× |
| utilidade pública | 8,4× | 1,6× | 6,6× |

**O grupo é escolhido por múltiplo, e na ordem subsetor → setor → mercado.** Um
subsetor pode ter pares bastantes para P/VP e não para EV/EBITDA, e cada mediana
viaja com o grupo que a produziu e com quantos pares entraram.

**Quatro regras de aplicabilidade**, todas declaradas na tela quando mordem:

- prejuízo tira o P/L, e não o inverte — P/L negativo não descreve quanto o
  mercado paga por lucro;
- patrimônio negativo tira o P/VP;
- **instituição financeira não usa EV/EBITDA** — depósito e captação são insumo
  do negócio, não financiamento (decisão 102);
- ponte que deixa o acionista em valor não positivo é recusada.

**E o divisor é o da ponte**, dos dois lados: comparar duas leituras que dividem
por contagens diferentes mediria a ponte, e não o modelo (decisão 83).

## 2. A cobertura

| leituras aplicadas | ativos |
|---:|---:|
| 3 de 3 | **70** |
| 2 de 3 | 24 |
| 1 de 3 | 3 |
| 0 de 3 | 0 |

**Os 97 avaliados recebem alguma leitura.** As recusas são as previstas: 19
instituições financeiras sem EV/EBITDA, 8 prejuízos sem P/L, 3 EBITDA não
positivo.

## 3. O achado: as duas leituras discordam, e muito

| divergência (múltiplos ÷ DCF − 1) | p10 | p25 | mediana | p75 | p90 |
|---|---:|---:|---:|---:|---:|
| | −6,9% | +26,5% | **+73,4%** | +213,0% | +981,3% |

**62 dos 97 passam do limite de 50%**, e **o DCF fica acima dos pares em apenas
14 de 97**.

| | potencial mediano |
|---|---:|
| pelo fluxo descontado | **−45,4%** |
| pelos múltiplos | **−3,2%** |

E a ordenação:

| | |
|---|---:|
| postos entre os dois potenciais | **0,445** |
| mesmo sinal de potencial | 67 de 97 |

Os extremos dos dois lados:

| | DCF | pares | divergência |
|---|---:|---:|---:|
| BBSE3 | R$ 38,24 | R$ 23,13 | −39,5% |
| SEER3 | R$ 16,96 | R$ 12,31 | −27,4% |
| POMO4 | R$ 0,16 | R$ 5,34 | +3.284% |
| EMBJ3 | R$ 0,22 | R$ 34,30 | +15.289% |

## 4. Como ler isso — e o que **não** se pode concluir

**O potencial mediano de −3,2% pelos múltiplos é quase mecânico.** As medianas
saem dos preços de mercado dos pares: uma avaliação relativa tende a devolver o
preço de mercado por construção. **Ela não confirma o nível do mercado**, e
dizer «os múltiplos dão razão ao mercado» seria ler tautologia como evidência.

**O que a medição estabelece, e é o que o item pedia:**

1. **O desacordo de nível do motor não é com o mercado — é com qualquer leitura
   relativa.** O DCF fica 73% abaixo do que os pares implicam na mediana, e
   acima em só 14 de 97. A §2.8 discutia isso em prosa; agora tem número.
2. **O teste de sanidade funciona por ativo.** Os extremos são informativos: a
   EMBJ3 vale R$ 0,22 pelo DCF e R$ 34,30 pelos pares, e o rastro já dizia por
   quê — excedente terminal de **−3.600%** do preço justo, com peso do terminal
   de 1.028%. A divergência não é ruído da triangulação; é a mesma coisa que o
   diagnóstico do terminal já apontava, dita por outro caminho.
3. **As duas ordenações são meio diferentes.** Postos de 0,445, mesmo sinal em
   67 de 97. **O múltiplo relativo é um sinal distinto, e não uma cópia do DCF**
   — o que o torna útil como conferência e o torna candidato a entrar na §0 como
   mais uma ordenação a medir.

**A explicação do desacordo já foi encontrada em outro lugar desta rodada.** A
[decisão 116](../decisoes/116-o-premio-de-mercado-fica-em-5-5-por-cento-por-medicao-das-duas-alternativas.md)
descartou o prêmio de risco: zerá-lo deixa dois terços do desacordo de pé. A
[decisão 112](../decisoes/112-a-rentabilidade-reverte-a-mediana-do-mercado-e-nao-ao-custo-de-capital.md)
mostrou onde ele mora: a rentabilidade das abertas brasileiras vive **abaixo**
do custo de capital delas, e o terminal neutro carrega esse déficit para sempre.
**Os múltiplos não carregam premissa nenhuma sobre perpetuidade** — e é
exatamente por isso que as duas leituras se afastam.

## 5. O que se decidiu

[Decisão 118](../decisoes/118-a-triangulacao-por-multiplos-e-segunda-leitura-declarada-e-nao-entra-no-preco.md):
**a triangulação entra, e não entra no preço.**

- Toda avaliação traz as três leituras, a mediana delas e a divergência.
- **Acima de 50% de divergência, a avaliação declara** — com os múltiplos que
  produziram cada leitura e de quantos pares saíram.
- **Nada é reconciliado.** Escolher uma média entre DCF e múltiplos seria propor
  um terceiro modelo que ninguém validou.

## 6. O que isto não diz

- **Não é modelo de preço.** O produto do motor continua sendo o fluxo
  descontado (decisão 103).
- **Não há medição de habilidade do múltiplo.** Se a ordenação por
  `múltiplos ÷ preço` prevê retorno melhor que o potencial do DCF é pergunta de
  coorte, e depende da base bruta (item C5). **Os postos de 0,445 dizem que vale
  a pena perguntar**, e isso entra como item.
- **As medianas são de uma data só.** O pacote é de 14/09/2026, como os outros
  pacotes versionados; múltiplo setorial se move com o ciclo, e o pacote precisa
  ser regerado junto com os demais.
- **Grupo pequeno vira grupo grande sem avisar na tela.** Quando o subsetor não
  reúne cinco pares, a mediana vem do setor; quando nem ele, do mercado. O grupo
  usado **viaja com a leitura** e aparece na tela, mas quem só olha o número não
  vê que ele é de um grupo mais largo.

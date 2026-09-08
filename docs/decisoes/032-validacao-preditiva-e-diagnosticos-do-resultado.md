---
numero: 32
titulo: Validação preditiva fora da amostra e diagnósticos estruturados no resultado
status: aceita
origem: voce
data: 2026-09-08
citacao: >
  Eu preciso que ele seja um motor de referência com aquelas premissas de
  filtragem de empresas (que foi feita apenas com o intuito de tornar o
  valuation mais preciso), apenas isso. Faça com que ele se torne um motor de
  referência e que sirva como base para tomada de decisão patrimonial.
afeta:
  - packages/equisim_core/lib/src/entities/valuation.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/test/valuation_guards_test.dart
  - lib/presentation/valuation/valuation_page.dart
  - tool/backtest_valuation.dart
  - tool/backfill_macro.dart
  - tool/probe_premium.dart
  - docs/validacao/validacao_preditiva.md
substitui: []
---

## Contexto

Depois da [decisão 31](031-escala-do-preco-tributo-e-invariancia-das-guardas.md)
o motor estava correto e declarava o que não sabia. Faltava a evidência que
separa um motor correto de um motor em que se pode apoiar decisão: **o potencial
que ele apura ordena o retorno que veio depois?**

Até aqui o projeto tinha validação de consistência interna — invariantes,
cobertura, recusa nomeada — e **nenhuma** validação preditiva. A
[decisão 27](027-recalibragem-apos-a-primeira-validacao.md) já havia
desacoplado o retorno esperado da carteira do nível do potencial, admitindo que
o nível não era confiável e que o que se usa é a **ordenação**. Essa ordenação
nunca tinha sido medida contra resultado realizado.

Faltava também outra coisa, e ela é de apresentação: o preço justo saía como um
número só, com a qualidade da estimativa espalhada em texto corrido. Um valor
cujo terminal responde por 85% do total, cuja taxa veio da inflação e cujo
divisor é ambíguo não é o mesmo objeto que um apoiado em crescimento
identificado — e chegavam iguais à tela.

## Decisão

**1. O motor passa a ter validação preditiva declarada, e ela é reproduzível.**

[`tool/backtest_valuation.dart`](../../tool/backtest_valuation.dart) roda a
cascata *point-in-time* em oito coortes anuais de 2018 a 2025 e confronta o
potencial com o retorno realizado em 12 e 36 meses — 36 é o horizonte de
convergência da [decisão 26](026-horizonte-de-convergencia-de-36-meses.md).
O resultado completo está em
[`docs/validacao/validacao_preditiva.md`](../validacao/validacao_preditiva.md).

O que ela mede, em 36 meses e no mesmo subconjunto de ativos:

| Ordenador | IC médio | Coortes positivas |
|---|---:|---:|
| Potencial do motor | **0,170** | **5 de 5** |
| Valor patrimonial sobre preço | 0,213 | 5 de 5 |
| Lucro sobre preço | 0,186 | 4 de 5 |

E os quintis do potencial são **monótonos** — −9,0%, +11,5%, +13,7%, +21,2%,
+40,8% de retorno médio em 36 meses, com 49,8 pontos percentuais entre as
pontas. O valor patrimonial espalha mais (59,7 p.p.) e **não** é monótono: o
quarto quintil dele rende menos que o terceiro, o que o torna utilizável para
separar extremos e não para dosar posição. O lucro sobre preço é monótono e
espalha 59,0 p.p.

**O motor é validado como ordenador de 36 meses, e não como preditor de nível.**
É exatamente o uso que a decisão 27 já lhe dava.

**2. Para que a validação fosse honesta, o histórico macro foi estendido.**
O cache começava em 09/2016, e a janela decenal do CDI numa coorte de 2018 tinha
dois anos. [`tool/backfill_macro.dart`](../../tool/backfill_macro.dart) traz de
2005 as três séries do Banco Central, fatiando a requisição porque o SGS recusa
janela maior que dez anos em série diária.

**3. O resultado passa a carregar `ValuationDiagnostics`** — peso do valor
terminal, participação do capital próprio, fator de normalização, se o
crescimento foi identificado, se a perpetuidade preserva excedente, e a lista
estruturada de ressalvas. Nada disso é novo no cálculo; o que muda é que sai com
o resultado, em forma que a máquina lê e que a carteira pode ponderar.

**4. Não há nota ordinal de confiança, e a ausência é uma medição.**

A primeira versão destes diagnósticos trazia uma nota — alta, média, baixa —
derivada da contagem de ressalvas. **O backtest a desmentiu:**

| Grupo | IC em 36 meses | Coortes positivas |
|---|---:|---:|
| Sem ressalva alguma | **−0,007** | 2 de 5 |
| Uma ou duas ressalvas | **0,206** | 5 de 5 |

A nota ordenava ao contrário do que prometia. Ela foi removida.

**5. A ressalva de custo da dívida estimado sai do conjunto.** Ela disparava em
469 das 821 avaliações do backtest — 57% —, porque a classificação sintética
virou o **método** pela decisão 31 e não é mais um recuo. Ressalva que vale para
a maioria não distingue nada.

**6. O prêmio de risco de mercado continua parametrizado em 5,50 p.p., e agora
com o motivo medido.** As âncoras calculam o CAGR do Ibovespa (12,22%) e do CDI
(9,40%) na mesma janela, o que dá um prêmio *ex post* de 2,83 p.p. — quase
metade do usado. A divergência não é descuido: dez anos de índice é estimador de
prêmio com erro-padrão da ordem de 8 pontos percentuais, e trocá-lo pelo
observado seria substituir uma premissa declarada por um número que a amostra
não sustenta.

O que a medição mostrou, e que fecha a questão para uso patrimonial: **o prêmio
é botão de nível, não de ordenação.** Entre 2,83 e 7,00 p.p., a correlação de
ordem do potencial contra a leitura de 5,50 p.p. fica entre **0,93 e 0,98**, e a
mediana do potencial vai de −43,2% a −54,5%. Como o motor é validado como
ordenador, a escolha do prêmio quase não toca o que ele serve para decidir.

## Consequências aceitas

- **A validação tem três vieses que ela não remove, e todos inflam o resultado.**
  *Sobrevivência* — o universo é o que está listado hoje, e quem fechou capital
  entre a coorte e o resgate não está aqui. *Reapresentação* — os exercícios vêm
  como a fonte os publica hoje. *Provento* — o retorno de referência é de preço,
  pela decisão 23, o que penaliza o motor em ativo de *payout* alto, já que o
  valor que ele apura inclui a distribuição. Os dois primeiros favorecem
  igualmente os fatores ingênuos, e o de sobrevivência favorece **mais** o valor
  patrimonial, que é o fator carregado em ativo em dificuldade.

- **Cinco coortes de 36 meses não são cinco observações independentes.** As
  janelas se sobrepõem, e o `t` de 3,33 sobre a média das cinco superestima a
  confiança. O que a medição sustenta é o **sinal e a consistência** — cinco de
  cinco positivas, quintis monótonos —, não um nível de significância.

- **O motor não supera os fatores ingênuos em coeficiente de informação.** Ele
  fica entre os dois em coeficiente de informação e **abaixo dos dois** em
  espalhamento de quintis; o que ele tem de próprio é a monotonicidade, que o
  valor patrimonial não tem, e que é o que permite dosar posição em vez de só
  separar as pontas. Quem quiser defender
  a cascata inteira precisa defendê-la por isso, pela auditabilidade e pelo preço
  justo em reais que um fator de ordenação não produz. **Não** por ser o
  ordenador mais forte, porque não é.

- **A remoção da nota de confiança tira da tela algo que seria confortável ter.**
  Um selo de qualidade por ativo é exatamente o que uma interface de decisão
  patrimonial pede. Ele foi construído, medido e descartado — e a alternativa
  seria apresentar uma ordenação que a evidência contradiz.

- **A explicação para a nota ter ordenado ao contrário é hipótese, não medição.**
  O ativo sem ressalva é o estável e previsível, que é o que o mercado precifica
  bem; a discordância informativa apareceria onde o modelo faz algo que o preço
  não fez. Plausível, não testado, e registrado como tal.

- **A alternativa descartada** era calibrar pesos por ressalva em vez de contá-las
  iguais. Recusada porque calibrar pesos contra cinco coortes sobrepostas
  produziria um ajuste à amostra com aparência de método — e porque a medição não
  mostra uma ordenação fraca a corrigir, mostra uma ordenação **invertida**.

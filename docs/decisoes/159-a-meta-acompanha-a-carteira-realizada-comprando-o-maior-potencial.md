---
numero: 159
titulo: A Meta acompanha a carteira realizada, que compra a cada aporte o ativo de maior potencial abaixo de um teto de peso, e a compara com o exigido, o esperado, o CDI e o Ibovespa
status: aceita
origem: voce
data: 2026-11-04
citacao: >
  Vamos supor que coloquemos uma data em que o investidor "iniciou a
  carteira", e podemos salvar isso no Firebase, com as cotações de cada ativo
  também salvas para os dias de compra e fazer as compras dos ativos baseados
  em quem está com o maior upside para o dia da compra. [...] Podemos seguir
  com todas as suas sugestões, a ressalva maior fica com o peso do
  investimento do ativo mesmo, vamos ver se o 2/N vai permitir que a gente
  construa uma carteira diversificada, qualquer coisa a gente muda depois.
afeta:
  - src/core/services/goal/portfolio-tracking.ts
  - src/core/services/backtest/portfolio-backtest.ts
  - src/core/services/b3/cash-dividends.ts
  - src/core/index.ts
  - src/app/tracking.ts
  - src/app/state/tracking-store.ts
  - src/app/services.ts
  - src/app/boot.ts
  - src/data/persistence/tracking-store.ts
  - src/data/persistence/account-data.ts
  - src/data/config/asset-paths.ts
  - src/features/goal/planner-page.tsx
  - src/features/goal/tracking-panel.tsx
  - src/features/goal/tracking-chart.tsx
  - src/features/auth/profile-page.tsx
  - firestore.rules
  - tool/upside-cohorts-package.ts
  - public/assets/validacao/upside_coortes.json
  - test/core/portfolio-tracking.test.ts
  - test/app/tracking.test.ts
  - test/data/account-data.test.ts
  - scripts/capture-screens.ts
  - docs/motor/07-aplicativo.md
substitui: []
---

## Contexto

A Meta respondia "quanto o plano exige" e desenhava, na curva de acumulação
(decisão 156), o patrimônio sob taxas constantes. Faltava o que o orientador
pediu como última peça do projeto: **o que a carteira de fato fez**. A
proposta foi fixar a data em que o investidor iniciou a carteira e, a cada
aporte, comprar o ativo da Principal com o maior potencial daquele dia, em
lotes, com a sobra indo para o aporte seguinte, até dizer se a carteira atinge
a rentabilidade que a meta exige.

Seis pontos precisavam de escolha, porque a regra literal tinha furos:

1. **Viés de antecipação.** Para começar no passado, o preço justo de cada data
   tem de ser o que o motor diria **naquela data**. O motor de hoje usa os
   balanços de hoje; aplicado em 2021, ele saberia o futuro. As coortes
   trimestrais da validação (decisões 97 e 128) são exatamente o motor ponto no
   tempo, de 31/03/2018 a 30/09/2025.
2. **Concentração.** O preço justo só muda a cada balanço; o preço muda todo
   dia. Medido nas coortes de 2021 a 2025, com carteiras de dez ativos
   sorteadas entre cinquenta, o líder de potencial se repete em 60% dos
   trimestres, e a mediana da maior sequência é de seis trimestres seguidos. A
   regra pura punha quase todo o dinheiro em um ou dois ativos.
3. **Proventos.** A comparação é contra o "esperado da carteira", que é
   retorno total (decisão 62), e contra o Ibovespa, que é índice de retorno
   total na metodologia da B3. Uma carteira só de preço perderia dos dois por
   construção. As decisões 23 e 89 deixaram a simulação de preço; estender
   provento a ela exige decisão nova — esta.
4. **Lote.** O lote-padrão da B3 é de 100 ações, e o mercado fracionário
   negocia de 1 a 99. Com aporte de mil reais e ação de quarenta, o lote
   cheio deixaria meses sem compra.
5. **A carteira muda.** Trocar um ativo da Principal no meio reescreveria as
   compras já feitas.
6. **O custo de capital das coortes.** O `ke` gravado nas coortes tem mediana
   perto de 7,5% ao ano mesmo em 2023 e 2025, com CDI acima de 13%. Um custo
   de capital próprio abaixo da renda fixa não serve de "esperado"; a causa
   não foi investigada nesta decisão.

## Decisão

A Meta ganha o **acompanhamento da carteira**. O usuário escolhe a data de
início e o dia do aporte (1 a 28); o plano congela a meta e a Principal
daquele dia. A partir dele:

- **Cada aporte cai no caixa da carteira e compra ações inteiras — lote de
  uma ação, como no fracionário — do ativo de maior potencial entre os que
  pesam menos que um teto, `2/N`** (o dobro do peso igual, limitado a 100%). O
  peso é o da posição no total em ações, antes da compra. Nenhum abaixo do
  teto: vale o maior potencial geral, e a compra registra que o teto foi
  ignorado. Nenhum que o caixa pague: não há compra, e o caixa espera o mês
  seguinte. A sobra fica no caixa, comum à carteira.
- **O preço justo vem de duas fontes.** Aporte agendado **antes** do dia em que
  o acompanhamento foi criado é retrospectivo: compra no próprio pregão, com a
  coorte vigente naquele dia, convertida para a base da série como
  `(1 + u_c) · P(c)`. A partir da criação, é ao vivo: compra com a avaliação
  do motor de hoje, no dia em que a página abre — o aporte vencido sem a
  página aberta compra no primeiro dia em que ela abre, e a compra declara a
  data agendada e a executada.
- **Depois da última coorte (30/09/2025), e enquanto o pacote não for
  refeito, a compra retrospectiva usa o preço justo da última coorte contra o
  preço do dia**, e a tela conta quantas compras fizeram isso. Coorte com mais
  de 122 dias é velha para esse fim.
- **Proventos entram no caixa na data ex**, sobre as ações detidas na
  data-com, e são reinvestidos pela mesma regra no aporte seguinte. O JCP
  entra líquido da retenção vigente na data-com: 15% até 2025 (Lei
  9.249/1995, art. 9º, § 2º) e 17,5% desde 01/01/2026 (Lei Complementar
  224/2025). O fato gerador é o pagamento ou o crédito, que a B3 não informa;
  a data-com é a aproximação. A retenção de 15% da validação e do beta
  (`CashDividend.netAmount`) não muda.
- **Cada compra é gravada uma vez e não muda mais**: coleção `trackingOrders`
  no Firestore, documento `<acompanhamento>-<aporte com 4 dígitos>`, que as
  regras só deixam criar pelo dono do acompanhamento e só regravar idêntico. Ao
  reabrir, as compras gravadas valem como estão; só o aporte sem registro é
  decidido. O plano mora em `trackings`. Os dois entram na exclusão da conta
  (decisão 157).
- **A comparação usa os mesmos aportes, nas mesmas datas**, em quatro destinos:
  o caminho exigido pela meta e o esperado da carteira, compostos à taxa anual
  na base de 365 dias; o CDI da série diária do Banco Central; e o Ibovespa da
  série da B3. O resumo dá o retorno ponderado pelo dinheiro (XIRR) contra o
  exigido, a distância ao caminho exigido em reais, e onde a carteira chega no
  fim do prazo se mantiver o ritmo.
- **O "esperado" é o da Meta no dia da criação**, congelado e rotulado com a
  data ("motor em AAAA-MM-DD"). O `ke` das coortes sai do pacote: não é usado
  em lugar nenhum.

O pacote `public/assets/validacao/upside_coortes.json` é gerado por
`npm run tool -- upside-cohorts-package` a partir de
`docs/validacao/backtest_trimestral.json`: guarda, por coorte, o potencial e o
preço de cada ativo avaliado.

## Consequências aceitas

**Retrospecto não é prova de habilidade.** O potencial do motor não comprovou
ordenar retornos na validação (decisões 96 e 103). O acompanhamento mostra o
que a regra fez, e a tela diz isso; um resultado bom num período não é
evidência de que a regra funciona (Bailey, Borwein, López de Prado e Zhu,
2014).

**Viés de sobrevivência no passado.** A Principal é a de hoje; começar em 2021
com ativos escolhidos em 2026 favorece o resultado (Elton, Gruber e Blake,
1996). A tela avisa ao escolher data passada.

**O teto de `2/N` é escolha, não ótimo.** Ele devolve a diversificação sem
tirar o aporte do ativo mais descontado, que só deixa de receber todos. Um
aporte grande ainda pode passar o teto, porque o teto filtra quem compra, e não
quanto. A ressalva do usuário fica registrada: se a carteira sair concentrada
demais, o teto muda por decisão nova. A alternativa do peso igual (DeMiguel,
Garlappi e Uppal, 2009) foi descartada porque apagaria a regra pedida.

**A simulação de carteira continua de preço.** O Backtest não muda: provento
entra só no acompanhamento, porque é o único lugar comparado a medidas de
retorno total.

**Sem imposto sobre ganho de capital e sem spread**: a carteira não vende, e o
imposto só existiria na venda. A tarifa da B3 entra como no Backtest
(decisão 126).

**O pacote das coortes envelhece.** De outubro de 2025 em diante o preço justo
retrospectivo é o da última coorte. Refazer as coortes no computador do
usuário e reempacotar resolve; o aplicativo não faz isso sozinho.

**As regras do Firestore precisam de publicação**
(`firebase deploy --only firestore:rules`). Até lá, a gravação das compras
falha, e a tela diz que o resultado não ficou guardado.

---
numero: 105
titulo: O aplicativo resolve o prior do beta e o custo de capital contra a alavancagem que a própria avaliação produz
status: aceita
origem: voce
data: 2026-09-20
citacao: >
  Seus itens de escopo para esta rodada são B9, B11 e B16.
afeta:
  - packages/equisim_core/lib/src/services/metrics/beta_shrinkage.dart
  - packages/equisim_core/lib/src/services/valuation/levered_rates.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/lib/src/usecases/prepare_valuation_inputs.dart
  - lib/data/repositories/beta_prior_repository.dart
  - lib/di/providers.dart
  - lib/presentation/valuation/valuation_providers.dart
  - tool/beta_prior_empacotar.dart
  - tool/backtest_valuation.dart
  - tool/gabarito_cascata.dart
  - assets/mercado/beta_prior.json
  - docs/validacao/prior_no_aplicativo.md
substitui: []
---

## Contexto

As decisões 40 a 46 descrevem um motor que **não rodava em produção**. Achado em
14/09/2026, na rodada do A5, e conferido no código: `ResolveBetaPrior` só era
chamado pelas ferramentas de diagnóstico. Sem prior não há beta desalavancado, e
sem `β_U` não há realavancagem: o aplicativo avaliava com o beta cru e o WACC
estático — o recuo declarado das decisões 40 e 41 —, de modo que o encolhimento
do beta, o custo de capital resolvido ano a ano, a rota derivada com taxas
coerentes, a isenção de realavancagem da Porta 1 e a recusa de estrutura da
decisão 45 nunca agiam.

A montagem padrão da validação também não passava prior, então ela media o mesmo
motor do aplicativo. **O que divergia eram as decisões**, que descreviam um motor
de diagnóstico.

**Por que não estava ligado.** Resolver o prior é varrer o universo inteiro —
cinco anos de cotação, o histórico de fundamentos e o perfil de cada um dos 376
papéis — para avaliar **um** ativo.

O item B11 listava três coisas a resolver antes de ligar:

1. a tensão da via do acionista, apontada pela lente `metodo`;
2. o defeito latente das premissas: com taxas resolvidas, o preço justo sai das
   premissas finais, mas os cenários, a taxa exibida e o rastro saíam das
   **interpoladas**;
3. desde 16/09/2026, mais duas: no caminho resolvido a varredura do nível da
   curva achava dois ativos subindo com a taxa, e o custo da dívida do
   solucionador e da rota derivada era o **observado**, que a
   [decisão 31](031-escala-do-preco-tributo-e-invariancia-das-guardas.md) já
   tinha descartado.

## Decisão

1. **O prior do beta é empacotado com o build**, gerado por
   `tool/beta_prior_empacotar.dart` sobre a mesma camada de dados que o
   aplicativo lê — CVM mesclada e setor da B3 por emissor. Sem pacote, ou com
   pacote de mais de um ano, o motor volta ao beta cru **e a avaliação diz que
   voltou**: a ressalva nomeia qual dos dois motores produziu o número.
2. **O custo da dívida do solucionador é o sintético, e é do ano.** O
   solucionador passa a receber o **prêmio de crédito**, não o custo pronto:
   `K_d,t = Rf_t + spread`, e `K_d,∞ = Rf_∞ + spread`. É a mesma classificação
   que `CostOfCapital.effectiveCostOfDebt` aplica, e a mesma leitura da decisão
   31 — o prêmio é da empresa, a taxa base é do ano. A rota derivada do capital
   próprio (decisão 102) usa o mesmo `K_d` nas duas rotas.
3. **Na via do acionista a dívida fica constante em termos nominais.** Ela
   desconta `lucro × (1 − b)`, isto é, o crescimento **já** é financiado por
   lucro retido; fazer a dívida crescer a `g` junto financiava o mesmo
   crescimento duas vezes, e o acionista pagava o `Ke` mais alto sem receber
   nada pela dívida nova que a conta supunha emitida. Na via da firma a premissa
   oposta é consistente, porque lá o fluxo do acionista credita o `+ΔD`.
4. **O que a tela mostra sai das premissas finais.** O rastro, os cenários, os
   diagnósticos e a taxa de desconto passam a sair do caminho de taxas e do
   retorno terminal do último passe. A taxa exibida é a do **ano 1** —
   `discountRateAt(1)` —, e não o campo escalar, que com o caminho resolvido
   guarda o chute da interpolação. O deslocamento que um cenário impõe ao
   desconto da firma é aplicado ao caminho de `Ke` resolvido do mesmo jeito.
5. **O peso do capital próprio não é confinado em `[0, 1]`** no solucionador,
   como já não é no WACC estático
   ([decisão 104](104-a-divida-do-wacc-e-a-liquida-como-no-resto-do-modelo.md)).

## O que foi medido

Sobre a entrada congelada do gabarito, em 20/09/2026
([prior_no_aplicativo.md](../validacao/prior_no_aplicativo.md)):

- **O aplicativo passa a resolver as taxas em 83 das 102 avaliações**, contra
  nenhuma antes.
- **A cobertura cai de 115 para 102.** Catorze ativos saem, todos pela recusa da
  decisão 45 — RENT3, RENT4, UGPA3, RAIL3, ECOR3, ENEV3, DXCO3, LOGG3, CAML3,
  DASA3, MOVI3, PNVL3, VAMO3, VBBR3 —, e a GOAU4 entra. Nos catorze, o valor da
  firma não cobre a dívida líquida já no primeiro iterado: eles eram avaliados
  porque o `Ke` do CAPM e o WACC estático não são a mesma conta.
- **O preço justo cai 2,4% na mediana**, com cauda dos dois lados: −79,6% na
  MYPK3 e +22,7% na EMBJ3.
- **A varredura do nível da curva não acha nenhum ativo subindo com a taxa**, em
  nenhuma das duas montagens: 0 de 102 e 0 de 102, contra 2 de 104 antes. A
  RADL3 e a SEER3, que alternavam pelo veredito da perpetuidade, ficaram
  monótonas.
- **O prior anda devagar, e é isso que autoriza o pacote**: a mediana
  desalavancada do universo é 0,6421, e recuada 90, 180 e 365 dias dá 0,6618,
  0,6695 e 0,6620 — 3,1%, 4,3% e 3,1% de diferença. A validade do pacote é de um
  ano, contra os sete dias da curva (decisão 86), que é taxa de um dia.

## Consequências aceitas

**Catorze ativos saem do aplicativo, e são grandes.** RENT3, UGPA3 e RAIL3 não
são companhias obscuras. A conta coerente diz que o fluxo da operação delas, ao
custo de capital que a própria alavancagem produz, não cobre a dívida líquida —
e a decisão 45 recusa em vez de lavar a recusa em preço. Recuar para a
interpolação onde o ponto fixo recusa reintroduziria exatamente o degrau que o
B10 mediu.

**O prior é do build, e não do dia.** Ele fica congelado até o próximo empacote,
como a curva na web (decisão 86) e o registro da B3 (decisão 83). A deriva está
medida e é de poucos pontos percentuais ao ano; a validade de um ano existe para
que um pacote esquecido não continue passando por atual.

**A montagem padrão da validação passa a resolver o prior na data da coorte**, o
que a torna mais cara — uma varredura do universo por coorte. Um prior de hoje
seria conhecimento futuro.

**A medição do backtest não foi refeita nesta rodada.** A base bruta — COTAHIST,
CVM ingerida, FRE — não está nesta máquina, e reexecutar o backtest depende dela.
A habilidade, a faixa calibrada, o custo das recusas e a ponte por papel
continuam medidos sobre o motor da decisão 102; refazê-las é o item C5.

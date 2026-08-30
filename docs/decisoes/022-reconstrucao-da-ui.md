---
numero: 22
titulo: Reconstrução da disposição da UI, com fronteira declarada
status: aceita
postura: reconstrucao
origem: voce
data: 2026-08-30
afeta:
  - lib/presentation/shell
  - lib/presentation/study
  - lib/presentation/backtest
  - lib/presentation/goals
  - lib/presentation/valuation
  - lib/presentation/components
  - lib/presentation/shared
  - lib/views
substitui: []
---

## Contexto

A [decisão 21](021-ondas-de-refatoracao-da-ui.md) registra que as quatro ondas
resolveram a **base do código** — tokens, contraste medido, ausência de estouro
— e explicitamente **não** a direção visual. Disposição, hierarquia e
arquitetura de informação ficaram abertas.

A lente `tela` do conselheiro rodou três vezes sobre capturas com dados reais
(390 dp claro, 1024 dp claro, 390 dp escuro) e convergiu num diagnóstico único:
**dois dos três rótulos de navegação não descrevem o que abrem.**

| Rótulo | Abre | Tensão |
|---|---|---|
| Carteiras | `StudyPage`, cujo título é "Novo estudo" | Não é lista de carteiras, é montagem de estudo |
| Meta | `GoalPage` | Coerente |
| Análise | `BacktestPage` | Backtest é uma análise entre várias; valuation, a mais estrita, mora dentro de "Carteiras" |

São seis frentes — estudo, valuation, meta, backtest, exportação, auditoria —
espremidas em três rótulos que não as nomeiam. Renomear a aba não resolve:
decidir o rótulo é decidir o que cada tela **é**.

Dois truncamentos que a mesma lente apontou já foram corrigidos e não fazem
parte deste escopo: a tabela de ativos e o método de valuation.

## Decisão

Abrir uma **postura de reconstrução** sobre as telas de operação, tratando a
disposição e a arquitetura de informação como trabalho declarado em vez de
dívida herdada.

**Dentro da fronteira** listada em `afeta`, e somente ali, a distinção entre
dívida herdada e regressão fica suspensa: toda divergência é acionável, porque
a decisão de refazer já foi tomada. Fora dela, a preservação continua valendo
integralmente.

`lib/presentation/audit/` fica **de fora**, deliberadamente. O painel de logs
serve ao orientador acompanhar a apuração de cada cálculo: público diferente,
propósito diferente, e nenhum achado da lente o mencionou. Incluí-lo tornaria
acionável uma tela de que ninguém reclamou.

Também ficam de fora `lib/presentation/theme/` — é o sistema construído pela
decisão 21, não objeto de reconstrução — e `lib/presentation/export/`, que não
tem superfície visual própria.

## Encerramento

A decisão recebe `status: cumprida` quando **todos os pacotes da EAP** em
`docs/eap/` tiverem seu `criterio_de_pronto` verificado. A EAP é o contrato do
encerramento: sem ela a postura ficaria aberta indefinidamente, e uma
reconstrução sem fim é indistinguível de não ter fronteira nenhuma.

Cumprida, a superfície volta à preservação e a linha de base da lente `tela` é
redesenhada a partir do estado novo — senão a execução seguinte reportaria
contra um alvo que já não existe.

## Consequências aceitas

- **O conselheiro fica mais barulhento nessas telas.** É o efeito pretendido, e
  é temporário. Se a lista virar ruído, o problema é a fronteira estar larga
  demais, não a postura estar errada.
- **O auditor não muda.** A postura governa o conselheiro; código novo continua
  sendo julgado como código novo, com o rigor de sempre. Reconstruir não afrouxa
  o gate.
- **Mexer em rótulo de navegação muda o que o usuário aprendeu.** Quem já usa a
  aplicação vai procurar coisas onde elas não estão mais. Aceito porque a base
  de usuários hoje somos nós e a banca, e o custo de manter nome errado é maior
  do que o de corrigi-lo agora.

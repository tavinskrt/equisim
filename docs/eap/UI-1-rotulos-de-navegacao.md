---
pacote: UI-1
titulo: Cada aba abre a tela que seu rótulo nomeia
decisao: 22
origem: lente `tela`, três execuções convergentes
escopo:
  - lib/presentation/shell/app_shell.dart
  - lib/presentation/study/study_page.dart
  - lib/presentation/backtest/backtest_page.dart
  - lib/presentation/valuation/valuation_page.dart
fora_de_escopo:
  - lib/presentation/audit
  - lib/presentation/goals
criterio_de_pronto: >
  Uma pessoa que nunca abriu a aplicação acerta, só lendo os três rótulos, o
  que encontrará em cada aba. Verificável nas capturas: o título no topo de
  cada tela não contradiz o rótulo que a abriu.
---

## O achado

A lente `tela` convergiu nas três execuções — 390 dp claro, 1024 dp claro,
390 dp escuro — sobre a mesma incoerência, ancorada nos dois lados:

| Rótulo | Abre | O que a captura mostra |
|---|---|---|
| **Carteiras** | `StudyPage` | título "Novo estudo" |
| Meta | `GoalPage` | coerente |
| **Análise** | `BacktestPage` | "PARÂMETROS DA SIMULAÇÃO", "EVOLUÇÃO COMPARADA" |

Evidência literal citada pela lente, em `app_shell.dart:33`:

```dart
static const _tabs = [
  (icon: Icons.dashboard_outlined, label: 'Carteiras'),
  (icon: Icons.flag_outlined,      label: 'Meta'),
  (icon: Icons.insights_outlined,  label: 'Análise'),
];
```

E em `app_shell.dart:53`:

```dart
children: const [StudyPage(), GoalPage(), BacktestPage()],
```

## Por que não é renomear aba

Seis frentes — estudo, valuation, meta, backtest, exportação, auditoria — vivem
sob três rótulos. Trocar as palavras redistribui o problema em vez de resolvê-lo:
"Análise" vira "Backtest" e valuation continua escondido dentro de "Carteiras",
alcançável só ao entrar num ticker ([study_page.dart:849](../../lib/presentation/study/study_page.dart)).

Decidir o rótulo é decidir **o que cada tela é**. É o trabalho, não o atalho.

## Caminhos que a lente ofereceu

Registrados como ela os deu, sem escolha feita — a escolha é humana, e uma
decisão só se defende quando as alternativas descartadas são conhecidas.

1. **Renomear para o que as telas fazem hoje.** "Carteiras" → "Estudos" ou
   "Simulador"; "Análise" → "Backtest". Custo: valuation continua sem porta
   própria, e o problema de seis frentes em três abas permanece.

2. **Dar porta de entrada real a "Carteiras".** Uma tela que lista os estudos
   salvos, movendo a criação de "Novo estudo" para fluxo secundário. Custo:
   tela nova, e é a opção mais cara.

3. *(Não veio da lente, registrada por completude.)* **Repensar a divisão em
   três abas.** Se são seis frentes, talvez três não seja o número. Custo: a
   maior mudança de todas, e a que mais mexe no que já se aprendeu a usar.

## O que fica de fora

`GoalPage` não entra: seu rótulo é o único coerente, e mexer nele seria
regressão. `lib/presentation/audit/` está fora da fronteira inteira, pela
decisão 22.

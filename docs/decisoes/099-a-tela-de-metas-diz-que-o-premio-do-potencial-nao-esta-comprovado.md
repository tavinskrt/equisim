---
numero: 99
titulo: A tela de metas diz, pela leitura medida, que o prêmio tirado do potencial não está comprovado
status: aceita
origem: voce
data: 2026-09-15
citacao: >
  Seus itens de escopo para esta rodada são C2b e B1.0, dando início à Fase 3.
afeta:
  - lib/presentation/goals/goal_page.dart
  - lib/presentation/goals/skill_copy.dart
  - lib/data/repositories/skill_reading_repository.dart
  - lib/di/providers.dart
  - packages/equisim_core/lib/src/services/valuation/skill_reading.dart
  - tool/regressao_condicional.dart
  - assets/validacao/habilidade.json
substitui: []
---

## Contexto

O retorno esperado da carteira na tela de metas é, desde a
[decisão 58](058-a-carteira-de-acoes-nao-espera-a-renda-fixa.md),
o `Ke` de cada ativo mais `z · prêmio`, com `z` tirado do potencial: quem está
descontado em relação aos pares espera mais. A §0 do
[plano do motor de referência](../plano-motor-de-referencia.md) mediu, em
11/09/2026, que o potencial ordena pior que o valor patrimonial sobre o preço e,
condicionado a ele, não acrescenta. A §3 do plano chamou isso de **defeito em
produção, e não pesquisa em aberto**, e recomendou declarar a ressalva na tela
sem esperar decisão nenhuma. Conferido em 14/09/2026: nada na tela dizia isso.

A medição de hoje, sobre o motor do dia, é a da terceira rodada da Fase 2 — 22
coortes trimestrais de 36 meses, com as deslistadas, na base da data
([decisão 97](097-a-coorte-forma-preco-contagem-e-valor-de-mercado-na-base-da-data.md)):
correlação de postos de 0,091 do potencial contra 0,181 do book-to-market, e o
potencial dado o B/M com coeficiente de 0,030 e `t` corrigido pela sobreposição
de 0,24, contra o crítico de 2,70
([decisão 96](096-o-t-da-habilidade-e-corrigido-pela-sobreposicao-contra-o-critico-dela.md)).

O que o potencial deve servir — e, com isso, o que o prêmio deve ser — é o item
B1 do plano, e é decisão do usuário. Este item não a toma: declara.

## Decisão

**O cartão do confronto com a meta diz, com o número medido, que o prêmio acima
do `Ke` sai de um ordenador sem habilidade comprovada.** A frase sai da leitura
empacotada com o aplicativo, `assets/validacao/habilidade.json`, que
`tool/regressao_condicional.dart --trimestral` grava junto da medição; ela cita a
correlação de postos contra a do B/M quando o potencial ordena pior, e o `t` da
perna do critério que falhou.

**O critério da decisão 96 mora no núcleo**, em `SkillReading.demonstrated`, e
não no pacote: quando a medição final (C1) aprovar, a ressalva some sem mudar
código. **Sem pacote, ou com pacote malformado, a ressalva diz que a habilidade
não foi medida** — a ausência não pode escondê-la.

## Consequências aceitas

**O número não muda.** O esperado continua `Ke + z · prêmio`, e a meta continua
julgada contra ele; tirar o prêmio, trocá-lo por um modelo transversal ou medir os
dois lado a lado é o B1.

**A leitura é a do motor do dia da medição, e não o veredito.** A Fase 3 vai mudar
o motor, e o pacote precisa ser regravado quando o C1 medir. O teste do pacote
reprova a suíte se o pacote disser outra coisa que `habilidade_trimestral.json`,
ou se o critério do núcleo discordar do `passaR3` da ferramenta.

**Alternativas descartadas.**

- *Texto fixo*: mentiria no dia em que o C1 aprovasse, ou teria de ser lembrado. O
  próprio cartão guarda o histórico de um rótulo que sobreviveu duas semanas à
  mudança do número.
- *Tirar o prêmio do esperado*: é mudar o método da meta, que é o B1.
- *Esconder o esperado*: tira do cartão a razão de existir.

**Só a tela de metas.** A de estudo mostra o potencial de cada ativo e o declara
"não um retorno previsto, e sem prazo para se realizar"; a de backtest diz que a
distância entre carteiras "não é recomendação de troca". Nenhuma das duas
transforma o potencial em retorno esperado.

---
numero: 35
titulo: O motor ganha DCF reverso e regressão condicional, e as duas medições reordenam o que vem depois
status: aceita
origem: voce
data: 2026-09-09
citacao: >
  Vamos começar. Quando o motor chegar no nível citado (um motor sem defeito
  conhecido, com incerteza calibrada e habilidade comprovada), quero ser
  avisado. Faça o item 1 então: DCF reverso e a regressão condicional.
afeta:
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - tool/dcf_reverso.dart
  - tool/regressao_condicional.dart
  - tool/validation/regression.dart
  - test/tool/regression_test.dart
  - docs/validacao/dcf_reverso.md
substitui: []
---

## Contexto

O motor carregava dois fatos medidos e nenhuma explicação medida para nenhum
dos dois: o potencial mediano em torno de −45%, e um coeficiente de informação
de 0,170 em 36 meses contra 0,213 do valor patrimonial sobre preço.

O primeiro admitia três hipóteses — terminal neutro, taxa de desconto,
saturações da base —, cada uma com um conserto de semanas. O segundo deixava
em aberto se a cascata via algo que os fatores ingênuos não viam.

Nenhuma das duas perguntas podia ser respondida por inspeção, e a primeira
tinha uma armadilha: **o conserto do terminal fecharia o vão independentemente
da causa verdadeira**, porque um retorno terminal livre tem graus de liberdade
de sobra para absorver um erro de taxa. O motor pareceria consertado.

## Decisão

**1. O DCF reverso entra no aparato de validação, e é reprodutível.**

[`tool/dcf_reverso.dart`](../../tool/dcf_reverso.dart) varre a cascata inteira
em três eixos — retorno terminal, prêmio de risco e nível da curva de desconto
— procurando o valor que iguala o preço justo ao preço de mercado, e obtém o
quarto eixo, o fluxo-base, por identidade de homogeneidade. A varredura é por
**grade antes de bissecção**: a monotonia é medida, não suposta, e um ativo com
mais de um cruzamento é declarado como tal.

**2. A regressão condicional entra junto.**
[`tool/regressao_condicional.dart`](../../tool/regressao_condicional.dart) roda
Fama-MacBeth em dois passos sobre as coortes da validação preditiva, com os três
ordenadores na mesma regressão, e reporta a IC incremental do potencial.

**3. `ValuationInputs.terminalReturnOverride` entra no núcleo como costura de
diagnóstico.** É nulo em produção e não altera comportamento algum; preenchido,
substitui o veredito de vantagem competitiva sem simular sua aprovação — a
narrativa de *moat* e o `moatApplied` continuam atrelados ao veredito real, e o
resultado declara a imposição.

**4. O resultado das duas medições reordena o roteiro**, e o que ele reordena
está registrado em [`docs/validacao/dcf_reverso.md`](../validacao/dcf_reverso.md):

- **O terminal neutro deixa de ser candidato a explicação do viés de nível.**
  É inatingível em 73 dos 122 avaliados — nem retorno perpétuo de 200% ao ano
  alcança o preço — e não é explicação exclusiva em ativo nenhum. A assimetria
  é estrita: 56 ativos em que a taxa resolve e o terminal não, **zero** no
  sentido contrário.
- **A normalização da base também deixa.** O fator aplicado tem mediana 1,00.
- **O nível da curva de desconto fica implicado, e declarado insuficiente.**
  Resolve 99 dos 122, mas ao custo de uma taxa de equilíbrio implícita mediana
  de 5,98% — abaixo do crescimento nominal da economia em 63 dos 99 e abaixo da
  âncora de inflação em 44.
- **O resíduo mora no fluxo-base**, e nenhuma instrumentação atual o isola. O
  multiplicador mediano necessário é 1,64×.
- **A ordenação da cascata em 36 meses não sobrevive ao controle.** O
  coeficiente do potencial cai de 0,170 para 0,041 quando o P/B e o L/P entram
  na mesma regressão, e a IC incremental fica em 0,031, com intervalo de 95% em
  [−0,090; +0,152].

## Consequências aceitas

**O trabalho de *fade* terminal perde a justificativa que tinha.** Trocar o
degrau da vantagem competitiva por decaimento contínuo do RONIC continua
defensável por teoria, e deixa de ser defensável como conserto do nível. Quem
o propuser depois desta decisão precisa de outro argumento.

**A prioridade de curva de juros observada sobe, com expectativa rebaixada.**
Ela é o único eixo com tração medida, e a própria medição diz que não fecha o
vão. Adotá-la esperando que o potencial mediano vá a zero seria contrariar o
que está escrito aqui.

**Abre-se uma frente que não estava no roteiro: auditar o nível do fluxo
explícito.** O suspeito nomeado é o freio de reinvestimento — o fluxo explícito
paga `1 − g/ROIC` e o terminal não paga nada —, e ele é hipótese, não medição.

**A cascata deixa de ser defendida pelo poder preditivo.** A
[decisão 32](032-validacao-preditiva-e-diagnosticos-do-resultado.md) já dizia
que ela não se justifica por ele; esta mede quanto disso é verdade e fecha a
questão. O que a sustenta é o preço justo em reais, a auditabilidade e a recusa
nomeada — e agora também o DCF reverso, que é afirmação sobre o preço que
fator de ordenação nenhum produz.

**Calibrar qualquer parâmetro para fechar o vão fica vedado por esta decisão.**
Ajustar o motor até a mediana do potencial ir a zero é ajustá-lo ao mercado, e
destrói o sinal que a validação preditiva mediu. Se algum dia isso for feito,
que seja por decisão que diga que está sendo feito.

**A não monotonia do preço justo no nível da curva sobreviveu à
[decisão 34](034-fronteira-das-vias-medida-na-taxa-estrutural.md)**, em 46 dos
122. Aquela decisão resolveu o caso que a motivou — mover só a taxa corrente —
e não o caso geral, porque deslocar as duas taxas juntas move também a
participação estrutural que decide a via. Fica registrado como pendência, e
não é corrigido aqui.

**A estatística nova não tem conferência externa.** A máquina do projeto não
tem `numpy`, `scipy` nem `statsmodels` — verificado em 09/09/2026. A regressão
múltipla é conferida contra o `Inference.ols` do núcleo no caso de um
regressor, e o caso multivariado fica com recuperação de coeficientes
conhecidos e ortogonalidade do resíduo, que são necessárias e não suficientes.

**A alternativa descartada** era ir direto ao *fade* terminal, que era o
primeiro item do roteiro proposto e a hipótese mais citada. Recusada porque ela
teria funcionado: o vão fecharia, a medição melhoraria, e o motor ficaria mal
especificado com aparência de consertado.

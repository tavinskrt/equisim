---
numero: 38
titulo: A pós-condição da ponte deixa de ser degrau e vira transição contínua entre as duas vias
status: aceita
origem: voce
data: 2026-09-10
citacao: >
  Pode realizar a correção antes de partir para o item 3
afeta:
  - packages/equisim_core/lib/src/entities/valuation.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/test/valuation_guards_test.dart
  - tool/vias.dart
  - docs/validacao/vias.md
substitui: []
---

## Contexto

A [decisão 37](037-aliquota-estrutural-no-fluxo-da-firma.md) corrigiu a
alíquota do fluxo da firma e, ao fazê-lo, derrubou nove ativos de 58,9% a
92,1% — VBBR3 de R$ 33,71 para R$ 2,65, PRIO3 de R$ 53,88 para R$ 7,46. Nenhum
deles caiu por causa do imposto: **todos trocaram de via**. O NOPAT maior
elevava o valor da firma, a participação do capital próprio cruzava os 20% da
pós-condição, a migração deixava de disparar e o ativo ficava na via da firma.

A [decisão 34](034-fronteira-das-vias-medida-na-taxa-estrutural.md) já havia
registrado a causa sem resolvê-la: *"Isto não concilia as duas vias, que seguem
discordando por medirem crescimento e base em séries de capital diferentes"*.

A medição está em [`vias.md`](../validacao/vias.md), e exigiu avaliar as duas
vias no mesmo ativo — o que o roteamento impede por construção.

**Em teoria as duas não deveriam discordar.** `FCFF/WACC` e `FCFE/Ke` são a
mesma avaliação vista de dois lados. A distância entre elas mede
inconsistência interna do motor, e ela é grande:

- razão firma ÷ acionista com mediana de **1,04×** — em agregado concordam —,
  mas **55 dos 92 discordam além de 1,5×** e **33 além de 2×**;
- a fonte mais frequente é o desconto (`WACC − Ke` difere de mais de 2 p.p. em
  59 de 92), seguida do crescimento (43) e da normalização da base (34);
- **nenhuma das duas é mais próxima do mercado**: 39 contra 53, com erro
  mediano de 59,1% e 53,3%.

Enquanto um limiar escolhia uma delas, essa discordância virava um degrau no
preço justo.

## Decisão

**O peso da via da firma passa a ser contínuo na participação do capital
próprio**, percorrendo a faixa que o projeto já declarava frágil:

```
s ≤ 0,20            → 0    (só o acionista)
0,20 < s < 0,35     → (s − 0,20) / 0,15
s ≥ 0,35            → 1    (só a firma)
```

**Nenhum parâmetro novo.** `minEquityShare = 0,20` marca desde a
[decisão 25](025-reconstrucao-do-motor-de-avaliacao.md) onde a ponte deixa de
ser utilizável; `fragileEquityShare = 0,35` marca desde a
[decisão 32](032-validacao-preditiva-e-diagnosticos-do-resultado.md) onde ela
deixa de ser frágil. Os dois passam a delimitar uma transição em vez de um
degrau.

**A combinação é do número, não dos cenários.** Duas vias que discordam por
múltiplos não têm banda comum, e apresentar a da firma em torno de um ponto que
é média das duas afirmaria uma dispersão que nenhuma delas mediu. A banda sai; o
peso e os dois valores de origem viajam no aviso, e a ressalva `viasMescladas`
marca o resultado.

**`ValuationInputs.laneOverride` entra como costura de diagnóstico**, nula em
produção. Sem ela a discordância não é medível, porque o roteamento nunca
avalia as duas vias do mesmo ativo.

## Consequências aceitas

**O efeito é cirúrgico, e são os mesmos ativos.** Onze dos 122 se movem além de
0,5%, todos na faixa exposta: VBBR3 +760,4%, SBFG3 +251,0%, AGRO3 +227,9%,
PRIO3 +149,3%, KLBN3/4/11 entre +96,7% e +111,5%, MULT3 +71,7%, MYPK3 +27,8%,
MOTV3 +4,3% e **QUAL3 −23,6%**. O potencial mediano vai de −42,3% para
**−40,0%**; os positivos ficam em 28.

**Não é restauração do que a decisão 37 derrubou, ainda que coincida.** A
alíquota estrutural continua valendo integralmente; o que os derrubava era o
degrau que ela fez cruzar. A QUAL3 é a prova: ela entra na transição e **perde**
23,6%, porque para ela a via do acionista vale menos. A regra não é restaurar
valor, é não saltar.

**A discordância continua, e agora está declarada em vez de escondida.** A
VBBR3 segue valendo R$ 2,65 por uma via e R$ 33,71 pela outra. Na faixa de
transição o preço justo é média ponderada de dois números que discordam por
ordem de grandeza — e é isso que a ressalva `viasMescladas` diz. Trocar um
degrau arbitrário por uma média declarada não resolve a inconsistência; torna-a
visível e contínua.

**Conciliar de verdade fica em aberto, e é a maior pendência de método do
motor.** Exige que crescimento, normalização da base e reinvestimento saiam de
um único conjunto de premissas, com a alavancagem ligando `Ke` e `WACC`. É
reconstrução da Porta 2, não ajuste de fronteira.

**A forma da rampa é linear, e é escolha.** Uma ponderação por precisão — o erro
da via da firma escala com `1/s` — teria fundamento mais forte e exigiria
estimar a variância de cada via, que não foi feito.

**Ativos fora da faixa continuam com uma via só**, e para eles a discordância
permanece invisível no resultado.

**A alternativa descartada** era manter o degrau e apenas declará-lo melhor.
Recusada porque o degrau não é problema de apresentação: ele fazia o preço
justo saltar por múltiplos quando um parâmetro se movia por pontos-base, e a
decisão 37 acabara de mostrar isso acontecendo em nove ativos de uma vez.

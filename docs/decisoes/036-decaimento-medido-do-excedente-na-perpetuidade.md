---
numero: 36
titulo: A vantagem competitiva deixa de ser degrau e passa a decair pela persistência medida do próprio ativo
status: aceita
origem: voce
data: 2026-09-09
citacao: >
  Vamos com a 1, então
afeta:
  - packages/equisim_core/lib/src/services/valuation/growth_guards.dart
  - packages/equisim_core/lib/src/entities/valuation.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/test/valuation_guards_test.dart
  - tool/fade_terminal.dart
  - docs/validacao/fade_terminal.md
substitui: []
---

## Contexto

A [decisão 35](035-dcf-reverso-e-regressao-condicional.md) tirou do decaimento
contínuo do retorno terminal o argumento que ele tinha — o terminal **não** é a
causa do viés de nível — e exigiu outro argumento de quem o propusesse depois
dela.

O argumento veio, e é sobre **forma**, não sobre nível. A exceção de vantagem
competitiva era um degrau: cinco condições cumulativas e, para quem passasse,
uma fração fixa de 0,30 do excedente preservada na perpetuidade. Medido em
09/09/2026 e registrado em [`fade_terminal.md`](../validacao/fade_terminal.md):

1. **O degrau vale de 10% a 32% de preço justo em onze ativos**, com mediana de
   5,7% nos 48 com excedente positivo.
2. **Ele está ordenado ao contrário do tamanho do efeito.** Dos oito negados
   que mais ganhariam, seis ganhariam mais que a maioria dos oito concedidos.
   SAPR4, SAPR11, TAEE4 e TAEE11 — saneamento e transmissão, excedente modesto
   e persistente — perdiam de 12% a 16% barrados só pelo corte de
   rentabilidade.
3. **O limiar separa ruído de estimação.** RENT3 e RENT4, mesma empresa e mesmo
   ROIC de 23,6%, caíam em lados opostos com folgas de +1,40 e −0,45 p.p.,
   porque o `r_∞` de cada classe difere pelo beta.
4. **O `λ = 0,30` fixo não é sustentado pelo dado.** Ele equivale a decaimento
   anual de `φ = 0,887`; a persistência medida por AR(1) sobre o excedente tem
   mediana de **0,48** e p90 de 0,78. Um único ativo dos 47 mensuráveis
   sustentava o pressuposto.

## Decisão

**O retorno terminal passa a ser `ROIC_∞ = WACC_∞ + φ^N · (ROIC_ciclo −
WACC_∞)`**, com `φ` estimado por AR(1) sobre o excedente do próprio ativo e `N`
o horizonte de projeção explícita.

**As condições que restam são de qualidade de dado** — sem retorno do ciclo,
sem custo de capital, histórico curto, Φ não medido ou acima de 0,60, e
persistência não estimável. **Os dois cortes de nível saem**: rentabilidade
insuficiente e saúde operacional. Eles eram limiares sobre o *tamanho* do
excedente, e é o tamanho que `λ · e₀` já contempla de forma contínua.

**A trava de saúde operacional continua inteira na Porta 2a**, que é onde ela
sempre resolveu o caso que a motivou: a QUAL3 perdeu a vantagem residual na
quarta rodada e **continuou** a +477,3% de potencial, porque o número vinha da
base normalizada. A isenção cíclica da [decisão 30](030-isencao-ciclica-da-trava-de-saude.md)
segue restrita à Porta 2a, e agora é o único lugar onde a questão se coloca.

**A correção de viés de amostra pequena foi implementada, medida e
descartada.** O viés de Kendall é real — o AR(1) com intercepto subestima `φ` —
mas com sete a dez pares a correção vale de 0,25 a 0,35, a mesma ordem de
grandeza do próprio `φ̂`. Rodada sobre o universo, ela pôs **dez dos vinte e
quatro** ativos com preservação positiva no teto, e o teto passou a decidir no
lugar do dado — trocando um `0,30` fixo por um `0,3487` fixo. Sem ela, o teto
morde uma vez em quarenta e sete.

**O resultado sai com a magnitude junto.** `ValuationDiagnostics` ganha
`terminalRetainedSpread`, e o veredito carrega `φ` cru e `φ` aplicado lado a
lado. Uma bandeira booleana era suficiente enquanto a exceção era binária; com
`λ` contínuo ela esconde a diferença entre preservar meio ponto-base e
preservar um terço.

## Consequências aceitas

**A cobertura quase triplica e a magnitude despenca.** Vinte e três dos 117
avaliados passam a ter preservação positiva, contra oito do degrau — mas o `λ`
mediano é de **0,0015**, com p90 em 0,088 e máximo em 0,258. Nenhum alcança os
0,30 que o degrau concedia.

**O efeito no preço justo é cirúrgico, e para baixo.** Oito ativos se movem
além de 0,5%. As seis maiores quedas são todas de quem tinha a exceção — EGIE3
−24,3%, BBSE3 −15,1%, CXSE3 −7,0%, ABEV3 −6,7%, VBBR3 −5,8% e WEGE3 −3,7% — e a
maior alta é a CPFE3, com +8,1%.

**O nível não se move, e isso era previsto.** O potencial mediano fica em
−52,2% antes e depois, com 14 positivos nos dois casos. É corroboração
independente da decisão 35: o terminal não é onde o vão mora.

**O viés para baixo do estimador fica declarado como conservadorismo.** A
persistência medida subestima a verdadeira, e a subestimação empurra o preço
justo para baixo — a direção em que este projeto já erra e admite errar. Quem
tiver amostra maior ou um estimador que encolha para uma média transversal
pode revisitar; o `φ` cru viaja no veredito para que isso seja possível sem
reexecutar tudo.

**`φ` estimado em sete a quinze pontos não é número de precisão.** Ele sustenta
uma ordem de grandeza — "o excedente não persiste dez anos" — e não uma
calibragem por ativo com três casas. O teto de `moatMaxPersistence = 0,90`
existe para que `φ → 1` não vire excedente perene, que é o que o retorno
terminal neutro da [decisão 25](025-reconstrucao-do-motor-de-avaliacao.md)
existe para negar.

**Números publicados mudam.** Toda menção a "sete ativos com vantagem
competitiva" e ao `moatRetainedSpread` de 0,30 fica defasada, incluindo a §2.8
das [limitações](../validacao/limitacoes.md) e as seções 12 a 16 do
[refinamento](../refinamento-do-valuation.md).

**A alternativa descartada** era o *fade* conservador: manter as cinco
condições como porta e trocar só o `0,30` pelo `λ` medido. Recusada porque
preserva exatamente o degrau que era o argumento inteiro para mexer.

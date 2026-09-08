---
numero: 31
titulo: Escala do preço, alíquota do escudo, custo da dívida e invariância das guardas ao horizonte
status: aceita
origem: voce
data: 2026-09-08
citacao: >
  Percorra todo o código e faça testes exaustivos e extensivos no motor de
  valuation a fim de encontrar erros. Pedi para que o Gemini fizesse isso
  também e ele me retornou este relatório. Cruze seus achados com os dele a fim
  de solucionarmos todos os problemas neste motor. Não ligo que você demore.
  Apenas quero precisão, metodologia, fundamentação teórica e solução.
afeta:
  - packages/equisim_core/lib/src/entities/fundamentals.dart
  - packages/equisim_core/lib/src/services/valuation/capital_base.dart
  - packages/equisim_core/lib/src/services/valuation/cost_of_capital.dart
  - packages/equisim_core/lib/src/services/valuation/growth_guards.dart
  - packages/equisim_core/lib/src/services/valuation/scenario_engine.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/test/usecases_test.dart
  - packages/equisim_core/test/valuation_guards_test.dart
  - packages/equisim_core/test/valuation_test.dart
  - test/presentation/logs_page_test.dart
  - lib/presentation/valuation/valuation_providers.dart
  - docs/validacao/auditoria_cruzada_valuation.md
substitui: []
---

## Contexto

Uma auditoria por execução sobre os 373 papéis do universo, cruzada com um
relatório independente produzido por outro modelo, mediu sete defeitos no motor
de avaliação reconstruído pela [decisão 25](025-reconstrucao-do-motor-de-avaliacao.md).
O cruzamento inteiro — o que se confirmou, o que não se confirmou e o que
nenhum dos dois lados tinha visto — está em
[`docs/validacao/auditoria_cruzada_valuation.md`](../validacao/auditoria_cruzada_valuation.md).

Os defeitos não são de calibragem. Cada um é uma grandeza medida na unidade
errada, uma convenção aplicada de dois jeitos no mesmo cálculo, ou um veredito
estatístico dependendo de um parâmetro de apresentação.

1. **O divisor da ponte por papel estava na escala das demonstrações, não na do
   preço.** `reconciledShares` arbitra entre as duas contagens publicadas por
   `N = lucro ÷ LPA` — mas os dois campos vêm das **mesmas** demonstrações, de
   modo que o árbitro só pode confirmar a contagem do exercício. Ele é
   tautológico para a pergunta que a ponte faz. Medido: o divisor saía errado
   por mais de 5% em **30 dos 120 avaliados**, com 2,65x na MOVI3 — R$ 35,39 de
   preço justo contra R$ 13,38 na escala certa — e 1,49x na B3SA3.

2. **A janela do ciclo descartava exercício de prejuízo.** `CapitalSeries.returns`
   exigia `lucro > 0`, e a mediana do ciclo passava a descrever só os anos bons
   da empresa. **52 dos 120** avaliados tinham ao menos um exercício descartado;
   a CVCB3 acusava 33,8% de ROIC mediano contra 0,55% com os quatro anos de
   prejuízo no lugar, e a MGLU3 22,4% contra 11,2%. Como o fator de normalização
   é `ciclo ÷ atual` e o DCF é homogêneo de grau 1 no fluxo-base, o viés ia
   inteiro para o preço justo.

3. **A Guarda 1 dependia do horizonte de projeção.** A deriva era
   `|inclinação| × N`, com `N` vindo da tela. **13 dos 120** trocavam de veredito
   entre `N = 5` e `N = 10`, e o preço justo ia junto: a AZZA3 de R$ 16,11 para
   R$ 57,48 (3,57x), a CYRE3 de R$ 8,53 para R$ 3,40 (0,40x). O horizonte
   sozinho, com a guarda estável, move o valor em cerca de 2%.

4. **A tela usava um horizonte que nenhuma decisão declara.** `ValuationSettings`
   injetava `projectionYears: 5` contra os 10 do núcleo, da decisão 25 e de todas
   as rodadas de validação — e um teste do núcleo afirma os dez. O número que o
   usuário via nunca foi o número validado.

5. **O escudo fiscal e o NOPAT usavam convenções tributárias diferentes.** O
   `nopat` da fonte é, em **4.572 de 4.572** exercícios do cache, exatamente
   `EBIT × 0,66` — alíquota estatutária. O escudo do WACC usava a efetiva do
   exercício, com mediana de 19,2% entre os avaliados, nula em 9 deles e no teto
   de 50% em outros 9.

6. **O custo da dívida era o mesmo para todo mundo que saía da banda.** A razão
   `despesa financeira ÷ dívida bruta` caía fora da faixa defensável em **70 dos
   120**, e os 70 recebiam `Rf + 10%`, que é o teto: a WEGE3, de caixa líquido,
   ficava com o custo de dívida de uma empresa em pré-falência.

7. **A Porta 1 barrava a financeira pelo que define o negócio dela.** Exigia
   setor financeiro **e** dívida bruta nula. A justificativa registrada citava a
   RENT3 classificada como `Finance` — mas isso é a taxonomia da **listagem**, e
   a porta compara contra a do **perfil**, onde a RENT3 vem como
   `consumo-ciclico`. Conferido: os 28 ativos com `servicos-financeiros` no
   perfil são bancos, seguradoras, resseguradora, corretora, bolsa e serviços
   financeiros diversos, e cinco caíam para a via da firma por terem passivo
   oneroso.

Havia ainda dois defeitos que não mudam preço nenhum e mudam o que o trabalho
afirma: as bandas de cenário não deslocavam a taxa de desconto **terminal**, que
é a que desconta metade a quatro quintos do valor — a banda saía em −11,2% /
+12,9% onde deveria sair em −19,8% / +30,9% —, e o rastro de auditoria descrevia
a projeção com crescimento e desconto **constantes**, escrevendo para o ano 10
um fluxo 2,45x maior que o usado e um fator de desconto 1,21x maior.

## Decisão

**1. A ponte por papel divide pela contagem que forma a cotação, e na
divergência adota a maior das duas.**

Quando as duas contagens publicadas concordam dentro da banda de conciliação —
o caso de 102 dos 119 avaliados —, o divisor é `N_ponte = VM ÷ P_mkt`, o que faz
o potencial virar `E ÷ VM − 1`: a comparação entre o capital próprio que o
modelo apura e o que o mercado atribui, sem contagem de ação alguma no caminho.

Quando divergem além dela, **nada no dado arbitra**, e isso foi medido, não
suposto:

- `N = lucro ÷ LPA` é **tautológico** para esta pergunta — os dois campos vêm
  das mesmas demonstrações, então ele só pode confirmar a contagem do exercício,
  e confirma em todos os divergentes;
- o valor de mercado da fonte é quase sempre `contagem corrente × preço` e
  herda o defeito dessa contagem: o MILS3 chega com R$ 760 mil de capitalização
  contra R$ 9,6 milhões de volume mediano por pregão;
- o `enterpriseToEbitda` publicado seria independente, mas erra por mais de 2x
  em 12% dos ativos cujas duas contagens **concordam** — o piso de ruído dele —
  e chega a discordar entre classes da mesma empresa: SAPR4 acusa 3,01 e
  SAPR11, 1,47;
- a série de preços não denuncia ação societária, porque o `close` da fonte já
  vem ajustado por ela: não há salto nenhum em dez anos, em ativo nenhum.

Sem árbitro, decide **o sentido do erro**. Divisor pequeno demais infla o preço
justo e produz sinal falso de desconto — o pior sentido possível, e o mesmo
argumento que a Porta 0 usa para justificar o corte de liquidez. Divisor grande
demais deprime o preço justo, e o erro que sobra é o conservador. Na
divergência, portanto, **adota-se a maior das duas**, declarando no resultado
qual foi e por quanto divergiam.

**A contagem do exercício continua onde sempre esteve certa**, que é a
reconstituição contábil: `VPA × N_exercício` reproduz o patrimônio publicado em
**4.461 de 4.462** exercícios do cache, e a contagem corrente o reproduz em
**nenhum**. ROIC, Φ, crescimento e retenção seguem medidos por ela.

**2. Exercício de prejuízo entra na série de retorno, com o sinal que tem.**
Ausência de lucro publicado continua fora — falta de dado não é retorno nulo.

**3. A deriva da tendência é medida na janela do ciclo**, oito exercícios, e não
no horizonte de projeção. Os dois lados da razão de dominância passam a falar do
mesmo intervalo.

**4. O horizonte da tela volta a dez anos**, igual ao do núcleo e ao da
decisão 25.

**5. O escudo fiscal do WACC usa a alíquota marginal estatutária de 34%**,
limitada pela capacidade de usá-la: com `EBIT < despesa financeira`, a parcela
excedente não abate imposto no exercício, e o escudo vale
`34% × min(1, cobertura)`. É o tratamento de Damodaran. A efetiva continua sendo
medida e é declarada quando se afasta mais de 10 p.p. da estatutária.

**6. Fora da banda, o custo da dívida vem de classificação sintética por
cobertura de juros**, na forma da tabela de Damodaran, com o prêmio confinado ao
mesmo teto de 10 p.p. Dentro da banda, o observado continua valendo: é o dado da
própria empresa.

**7. A Porta 1 roteia pelo setor.** A exigência de dívida nula sai.

**8. As bandas de cenário deslocam as duas taxas de desconto**, e o piso que
protege a perpetuidade passa a proteger a **terminal**, que é a que entra
naquele quociente.

**11. Migração de via que falha vira recusa nomeada, não número sem conteúdo.**
Quando a participação do capital próprio no valor da firma cai abaixo do corte e
a via do acionista não se aplica, o ativo deixa de ser avaliado com o motivo
escrito — o que a decisão 25 exige de toda saída. Publicar o resíduo
contradiria a própria afirmação que motiva a pós-condição: a AMER3 saía a
R$ 0,20 em dez anos e R$ 1,47 em cinco, um fator de 7,35 vindo só da forma da
curva de desconto.

**9. O rastro de auditoria descreve a conta que foi feita** — taxa, crescimento
e retenção ano a ano, fator de desconto acumulado, e a fórmula do terminal que
foi efetivamente aplicada, que com retorno neutro não tem *spread* de Gordon.

**10. A retenção sai do retorno do fluxo-base, não do ciclo por princípio.**
`ROIC_base = retorno_atual × fator`: normalizado sem saturar dá o retorno do
ciclo, saturado dá o que a saturação impôs, não normalizado dá o corrente. Usar
o ciclo sobre base não normalizada exigia menos reinvestimento do que a empresa
precisa — medido na AZZA3, 17% a mais de valor da firma.

## Consequências aceitas

- **Todo preço justo muda de novo, e alguns muito.** É a segunda troca de escala
  depois da decisão 25. A AZZA3 sai de +224,9% para −27,6% no horizonte da tela;
  a B3SA3 de −81,2% para −74,7%; a MILS3 de −50,6% para −86,8%. Números em
  capturas, telas e no texto precisam ser refeitos mais uma vez.

- **A alavancagem alta ficou mais sensível, e a MOVI3 é o caso a olhar.** O
  escudo cheio derruba o WACC de quem tem 87% de dívida na estrutura, e o
  potencial dela **subiu**. O preço justo de uma empresa cuja dívida líquida
  consome quase todo o valor da firma é resíduo de subtração, e é isso que a
  pós-condição de `equityShare` existe para declarar — com o divisor corrigido
  ela deixou de disparar, o que torna o caso menos visível e não menos frágil.
  Fica registrado como pendência aberta.

- **A dependência do horizonte não foi eliminada, foi reduzida a uma ordem de
  grandeza defensável.** O decaimento linear da taxa e do crescimento é
  parametrizado por `N`, de modo que trocar 5 por 10 ainda muda a duração da
  transição. O que saiu foi a troca de **veredito** de uma guarda estatística;
  o que fica é uma diferença de forma da curva, da ordem de 2% num ativo típico
  e de até 23% em quem tem *spread* grande entre a taxa corrente e a de
  equilíbrio.

- **A regra da maior contagem é conservadora por escolha, e erra nessa direção
  em alguns ativos.** Onde a contagem do exercício é a estagnada e a maior — a
  B3SA3, com 7,5 bilhões contra 5,05 bilhões, e a RENT3, com 2,0 bilhões contra
  1,12 —, o preço justo sai deprimido por esse fator. O aviso traz as duas
  candidatas e a razão entre elas, para que quem confere saiba o tamanho da
  ressalva. A alternativa era escolher por um árbitro que a medição mostrou não
  existir, e errar às vezes no sentido de inventar desconto.

- **A divergência é limitação de fonte, e passa a estar declarada como tal.** A
  brapi publica duas contagens de papéis que discordam além de uma ação
  societária plausível em 85 de 359 ativos com as duas preenchidas, e nenhum
  campo do próprio dado resolve o conflito. Resolver isso de verdade exige outra
  fonte para a base societária — CVM ou B3 —, e é trabalho de camada de dados,
  não de motor.

- **A classificação sintética herda a contaminação que veio consertar.** A
  cobertura de juros usa a mesma despesa financeira que carrega arrendamento e
  variação cambial, e por isso subestima a cobertura de quem tem IFRS 16
  relevante. O erro que ela substitui era pior: nenhuma discriminação entre a
  empresa de caixa líquido e a alavancada.

- **A alíquota de 34% não distingue instituição financeira, que paga 45%.** Não
  há efeito prático porque a Porta 1 as roteia para a via do acionista, que
  desconta ao Ke; quem levar o WACC para lá precisa tratar o caso.

- **Duas críticas do relatório externo foram recusadas com medição.** A de que o
  motor usa "o CDI diário de pico como taxa livre de risco" ignora a estrutura a
  termo que a decisão 25 introduziu: o desconto vai de 14,09% no primeiro ano a
  9,40% de taxa livre de risco terminal, e a perpetuidade não desconta a 18%. E
  a de que `maxGrowthStdError` barra o crescimento de 47,5% dos ativos atribui
  ao parâmetro errado: o bloqueio alcança 55,8%, mas a precisão responde por 22
  dos 67 casos e a discordância entre estimadores pelos outros 45. As duas ficam
  registradas na auditoria cruzada, com os números.

- **O nível conservador da distribuição não foi tratado, e não é defeito.** A
  mediana de potencial negativa é consequência declarada da estrutura a termo e
  do terminal neutro, aceita pelas decisões 25 e 27. Mexer nisso é decisão nova.

- **A alternativa descartada para o item 1** era a do relatório externo: adotar
  sempre `sharesOutstanding` e eliminar o recuo para a contagem do exercício.
  Recusada por duas medições. A contagem do exercício é a única que reconstrói o
  patrimônio publicado, e removê-la destruiria ROIC, Φ e crescimento; e o valor
  de mercado da fonte é corrompido em pelo menos quatro ativos, onde seguir a
  regra sem ressalva levaria o MILS3 a um potencial de mais de 240.000%.

  A segunda alternativa descartada foi um **teste de plausibilidade da
  capitalização** — exigir que o valor de mercado valha ao menos vinte pregões
  de volume mediano. Ele separa bem os quatro casos mais grosseiros (MILS3,
  COGN3, ANIM3 e CPLE3, de 0,1 a 16,1 pregões, contra mediana de 251 no
  universo), mas **deixa passar a SAPR**, cuja capitalização de 87,8 pregões é
  perfeitamente plausível e ainda assim está três vezes abaixo da escala do
  balanço. Um teste que resolve quatro casos e falha no quinto não é um árbitro;
  é mais um limiar a calibrar. A regra da maior contagem resolve os cinco pela
  mesma afirmação.

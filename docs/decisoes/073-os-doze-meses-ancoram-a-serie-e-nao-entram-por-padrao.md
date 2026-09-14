---
numero: 73
titulo: Os doze meses ancoram a série inteira, recusam buraco, e não entram por padrão
status: aceita
origem: parecer
data: 2026-09-14
afeta:
  - packages/equisim_core/lib/src/services/cvm/trailing_twelve_months.dart
  - packages/equisim_core/lib/src/services/cvm/cvm_series.dart
  - packages/equisim_core/test/trailing_twelve_months_test.dart
  - packages/equisim_core/test/cvm_series_test.dart
  - docs/validacao/cvm_trimestral.md
substitui: []
---

## Contexto

A §0.2 do plano mediu que o potencial do motor é **lento**: autocorrelação de
posto de +0,666 entre coortes anuais, porque entre duas DFPs o preço justo fica
congelado. A CVM publica ITR a cada trimestre, com defasagem mediana de 40 dias.

Mas o motor presume **um exercício por ano** em quase toda guarda — retorno
`lucro_t ÷ base_{t−1}`, crescimento por diferença anual, janela de ciclo, oito
exercícios na Porta 0. Pôr trimestres na série faria um ponto a seis meses do
anterior entrar como se fosse um ano.

## Decisão

**A série inteira é ancorada no documento mais recente publicado.** Se ele é o
ITR de 30/06, todos os pontos viram doze meses terminados em 30/06 de cada ano
— `DFP_{y−1} + acumulado_y − acumulado_{y−1}`, com o estoque na data do
trimestre. Todos a exatamente um ano de distância; toda guarda anual continua
valendo.

Três recusas, todas medidas:

1. **Soma de períodos que não fecham** devolve nulo: o acumulado tem de começar
   no dia seguinte ao fim do exercício anual, o comparativo onde o exercício
   começou, e os dois acumulados têm de ter o mesmo comprimento.
2. **Série com buraco recua inteira para a âncora de DFP.** Em 14/09/2026 a CVM
   **não publica o ITR de 2025** — o diretório lista 2017 a 2024 e 2026 —, e a
   primeira versão montou junho/24 seguido de junho/26. As guardas leram dois
   anos como um: a QUAL3 foi de −22% a **+908%**, e a mediana do movimento no
   universo foi de **25,3%**.
3. **A mescla com o mercado nunca olha para a frente**: um ponto de junho usa o
   exercício de mercado encerrado até junho, e não o de dezembro do mesmo ano.

E a decisão que importa: **a série ancorada fica disponível, e não é o
padrão.** O motor continua avaliando pela série de DFPs.

## Consequências aceitas

**A razão de não ser padrão é que o efeito é grande e o valor não está
provado.** Medido em 04/09/2024, quando os ITRs são contíguos e 349 das 371
séries ancoram em trimestre: a mediana do `|Δ potencial|` entre a série anual e
a ancorada é de **9,8%**, 51 ativos se movem mais de 10 p.p., e a correlação de
postos entre as duas ordenações é de **0,816** — contra **0,968** entre a
montagem só de mercado e a anual da CVM.

**Não é defeito da soma.** Conferido no caso mais extremo, CSNA3 (+136% →
−47%): o lucro de doze meses terminado em junho/23 é **prejuízo de R$ 0,10 bi**,
onde a série de dezembro tinha +R$ 2,17 bi em 2022. A série ancorada vê a virada
do ciclo seis meses antes, e as guardas reagem a isso.

**É o motor sensível à janela**, e se essa sensibilidade é informação ou ruído é
exatamente a pergunta da coorte trimestral — C1c, na Fase 2. Pôr a série por
padrão antes dela seria trocar a ordenação de metade do universo sem evidência
de que a nova ordena melhor.

**Hoje, com o ITR de 2025 ausente na fonte, a série ancorada recua para DFP em
todo o universo** — o comportamento é idêntico ao anual até a CVM republicar o
arquivo.

---
numero: 97
titulo: A coorte forma preço, contagem e valor de mercado na base de ações da data, e o aplicativo declara a cobertura que a faixa mediu nessa montagem
status: aceita
origem: voce
data: 2026-09-15
citacao: >
  Seus itens de escopo para esta rodada são C1d, C1c e C3. [...] Caso haja
  necessidade da inserção de outro item na lista, não hesite em fazer.
afeta:
  - tool/backtest_valuation.dart
  - tool/coortes/base_da_data.dart
  - tool/coortes/deslistadas.dart
  - tool/cvm/codigos_fca.dart
  - tool/b3_deslistadas_contagem.dart
  - tool/b3_ponte.py
  - tool/b3_complemento_baixar.py
  - tool/ponte_por_papel.dart
  - tool/cobertura_banda.py
  - test/tool/base_da_data_test.dart
  - assets/validacao/banda_calibrada.json
  - lib/presentation/valuation/valuation_page.dart
  - test/data/calibrated_band_asset_test.dart
  - test/presentation/calibrated_band_card_test.dart
  - docs/validacao/backtest_trimestral.json
  - docs/validacao/ponte_por_papel.md
  - docs/validacao/cobertura_banda.md
  - docs/validacao/cobertura_banda_trimestral.json
substitui: []
---

## Contexto

O item C3 do plano: a validação não exercitava a ponte por papel. A coorte
reconstruía o valor de mercado como `contagem do exercício × preço da coorte`, e
com a mesma contagem como corrente a razão de unidade saía 1 e as duas
candidatas a divisor, iguais, por construção (limitações §3.5).

**Levantar a peça achou um defeito maior que o item.** O preço da coorte das
listadas vinha da fonte de mercado, que publica o fechamento **ajustado por todo
evento de ações até hoje**, e a contagem do exercício está na base daquele ano.
A MGLU3 de 30/09/2020 entrava a R$ 212,38, e o fechamento do dia foi R$ 84,95: o
desdobramento de 4 para 1 de outubro de 2020 e o grupamento de 10 para 1 de 2024
levaram o preço à base de hoje. O valor de mercado saía errado pelo produto dos
eventos posteriores, no potencial e no book-to-market igualmente; e o volume da
fonte, que não é ajustado, dava à Porta 0 um financeiro errado pelo mesmo fator —
a IFCM3 de 2022 com R$ 4,4 bilhões por dia, contra R$ 4,6 milhões no COTAHIST.
Medido: 697 de 2.247 observações das listadas estavam fora da base da data por
mais de 2%, e 386 por mais de 1,5 vez.

**E o defeito olhava para a frente.** Companhia que desdobra depois costuma ser a
que subiu, e a que agrupa, a que caiu: o defeito a fazia parecer barata e cara,
respectivamente, na data da coorte.

## Decisão

1. **A série de preço da listada vai à base da data**
   (`tool/coortes/base_da_data.dart`): a da fonte vezes o fator
   `fechamento bruto ÷ fechamento da fonte`, medido no último pregão do COTAHIST
   até a data e no mesmo dia da fonte. O fator é medido, e não reconstruído dos
   eventos do registro da B3, que repete evento — a BBAS3 de 2018 tem fator 2 no
   preço e produto 8 no registro. O volume é refeito do financeiro do COTAHIST.
   Sem pregão a até dez dias, não há preço da data e a observação sai, como já
   era nas deslistadas.
2. **O ticker renomeado é encadeado pelos códigos da companhia**: os da ponte do
   universo, os que a FCA declara e as espécies da raiz de cada um. A BHIA3 de
   2020 é o pregão da VVAR3.
3. **A contagem da data vem do Formulário de Referência** (A3.4), agora também
   para as listadas, e entra como contagem corrente **e** como a contagem oficial
   que arbitra o divisor — o papel que o registro da B3 tem no aplicativo.
4. **O valor de mercado é o da companhia, espécie a espécie**: ordinárias e
   preferenciais pela divisão do quadro de capital social, cada uma ao fechamento
   bruto do papel mais negociado dela, e a espécie sem pregão pelo preço da outra.
   Nas deslistadas também. É a convenção em que a unit mede as ações dela.
5. **O `mercado` fica como estava**, para reproduzir as medições de 11/09/2026,
   com o defeito declarado no cabeçalho.
6. **O pacote da faixa calibrada sai da montagem corrigida** — coortes
   trimestrais, com as deslistadas da ponte ampliada no C1d —, e **o aplicativo
   passa a declarar a cobertura que ela mediu**. Na montagem corrigida, a faixa
   de 80% cobriu 74,9% em 12 meses e 73,0% em 36, fora da amostra. O cartão diz
   "8 de cada 10" só quando a cobertura medida fica a até 5 pontos da nominal; do
   contrário, diz a cobertura e que a faixa não está calibrada. O teste do pacote
   deixa de exigir os 5 pontos e passa a exigir que a cobertura declarada seja a
   que `tool/cobertura_banda.py` gravou.

## Consequências aceitas

**O instrumento mede outra coisa, e toda leitura anterior das coortes do
aplicativo carrega o defeito.** Na mesma execução e nas mesmas 480 observações
de 30/09, o IC do book-to-market em 36 meses cai de 0,255 para 0,151, e o do
potencial, de 0,179 para 0,085; em 12 meses, o do B/M vai de 0,147 (`t` 4,03) a
0,069 (`t` 1,57). **O defeito inflava os dois sinais de valor, e o B/M mais.** O
potencial condicionado ao B/M quase não muda — 0,052 para 0,028 em 36 meses —, e
a conclusão da §0 do plano de que o motor não acrescenta ao B/M continua.

**O contrafactual reproduz a rodada anterior**: das 818 avaliações de 30/09 que a
montagem antiga produz nas duas execuções, 803 são idênticas e 15 diferem menos de
0,2%, pela reingestão da CVM com o ITR de 2025.

**O R2 deixa de estar atingido.** A faixa calibrada fechava os 5 pontos sobre a
montagem com o defeito. Na corrigida, a de 80% em 12 meses vai de 0,76 a 8,2
vezes o preço justo — era de 0,64 a 10,7 — e cobre menos: 84,8/74,9/49,1% em 12
meses e 83,6/73,0/47,0% em 36. Cinco variantes exploratórias — por terço de
potencial, com mínimo de coortes, só setembro — e uma recalibragem aninhada,
fixada por escrito antes de rodar, não fecharam os dois horizontes (ver
[cobertura_banda.md](../validacao/cobertura_banda.md) §8). **Mostrar a faixa com
a cobertura medida é a escolha, e é reversível**: as alternativas eram o pacote
da montagem com defeito, que afirma uma cobertura que não se sustenta, ou tirar o
cartão, e a única incerteza que o aplicativo mostraria seriam os cenários, que
são sensibilidade e cobriram de 8% a 13%. O critério do R2 continua sendo o de
5 pontos; o que muda é o que o pacote precisa cumprir para ir ao aplicativo.

**A razão de unidade inferida do valor de mercado falha quando as espécies
negociam a preços diferentes.** Contra a composição que a FCA declara, ela acerta
141 de 220 observações de unit — a SANB11 em 31 de 31, a ENGI11 em 4 de 31, a
BRBI11 em nenhuma —, e unit com a razão errada é avaliada por ação. O aplicativo
de hoje passa nas nove units (decisão 61), mas a fragilidade é a mesma: virou o
item B16.

**A contagem do Formulário de Referência não é a oficial da B3.** Bate a 1% em 281
de 291 emissores na data em que as duas existem; nas dez que divergem — TOKY por
20 vezes, AGXY por 12,8 —, o divisor da coorte herda o erro.

---
numero: 28
titulo: Precedência do ciclo em commodity, saturação do fator de base e filtro de saúde no moat
status: aceita
origem: orientador
data: 2026-09-07
citacao: >
  Em setores de commodities e cíclicos pesados (Materiais Básicos, Papel e
  Celulose, Petróleo e Mineração), a Guarda 1 não deve impedir a normalização;
  para esses setores, a Guarda 3 (Reversão ao Ciclo) tem precedência
  obrigatória. Impor um teto de saturação simétrico no fator multiplicador da
  base: f = clip(retorno_ciclo / retorno_atual, 0,33, 3,00). Elevar o limiar de
  capital externo do Moat para Phi <= 0,60 para acomodar concessões e estrutura
  de bancos; adicionar um filtro de saúde operacional mínima: reprovar no Moat
  qualquer ativo cujo Lucro/EBITDA tenha recuado mais de 50% no triênio recente.
afeta:
  - packages/equisim_core/lib/src/services/valuation/cyclical_sectors.dart
  - packages/equisim_core/lib/src/services/valuation/growth_guards.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/lib/src/usecases/prepare_valuation_inputs.dart
  - tool/validation/out_of_sample.dart
  - docs/refinamento-do-valuation.md
substitui: []
---

## Contexto

A terceira rodada de validação fora da amostra
([decisão 27](027-recalibragem-apos-a-primeira-validacao.md)) instrumentou as
guardas e, com isso, mediu três coisas que antes eram suposição — registradas na
§13 do [refinamento](../refinamento-do-valuation.md):

1. **A Guarda 1 lia a perna de alta do ciclo como tendência estrutural.** A
   SUZB3 tinha `Φ = 0,77`, abaixo do limiar de comparabilidade, e ainda assim
   não normalizava: o que a segurava era a tendência, com 41,5% de retorno
   corrente contra 18,4% de mediana do ciclo. Saía a +259,1% de potencial.

2. **O fator de normalização não tinha teto.** `f = ciclo / atual` explode
   quando o exercício corrente tem retorno próximo de zero, e o DCF é homogêneo
   de grau 1 no fluxo-base. A MBRF3 recebeu 21,4x e saiu a +406,1%; FESA4 e
   DXCO3 já vinham recebendo dez vezes antes desta rodada.

3. **`Φ ≤ 0,35` era o que prendia as franquias, e premiava quem encolhe.** EGIE3
   caía com 0,58 e ITUB4 com 0,50 — concessão e banco acusam Φ alto por
   definição do negócio. Do outro lado, a QUAL3 passava com `Φ = 0,01`, não por
   financiar crescimento por dentro, mas por não haver crescimento nenhum a
   financiar: o lucro dela caiu de R$ 0,10 bi em 2022 para R$ 0,02 bi em 2025.

## Decisão

**1. Em setor de commodity e cíclico pesado, a Guarda 3 tem precedência sobre a
Guarda 1.** Quando o exercício corrente destoa do ciclo, a base é normalizada
mesmo que a tendência do retorno domine a reversão à média. O critério é
setorial e vem de fora do dado: em commodity o preço reverte à média por
definição do produto, e nenhuma sequência de anos de alta muda isso.

O recorte é `materiais-basicos` por inteiro — papel e celulose, siderurgia,
mineração, petroquímicos, fertilizantes — mais os subsetores de exploração e
refino de petróleo, que a fonte publica sob a chave `energia`. **A chave
`energia` não entra inteira**: ela reúne 28 concessionárias de energia elétrica,
cuja natureza é o oposto da de uma commodity. A separação exige o subsetor, que
passou a ser carregado até a cascata.

**2. O fator de normalização é saturado em `[0,33; 3,00]`.** A banda é simétrica
em razão, não em diferença: normalizar para cima e para baixo custa o mesmo,
senão o teto vira viés de direção. É a resposta explícita à pergunta que a
[`normalizacao_fluxo_base.md`](../validacao/normalizacao_fluxo_base.md) fazia
sobre `τ` — quanto se autoriza um único exercício a mover a avaliação inteira —
e que a decisão 25 deixou sem resposta ao remover a banda.

**3. O *moat* passa a exigir saúde operacional, e afrouxa o corte de capital
externo.** `Φ ≤ 0,60` acomoda concessão e banco. Em contrapartida, reprova quem
teve **lucro ou EBITDA recuando mais de 50% no triênio recente** — a pior das
duas quedas, medida do exercício corrente contra o de três anos antes. Vantagem
competitiva é afirmação sobre o futuro do retorno excedente; quem encolheu pela
metade não a sustenta, por mais alta que a mediana da janela ainda esteja.

## Consequências aceitas

- **Os dois casos extremos foram resolvidos, e são verificáveis.** SUZB3 saiu de
  +259,1% para **+16,7%**, com o preço justo caindo de R$ 168,38 para R$ 54,73;
  MBRF3 saiu de +406,1% para **−28,9%**. A QUAL3 perdeu a vantagem residual, com
  queda medida de 83,2% no triênio, e a EGIE3 a ganhou.

- **A QUAL3 continua com o maior potencial do universo, agora em +477,3%.** O
  filtro de saúde tirou dela o *moat*, que é o que a determinação pediu, e **não**
  tocou na avaliação: a mediana de ROIC de oito anos ainda carrega os exercícios
  bons de antes da queda, e é dela que o número sai. Se o mesmo sinal de
  deterioração deve alimentar a Porta 0 ou a janela do ciclo é pergunta aberta,
  não resolvida aqui.

- **O ITUB4 continua fora da exceção, e não por calibragem.** A fonte não publica
  `netIncome` para ele em **nenhum** dos dezesseis exercícios; sem lucro não há
  série de retorno, e sem retorno do ciclo o *moat* não tem o que preservar.
  Elevar Φ para 0,60 removeu o segundo impedimento dele e deixou o primeiro, que
  é de cobertura de dado. A avaliação sai pelo LPA publicado, por caminho
  alternativo — e com o freio de reinvestimento desligado, o que o resultado já
  declarava.

- **Um recorte setorial é uma lista mantida à mão.** Ela vive em
  `CyclicalSectors`, é declarada e não inferida, e envelhece com a taxonomia da
  fonte. É a mesma natureza do `config/distressed_tickers.json` que a decisão 25
  aceitou: informação que a fonte não fornece em formato utilizável e que alguém
  precisa manter.

- **A saturação torna conservador o preço justo de quem a toca, e isso é
  declarado no resultado.** Quatorze ativos foram confinados na rodada de
  consolidação, onze no teto e três no piso. O aviso traz o fator bruto que teria
  sido aplicado, para que o corte não seja invisível.

- **O limite é de política, não de estatística.** Não há teste que diga que 3,0x
  é onde um exercício deixa de ser atípico — a §2 da
  `normalizacao_fluxo_base.md` já mostrava que os dados não sustentam essa
  leitura para `τ`. O que a banda afirma é quanta autoridade um único exercício
  tem sobre a avaliação inteira, e afirmar isso explicitamente é melhor que
  deixar o quociente decidir.

- **A alternativa descartada para o item 1** era mexer no `minTrendDominance`
  para todos os setores. Recusada porque o teste de tendência **está certo** onde
  há tendência de verdade: numa empresa de crescimento, o nível corrente é o novo
  patamar, e afrouxar o limiar globalmente destruiria essa leitura para consertar
  um problema que é de commodity.

- **Esta decisão não abre reconstrução**, e opera dentro do `afeta` da
  [decisão 25](025-reconstrucao-do-motor-de-avaliacao.md), cuja
  `postura: reconstrucao` segue aberta.

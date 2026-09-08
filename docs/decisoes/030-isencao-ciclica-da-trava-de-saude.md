---
numero: 30
titulo: Setor cíclico é isento da trava de saúde na Porta 2a, e não no moat
status: aceita
origem: orientador
data: 2026-09-07
citacao: >
  Os ativos pertencentes ao recorte de CyclicalSectors ficam ISENTOS da trava de
  saúde operacional na Porta 2a. Em commodities, uma queda de lucro > 50% entre
  o pico de 2022 e o vale de 2025 decorre da oscilação do preço internacional do
  insumo, e não de deterioração estrutural da empresa. A trava permanece 100%
  ativa para todos os demais setores. Para o Moat, a trava de saúde operacional
  continua barrando qualquer ativo com queda > 50% no triênio, inclusive
  cíclicos.
afeta:
  - packages/equisim_core/lib/src/services/valuation/growth_guards.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/test/valuation_guards_test.dart
  - tool/validation/out_of_sample.dart
  - docs/refinamento-do-valuation.md
substitui: []
---

## Contexto

A [decisão 29](029-saude-operacional-na-porta-2a.md) levou o filtro de saúde
operacional para a Porta 2a e resolveu a QUAL3, que caiu de +477,3% para +68,0%.
A §15.2 do [refinamento](../refinamento-do-valuation.md) registrou, no mesmo ato,
o efeito colateral medido: **quatro dos treze ativos alcançados pela trava eram
cíclicos pesados** — VALE3, GGBR4, GOAU4 e DXCO3 —, e a queda de mais de 80% que
eles acusavam era do pico de 2022 para o vale de 2025.

Isso é oscilação do preço internacional do insumo, não quebra de modelo de
negócio. E colidia com a decisão anterior: a
[decisão 28](028-travas-de-ciclo-saturacao-e-saude.md) tinha dado à Guarda 3
precedência sobre a Guarda 1 em commodity **justamente** para deixar a reversão
ao ciclo operar; uma trava que morde só na subida a desfazia no vale, que é onde
ela mais importa. A VALE3 saiu de −14,5% para −70,3% de potencial, e a GGBR4
para −92,7%.

## Decisão

**Na Porta 2a, o recorte de `CyclicalSectors` é isento da trava de saúde
operacional.** Em commodity a base converge ao ciclo nos dois sentidos — para
baixo no topo e para cima no vale —, limitada apenas pela saturação em
`[0,33; 3,00]`, que continua valendo igual.

**Fora do recorte, a trava permanece integral.** Consumo, saúde, educação,
serviços e varejo seguem com o teto em 1,00 quando o resultado recuou mais de
50% no triênio. É o que impede que uma empresa com quebra de modelo de negócio
tenha o fluxo inflado até a mediana de um passado que não volta.

**No *moat* não há isenção alguma.** A regra da decisão 28 fica intacta: nenhum
ativo com queda acima de 50% no triênio recebe retorno excedente na
perpetuidade, commodity em vale inclusive. As duas guardas fazem perguntas
diferentes — a Porta 2a pergunta qual é o nível normal do fluxo, o *moat*
pergunta se há excedente que sobrevive para sempre —, e um vale de ciclo responde
"sim" à primeira e "não" à segunda.

## Consequências aceitas

- **Os quatro casos foram restaurados, e a lista do *moat* não mudou.** A VALE3
  voltou a −14,5% e a GGBR4 a −73,6%; DXCO3 e KLBN11 acompanharam. A vantagem
  residual continua em sete ativos — ABEV3, BBSE3, EGIE3, LEVE3, SAUD3, VBBR3 e
  WEGE3 —, o que é a verificação de que a isenção não vazou para onde não devia.

- **A GOAU4 saltou para +127,4%**, com fator de 2,36x sobre um exercício de vale.
  É o comportamento pretendido levado ao limite: a *holding* da Gerdau tem a
  mesma rentabilidade de ciclo da controlada e um preço muito mais deprimido.
  Fica declarado como o caso de maior efeito da isenção, para quem for conferir.

- **Três nomes de commodity continuam travados, e não por decisão de método.** A
  BRAP4, a FESA4 e a UNIP6 seguem com o teto em 1,00 porque **a fonte não
  devolve perfil para elas**: `sectorKey` e `industry` vêm nulos. O padrão é
  sistemático — a brapi classifica a classe ON e deixa a PN sem perfil, e as
  irmãs BRAP3, FESA3 e UNIP3 vêm todas como `materiais-basicos`. São **17 dos
  120 avaliados** sem setor, e 90 dos 373 perfis do cache.

  O efeito passa da isenção: `sectorKey` alimenta também a Porta 1, de modo que
  ITSA4, SANB4, BRSR6 e PINE4 nunca podem acionar a porta de instituição
  financeira. Resolver o perfil pela raiz do ticker — `BRAP4 → BRAP3` — é o
  remédio evidente, e **não foi feito aqui**: é mudança na camada de dados que
  altera o roteamento de via, não a aplicação desta determinação.

- **A distribuição recuperou parte do que a decisão 29 tinha deslocado**, sem
  voltar ao ponto anterior: a mediana foi de −46,0% para −44,8% e o p75 de −19,5%
  para −14,5%. O que sobra de conservadorismo é o dos nove ativos não cíclicos
  que continuam travados, e é deliberado.

- **A regra depende de uma lista mantida à mão**, e agora ela decide mais coisa:
  além da precedência da Guarda 3, decide quem escapa da trava de saúde.
  `CyclicalSectors` envelhece com a taxonomia da fonte, e um setor que deveria
  estar lá e não está passa a ser penalizado duas vezes.

- **A alternativa descartada** era medir a queda contra a mediana do ciclo em vez
  do exercício de três anos antes, o que distinguiria "caiu do pico" de "caiu do
  normal" sem precisar de recorte setorial. Recusada por ora porque mudaria o
  significado do corte de 50% e exigiria recalibrá-lo — a isenção setorial
  resolve o caso medido com uma afirmação que já estava registrada na decisão 28.

- **Esta decisão opera sob preservação.** A [decisão 25](025-reconstrucao-do-motor-de-avaliacao.md)
  está `cumprida` desde 07/09/2026, e a superfície do motor de avaliação voltou a
  exigir decisão registrada para mudança de método. Esta é essa decisão.

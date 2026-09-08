---
numero: 33
titulo: O prêmio de crédito passa a ter dois direcionadores arbitrados, e a base acionária ganha guarda de consistência
status: aceita
origem: voce
data: 2026-09-08
citacao: >
  Analise o JSON de auditoria anexo e corrija as seguintes inconsistências
  estruturais no código do motor de valuation. [...] As correções acima não
  devem ser tratadas como exceções condicionais por ticker (como
  `if ticker == 'X'`), mas sim como regras genéricas e universais do pipeline:
  validação automática de consistência da base acionária entre exercícios,
  mapeamento estrutural de classes de Units pela B3 e despacho de modelos
  financeiros indexados pela classificação setorial da empresa.
afeta:
  - packages/equisim_core/lib/src/entities/fundamentals.dart
  - packages/equisim_core/lib/src/services/valuation/cost_of_capital.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/test/usecases_test.dart
  - packages/equisim_core/test/valuation_guards_test.dart
  - packages/equisim_core/test/valuation_test.dart
  - tool/deep_audit.dart
substitui: []
---

## Contexto

Uma auditoria do rastro exportado pelo próprio aplicativo — 18 avaliações,
`docs/validacao/` — apontou nove inconsistências. **Cinco não se confirmaram
contra o dado**, e a conferência de cada uma está na §7 da
[auditoria cruzada](../validacao/auditoria_cruzada_valuation.md). Duas se
confirmaram, e são o objeto desta decisão.

**1. O prêmio de crédito estava errado, e errado contra as empresas mais
sólidas.** A [decisão 31](031-escala-do-preco-tributo-e-invariancia-das-guardas.md)
trocou a razão observada `despesa financeira ÷ dívida bruta` pela classificação
sintética por **cobertura de juros**, porque a razão caía fora da banda
defensável em 70 dos 120 avaliados. A troca resolveu metade do problema e
carregou a outra metade: a cobertura tem a **mesma despesa contaminada** no
denominador.

Medido em 08/09/2026 sobre os avaliados:

| Ativo | Cobertura | Dív. líq./EBITDA | Prêmio pela cobertura |
|---|---:|---:|---:|
| ABEV3 | 3,77x | **−0,57x** (caixa líquido) | 2,4 p.p. |
| WEGE3 | 3,68x | **−0,30x** (caixa líquido) | 2,4 p.p. |
| RADL3 | 1,50x | **0,70x** | 7,5 p.p. |
| SAPR11 | 0,76x | **0,60x** | **10,0 p.p.** (o teto) |
| AZZA3 | 1,26x | **1,17x** | 7,5 p.p. |

Saneamento regulado com 0,60x de alavancagem pagando o teto de dez pontos, e
empresa de caixa líquido pagando dois, não é ordenação de crédito — é o eco da
contaminação. Na AZZA3 isso produzia custo de dívida de 21,6% e WACC inicial de
18,20%.

**2. A contagem de ações de um exercício pode vir quebrada sem que nada
denuncie.** A fonte publica a contagem e as métricas por ação na mesma base, de
modo que um erro de escala nas duas **se cancela** em `VPA × N` e passa
despercebido no patrimônio. Ele não se cancela no divisor da ponte por papel,
que usa `N` sozinho.

O caso é a EQTL3: o exercício de 2024 vem com **246.152** ações contra 1,50
bilhão em 2023 e 1,26 bilhão em 2025 — fator de cinco mil —, com VPA de
R$ 121.419,23 e lucro por ação de R$ 11.422,52. O patrimônio sai correto em
R$ 29,9 bilhões. Hoje isso não muda número nenhum, porque o exercício de 2025 já
é público; **numa análise datada entre as duas divulgações o preço justo por
papel sairia cinco mil vezes errado**, e é isso que a validação preditiva faz em
cada coorte.

## Decisão

**1. O prêmio de crédito passa a ter dois direcionadores, e a própria despesa
financeira arbitra qual pode falar.**

- **Alavancagem** (`dívida líquida ÷ EBITDA`) mede o estoque da dívida e não
  passa pela despesa financeira. Faixas na convenção de covenant do crédito
  corporativo brasileiro, teto no mesmo `maxCreditSpread` de 10 p.p.
- **Cobertura de juros** (`EBIT ÷ despesa financeira`) mede a capacidade de
  serviço, que a alavancagem não mede.
- **Quando a razão observada cai dentro da banda defensável**, a despesa é juro
  de dívida e a cobertura é informação: vale a **mais exigente** das duas, porque
  estoque alto e serviço apertado são riscos que se somam.
- **Quando cai fora**, a despesa está medindo outra coisa e a cobertura sai da
  conta: sobra a alavancagem.

Usar só uma das duas erra dos dois lados, e as duas medições estão registradas.
Só a cobertura punia as sólidas, como na tabela acima. Só a alavancagem premiava
quem não paga o que deve: a **MOVI3**, cujo EBIT não cobre um juro plenamente
plausível — R$ 3,59 bi sobre R$ 21,9 bi de dívida, 16,4% ao ano —, ganhava cinco
pontos de desconto e saltava de **+170% para +622%** de potencial.

**2. A contagem de ações do exercício mais recente é conferida contra a
vizinhança da própria série.** Quando destoa por mais de
`CapitalSeries.neighbourFactor` — o mesmo 8,0x que a série de capital já usa —,
ela é descartada do divisor da ponte, que passa a usar a contagem implícita no
valor de mercado, com a queda declarada no resultado.

O fator é largo de propósito, e o raciocínio já estava escrito na série de
capital: falha de fonte é de **ordem de grandeza**, salto societário real fica
entre duas e nove vezes e **precisa passar**. A VIVT3 dobrou a base em 2024 —
1,65 para 3,26 bilhões, com o VPA caindo de R$ 42,13 para R$ 21,40 e `VPA × N`
estável em R$ 69 bilhões — e passa, que é o certo: foi desdobramento, não erro.

**As bases contábeis não são tocadas.** Nelas o erro de escala se cancela contra
o valor por ação publicado na mesma escala, e mexer ali estragaria o que está
certo.

## Consequências aceitas

- **O custo da dívida desceu no universo inteiro, e a distribuição ficou
  utilizável.** O teto passou a alcançar **6 dos 104** com estrutura de capital
  observável, contra 70 sob a razão observada e 104 sob a alavancagem sozinha. A
  mediana do custo aplicado é de 16,49% e a do WACC corrente caiu de 17,84% para
  16,88%. Os seis que ficam no teto — AXIA3, CAML3, DXCO3, EQTL3, PRNR3 e
  YDUQ3 — são alavancados de verdade ou não têm EBITDA positivo.

- **Três ativos passaram a ser avaliados, e um deles é o novo máximo do
  universo.** Com WACC menor, o valor da firma passa a cobrir a dívida líquida em
  casos que antes caíam na recusa da ponte de equity. A BHIA3 entrou a **+224,6%**
  e a ressalva `ponteFragil` acompanha o número. É a pendência aberta que a
  decisão 31 já registra — a ponte continua sendo chave binária —, agora
  declarada em campo estruturado em vez de só em texto.

- **A união das duas razões é mais exigente que cada uma.** Onde a despesa é
  utilizável, o ativo recebe o pior dos dois prêmios. É deliberado: prêmio baixo
  demais infla o preço justo, que é o sentido de erro que este projeto declara
  como o pior.

- **A guarda de consistência não conserta o exercício quebrado, só o tira do
  divisor.** O patrimônio e o capital investido daquele ano continuam sendo
  calculados com a contagem torta e o valor por ação torto, que se cancelam. Se
  algum dia a fonte publicar os dois desalinhados, isso deixa de valer, e não há
  teste no motor que perceba.

- **Cinco dos nove apontamentos da auditoria não foram implementados**, e a §7 da
  auditoria cruzada traz a conferência de cada um com o número que decide.
  Resumidamente: a base da VIVT3 não está duplicada; o multiplicador de *unit* já
  é medido e aplicado; instituição financeira já vai para o modelo de lucro
  distribuível desde a decisão 31; o motor não usa CapEx em lugar nenhum; e
  indexar o crescimento terminal à inflação **não muda nada** com retorno
  terminal neutro, porque ali `g` sai da fórmula.

- **Expurgar arrendamento da dívida líquida foi recusado com medição.** Sob
  IFRS 16 / CPC 06 R2 o passivo de arrendamento e o ativo de direito de uso
  entram **juntos** no balanço, e a conferência das duas rotas do capital
  investido confirma que é o caso aqui: as rotas de financiamento e de operação
  concordam dentro de ±20% em PETR4, VIVT3, AZZA3 e RENT3. Como o EBIT já é
  líquido da depreciação do direito de uso e o juro do arrendamento fica abaixo
  dele, o fluxo descontado é anterior a esse juro — e deduzir o passivo na ponte
  é o tratamento consistente. Removê-lo subtrairia uma obrigação real e inflaria
  o capital próprio.

- **A alternativa descartada** era estimar o juro bancário da AZZA3 separando-o
  do arrendamento e do câmbio, como o apontamento pedia. Recusada porque a fonte
  não publica a abertura: qualquer separação seria arbitrada, e o efeito dela
  entraria no preço justo sem que nada a sustentasse. A alavancagem responde à
  mesma pergunta com dado que existe.

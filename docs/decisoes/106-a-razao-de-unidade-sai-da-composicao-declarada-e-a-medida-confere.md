---
numero: 106
titulo: A razão de unidade sai da composição declarada na FCA, e a medida no valor de mercado vira conferência
status: aceita
origem: voce
data: 2026-09-20
citacao: >
  Seus itens de escopo para esta rodada são B9, B11 e B16.
afeta:
  - packages/equisim_core/lib/src/services/cvm/unit_composition.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/lib/src/usecases/prepare_valuation_inputs.dart
  - lib/data/repositories/unit_composition_repository.dart
  - lib/di/providers.dart
  - lib/presentation/valuation/valuation_providers.dart
  - tool/unit_empacotar.dart
  - tool/cvm/codigos_fca.dart
  - tool/backtest_valuation.dart
  - assets/cvm/units.json
  - docs/validacao/ponte_por_papel.md
substitui: []
---

## Contexto

A ponte por papel precisa saber quantas ações a unit reúne, porque as
demonstrações vêm por ação e a cotação é por unit. A
[decisão 61](061-a-tolerancia-da-razao-de-unidade-e-relativa.md) inferia
essa razão do valor de mercado:

```
u = round( contagem × preço da unit ÷ valor de mercado )
```

**Ela só devolve o número de ações da unit quando ordinária e preferencial valem
o mesmo.** Medido no C3, em 15/09/2026, contra a composição que a companhia
declara na FCA: a razão acerta **141 de 220** observações de unit nas coortes
([ponte_por_papel.md](../validacao/ponte_por_papel.md) §3). Erra de três jeitos:

- **cai em 1**, fora da folga de 5% do inteiro, em 49 observações — a unit é
  avaliada como ação, e o potencial sai de três a cinco vezes errado. Na ALUP11
  de 2019 a ON negociava 35% acima da PN, e a razão deu 2,69;
- **cai no inteiro errado** dentro da folga, em 12 — a ENGI11 com 4 em vez de 5
  em cinco coortes, a IGTI11 com 4 em cinco e 8 em duas —, e aí o erro não tem
  aviso nenhum;
- **não tem espécie negociando**, em 18 — a BRBI11, cujas ON e PN não negociam
  na data: o valor de mercado recua para a contagem vezes o preço da unit, e a
  razão volta a 1 por construção.

No aplicativo as nove units passaram em 04/09/2026, mas **a convenção do valor de
mercado da fonte não é conhecida**, e é ela que decide se o erro aparece.

A composição existe em fonte primária e datada: o quadro de valores mobiliários
da FCA da CVM traz, para cada unit, a coluna `Composicao_BDR_Unit` em texto
livre — "1 ON e 4 PN", "1 KLBN3 + 4 KLBN4", "2 ações preferenciais e 1 ação
ordinária" —, um formulário por ano.

## Decisão

1. **A composição declarada decide a razão de unidade**, pelo formulário mais
   recente **até** a data da avaliação. Formulário posterior não entra: numa
   coorte de 2019, a composição de 2024 seria conhecimento futuro.
2. **A razão medida no valor de mercado vira conferência.** Ela continua sendo
   calculada, entra no rastro de auditoria ao lado da declarada, e **quando as
   duas discordam a avaliação diz isso** — a divergência é o sinal de que as
   espécies negociam a preços diferentes, ou de que uma delas não negociou.
3. **Sem composição declarada, vale a medida — e a avaliação declara que
   inferiu.** A ONCO11 é o caso hoje: a companhia só declara a ONCO3 na FCA.
4. **A chave é o CNPJ**, e não o código de negociação. A coluna de código da FCA
   é texto livre: vem em branco em 44% das linhas e zerada no BTG, que declara a
   composição da BPAC11 sob `000000`. A ponte é a do registro oficial da B3
   ([decisão 82](082-a-ponte-comeca-pelo-registro-oficial-da-b3.md)).
5. **A leitura do texto livre mora no núcleo** (`UnitCompositionCodec.parse`), e
   não na ferramenta: ela deixou de ser conferência e passou a decidir número.
   Recibo e bônus de subscrição não são ação — a BMGB11 declara "1 PN + 3
   Recibos de Subscrição" e tem uma ação —, e composição acima de dez ações é
   **recusada** em vez de confinada, porque um divisor plausível para um texto
   que o leitor não entendeu é pior que nenhum.

## O que foi medido

**As nove units do universo saem com a composição declarada**: ALUP11 3,
BPAC11 3, BRBI11 3, ENGI11 5, IGTI11 3, KLBN11 5, SANB11 2, SAPR11 5, TAEE11 3.
A décima, a ONCO11, não é declarada como unit pela companhia.

**No aplicativo, em 14/09/2026, nenhum número muda.** Nas sete units avaliadas, a
razão medida coincide com a declarada, e nenhuma conferência dispara — é o que a
decisão 61 já tinha visto ao medir as nove a até 2,4% do inteiro. **O que muda é
de onde o número vem**: ele deixa de depender de uma convenção de fonte que não
é conhecida, e a avaliação passa a dizer qual das duas razões valeu.

**O leitor ganhou um caso que errava.** O código de negociação de três letras: a
ENGI11 de 2018 declara "1 ENG3 e 4 ENGI4", e exigir quatro letras somava só o 4 —
a unit saía com quatro ações em vez de cinco. Corrigido, com teste sobre as
dezoito formas que as companhias de fato escreveram.

## Consequências aceitas

**As coortes só recolhem o ganho quando o backtest for reexecutado.** O código
das coortes já passa a composição por CNPJ e por data; a medição de
[ponte_por_papel.md](../validacao/ponte_por_papel.md) §3 continua sendo a da
inferência até que o backtest rode de novo (item C5).

**A composição é a do formulário, e o formulário pode errar.** A FCA é
declaração da companhia, sem conferência da CVM. A conferência que o projeto tem
é a razão medida, e é por isso que ela ficou — divergência entre as duas é sinal,
e não ruído a esconder.

**A ONCO11 continua pela razão medida.** Onde a companhia não declara, o motor
não inventa: ele infere e diz que inferiu.

---
numero: 83
titulo: A contagem oficial da B3 arbitra o divisor por papel, líquida de tesouraria
status: aceita
origem: parecer
data: 2026-09-14
afeta:
  - packages/equisim_core/lib/src/services/b3/b3_registry.dart
  - packages/equisim_core/lib/src/services/b3/corporate_events.dart
  - tool/b3_cotahist.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/lib/src/usecases/prepare_valuation_inputs.dart
  - packages/equisim_core/lib/equisim_core.dart
  - packages/equisim_core/test/b3_registry_test.dart
  - packages/equisim_core/test/valuation_guards_test.dart
  - packages/equisim_core/test/audit_test.dart
  - lib/data/repositories/b3_registry_repository.dart
  - lib/di/providers.dart
  - lib/presentation/valuation/valuation_providers.dart
  - assets/b3/emissores.json
  - pubspec.yaml
  - tool/b3_companhias_baixar.py
  - tool/b3_empacotar.dart
  - tool/b3_eventos_conferir.dart
  - tool/padrao_ligar.dart
  - test/data/b3_tesouro_package_asset_test.dart
  - test/data/tesouro_datasource_test.dart
  - docs/validacao/b3_registro.md
substitui: []
---

## Contexto

A ponte por papel divide o valor do capital próprio por uma contagem de ações,
e a fonte de preços publica duas que divergem. Desde a
[decisão 61](061-a-tolerancia-da-razao-de-unidade-e-relativa.md) a regra é
**adotar a maior** na divergência, e o próprio código registrava por quê: "a
fonte não tem árbitro" — o árbitro `lucro ÷ LPA` é tautológico, porque a fonte
calcula o LPA com a mesma contagem. O plano tinha isso como itens A3.1 (fonte
declarada de eventos e contagem), A3.3 (evento no divisor) e A1.5 (tesouraria no
divisor).

## A fonte

O registro de empresas listadas da B3 traz, por emissor, a **quantidade de ações
por classe** e os **eventos de ações** com fator e data-com. Em 14/09/2026, 297
de 297 emissores do universo. Detalhe em [b3_registro.md](../validacao/b3_registro.md).

**A convenção do fator foi medida, não suposta.** Bonificação e desdobramento
vêm em acréscimo percentual, grupamento em multiplicador, e eventos da mesma
data e ISIN se compõem — a B3 escreve 1 para 2 como ÷10 e ×20 no mesmo dia.
Composto, o fator bate com a razão de preço do COTAHIST em 93,4% de 243 eventos
a 15%.

## O que a contagem oficial mostrou

**A regra do maior errava nos dois sentidos, e o diagnóstico registrado estava
errado.**

- **A "contagem do exercício" da fonte é, em dez ativos, o capital autorizado**
  — um número redondo: GGBR3/4 com 4.499.999.700 contra 1.978.018.049
  emitidas, CSAN3 com 8 bilhões contra 3,97, B3SA3 com 7,5 contra 5,05, RENT3/4
  com 2 contra 1,12, COGN3, ENMT3/4, VIVR3. A regra do maior o adotava, e o
  preço justo saía até 2,3x **subestimado**.
- **Divisor pequeno demais, o pior sentido**: AUAU3 com 451 milhões contra 861,
  AZUL3 com 21,7 milhões implícitos contra 368,6.
- **MILS3 e MEAL3 não eram grupamento.** A §1.7 das limitações os tratava como
  grupamento aparente; a B3 registra 234 e 287 milhões de ações e nenhum evento.
  A contagem "corrente" da fonte — 48.172 e 307.010 — está errada, e a regra do
  maior acertava por acaso.

**O total da B3 inclui a tesouraria**: bate com o capital integralizado da CVM,
com as ações em tesouraria, em 260 de 293 emissores.

## Decisão

1. **A contagem oficial arbitra o divisor**, na unidade negociada e **líquida da
   fração em tesouraria** da CVM — nunca da contagem absoluta, que não tem
   escala (decisão 70). É o que liga o A1.5 ao divisor.
2. **Nunca olha para a frente**: registro consultado depois da data da
   avaliação não existe nela, e é por isso que coorte de backtest não o usa.
3. **Registro com até 31 dias arbitra sozinho.** Mais velho, só vale quando
   concorda com alguma das contagens da fonte, dentro da banda de conciliação —
   um evento de ações depois da consulta o deixaria defasado por um fator, e a
   fonte já o refletiria. Recusado, fica registrado no resultado e declarado no
   aviso.
4. **O WACC estático pondera o capital próprio pelo divisor**, e não pelo
   `marketCap` da fonte. A lente `metodo` apontou que o peso readquiria a
   contagem que a ponte acabava de arbitrar; o teste reproduz 1,07 p.p. de WACC
   com o valor de mercado 2,6x errado. Quando o divisor é o do mercado, os dois
   números são o mesmo.
5. No aplicativo, o registro chega por pacote versionado, como a CVM.

## Efeito medido

Em 14/09/2026, na mesma execução, fonte de mercado e dois pontos do CDI, só o
divisor trocado (`tool/padrao_ligar.dart`):

| | divisor da fonte | contagem oficial |
|---|---:|---:|
| avaliados | 128 | 128 |
| potencial mediano | −37,6% | **−28,7%** |
| mediana do `\|Δ\|` | | 1,0% |
| `\|Δ\|` > 10 p.p. | | 8 |
| correlação de postos | | **0,982** |

A maioria não se move — as contagens concordam em 236 de 363 ativos. Os que se
movem são os de divisor errado: GGBR4 de −63,0% a −15,7%, RENT3 de −53,7% a
−17,5%, COGN3 de −38,2% a −9,9%, AZEV4 de −91,9% a −56,3%. **O nível do motor
subia porque os ativos com o capital autorizado no divisor estavam, todos, com o
preço justo deprimido.**

## Consequências aceitas

O registro é da data do build. Um evento de ações entre o build e a avaliação,
num ativo cuja fonte ainda não o refletiu, passa despercebido por até 31 dias.

A tesouraria usada é a fração do último exercício da CVM, e não a da data do
registro: recompra e cancelamento no meio do ano não entram.

**A distância entre pregões passa a ser contada em dias de calendário** no
detector de `CorporateEvents` e nas ferramentas do COTAHIST. A auditoria do gate
apontou que datas em hora local cruzando o horário de verão perdiam uma hora, e
oito dias contavam como sete. Refeita a conferência, um evento oficial a mais
entra na série e a cobertura vai de 41,7% a 41,5%.

**A inferência de eventos pelo preço tem teto medido contra o registro** — 41,5%
dos eventos oficiais encontrados, 63,8% dos inferidos confirmados — e continua
sendo a única fonte para companhia deslistada (item A3.2).

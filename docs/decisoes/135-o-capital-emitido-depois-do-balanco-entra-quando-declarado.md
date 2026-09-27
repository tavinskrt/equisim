---
numero: 135
titulo: O capital emitido depois do balanço entra no patrimônio da ponte quando o valor é declarado, e é avisado quando não é
status: aceita
origem: voce
data: 2026-09-24
citacao: >
  Após realizar a leitura do documento plano-motor-de-referencia.md
  atualizado, aprovo a execução do item B28 e a finalização do C7.
afeta:
  - packages/equisim_core/lib/src/entities/share_issue.dart
  - packages/equisim_core/lib/src/services/cvm/capital_events.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/lib/src/usecases/prepare_valuation_inputs.dart
  - packages/equisim_core/lib/src/entities/valuation.dart
  - packages/equisim_core/test/capital_posterior_test.dart
  - tool/cvm/emissoes_fre.dart
  - tool/coortes/eventos_de_acoes.dart
  - tool/capital_empacotar.dart
  - tool/backtest_valuation.dart
  - tool/gabarito_cascata.dart
  - tool/validation/congelado.dart
  - test/tool/capital_fre_test.dart
  - lib/data/repositories/capital_events_repository.dart
  - lib/di/providers.dart
  - lib/presentation/valuation/valuation_providers.dart
  - assets/cvm/capital.json
substitui: []
---

## Contexto

A lente `metodo` achou, na rodada do C7, uma premissa que ninguém tinha escrito
(item B28). O capital próprio da ponte sai do último balanço publicado, e o
divisor é a contagem que forma a cotação de hoje. **Uma emissão entre as duas
datas entra no divisor e não entra no patrimônio**, porque as ações novas estão
na contagem e o dinheiro que elas trouxeram não está no balanço. O preço justo
por papel sai subavaliado na proporção do capital captado. A recompra faz o
contrário.

O item pedia medir antes de decidir. **A medição começou pela contagem do FRE e
parou nela**: a variação da contagem entre o balanço e a data mistura emissão com
bonificação — que a fonte de preços nem sempre ajusta, e aparecia como emissão
de 10% no Bradesco todo ano — e com desdobramento que o formulário registrou só
como aprovação de capital. **O dado bom é o quadro de aumentos do capital social
do FRE**, que declara emissão por emissão a data, o valor total, a quantidade de
ações, o preço, o tipo de subscrição e a forma de integralização. Ele tem três
limites, e cada um virou regra:

- **Bonificação também aparece nele**, como «subscrição particular» com o valor
  da reserva capitalizada — a SHUL4 de 2021, «Ações Bonificadas» a R$ 0,26; a
  SLCE3 de 2023, preço de emissão zero e forma em branco;
- **cada versão do formulário relista os aumentos com identificador novo** — a
  ALPA4 de 2019 aparece em cinco documentos com cinco identificadores —, e somar
  por identificador contaria a emissão cinco vezes;
- **o quadro acabou em 2023**. O formulário novo da CVM não o tem, nem o de
  desdobramentos: o último aumento lido é de setembro de 2023.

Depois de 2023 sobra o quadro de **capital social**, que continua e diz, a cada
versão, o capital integralizado e a contagem. **A variação dele não é valor
declarado**: não separa a bonificação que capitaliza reserva de uma emissão, nem
a troca de ações de uma reorganização de uma subscrição. Ela aparece com R$ 5,2
bilhões na RENT3 de 2024, com R$ 49,8 bilhões na BPAC11 de 2025 e com R$ 14
bilhões na SAUD3 de 2026, e nos três o preço bruto não se mexe como numa
emissão desse tamanho.

## Decisão

1. **A cascata soma ao patrimônio da ponte a emissão com valor declarado** que
   cai depois do fim do exercício usado e até a data da avaliação: pelo valor de
   emissão, depois do fluxo e antes da divisão por papel. Emissão a preço de
   mercado é neutra em valor para quem já era acionista, e o capital novo não
   está no fluxo projetado. A soma é a mesma nas duas vias, capital ÷ papéis, e
   o cenário base continua sendo o preço justo.
2. **Valor declarado é o do quadro de aumentos**, lido do formulário mais
   recente recebido até a data que tem o quadro, sem capitalização sem ação
   nova, sem emissão de preço zero e sem forma que diga bonificação, reserva ou
   lucro acumulado.
3. **A variação do capital depois de 2023 entra marcada como não declarada**, e
   só quando nenhum evento de ações a explica: o registro da B3, o quadro do FRE
   ou o preço bruto caindo pela razão da contagem no pregão em que o `DISMES`
   troca. **A cascata não a soma**: diz que ela existe e quanto o preço justo
   mudaria por papel se fosse emissão por valor.
4. **O aplicativo recebe as duas listas num pacote** (`assets/cvm/capital.json`),
   e o gabarito e a entrada congelada o leem na montagem do aplicativo. **O
   backtest usa só o que era conhecido na data**: o formulário recebido até ela.
5. **O rastro mostra o patrimônio do balanço e soma o capital novo num passo
   próprio**, e o diagnóstico ganha `postStatementCapital`.

## O que foi medido

**O pacote de hoje** tem 375 ativos: 31 emissões com valor declarado, em 23
ativos, a última de setembro de 2023, e 145 variações de capital sem declaração,
em 112 ativos. **No aplicativo, nenhum preço justo muda**: o balanço usado é o de
2025, e depois dele nenhuma emissão foi declarada. O aviso de variação sem
declaração sai em nove ativos (BEEF3, BHIA3, BMGB4, EGIE3, HYPE3, ISAE4, PGMN3,
SAUD3 e VULC3).

**Nas coortes, 111 observações de 31 papéis recebem capital**, e a mediana do
efeito no potencial é de +0,35 p.p. **O efeito é raro e grande onde há evento**:

| papel | coortes | emissão | potencial |
|---|---|---|---|
| ALOS3 | 30/06 a 31/12/2023 | incorporação da brMalls, R$ 10,9 bi | +72 a +84 p.p. |
| BRFS3 | 30/06 a 31/12/2022 | oferta de R$ 5,4 bi | +37 a +61 p.p. |
| LIGT3 | 30/09 e 31/12/2021 | emissão de R$ 1,4 bi | +28 a +31 p.p. |

Na ALOS3 a contagem de hoje já tinha as ações da incorporação, e o patrimônio do
balanço de 2022 era só o da Aliansce Sonae: **o preço justo por papel saía pela metade**.

**As três correções da rodada juntas** — esta, a 136 e a 137 — levam o potencial
condicionado ao B/M em 36 meses de 0,052 a 0,058, com `t` corrigido de 0,30 a
0,34 contra 2,70: **o R3 continua sem passar**. A faixa calibrada mantém a
cobertura a até 5 p.p. da nominal nos dois horizontes, e o R2 continua atingido
([habilidade_trimestral.md](../validacao/habilidade_trimestral.md) §11).

## Consequências aceitas

**Depois de 2023 o motor não corrige, avisa.** O motor de hoje avalia o balanço
de 2025, e a correção automática dele não acontece em nenhum ativo: o formulário
não declara mais o valor. O aviso diz o tamanho do erro possível, e é tudo o que
o dado sustenta.

**A recompra fica de fora.** Ela reduz o caixa depois do balanço e a contagem
líquida de tesouraria ao mesmo tempo, e os dois erros se compensam em parte:
para uma recompra de 2% das ações a um preço de tela que é o dobro do preço
justo, o preço justo sai 2% alto. O FRE tem a movimentação de tesouraria; ligá-la
é item próprio, se a medição mostrar que pesa.

**O valor de emissão é a hipótese**, e não o valor econômico do que entrou. Numa
incorporação, a companhia incorporada entra pelo valor da troca de ações; se a
troca foi cara, o motor a herda.

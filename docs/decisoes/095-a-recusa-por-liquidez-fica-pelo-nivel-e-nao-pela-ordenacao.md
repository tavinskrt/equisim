---
numero: 95
titulo: A recusa por liquidez fica pelo nível do preço justo, e não pela ordenação, que sobreviveu às deslistadas
status: aceita
origem: voce
data: 2026-09-15
citacao: >
  autorizo o prosseguimento da implantação da Fase 2, com os itens C2b, C0b,
  C1a e C1b.
afeta:
  - tool/recusas_custo.py
  - docs/validacao/recusas_custo.md
  - docs/validacao/recusas_custo_deslistadas.json
  - docs/validacao/recusas_custo_so_deslistadas.json
substitui: []
---

## Contexto

O item C0b do plano. A [decisão 91](091-as-recusas-ficam-e-a-liquidez-e-remedida-com-as-deslistadas.md)
manteve todas as recusas e mediu, nos recusados só por liquidez, que o potencial
solto do corte ordena o retorno além do book-to-market — o que nas avaliadas não
acontece. Manteve a recusa por três razões, e mandou remedir a primeira antes de
qualquer soltura: **o viés de sobrevivência é máximo nesse grupo**; o nível do
potencial confirma o beta enviesado que a Porta 0 declara; e o volume não é
investível.

O C1b ([decisão 93](093-as-deslistadas-entram-nas-coortes-e-o-t-e-o-menor.md))
pôs as deslistadas nas coortes.

## Decisão

1. **O viés de sobrevivência não explica a ordenação.** Na mesma execução, com as
   deslistadas, os soltos passam de 848 para 1.003, e o potencial dado o B/M
   continua ordenando:

   | soltos do corte de liquidez | n | IC dado o B/M, 12m | `t` | IC dado o B/M, 36m | `t` para o critério |
   |---|---:|---:|---:|---:|---:|
   | listadas | 848 | 0,120 | 2,75 | 0,169 | 2,56 |
   | com as deslistadas | 1.003 | 0,116 | 2,73 | 0,189 | 3,08 |

   Começando o retorno um mês depois, 0,105 (`t` 2,63) e 0,182 (`t` 2,91). O viés
   pesa no **nível** do retorno — a média em 36 meses cai de 73% para 68% com as
   deslistadas, que renderam 46% —, e não na ordenação.

2. **A recusa fica, pela razão que continua de pé: o nível.** A Porta 0 declara
   duas razões para o corte (decisão 25, `EligibilityGate`): as guardas foram
   calibradas em ativos do decil superior de liquidez, e avaliar abaixo dele é
   extrapolar; e beta de papel com pouco negócio sai baixo por negociação não
   sincrônica, reduz o custo de capital e infla o preço justo. A medição responde
   à primeira pela ordenação, que funciona fora da fronteira, e confirma a segunda
   pelo nível: o potencial mediano dos soltos é de −24,5%, contra −52,1% das
   avaliadas. Soltar agora poria na tela preços justos inflados, e na ordenação da
   carteira os ilíquidos no topo **por nível**, e não pelo sinal que ordena dentro
   do grupo deles.

3. **A razão da investibilidade sai.** Ela era da decisão 91, e não da Porta 0:
   o corte de R$ 2 milhões por dia não foi posto por escala de carteira, e o
   aplicativo serve a quem aporta todo mês quantias pequenas — um volume de
   R$ 37 mil por dia não impede a compra.

4. **O caminho para soltar entra no plano**: medir o beta com correção por
   negociação não sincrônica — Dimson, ou Scholes-Williams — e remedir o nível dos
   soltos com ele. Se o nível convergir ao das avaliadas, a recusa por liquidez
   perde a razão que resta.

## Consequências aceitas

**O motor segue sem avaliar onde tem sinal.** 1.003 observações recusadas ordenam
melhor, condicionadas ao B/M, do que as 951 avaliadas; a ordenação da carteira
continua sem elas até o beta ser corrigido — ou até o B1 decidir que a ordenação
sai de um modelo transversal, onde elas podem entrar sem preço justo.

**As deslistadas acrescentam pouco ao grupo**: 155 soltos, de 33 companhias. O
`t` delas sozinhas é de 1,10 em 12 meses.

**O `t` de 36 meses usa o menor entre o comum e o de Newey-West**, pela decisão
93. No grupo das deslistadas sozinhas, o de Newey-West chegou a 4,06 contra 2,39
do comum: com cinco coortes, a estimativa do erro-padrão oscila demais para
decidir, e a regra do menor é o que impede que ela decida.

Ver [recusas_custo.md](../validacao/recusas_custo.md) §6.

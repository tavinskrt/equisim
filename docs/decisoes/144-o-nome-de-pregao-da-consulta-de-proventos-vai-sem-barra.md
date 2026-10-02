---
numero: 144
titulo: O nome de pregão da consulta de proventos da B3 vai sem barra, e os nove emissores que ficaram sem histórico são consultados de novo
status: aceita
origem: voce
data: 2026-10-01
citacao: >
  Pode consultar a B3 e fazer o backtest com o prêmio normalizado.
afeta:
  - tool/b3_complemento_baixar.py
  - assets/b3/proventos.json
substitui: []
---

## Contexto

O item B44 do plano foi aberto em 29/09/2026, ao medir o prêmio implícito
([premio_implicito.md](../validacao/premio_implicito.md) §3.2): os nove
emissores com barra no nome de pregão — `AMBEV S/A`, `KLABIN S/A`, `CURY S/A`,
`LIGHT S/A`, `IMC S/A`, `OUROFINO S/A`, `EMBPAR S/A`, `HAGA S/A` e `WETZEL S/A`
— vieram da B3 sem provento nenhum, e nenhum emissor com barra veio com
provento. O retorno total das coortes (decisão 89) dessas companhias era o de
preço: 66 observações avaliadas de 3.070, Ambev e Klabin entre elas. O pacote
de proventos do aplicativo também não as tinha, e o beta delas saía do retorno
de preço.

A consulta `GetListedCashDividends` é pelo nome de pregão, que o baixador
mandava sem espaços (`AMBEVS/A`). Testado em 01/10/2026, com autorização do
usuário: `AMBEVS/A` devolve zero proventos; `AMBEVSA` devolve os 40 da Ambev
S.A.; `AMBEV` sozinho devolve 134, os da antiga Companhia de Bebidas (ON e PN,
até 2013), incorporada.

## Decisão

**O nome entra sem espaços e sem barra** (`nome_da_consulta`, em
`tool/b3_complemento_baixar.py`), nas listadas e nas deslistadas. Os nove
emissores foram consultados de novo: sete voltaram com histórico (Ambev 40
proventos, Klabin 219, Embpar 58, Ourofino 25, Light 24, Cury 20, IMC 4), e
Haga e Wetzel seguem sem nenhum — não pagaram. O pacote do aplicativo
(`assets/b3/proventos.json`) foi regerado: 246 emissores, sete a mais.

## Consequências aceitas

- O beta de retorno total dessas companhias, no aplicativo e nas coortes, passa
  a incluir os proventos delas, e o preço justo delas muda por isso.
- A Haga e a Wetzel, sem provento, continuam com retorno total igual ao de
  preço — agora porque não pagaram, e não por falta do dado.
- A série do prêmio implícito passa a somar as sete companhias. Na data
  congelada, com esta correção e a da decisão 143 juntas, a soma vai de 259
  para 268 companhias, e o rendimento agregado de 6,07% para 6,05%.

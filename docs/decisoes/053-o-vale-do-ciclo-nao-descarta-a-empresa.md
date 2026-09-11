---
numero: 53
titulo: O fluxo-base é reconstruído do ciclo quando o exercício vem no prejuízo, e a normalização deixa de funcionar só no pico
status: aceita
origem: voce
data: 2026-09-11
citacao: >
  Prossiga com o item 1 do bloco A. Mesmo esquema: ao final, reestruture a
  lista necessária para chegar no valuation sem erros conhecidos e motor de
  referência. Ao final, rode as lentes.
afeta:
  - packages/equisim_core/lib/src/services/valuation/capital_base.dart
  - packages/equisim_core/lib/src/entities/valuation.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/test/valuation_guards_test.dart
  - tool/base_negativa.dart
  - docs/validacao/base_negativa.md
substitui: []
---

## Contexto

A Guarda 1 normaliza o exercício-base contra a mediana do ciclo porque **um
exercício não descreve a empresa**. O fator é `ciclo ÷ atual` e exige
denominador positivo — de modo que a correção funciona no pico e **desliga no
vale**.

Medido pela composição das recusas: sete ativos elegíveis saíam por "os dados
não sustentam nenhuma das duas vias", e em quase todos a causa era o último
exercício ter vindo no prejuízo. Entre eles USIM3, USIM5, CSAN3 e CSNA3 —
cíclicos num ano ruim, descartados por causa dele.

## Decisão

**Quando o retorno corrente não é positivo, o fluxo-base é reconstruído:**

```
fluxo-base = retorno do ciclo × capital de hoje
```

É a mesma conta que o fator faz, escrita de um jeito que sobrevive ao
denominador. O retorno que governa o freio de reinvestimento já era o do ciclo
nesse caso, de modo que as duas pontas passam a falar do mesmo ano.

**Três condições, e nenhuma é parâmetro novo:**

| Condição | Origem |
|---|---|
| ciclo positivo e medível | sem isso não há a que voltar |
| ao menos `minPositiveFlow` da janela positiva | o mesmo corte da Porta 3 |
| a trava de saúde não reprovar | a mesma da normalização, com a isenção cíclica da decisão 30 |

**Cada uma barra ao menos um ativo**: AMER3, BHIA3 e DASA3 pelo sinal do ciclo;
HBSA3 pela frequência; RAPT4 pela saúde.

**A ressalva `baseReconstruida` marca o resultado**, e o aviso diz o retorno do
vale, o do ciclo e a fração positiva da janela.

## Consequências aceitas

**Sete ativos passam a ser avaliados, e nenhum preço existente muda.** A
alteração é estritamente aditiva. O universo vai de 120 para 127, os potenciais
positivos de 37 para 40, e o p75 de +10,7% para +11,4%.

**Quatro dos sete saem abaixo do preço de mercado** — USIM3 −55,1%, USIM5
−58,8%, CSAN3 −65,0%, AZEV4 −93,1%. A reconstrução não é máquina de gerar
potencial: é a remoção de um viés de sobrevivência que descartava a empresa no
ano ruim e a mantinha no ano bom.

**A trava de saúde foi retirada e reposta, por medição.** O argumento para
tirá-la é verdadeiro: ela devolve nulo quando a referência de três anos atrás
também era prejuízo, e por isso dispara em quem perdeu agora e cala em quem já
perdia — a RAPT4 fica de fora com **oito de oito exercícios positivos** e a
AZEV4 entra com quatro dos oito negativos.

Ainda assim ela fica: **sem ela a RAPT4 entra a +311,7% de potencial**, com o
resultado caído 109% no triênio e o fluxo-base reconstruído sobre um retorno de
ciclo que a empresa acabou de deixar de ter. Reconstruir a base **erra para
cima**, o risco é assimétrico, e a ordenação imperfeita é o preço menor.

**A AZEV4 é avaliada e sai a −93,1%.** Admitir não é resgatar: o guarda a
deixou passar e a conta disse que o capital próprio dela não vale quase nada.

**O motor não distingue o primeiro ano de um declínio de um vale de ciclo.** A
trava é o que tenta, e tem o buraco acima. O que limita o estrago é a
frequência: dois anos de prejuízo derrubam a janela abaixo do corte e o ativo
sai.

**A alternativa descartada** era manter a recusa, com o argumento de que
prejuízo é informação e projetar sobre ele é prudente. Recusada porque não é
prudência e sim viés: o mesmo motor normaliza **para baixo** o exercício de pico
sem hesitar, e recusar o de vale trata as duas pontas do ciclo com pesos
diferentes. Quem aceita corrigir o pico aceita corrigir o vale, ou não estava
corrigindo ciclo nenhum.

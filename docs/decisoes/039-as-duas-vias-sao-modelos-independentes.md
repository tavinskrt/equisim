---
numero: 39
titulo: As duas vias são modelos independentes, e amarrar seus insumos não as concilia
status: aceita
origem: voce
data: 2026-09-10
citacao: >
  Comece com a fase A1, portanto. Lembre-se de não se prender a decisões
  antigas e de executar as lentes.
afeta:
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/test/valuation_guards_test.dart
  - tool/insumos_compartilhados.dart
  - docs/validacao/insumos_compartilhados.md
substitui: []
---

## Contexto

A [decisão 38](038-transicao-continua-entre-as-vias.md) removeu o degrau que a
discordância entre as vias produzia, e registrou que **não** removeu a
discordância: 55 de 92 ativos além de 1,5×, 33 além de 2×.

Restava decidir se conciliá-las exigia reconstruir a Porta 2 ou se bastava
amarrar os insumos. A hipótese barata era boa: uma empresa tem **um**
crescimento e **uma** posição no ciclo, e as duas vias os medem separadamente —
sobre capital investido de um lado e patrimônio do outro, divergindo em mais de
3 p.p. no crescimento em 44 de 96 e com fator fora de [0,8; 1,25] em 35.

A medição está em [`insumos_compartilhados.md`](../validacao/insumos_compartilhados.md).

## Decisão

**O caminho de amarrar os insumos fica descartado, por medição.** Impor às duas
vias o mesmo crescimento e o mesmo fator de normalização fecha **15,5%** da
dispersão no melhor sentido do empréstimo e **11,3%** no outro. Restam **52 dos
96 além de 1,5×**, apenas 13 passam a concordar dentro de 1,1×, e em **39 dos
96 a discordância piora**. O crescimento sozinho não move nada.

**Fica estabelecido que as duas vias são modelos independentes**, e não dois
olhares sobre um. Os casos que encerram a questão são POSI3 e PRIO3: já usavam
crescimento **idêntico** e fator **idêntico** nas duas vias, e os preços justos
diferem por **28,15×** e **5,9×**. Não há o que amarrar onde já está amarrado.

A identidade `FCFF/WACC ≡ FCFE/Ke` nunca foi construída no motor, e as duas
razões são nomeáveis:

1. **Os fluxos não derivam um do outro.** O da firma é `NOPAT = EBIT × (1 − t)`;
   o do acionista é o LPA publicado. Não existe a ponte
   `FCFE = FCFF − juros × (1 − t) + ΔDívida`, e o termo `ΔDívida` não existe em
   lugar nenhum do motor.
2. **`Ke` e `WACC` não estão ligados pela alavancagem.** O beta é regressão crua
   contra o Ibovespa; não há beta desalavancado ligando as duas taxas.

**Duas costuras de diagnóstico entram no núcleo**, nulas em produção:
`growthOverride` e `baseFactorOverride`. Sem elas a hipótese não era testável,
porque cada via calcula os dois por dentro.

## Consequências aceitas

**A conciliação passa a ter escopo nomeado, e é maior do que "Porta 2".** Exige
derivar uma via da outra e ligar as duas taxas por um beta desalavancado — duas
reconstruções, a da Porta 2 **e** a do custo de capital.

**O beta *bottom-up* deixa de ser sucessor e vira pré-requisito.** Ele estava
depois da ingestão da CVM no roteiro; sem beta desalavancado não há como amarrar
`Ke` a `WACC`, e sem as taxas amarradas a identidade continua quebrada por
construção. A fila muda por isso.

**A divergência continua sendo defeito conhecido, e não vira limitação.** Dois
modelos que a teoria diz idênticos e que diferem por 28× não são escolha de
método. Enquanto não for fechada ou substituída por caminho único, o motor não
pode ser descrito como "sem defeito conhecido".

**A via do acionista para instituição financeira é exceção legítima e
permanece.** Ali não há valor da firma nem dívida líquida com sentido
econômico, e ela deve seguir como modelo independente — declarado como tal, sem
pretensão de identidade com coisa alguma.

**Um teste do núcleo mudou de sinal ao ser escrito, e o motor estava certo.** A
primeira versão exigia que crescer mais valesse mais; medido, vale **menos** no
fixture, porque com retorno abaixo do custo de capital o freio `b = g/ROIC`
cobra mais do que o crescimento devolve. O teste passou a travar essa
propriedade em vez da suposição.

**A alternativa descartada** era adotar o compartilhamento assim mesmo, pelos
15,5%. Recusada porque piora 39 dos 96 casos e porque teria dado à conciliação
uma aparência de resolvida que a medição não sustenta.

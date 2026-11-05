---
numero: 160
titulo: A interface deixa o peso e o retorno esperado da carteira, e enxuga textos do Estudo, da Meta e do Backtest
status: aceita
origem: voce
data: 2026-11-05
citacao: >
  Na tela "Estudo", gostaríamos de tirar a coluna "Peso" (e o botão
  equiponderar e a explicação do que o peso é, no ícone de explicação) e o
  texto amarelo de "Concentração setorial". Podemos tirar também essa primeira
  barra anexada inteira, já que esses dados são basicamente duplicatas e o
  "esperado da carteira" é apenas a média das taxas de desconto considerando o
  "peso", mas como não existe mais peso, podemos tirar. [...] Temos que tirar o
  "esperado da carteira" da curva de acumulação (e do carteira realizada
  contra a meta) e do acompanhamento da carteira. Podemos remover também a aba
  "Carteira frente à meta". Quando tratamos que as compras usaram o preço
  justo de uma coorte no passado, precisaríamos saber o que a coorte
  significa, uma explicação. [...] Vamos precisar de uma explicação do que que
  essa base 100 é, abaixo do gráfico, como o TWR.
afeta:
  - src/app/state/study-store.ts
  - src/app/tracking.ts
  - src/features/study/builder-page.tsx
  - src/features/study/portfolio-column.tsx
  - src/features/study/sector-donut.tsx
  - src/features/goal/planner-page.tsx
  - src/features/goal/tracking-panel.tsx
  - src/features/goal/tracking-chart.tsx
  - src/features/backtest/backtest-page.tsx
  - src/features/backtest/evolution-chart.tsx
  - test/app/study-store.test.ts
  - test/app/tracking.test.ts
  - docs/motor/07-aplicativo.md
  - README.md
substitui: []
---

## Contexto

A carteira já era equiponderada na prática. Incluir e tirar ativo
reequipondera (`Portfolio.add` e `Portfolio.remove`), e nenhum controle da
interface escolhia outro peso. Mesmo assim, o Estudo mostrava uma coluna de
peso e um botão de equiponderar. No alto, um resumo repetia a contagem de
ativos e o exigido, e trazia o "Esperado da carteira": a média dos Ke pelo
peso.

O mesmo esperado aparecia em três lugares da Meta (decisão 159):

- na curva de acumulação;
- no cartão "Carteira frente à meta";
- no acompanhamento, como métrica e como curva.

Outros textos repetiam o que a tela já mostrava: o aviso de concentração
setorial, a frase de viabilidade e as referências da Meta, e a explicação da
janela e o aviso de horizonte do Backtest. Faltava explicar o que é coorte nos
avisos do acompanhamento, e o que é a base 100 no gráfico de evolução.

Também havia um defeito de responsividade: o nome "Petróleo, Gás e
Biocombustíveis" alargava a tabela da rosca de setores além do cartão.

## Decisão

**O peso sai da interface, e com ele o retorno esperado da carteira; os textos
repetidos saem, e os conceitos que faltavam ganham explicação.**

1. **Estudo.**
   - Saem a coluna Peso, o botão Equiponderar, o verbete "Peso" da explicação
     das colunas, o aviso de concentração setorial e o resumo do alto.
   - Cada linha de ativo fica numa linha só, também no celular.
   - Um estudo gravado com outros pesos abre equiponderado
     (`withEqualWeights`), para que um peso invisível não chegue ao backtest.
2. **Rosca de setores.** A tabela passa a layout fixo, e o nome do setor quebra
   a linha em vez de alargar o cartão. O subtítulo deixa de falar em peso.
3. **Meta.**
   - Saem a frase de viabilidade e a linha de referências abaixo das métricas
     (CDI e Ibovespa seguem nas métricas), a curva do esperado na acumulação,
     e o cartão "Carteira frente à meta".
   - No acompanhamento, saem a métrica e a curva do esperado. Um
     acompanhamento novo grava o esperado vazio. O de antes guarda o número,
     que a tela ignora.
4. **Coorte explicada.** Todo aviso do acompanhamento que fala de coorte diz o
   que ela é (`cohortMeaning`): a fotografia trimestral do preço justo, o motor
   no último dia de cada trimestre com só os dados públicos até ali. Os
   lugares são o aviso de compras com coorte velha, o aviso de início no
   passado e a tabela de compras, quando alguma veio de coorte.
5. **Backtest.**
   - Saem a explicação da janela ao lado do controle e o aviso de que a janela
     não cobre o prazo da meta.
   - Abaixo da evolução em base 100, o rodapé explica que as duas carteiras
     partem de 100 e cada ponto diz no que esses 100 se transformaram.

## Consequências aceitas

- **O núcleo não muda.** `ExpectedReturn`, `SectorConcentration` e o campo do
  esperado no registro do acompanhamento seguem lá, sem tela que os mostre.
  Nenhum número da simulação, da meta ou do acompanhamento muda.
- **O acompanhamento compara a carteira com o exigido, o CDI e o Ibovespa.**
  Sai a comparação com o esperado prevista na decisão 159; o resto dela
  continua valendo.
- **Sem o aviso de horizonte**, nada mais lembra, no Backtest, que uma janela
  mais curta que o prazo da meta acumula só parte do plano. O prazo da meta
  continua logo abaixo do controle da janela, para a comparação a olho.

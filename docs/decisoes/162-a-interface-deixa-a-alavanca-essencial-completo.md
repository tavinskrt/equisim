---
numero: 162
titulo: A interface deixa a alavanca Essencial/Completo e mostra sempre tudo
status: aceita
origem: voce
data: 2026-11-06
citacao: >
  Vamos remover a alavanca "essencial/completo". Vamos deixar apenas as
  informações da versão "completo" sendo exibidas na tela. Não esqueça de
  remover o código morto.
afeta:
  - src/app/state/preferences-store.ts
  - src/features/shell/app-shell.tsx
  - src/features/shell/command-palette.tsx
  - src/features/auth/profile-page.tsx
  - src/features/asset/asset-xray.tsx
  - src/features/backtest/backtest-page.tsx
  - src/features/backtest/portfolio-metrics.tsx
  - src/copy/verdict-copy.ts
  - test/ui/screens.test.tsx
  - test/ui/motion.test.tsx
  - docs/motor/07-aplicativo.md
  - docs/motor/03-base-e-crescimento.md
  - docs/estudo/04-fluxo-de-caixa-descontado.md
  - README.md
substitui: []
---

## Contexto

A reconstrução em TypeScript (decisão 152) trouxe uma alavanca de profundidade
da interface com dois valores: **Essencial** (`guided`) e **Completo**
(`analyst`). Ela aparecia em três lugares:

- no cabeçalho, ou acima da área no celular;
- nas preferências do perfil;
- num comando da busca (Ctrl/⌘ + K).

O padrão era o Essencial, e a escolha ficava guardada no navegador
(`equisim:modo`).

A alavanca mudava duas telas, e nenhum número, porque o modo só decidia o que
aparecia:

- **Raio-X**: no Essencial ficavam a leitura, a régua, o simular, os valuations
  salvos e as ressalvas recolhidas, mais um aviso que apontava o Completo. O
  Completo acrescentava a faixa calibrada, o modelo e a taxa, o lucro de
  partida, a sensibilidade, os múltiplos de pares e a projeção de dez anos.
- **Backtest**: no Essencial, a tabela lado a lado tinha cinco métricas e um
  aviso no lugar da dispersão risco × retorno e da correlação. O Completo
  mostrava as dez métricas e os dois gráficos.

## Decisão

**A alavanca sai, e as duas telas mostram sempre o que o Completo mostrava.**

1. **Sem controle de modo.**
   - Saem os dois controles da casca, o do perfil e o comando da busca.
   - Saem do estado das preferências o tipo `DetailMode`, o campo `mode`,
     `setMode` e a leitura de `equisim:modo`. Uma chave já gravada num
     navegador fica lá, sem ninguém que a leia.
2. **Raio-X.** Todas as seções aparecem e o índice lateral lista todas. As
   ressalvas ficam no cartão inteiro, e não mais recolhidas. Sai o aviso que
   apontava o Completo.
3. **Backtest.**
   - A tabela lado a lado mostra sempre as dez métricas. Sai a propriedade
     `essential` de `SideBySidePortfolios`, junto com o recorte de cinco linhas.
   - A dispersão risco × retorno e a correlação aparecem sempre, e sai o aviso
     que as substituía.
4. **O veredito em linguagem simples continua** no alto do Raio-X, com os
   limiares do item 6 da decisão 152. Ele já aparecia nos dois modos.

## Consequências aceitas

- **O núcleo não muda.** Nenhum número muda, porque o modo nunca entrou em
  conta.
- **Quem está começando vê a tela inteira.** O Essencial servia para entrar
  aos poucos. Daqui em diante, o que guia a leitura são as explicações de cada
  cartão (os ícones de dica) e o índice lateral do Raio-X.
- **A decisão 152 segue valendo no resto.** Só a alavanca de profundidade sai;
  o veredito e os limiares dele ficam como estão.

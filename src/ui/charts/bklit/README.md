# Bklit UI (código de terceiros)

Cópia do gráfico de linha da [Bklit UI](https://github.com/bklit/bklit-ui),
`packages/ui/src` do commit clonado em 28/10/2026, sob a licença MIT (aviso em
[THIRD_PARTY_NOTICES.md](../../../../THIRD_PARTY_NOTICES.md)). Entrou pela
decisão 156, como piloto na curva de acumulação da Meta.

São os 64 arquivos alcançados a partir de `line-chart`, `line`, `grid`,
`x-axis`, `y-axis` e `tooltip`, e nada mais. **Não edite estes arquivos para
mudar o visual de um gráfico do Equisim**: o tema vem das variáveis
`--chart-*` em `src/styles.css`, e o uso, de quem importa `index.ts`.

O que mudou em relação ao original, e só isto:

1. `@/lib/utils` virou import relativo para `lib/utils.ts`.
2. A diretiva `"use client"` do Next.js saiu do topo dos arquivos.
3. `motion.*` virou `m.*` (`motion/react-m`): o Equisim roda o Motion em
   `LazyMotion` estrito (decisão 155), que recusa o componente `motion`
   completo. Nenhum dos arquivos usa animação de layout, então o `m` com
   `domAnimation` faz o mesmo.
4. Três ajustes pedidos pelo gate local de QA (`scripts/qa-local.mjs`), sem
   mudar o desenho: em `loading-sweep.tsx`, a opacidade arredonda por
   `Math.round` em vez de ida e volta por `toFixed`; em
   `tooltip/date-ticker.tsx`, a pílula usa os tokens
   `chart-tooltip-background` e `chart-tooltip-foreground` em vez da paleta
   `zinc`; em `y-axis.tsx`, o recuo de 8 px dos rótulos saiu do `style` para
   as classes `pr-2` e `pl-2`.

Para atualizar, copie de novo a mesma lista de arquivos do repositório de
origem e reaplique os quatro passos.

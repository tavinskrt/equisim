---
numero: 19
titulo: Decisões passam a viver em arquivo próprio; o parecer é congelado
status: aceita
origem: voce
data: 2026-08-30
afeta:
  - docs/decisoes
  - docs/apontamentos
  - scripts/gerar-estado.mjs
  - PLANO_ARQUITETURA.md
substitui: []
---

## Contexto

O `PLANO_ARQUITETURA.md` soldava quatro conteúdos com quatro velocidades e
quatro autoridades diferentes: decisões (que nunca mudam), estado das fases
(que muda a cada commit), medições (que vencem por data) e o raciocínio do
parecer (que é histórico). Manter isso íntegro à mão exigia editar 1.313 linhas
onde o imutável e o volátil se alternavam.

Não se sustentou. Três sintomas medidos em `85fd0c1`:

- As dezenove decisões estão declaradas em **duas tabelas separadas por 1.240
  linhas** — 0 a 8 na linha 7, e 9 a 18 na linha 1.264. A nº 9 é invocada sete
  vezes ao longo do texto como autoridade para revogar decisões anteriores, e
  vive numa célula a 1.200 linhas da primeira citação.
- As Fases 0 a 5 estão marcadas como concluídas em 19–20/08, e nove commits
  posteriores — as Ondas 1 a 4 de refatoração da UI — não têm lugar no roadmap.
- `RELATORIO_ANALISE.md`, citado na linha 5 como "documento anterior", não
  existe no repositório.

Célula de tabela não é endereço: não tem status, não tem data própria, não diz
o que governa, e nenhuma verificação automática consegue conferir se o código
ainda a respeita.

## Decisão

Separar por velocidade de mudança e por autoridade:

| Conteúdo | Muda | Destino |
|---|---|---|
| Decisões | nunca — só é substituída | `docs/decisoes/NNN-slug.md`, uma por arquivo |
| Estado | a cada commit | `docs/estado.md`, **gerado** por `scripts/gerar-estado.mjs` |
| Apontamentos externos | chegam fora do git | `docs/apontamentos/AAAA-MM-DD-quem.md` |
| Parecer e raciocínio | não deveria mudar | `PLANO_ARQUITETURA.md`, **congelado** |

O `PLANO_ARQUITETURA.md` **para de ser mantido** e passa a ser documento
histórico datado. Não se atualiza um parecer; substituem-se as decisões dele.
Documento congelado não apodrece — apenas envelhece, honestamente.

As decisões 0 a 18 permanecem válidas onde estão. Migrá-las para arquivo é
trabalho separado, e só se paga quando alguma precisar ser substituída.

## Consequências aceitas

- **Dois lugares durante a transição.** Quem procura uma decisão de 0 a 18 vai
  ao parecer; de 19 em diante, a `docs/decisoes/`. Unificar exigiria reescrever
  dezenove registros cuja proveniência está correta hoje — custo alto e risco de
  perder citação literal do orientador no caminho.
- **O parecer fica com afirmações que envelhecem.** É o preço de congelar, e é
  deliberado: um documento datado que se sabe datado engana menos que um
  documento vivo que ninguém atualiza.
- **Nada disso verifica semântica.** O gate local confere referência quebrada —
  caminho de `afeta` que não existe, número citado sem arquivo. Se o código
  ainda *respeita* a decisão é pergunta semântica, e cabe à lente `registro` do
  conselheiro, que aconselha e não bloqueia.

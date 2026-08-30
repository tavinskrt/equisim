---
numero: 20
titulo: Cadeia de QA por agente, com auditor que bloqueia e conselheiro que não
status: aceita
origem: voce
data: 2026-08-30
afeta:
  - scripts
  - .githooks
  - CLAUDE.md
  - lib/audit
substitui: []
---

## Contexto

Esta decisão é escrita **em resposta a um achado da própria ferramenta que ela
registra**. A lente `registro` do conselheiro reportou, com âncora no commit
`9ffaa6d` de 28/08/2026, uma tensão da classe ESTRUTURA SEM REGISTRO: o
repositório passou a hospedar uma infraestrutura extensa de auditoria por
modelo de linguagem, mais o barramento `lib/audit/`, sem decisão que os
explicasse.

O custo que ela apontou é específico e procede: o TCC é de engenharia de
software e sua evidência acadêmica é *a qualidade e a corretude verificável da
construção*. Um gate que governa o que entra no repositório, sem registro do
que ele faz e por que existe, enfraquece exatamente essa evidência — a banca
não consegue avaliar um mecanismo que não foi declarado.

## Decisão

Três agentes, com papéis que não se sobrepõem:

| Papel | Quem | Lê | Escreve | Bloqueia |
|---|---|---|---|---|
| **Auditor** | Gemini, backend `agy` | o diff | nada | sim — código 1 no `pre-push` |
| **Conselheiro** | Gemini, sete lentes | domínios inteiros | nada | **nunca** — código 0 sempre |
| **Implementador** | Claude Code | o repositório | código | — |

Mais uma camada determinística local ([scripts/qa-local.mjs](../../scripts/qa-local.mjs)),
sem rede, no `pre-commit`.

A regra que sustenta o arranjo: **quem propõe não bloqueia; quem bloqueia não
propõe.** O auditor é confiável porque é estreito — exige âncora em arquivo e
linha, e sua calibragem de severidade só reprova linha adicionada. Ampliá-lo
para "proponha melhorias" destruiria essa calibragem. Por isso o conselheiro é
um segundo agente, que compartilha o transporte e nada mais.

O barramento `lib/audit/` é parte da mesma evidência por outro caminho: ele
expõe a apuração de cada cálculo numa janela paralela, para que o orientador
acompanhe o número sendo formado em vez de confiar no resultado.

## Consequências aceitas

- **O conselheiro nunca entra em hook.** No instante em que um conselho puder
  travar um `git push`, o gate inteiro vira obstáculo e alguém o arranca. Ele
  sai com código 0 mesmo em falha de rede, cota ou JSON inválido.
- **O gate local só bloqueia referência quebrada, nunca defasagem.** Um gate que
  trava o push porque um documento envelheceu seria arrancado na primeira
  semana. Defasagem é semântica e cabe ao conselheiro.
- **Custo em tempo, não em dinheiro.** A cota é da assinatura Google AI Pro. Uma
  lente leva minutos, e seis das sete são texto puro — só `tela` depende de
  captura e do backend `api`, cujo tier gratuito dá vinte requisições por dia.
- **O conselho é falível e precisa de material completo.** Já se observou uma
  execução produzir duas tensões falsas porque a árvore enviada listava só cinco
  diretórios: material parcial gera ausência falsa, indistinguível de achado
  real para quem lê. Toda lente cujo objeto é "o que existe" envia listagem
  completa no escopo declarado.

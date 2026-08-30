# Registro de decisões

Uma decisão por arquivo, nomeado `NNN-slug.md`. **Depois de aceita, uma decisão
não se edita** — ela se substitui por outra, que a cita.

## Por que assim

O `PLANO_ARQUITETURA.md` misturava quatro conteúdos com quatro velocidades
diferentes: decisões (que nunca mudam), estado das fases (que muda a cada
commit), medições (que vencem por data) e o raciocínio do parecer (que é
histórico). Manter isso íntegro à mão exigia editar 1.313 linhas onde o
imutável e o volátil se alternavam. Não se sustentou: decisões passaram a ser
citadas como autoridade sem ter definição em lugar nenhum, e o roadmap parou de
saber o que o repositório tinha.

A separação por velocidade é o que conserta. Aqui mora só o que não muda.

## Formato

```markdown
---
numero: 9
titulo: Sem rebalanceamento; aporte inicial mais mensal
status: aceita
origem: orientador
data: 2026-08-19
citacao: >
  com a rentabilidade mensal podemos evidenciar ações
  com upside maior
afeta:
  - packages/equisim_core/lib/src/entities/
  - lib/presentation/backtest/
substitui: []
---

## Contexto

O que estava em aberto, e por que precisava ser decidido.

## Decisão

O que foi decidido, em uma ou duas frases.

## Consequências aceitas

O que se abre mão ao decidir assim. Alternativa descartada, e por quê.
```

## Os campos, e por que cada um existe

| Campo | Obrigatório | Para que serve |
|---|---|---|
| `numero` | sim | Endereço estável. É por ele que o resto do projeto cita. |
| `titulo` | sim | Uma linha, no indicativo. |
| `status` | sim | `aceita`, `cumprida`, `substituida-por-NNN`, `revogada` ou `perdida`. |
| `origem` | sim | `voce`, `orientador`, `dev:<nome>` ou `parecer`. |
| `data` | sim | Separa dívida herdada de regressão deliberada. |
| `citacao` | quando houver | Fala literal de quem decidiu. |
| `afeta` | sim | Caminhos governados pela decisão. |
| `substitui` | sim | Números que esta decisão derruba. Lista vazia é comum. |
| `postura` | quando houver | `reconstrucao`. Ver abaixo. |

### `status: cumprida` e `postura` andam juntos

Os dois entraram com a [decisão 22](022-reconstrucao-da-ui.md) e estavam em uso
sem constar desta tabela — divergência que a lente `registro` apontou, e com
razão: este README é o contrato que baliza
[postura.ts](../../scripts/qa/advisor/postura.ts), e automação rodando sobre
contrato não documentado é o que faz o registro deixar de descrever o projeto.

`postura: reconstrucao` declara que, **dentro do `afeta` daquela decisão**, a
distinção entre dívida herdada e regressão está suspensa: ali toda divergência
é acionável, porque a decisão de refazer já foi tomada. Fora dela a preservação
continua valendo integralmente.

`status: cumprida` fecha essa abertura. É o único status que **não** revoga a
decisão nem a substitui — ela continua valendo como registro do que se decidiu;
o que terminou é o trabalho que ela autorizava. `postura.ts` só conta
`status: aceita`, então marcar `cumprida` devolve a superfície à preservação
sozinho, sem tocar em configuração nenhuma.

**Marcar o status não é editar a decisão.** O corpo dela — contexto, decisão,
consequências — segue imutável, como o de qualquer outra. Uma decisão com
postura declara, no próprio texto, a condição de encerramento; alcançá-la é
registrar um fato, não mudar de ideia. Mudar de ideia continua exigindo decisão
nova que cite a anterior.

### `origem` e `citacao` são o que sobrevive até a banca

Decisão se defende pela origem. Quando o orientador determina algo numa reunião,
a fala dele é a justificativa — e reescrevê-la com outras palavras a
enfraquece. A decisão nº 9 é o caso exemplar: ela nasceu de uma frase do
orientador, foi invocada sete vezes no parecer para derrubar decisões
anteriores, e não tinha lugar canônico onde estivesse definida. Estava a um
`Ctrl+F` de se perder.

### `data` é o que torna a divergência computável

Sem ela não há como separar o código que **já estava assim** quando a decisão
foi tomada do código que **passou a contrariá-la depois**. O primeiro é dívida
herdada e entra num inventário; o segundo é regressão e vira tarefa. Os dois
chegam ao relatório com o mesmo peso quando não há data.

### `afeta` é o que a máquina consegue conferir

O gate local verifica que esses caminhos existem. Não verifica se o código
respeita a decisão — isso é semântico e cabe à lente `registro` do conselheiro.

## `status: perdida`

Reservado para número citado como autoridade em algum ponto do projeto, sem
definição localizável em lugar nenhum. **Não se preenche com suposição.** Uma
lacuna preenchida com dedução contamina exatamente o registro que esta pasta
existe para consertar; reconstituir é decisão de quem participou, não de quem
está lendo.

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
| `status` | sim | `aceita`, `substituida-por-NNN`, `revogada` ou `perdida`. |
| `origem` | sim | `voce`, `orientador`, `dev:<nome>` ou `parecer`. |
| `data` | sim | Separa dívida herdada de regressão deliberada. |
| `citacao` | quando houver | Fala literal de quem decidiu. |
| `afeta` | sim | Caminhos governados pela decisão. |
| `substitui` | sim | Números que esta decisão derruba. Lista vazia é comum. |

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

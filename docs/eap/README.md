# EAP da reconstrução da UI

Decomposição do trabalho declarado pela
[decisão 22](../decisoes/022-reconstrucao-da-ui.md). Um pacote por arquivo,
`UI-N-slug.md`.

## O que esta pasta é, e o que não é

**É especificação do alvo.** Cada pacote diz o que precisa existir e como se
confere que existe.

**Não é rastreador de estado.** Não há caixinha de feito aqui. O estado sai do
repositório, por `npm run estado` — e a razão é concreta: o
`PLANO_ARQUITETURA.md` já continha uma EAP informal, com `- [x]` e fases
marcadas como concluídas, e ela parou de descrever a realidade em nove commits.
Reconstruir o mesmo formato sem mudar o que o faz apodrecer daria o mesmo
resultado.

## Formato

```yaml
---
pacote: UI-1
titulo: <uma linha, no indicativo>
decisao: 22                    # a decisão que autoriza este pacote
origem: <de onde veio o achado>
escopo:
  - <caminhos que o pacote toca>
fora_de_escopo:
  - <o que explicitamente não entra>
criterio_de_pronto: >
  <observação verificável — algo que se possa conferir olhando>
---
```

`criterio_de_pronto` escrito como observação, não como intenção. "Melhorar a
navegação" não se confere; "cada aba abre a tela que seu rótulo nomeia" se
confere.

`fora_de_escopo` não é burocracia: é o que impede um pacote de escorregar para
o repositório inteiro.

## Relação com o encerramento

A decisão 22 fecha quando **todos** os pacotes tiverem o critério verificado.
Isso torna esta pasta o contrato do encerramento, e traz uma consequência que
vale dizer em voz alta: **acrescentar pacote estende o trabalho declarado.**

Pacote novo entra apenas enquanto a fronteira está aberta, e entrar é ato
deliberado — não é onde se anota ideia solta. Ideia solta que ainda não foi
confirmada fica na lista abaixo.

## Candidatos, ainda não confirmados

Observações que **não** passaram pela lente e portanto **não** gateiam o
encerramento. Só viram pacote depois de confirmadas.

- **Distribuição do espaço em 1024 dp.** Na captura `estudo@1024.png`, a
  Carteira Reserva vazia ocupa metade da largura enquanto a tabela da Principal
  fica espremida à esquerda; e o cabeçalho passa de apertado em 390 dp para
  solto em 1024 dp, sem que nenhuma das duas larguras trate o bloco como
  conjunto. *Origem: observação de leitura das capturas, feita pelo
  implementador. As três execuções da lente `tela` não levantaram isto* — ou o
  problema não existe, ou a lente não pega distribuição de espaço tão bem
  quanto pega incoerência de rótulo.

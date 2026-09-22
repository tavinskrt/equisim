---
numero: 124
titulo: A faixa calibrada replica sobre o motor da Fase 3 — a forma da decisão 100 não era ajuste ao teste
status: aceita
origem: voce
data: 2026-09-21
citacao: >
  Seus itens de escopo para esta rodada são B20, B22, B23, B21 e C5.
afeta:
  - docs/validacao/cobertura_banda.md
  - assets/validacao/banda_calibrada.json
  - docs/plano-motor-de-referencia.md
substitui: []
---

## Contexto

A [decisão 100](100-a-faixa-calibrada-sai-da-volatilidade-do-papel-e-o-justo-entra-com-o-peso-medido.md)
escolheu a forma da faixa calibrada — **convergência parcial na escala da
volatilidade** — e o fez com a regra escrita e posta em staging **antes** de a
ferramenta rodar. Foi a **sétima forma tentada** desde a decisão 92.

**Sétima tentativa é o número que obriga a réplica.** O item C2c existia por
isso: «a forma da decisão 100 é remedida sobre o motor que a Fase 3 deixar, **sem
escolher outra**» — porque uma forma que só cobre a amostra em que foi escolhida
é ajuste ao teste, e não calibragem.

O motor mudou doze vezes entre a decisão 100 e hoje (decisões 104 a 121), e a
base bruta foi reconstruída do zero pelo item C5.

## O que foi medido

Com as coortes reexecutadas — 10.919 observações, 31 coortes —, a **mesma forma**,
sem reescolha ([cobertura_banda.md](../validacao/cobertura_banda.md)):

| horizonte | n | 90% nominal cobre | 80% cobre | 50% cobre | desvio máximo |
|---|---:|---:|---:|---:|---:|
| 12 meses | 2.656 | **88,1%** | 79,1% | 50,8% | **1,9 p.p.** |
| 36 meses | 1.041 | **89,3%** | 81,2% | 52,6% | **2,6 p.p.** |

O critério do R2 é **5 p.p.**, nos dois horizontes.

E ela é estável por tercil de potencial — 88,3 / 87,5 / 88,3 em 12 meses — e
entre grupos: 88,5% nas listadas contra 85,0% nas deslistadas em 12 meses,
88,9% contra 93,9% em 36.

## Decisão

**A faixa calibrada replica, e o item C2c está atendido. O R2 é atingido sobre o
motor da Fase 3.**

1. **A forma não foi reescolhida.** É a mesma `VolatilityBandTable` da decisão
   100, sobre coortes reconstruídas de uma base bruta baixada de novo e um motor
   que mudou doze vezes. **Isso é réplica, e não reajuste.**
2. **O desvio caiu.** Na decisão 100, sobre o motor de então, a forma passava com
   folga menor; aqui o desvio máximo é de 2,6 p.p. contra o limite de 5.
3. **O pacote do aplicativo foi regerado** (`assets/validacao/banda_calibrada.json`),
   e é o que a tela de avaliação passa a mostrar.
4. **O R2 continua sendo o que a decisão 92 diz que é**: a incerteza é a faixa
   calibrada, e os cenários são sensibilidade. O que muda é que a faixa agora
   cobre o que promete **fora da amostra em que foi escolhida**.

## Consequências aceitas

**Uma condição atingida não é o alvo inteiro.** Das três do motor de referência,
R1 depende de o registro não ter defeito conhecido aberto, R2 está atingido e
**R3 está medido e reprovado** — o potencial condicionado ao book-to-market tem
`t` corrigido de 0,15 contra o crítico de 2,70, e nenhuma das cinco ordenações
passa ([decisão 123](123-o-multiplo-de-pares-entra-como-quarta-ordenacao-e-nao-passa.md)).

**A réplica é de uma amostra que se sobrepõe à original.** As coortes são as
mesmas datas; o que mudou foram o motor, a base e o preço justo dentro delas. É
réplica **do modelo**, e não de amostra independente — e uma amostra
verdadeiramente fora só existe com o tempo passando.

**O 36 meses continua com 1.041 observações e 22 coortes efetivas.** A
sobreposição entre coortes trimestrais de horizonte trienal é grande, e a
cobertura medida carrega essa dependência — é a mesma ressalva que a decisão 96
impõe ao `t`, e ela não desaparece por a cobertura ser um percentual em vez de
um teste.

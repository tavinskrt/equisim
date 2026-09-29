# Guia de estudo do Equisim

Este guia existe para quem precisa **entender** o que o motor de avaliação do
Equisim faz, sem ter estudado finanças nem estatística antes. Ele começa do zero
("por que dinheiro de hoje vale mais que dinheiro de amanhã") e termina com
cinco empresas reais calculadas passo a passo, com cada conta refeita.

> **Documentação do projeto ≠ guia de estudo.** A [documentação do motor](../motor/README.md)
> prova que cada linha tem fonte, fórmula e base teórica, e aponta para o
> código. Este guia **ensina** o que está por trás dessas linhas. Os dois se
> referem um ao outro.

---

## Por onde começar

| Se você quer… | Leia |
|---|---|
| aprender do zero, na ordem | os capítulos 1 a 7, depois os casos |
| entender um número da tela agora | o [capítulo 4](04-fluxo-de-caixa-descontado.md), seção 4.10, e o caso parecido |
| entender um passo do painel de logs | a [tabela do painel](../AUDITORIA_DE_CALCULOS.md) |
| preparar a reunião com o orientador | as [perguntas](perguntas-do-orientador.md) e o [capítulo 7](07-como-o-motor-foi-validado.md) |
| um plano de oito semanas | [onde estudar](onde-estudar.md) |
| o significado de um termo | o [glossário](glossario.md) |

## Os capítulos

| # | Capítulo | Pergunta que responde | Tempo |
|---:|---|---|---|
| 1 | [Dinheiro no tempo](01-dinheiro-no-tempo.md) | Quanto vale hoje um dinheiro futuro? | 40 min |
| 2 | [A empresa em números](02-a-empresa-em-numeros.md) | Quais números da empresa o motor lê, e o que eles querem dizer? | 50 min |
| 3 | [Risco e retorno](03-risco-e-retorno.md) | De onde vem a taxa de desconto? | 1h30 |
| 4 | [O fluxo de caixa descontado do Equisim](04-fluxo-de-caixa-descontado.md) | Como o motor chega ao preço justo, e o que são os números em volta? | 2h |
| 5 | [Bancos](05-bancos.md) | Por que banco é avaliado de outro jeito, e que contas mudam? | 40 min |
| 6 | [A estatística que o motor usa](06-estatistica.md) | Como o motor decide se uma estimativa é confiável? | 1h30 |
| 7 | [Como o motor foi validado](07-como-o-motor-foi-validado.md) | O motor funciona? O que se pode afirmar? | 40 min |

## Os casos

Cinco empresas avaliadas pelo motor em 14/09/2026, sobre a entrada congelada do
gabarito. Cada caso segue os passos do painel de logs, na ordem, com as contas
refeitas e o porquê de cada uma.

| Caso | O que ele mostra | Resultado |
|---|---|---|
| [WEGE3 — WEG](casos/wege3.md) | a via da firma completa, com caixa líquido e vantagem competitiva residual | R$ 12,53 (mercado: R$ 50,74) |
| [ITUB4 — Itaú](casos/itub4.md) | a via do acionista de um banco, e o que não é calculado nela | R$ 21,76 (mercado: R$ 42,35) |
| [VALE3 — Vale](casos/vale3.md) | normalização pelo ciclo em commodity | R$ 70,25 (mercado: R$ 75,48) |
| [SAPR11 — Sanepar](casos/sapr11.md) | unit (5 ações por papel) e concessão | R$ 36,74 (mercado: R$ 34,74) |
| [RENT3 — Localiza](casos/rent3.md) | a recusa: quando a conta não fecha | recusada |

Os dados de cada caso — insumos, resultado, cenários, Monte Carlo, faixa
calibrada, múltiplos e o rastro inteiro do painel de logs — estão em
[casos/dados/](casos/dados/), gerados por:

```bash
dart run tool/casos_de_estudo.dart
```

A entrada é congelada: o resultado só muda se o motor mudar. Quando isso
acontecer, rode de novo e confira os números dos casos.

## Convenções deste guia

- Números em português: vírgula decimal, ponto de milhar (R$ 1.234,56).
- Fórmulas em texto simples, sem notação matemática pesada:
  `valor presente = fluxo ÷ (1 + taxa)^anos`.
- "No código:" aponta o arquivo que faz a conta, para quem quiser conferir.
- Toda afirmação sobre o que o motor faz foi conferida no código em
  28/09/2026. Se o código mudar, a [documentação do motor](../motor/README.md)
  muda junto, e este guia deve ser relido.

---
numero: 117
titulo: Risco-país e ajuste por tamanho são recusados, com medição — o R_f brasileiro já contém um, e o beta já cobra o outro
status: aceita
origem: voce
data: 2026-09-21
citacao: >
  Seus itens de escopo para esta rodada são B6, B7, B3, B4 e B5.
afeta:
  - tool/tamanho.dart
  - tool/premio_de_mercado.dart
  - docs/validacao/risco_pais_e_tamanho.md
substitui: []
---

## Contexto

O item B4 acusava: «não há prêmio de risco-país, nem ajuste por tamanho, nem
qualquer fator além do beta. Um CAPM de fator único é defensável num artigo e é
fraco como motor de referência». O critério de pronto pedia decisão registrada,
com os dois **implementados ou recusados com medição**.

## O que foi medido

Sobre a entrada congelada do gabarito, com a montagem conferida ativo a ativo
([risco_pais_e_tamanho.md](../validacao/risco_pais_e_tamanho.md)).

### Risco-país

A taxa livre de risco deste motor é **brasileira, em reais** — CDI e curva do
Tesouro Nacional, que já precificam risco soberano e inflação local.

| | nominal | real (IPCA de 4,5%, Fisher) |
|---|---:|---:|
| `R_f` corrente | 14,15% | **9,23%** |
| `R_f` terminal | 9,40% | **4,69%** |

Contra um juro real americano de longo prazo da ordem de 2%. A forma usual do
ajuste — `ERP_maduro + CRP` ≈ 8% — custa, sobre esse `R_f`: **−13,29%** de preço
justo mediano e **quatro avaliações**.

### Tamanho

| postos de `log`(valor de mercado) contra | |
|---|---:|
| beta | **−0,327** |
| taxa de desconto | −0,184 |

| tercil | beta mediano | desconto mediano | potencial mediano |
|---|---:|---:|---:|
| menor (R$ 2,25 bi) | **1,387** | 18,91% | −34,04% |
| maior (R$ 94,11 bi) | **0,876** | 17,89% | −42,16% |

A diferença de beta é de **0,511** — ao prêmio de 5,5%, **2,81 p.p.** de custo do
capital próprio a mais para os menores.

Dois pontos somados ao prêmio só do tercil menor: preço justo **−11,64%** nele,
**0,00%** no universo, postos do potencial em **0,9920**, nenhuma avaliação
perdida.

## Decisão

**Os dois são recusados, com a medição ao lado.**

1. **Risco-país não entra, porque já entrou.** Somá-lo sobre um `R_f` de 9,23%
   de juro real é contar duas vezes a mesma coisa: o prêmio-país existe para
   compensar quem desconta ao Treasury, e este motor não desconta ao Treasury.
   **A forma correta de usá-lo seria converter a avaliação para dólar** e
   descontar à curva americana — caminho legítimo para quem avalia emergente em
   moeda forte, e que não é o deste projeto, que avalia companhia brasileira em
   reais contra preço em reais.
2. **Tamanho não entra, porque o beta já cobra a magnitude certa — e um pouco
   mais.** 2,81 p.p. de diferença entre os tercis extremos passa da ordem de
   grandeza do prêmio por tamanho da literatura de fatores. Somar por cima seria
   empilhar o mesmo ajuste duas vezes.
3. **E somar não muda a ordenação.** Postos de 0,9920. O que muda é o nível de um
   terço do universo, **para baixo, justamente no tercil de potencial menos
   negativo** — afastando o motor do mercado em vez de aproximá-lo.
4. **O CAPM continua de fator único, e isso continua declarado.** A recusa é do
   ajuste, e não da crítica: o que a medição estabelece é que os dois fatores
   nomeados pelo item **já estão dentro do modelo por outro caminho**, e não que
   um modelo multifatorial seja desnecessário.

**O motor não muda.**

## Consequências aceitas

**Não há medição de retorno realizado por tamanho.** Se pequenos brasileiros
renderam mais no período, é pergunta de coorte e depende da base bruta (item
C5). O que está medido é o que o motor **cobra**, e o que um ajuste mudaria.

**O beta maior dos pequenos pode carregar ruído de liquidez.** A
[decisão 108](108-a-recusa-por-liquidez-fica-e-o-beta-corrigido-fecha-um-terco-da-distancia.md)
mediu o viés de negociação não sincrônica e manteve a recusa por liquidez; aqui
a leitura é sobre quem **passa** no corte, onde o viés é menor — mas não é zero,
e ele empurra na direção de o beta dos pequenos estar **subestimado**. Isso
reforça a decisão, e não a enfraquece.

**Outros fatores continuam fora.** Valor, momento e qualidade não entram no custo
de capital, e a §0 do plano já mostrou que o book-to-market ordena mais que o
potencial — assunto do B1 e do C1, e não deste item.

**O valor de mercado usado é o da fonte**, que erra em alguns tickers (decisão
83). Ele entra **só na ordenação** por tamanho, onde erro de escala não troca
tercil; nenhuma conta de dinheiro depende dele.

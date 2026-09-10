# O degrau da vantagem competitiva

Medido em 09/09/2026, sobre os 117 ativos que a cascata avalia e para os quais
o retorno do ciclo é medível.

```bash
dart run tool/fade_terminal.dart   # grava fade_terminal.json
```

---

## 0. Por que esta medição

A [decisão 35](../decisoes/035-dcf-reverso-e-regressao-condicional.md) tirou do
decaimento contínuo de `RONIC` o argumento que ele tinha: o terminal **não** é
a causa do viés de nível, e trocá-lo não conserta o nível. A mesma decisão diz
que quem propuser a troca depois dela precisa de outro argumento.

Este documento produz o outro argumento, e ele não é sobre nível — é sobre
**descontinuidade**. A exceção de vantagem competitiva é um degrau: quem passa
nas cinco condições recebe `r_∞ + 0,30·(ROIC_ciclo − r_∞)`; quem falha em uma
recebe `r_∞`, e nada entre os dois.

É defeito da mesma família do que a
[decisão 34](../decisoes/034-fronteira-das-vias-medida-na-taxa-estrutural.md)
corrigiu na fronteira das vias: preço justo descontínuo numa grandeza contínua.

---

## 1. O degrau é material

Dos 117 avaliados, **48 têm excedente positivo** — `ROIC` do ciclo acima do
custo de capital de equilíbrio — e **8 recebem a exceção**.

Saltando de `λ = 0` para `λ = 0,30`, o preço justo se move:

| p25 | mediana | p75 | máx |
|---:|---:|---:|---:|
| 0,9% | **5,7%** | 9,9% | 32,2% |

Acima de 10% em 11 dos 48. Não é ruído de arredondamento: é o tamanho da
diferença entre estar de um lado ou do outro de um limiar.

## 2. E ele está ordenado ao contrário

Os oito **negados** que mais ganhariam com a exceção:

| Ativo | salto | ROIC ciclo | `r_∞` | o que barra |
|---|---:|---:|---:|---|
| UNIP6 | **22,3%** | 28,9% | 12,5% | inorgânico, saúde |
| SLCE3 | **18,6%** | 12,7% | 10,1% | inorgânico, rentabilidade, saúde |
| SAPR4 | **16,2%** | 11,9% | 9,5% | **rentabilidade** |
| BEEF3 | 14,8% | 16,9% | 13,4% | inorgânico, rentabilidade |
| SAPR11 | 14,6% | 11,9% | 9,6% | **rentabilidade** |
| TAEE4 | 13,7% | 12,4% | 11,0% | **rentabilidade** |
| MBRF3 | 12,2% | 44,5% | 14,1% | inorgânico, saúde |
| TAEE11 | 11,7% | 12,4% | 11,2% | **rentabilidade** |

Contra os oito **concedidos**, cujo salto vai de 0,0% (LEVE3, SAUD3) a 32,2%
(EGIE3), com mediana em torno de 9%.

**Seis dos oito negados acima ganhariam mais do que a maioria dos concedidos.**
A exceção entrega o prêmio onde ele pesa menos e o nega onde pesa mais — e a
razão não é econômica, é onde o limiar caiu.

Quatro deles — SAPR4, SAPR11, TAEE4 e TAEE11 — são barrados **só** por
rentabilidade: saneamento e transmissão, com excedente de 2,4 p.p. a 1,4 p.p.,
abaixo dos 5 p.p. de `moatMinSpread` e do múltiplo. É exatamente o perfil de
excedente modesto e persistente que um `λ` contínuo descreve e um corte não.

### A vizinhança do corte é povoada

Dezenove ativos estão a menos de 3 p.p. da aprovação. Entre eles, **RENT3 e
RENT4** — mesma empresa, mesmo ROIC de 23,6% — caem em lados opostos da conta
de rentabilidade, com folgas de +1,40 e −0,45 p.p., porque o `r_∞` de cada
classe difere pelo beta. O limiar está separando ruído de estimação.

### E ele pode cortar para o outro lado

A **VBBR3** tem salto de **−90,2%**: impor `λ = 0,30` derruba o preço justo em
nove décimos. É a não monotonia que o
[DCF reverso](dcf_reverso.md#26-um-achado-colateral-a-não-monotonia-sobreviveu)
mediu em 46 dos 122 — o terminal maior aumenta o valor da firma, a
participação do capital próprio cruza os 20%, a migração de via deixa de
disparar e o ativo cai na via que para ele devolve menos. O degrau da vantagem
competitiva e o degrau da ponte de equity interagem.

---

## 3. Que `λ` a persistência medida sugere — e é aqui que a intuição vira

`λ = 0,30` afirma que 30% do excedente sobrevive à perpetuidade. Se o excedente
decai a uma taxa `φ` ao ano ao longo dos dez anos de projeção, isso equivale a
`φ¹⁰ = 0,30`, ou seja **`φ = 0,887`**.

Estimando `φ` por AR(1) sobre o excedente `ROIC_t − r_∞` de cada ativo:

| | p25 | mediana | p75 | p90 | máx |
|---|---:|---:|---:|---:|---:|
| `φ` observado | 0,27 | **0,48** | 0,67 | 0,78 | 0,93 |
| `λ = φ¹⁰` | — | **0,0007** | 0,019 | 0,088 | 0,476 |

**Um único ativo dos 47 mensuráveis tem `φ` acima dos 0,887 que o parâmetro
fixo pressupõe.** A mediana de `λ` implícita é 0,0007 — três ordens de grandeza
abaixo de 0,30. Seis ativos têm `φ ≤ 0`: o excedente deles oscila em vez de
decair, e não há vantagem a preservar.

**A conclusão é robusta ao viés de amostra pequena.** O AR(1) com sete a quinze
pontos é enviesado para baixo — o viés de Kendall é da ordem de `−(1+3φ)/n` —,
mas corrigi-lo desloca `φ` em algo como 0,05 a 0,10. Para sustentar `λ = 0,30`
seria preciso levar a **mediana** de 0,48 a 0,887, o que está muito além de
qualquer correção de viés defensável. O p90 observado, 0,784, ainda fica
abaixo.

A fração mediana de anos com excedente positivo é de **0,60**: as empresas
passam a maior parte do tempo acima do custo de capital, mas o *tamanho* do
excedente não se sustenta de um ano para o outro.

---

## 4. O que isto autoriza

**Autoriza:** afirmar que a exceção de vantagem competitiva é descontínua, que
a descontinuidade vale de 10% a 32% de preço justo em onze ativos, que ela está
ordenada ao contrário do tamanho do efeito, e que o `λ = 0,30` fixo **não é
sustentado pela persistência medida do universo** — é alto por uma ordem de
grandeza.

Isso é o "outro argumento" que a decisão 35 exige. E ele é sobre forma, não
sobre nível.

**Não autoriza:** esperar que a troca melhore o potencial. Ela o **piora**: os
oito concedidos hoje perderiam quase todo o prêmio, e os negados ganhariam
quase nada, porque o `λ` medido deles também é próximo de zero. Em prática, um
*fade* honesto é quase idêntico a **remover a exceção**.

**Não autoriza tampouco** tratar `φ` estimado em sete a quinze pontos como
número de precisão. Ele sustenta uma ordem de grandeza — "o excedente não
persiste dez anos" — e não uma calibragem por ativo com três casas.

---

## 5. A questão de governança que isto abre

As condições que barram hoje não são todas da mesma natureza:

| Condição | Natureza | Origem |
|---|---|---|
| sem retorno do ciclo, sem custo de capital, histórico curto | **qualidade de dado** — sem elas não há o que estimar | decisão 25 |
| capital externo (Φ) | qualidade de dado — crescimento inorgânico contamina a série | decisões 25, 28 |
| rentabilidade insuficiente | **nível** — é o corte que cria o degrau | decisão 25 |
| saúde operacional | **nível** | decisões 28, 29, 30 |

Um `λ` contínuo torna as duas últimas redundantes por construção: excedente
pequeno produz `λ·e₀` pequeno sem precisar de limiar, e deterioração aparece na
própria série que estima `φ`. Removê-las, porém, deixa inerte parte do que as
decisões 28, 29 e 30 construíram — inclusive a isenção cíclica da decisão 30.

Isso é decisão de registro, não de código.

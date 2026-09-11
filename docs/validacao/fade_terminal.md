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

*As folgas desta subseção são medidas contra o corte de rentabilidade, que a
decisão 36 removeu. Ficam como registro do regime que o motivou.*

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

**A conclusão é robusta ao viés de amostra pequena** — mas por um caminho
diferente do que se supunha aqui. O AR(1) com sete a quinze pontos é enviesado
para baixo, e o viés de Kendall é da ordem de `−(1+3φ)/n`. A primeira redação
desta seção estimou o deslocamento em 0,05 a 0,10; **medido, ele vale de 0,25 a
0,35**, e a §6.4 mostra o que isso fez. O que sustenta a conclusão não é a
correção ser pequena: é que nem com ela a mediana chega perto dos 0,887 que o
parâmetro fixo pressupõe, e que aplicá-la joga o grupo de cima no teto,
reintroduzindo o degrau um passo adiante.

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
própria série que estima `φ`.

**Resolvido em 09/09/2026 pela [decisão 36](../decisoes/036-decaimento-medido-do-excedente-na-perpetuidade.md),
e custou menos do que parecia.** A trava de saúde tem **dois** usos, e só o do
*moat* saiu: na Porta 2a ela continua inteira, proibindo normalizar a base para
cima — que é onde a QUAL3 era de fato resolvida. A isenção cíclica da decisão 30
opera ali, e segue valendo. Do que as decisões 28, 29 e 30 construíram, ficou
inerte a consulta secundária que o *moat* fazia, e não a trava.

---

## 6. O que a implementação produziu

Implementado pela [decisão 36](../decisoes/036-decaimento-medido-do-excedente-na-perpetuidade.md)
e medido contra o mesmo universo, na mesma data e com as mesmas âncoras.

### 6.1 A cobertura quase triplica e a magnitude despenca

| | degrau | decaimento medido |
|---|---:|---:|
| ativos com preservação positiva | 8 | **23** de 117 |
| `λ` mediano | 0,300 | **0,0015** |
| `λ` p75 / p90 | 0,300 | 0,0429 / 0,0879 |
| `λ` máximo | 0,300 | **0,2580** |
| ativos no teto (`λ = 0,3487`) | — | **0** |

SAPR4 e SAPR11 passam a receber preservação, junto com CPFE3 e QUAL3 — os casos
que o corte de rentabilidade barrava por 2,3 a 2,4 p.p. de excedente.

### 6.2 O efeito no preço justo é cirúrgico, e para baixo

**Oito dos 117 se movem além de 0,5%.**

| Ativo | variação | `λ` novo | tinha a exceção |
|---|---:|---:|:---:|
| EGIE3 | **−24,3%** | 0,0000 | sim |
| BBSE3 | **−15,1%** | 0,0015 | sim |
| CXSE3 | −7,0% | 0,0000 | sim |
| ABEV3 | −6,7% | 0,0429 | sim |
| VBBR3 | −5,8% | 0,0000 | sim |
| WEGE3 | −3,7% | 0,1719 | sim |
| RADL3 | +1,1% | 0,0420 | não |
| CPFE3 | **+8,1%** | 0,2580 | não |

As seis maiores quedas são todas de quem tinha a exceção. É o esperado: o
degrau lhes dava 0,30 e a série deles não sustenta nem um décimo disso.

### 6.3 O nível não se move, e isso corrobora a decisão 35

| | antes | depois |
|---|---:|---:|
| potencial mediano | −52,2% | **−52,2%** |
| potenciais positivos | 14 | **14** |

A troca do terminal — a hipótese que estava em primeiro lugar da fila para
consertar o viés de nível — não move o nível em ativo nenhum além dos oito
acima. É a segunda medição independente a dizer o mesmo.

### 6.4 A correção de viés foi implementada, medida e descartada

O viés de Kendall é real: o AR(1) com intercepto subestima `φ`, e a correção de
primeira ordem vale `(1 + 3φ̂)/T`. Ela foi escrita e rodada.

Com sete a dez pares, a correção vale de 0,25 a 0,35 — **a mesma ordem de
grandeza do próprio `φ̂`**, cujo erro-padrão nesses tamanhos é de 0,3 a 0,4.
O efeito medido:

| | com correção | sem correção |
|---|---:|---:|
| ativos com preservação | 24 | 23 |
| `λ` mediano | 0,0310 | 0,0015 |
| `λ` p75 / p90 / máx | 0,3487 / 0,3487 / 0,3487 | 0,0429 / 0,0879 / 0,2580 |
| **ativos no teto** | **10 de 24** | **0** |

Com a correção, p75, p90 e máximo colapsam no mesmo número: **o teto passou a
decidir no lugar do dado**, trocando um `0,30` fixo por um `0,3487` fixo para o
grupo de cima. Era reintroduzir o degrau um passo adiante.

Ficou o `φ̂` cru, e o viés para baixo fica **declarado como conservadorismo** —
a persistência medida subestima a verdadeira, e a subestimação empurra o preço
justo para baixo, que é a direção em que este projeto já erra e admite errar.

### 6.5 O que continua em aberto

1. **`φ` por ativo em sete a quinze pontos é ordem de grandeza, não
   calibragem.** O conserto estatístico correto é encolher para uma média
   transversal, e o núcleo avalia um ativo por vez — não enxerga a seção. Fazer
   isso exigiria passar a média como parâmetro, o que é decisão nova.
2. **A não monotonia da VBBR3 continua.** Ela vinha da interação entre o
   terminal e a fronteira dos 20% da ponte, e o decaimento medido não a toca —
   só torna o salto menor.
3. **O excedente é medido contra `r_∞`**, e portanto uma revisão da curva de
   desconto (item 4 do roteiro) muda a série que estima `φ`.

---

## 7. Duas correções posteriores, de 10/09/2026

Ambas vieram da auditoria e do conselheiro, e nenhuma muda preço justo hoje.

### 7.1 O AR(1) passou a exigir anos adjacentes

`CapitalSeries.returns` pula exercício sem base ou sem lucro, então a lista
pode ter buraco de calendário. A regressão pareava posições, não anos — e
regredir 2023 sobre 2019 leria quatro anos de decaimento como um, enviesando
`φ` para baixo.

O ano passou a viajar com o excedente, e só pares adjacentes entram. O
parâmetro mínimo passou a contar **pares** em vez de pontos, porque série com
buraco tem menos pares que pontos e contar pontos deixaria passar o caso que o
requisito existe para barrar.

**Efeito medido: zero.** Nenhum dos 122 preços justos se move além de 0,5% — o
cache não tem buracos nas séries que chegam a ter `λ` positivo. É conserto que
previne, não que corrige.

### 7.2 O retorno terminal aplicado saiu no resultado

`ValuationDiagnostics.terminalReturnOnCapital` passou a carregar o número que a
conta usou. Ele é `r_∞ + λ·(ROIC do **ciclo** − r_∞)`, e o ciclo **não** é
`returnOnCapital` — este é o do fluxo-base, `retorno corrente × fator`. Quem
remontasse o terminal a partir dos campos anteriores erraria em todo ativo com
fator diferente de 1, e era o que `tool/fluxo_explicito.dart` fazia.

---

## 8. D12 — a volta entre o veredito e a taxa (10/09/2026)

A [decisão 44](../decisoes/044-moat-contra-a-taxa-resolvida.md) fechou **um**
passe de uma volta circular:

```
veredito → retorno terminal → projeção → alavancagem → taxa de equilíbrio → veredito
```

Ela mediu o veredito contra a taxa interpolada, refez contra a resolvida, e
parou. **O segundo passe resolve as taxas de novo, e a taxa que ele devolve não
é a que o veredito usou** — de modo que a pergunta se repõe exatamente como
estava. Parar ali foi escolha declarada, sustentada por um `λ` mediano de
0,0015.

### 8.1 A cauda é mais longa do que o argumento supunha

Fechando a volta até o par parar de mudar, com teto de dez passes:

| passes até estabilizar | ativos |
|---:|---:|
| 1 | 81 |
| 2 | 11 |
| 3 | 1 |
| 4 | 2 |
| 5 | 3 |
| 6 | 1 |
| 8 | 1 |
| 9 | 4 |
| 10 (teto) | 1 |
| **não estabilizaram** | **3** |

**Doze precisam de três passes ou mais**, e não de dois. O `λ` mediano continua
pequeno; o que ele não dizia é que a cauda existe.

### 8.2 Três não têm ponto fixo, e isso é propriedade do problema

Na fronteira exata do veredito, conceder o excedente muda a taxa de equilíbrio
o bastante para recusá-lo, e recusá-lo a devolve. Não é falha numérica: é a
circularidade não tendo solução naquele ponto.

O teto existe por isso, e a parada é declarada com o motivo — se foi o teto ou
se foi o solucionador não fechar a taxa que o veredito seguinte pedia. **Vale
sempre o último par consistente entre si**: retorno terminal e caminho de taxas
resolvidos um contra o outro.

### 8.3 O defeito que o laço expôs

O código anterior adotava o veredito refeito **antes** de saber se a taxa dele
existia:

```dart
moat = novoMoat;                       // adotado
final segundo = resolverTaxas(...);    // e só então resolvido
if (segundo.isOk && ...) r = segundo;  // se falhar, r fica o anterior
```

Quando o solucionador não fechava, o preço saía com o **retorno terminal de um
passe descontado pelo caminho de taxas do outro** — premissa de uma conta
contra o desconto de outra, sem nada acusando.

Aconteceu em dois ativos, e vale 17,5%:

| Ativo | variação ao corrigir |
|---|---:|
| KLBN3 | **+17,5%** |
| KLBN11 | +17,4% |

Agora o veredito só é adotado depois que a taxa dele fecha.

### 8.4 O efeito do ponto fixo em si

| Ativo | variação | passes |
|---|---:|---:|
| TAEE4 | −2,7% | 10 (teto) |
| SMTO3 | −1,8% | 9 |

Os dois que a cauda alcançou. O potencial mediano do universo não se move.

### 8.5 E a auditoria pegou um `NaN` de brinde

Pelo lado do acionista o `enterpriseValue` do solucionador é `E + D`, e com
caixa líquido maior que o próprio negócio ele fica não positivo. A participação
do capital próprio perdia sentido e saía como **`NaN%` no aviso ao usuário**.

`equityShareAt` passa a devolver nulo — não é "zero por cento", é "a pergunta
não se aplica" —, e o aviso diz isso com palavras.

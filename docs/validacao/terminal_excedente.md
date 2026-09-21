# O excedente do capital instalado na perpetuidade — item B12

> **Medido em 21/09/2026**, sobre a entrada congelada do gabarito da cascata
> (`tool/gabarito_cascata.dart`), que fixa cache, Ibovespa e universo. Os
> números saem dos diagnósticos que a cascata devolve, e não de uma conta
> paralela.

## 1. A álgebra, e o que o rótulo não diz

O terminal neutro do motor é `VT = lucro_{N+1}/r`. O que faz o crescimento sair
da fórmula é a afirmação `RONIC_∞ = r`: **o capital novo não cria valor**, de
modo que reinvestir é indiferente e a taxa de crescimento perpétuo some.

A mesma expressão, reagrupada:

```
VT = lucro_{N+1}/r = capital_N + EVA_{N+1}/r
com  EVA_{N+1} = lucro_{N+1} − r·capital_N
```

A segunda parcela é o que o capital **já instalado** rende acima — ou abaixo —
do custo dele, mantido para sempre. **O rótulo "não há lucro econômico em
perpetuidade" é afirmação sobre o retorno médio, e essa afirmação só seria
verdadeira se `EVA_{N+1}` fosse zero.**

Nas concessões a [decisão 88](../decisoes/088-o-prazo-da-concessao-corta-o-excedente.md)
já corta esse excedente no fim do contrato, pela mesma álgebra: ali
`VT = capital_N + EVA·anuidade(M)`. Fora delas, `M` é infinito.

## 2. A medição inverte o que o item supunha

O item B12 falava em "manter para sempre o retorno **acima** do custo". Medido,
é o contrário na grande maioria: o capital instalado rende, na perpetuidade,
**0,71 vez** o custo de capital de equilíbrio na mediana, e fica abaixo dele em
**71 dos 83** avaliados em que a decomposição se aplica.

| | mediana |
|---|---:|
| retorno implícito do capital instalado | **12,9%** |
| custo de capital de equilíbrio | 18,9% |
| razão entre os dois | **0,710** |

| razão retorno ÷ custo | p10 | p25 | mediana | p75 | p90 |
|---|---:|---:|---:|---:|---:|
| | 0,389 | 0,516 | **0,710** | 0,940 | 1,050 |

**O terminal mantém um déficit, e não um excedente.** Para o ativo mediano, ele
avalia o negócio em 71% do capital investido que a projeção implica — que é o
que vale uma companhia que rende abaixo do custo de capital para sempre.

O peso disso no preço:

| peso de `EVA_{N+1}/r` no valor do capital próprio | p10 | p25 | mediana | p75 | p90 |
|---|---:|---:|---:|---:|---:|
| | −61,8% | −30,7% | **−14,1%** | −2,6% | +2,3% |

Passa de 10% em módulo em **50 dos 83**, de 20% em **33** e de 50% em **11**. Os
extremos são ativos de capital próprio fino, onde qualquer parcela do terminal
sai amplificada — a EMBJ3 chega a −610%, com peso do terminal de 238%.

### De onde vem o mecanismo

O capital da projeção parte de `lucro_1 ÷ ROIC_base` — a base observada — e
acumula a retenção de cada ano. O `ROIC` que o freio de reinvestimento faz
convergir para o custo de capital é o **marginal**: cada real retido rende
`ROIC_t`, e `ROIC_t → r_N`. A **média** `lucro/capital` caminha na direção do
marginal e não chega lá em dez anos, de modo que ela termina perto do `ROIC`
observado do ativo. Companhia que rende pouco continua rendendo pouco no
terminal, e é isso que o preço carrega.

## 3. Decair num horizonte não é uma terceira opção

O item oferecia três saídas: fica, decai, ou acaba num horizonte. A 18,9% ao
ano, as duas últimas colapsam na primeira.

Com o excedente truncado em `M` anos — exatamente a forma da decisão 88 —, ele
vale `EVA·(1 − (1+r)^-M)/r`, e o preço justo se move:

| horizonte | p25 | mediana | p75 |
|---|---:|---:|---:|
| 0 anos (`VT = capital_N`) | +2,2% | **+14,1%** | +28,4% |
| 10 anos | +0,4% | +2,5% | +4,8% |
| 20 anos | +0,1% | +0,4% | +0,8% |
| 30 anos | +0,0% | +0,1% | +0,2% |

**Vinte anos devolvem 0,4% do preço justo.** A escolha é binária: ou o instalado
mantém o retorno que a projeção alcança, ou converge ao custo de capital de
imediato.

## 4. O que se decidiu, e por quê

[Decisão 107](../decisoes/107-o-terminal-neutro-e-do-capital-novo-e-o-instalado-mantem-o-retorno-que-tem.md):
**o número fica, o rótulo muda, o peso é declarado.**

- **O número fica** porque trocar o terminal por `capital_N` é afirmar reversão
  da rentabilidade à média, e o motor não mediu isso. A
  [decisão 35](../decisoes/035-dcf-reverso-e-regressao-condicional.md) exige que
  quem proponha trocar o terminal traga um argumento que não seja o viés de
  nível; o argumento do B12 é sobre declaração.
- **O rótulo muda**: o retorno neutro é `RONIC_∞ = r`, sobre o capital novo.
- **O peso é declarado**: nos diagnósticos, sempre no rastro de auditoria, e
  como ressalva na avaliação acima de 20% em módulo — o corte que separa a
  parcela que é detalhe da que é a premissa dominante.

## 5. Como a decomposição é conferida

Ela não é aproximação: é a mesma álgebra do terminal de contrato, por outro
caminho. O teste `o terminal neutro e o capital instalado › tirar o excedente é
o mesmo que cortar o contrato em zero ano` confere, para três níveis de `ROIC`,
que

```
preço justo(contrato de 0 ano) = preço justo(neutro) − excedente descontado
```

ao centavo. Se as duas contas divergirem, a parcela declarada deixa de valer, e
a suíte reprova.

## 6. O que isto não diz

- **Não diz que o motor erra o nível.** Diz que a premissa sobre o retorno do
  capital instalado é a persistência, e que ela vale 14% do preço na mediana.
- **Não mede reversão à média.** Medir se o `ROIC` brasileiro reverte, em que
  horizonte e com que dispersão, é o item **B19**, e é o que pode reabrir a
  escolha.
- **A decomposição não existe em toda avaliação.** Com vantagem competitiva
  concedida o terminal é outro; com contrato, o corte já está feito; sem capital
  medível, não há o que separar. São 19 dos 102 avaliados.

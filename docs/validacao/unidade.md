# A unit que a tolerância não reconhecia

Medido em 11/09/2026, com preços de 04/09/2026.

```bash
dart run tool/unidade.dart        # grava unidade.json
dart run tool/unit_vs_classe.dart # confronta unit e classe
dart run tool/grupamento.dart     # grava grupamento.json
```

---

## 1. O defeito

`ValuationCascade.quotedUnitRatio` mede `ações × preço ÷ valor de mercado`,
arredonda, e recusa o resultado a mais de **0,12 absolutos** de um inteiro.

O desvio que ela testa é a discordância **relativa** entre `ações × preço` e
`u × valor de mercado` — o quanto o preço andou desde o valor de mercado
publicado. Testá-la com banda absoluta dá 12% de folga em `u = 1`, onde aceitar
e recusar devolvem o mesmo 1,0, e 1,2% em `u = 10`, onde o fator errado custa
dez vezes.

## 2. Os 359 ativos com razão mensurável

| ticker | bruto | inteiro | desvio abs | desvio rel | u adotado (antes) |
|---|---:|---:|---:|---:|---:|
| AZUL3 | 18,4466 | 18 | 0,4466 | 2,48% | 1 (teto) |
| KLBN11 | 4,9745 | 5 | 0,0255 | 0,51% | 5 |
| ENGI11 | 4,9633 | 5 | 0,0367 | 0,73% | 5 |
| **SAPR11** | **4,8799** | **5** | **0,1201** | **2,40%** | **1** |
| TAEE11 | 3,0174 | 3 | 0,0174 | 0,58% | 3 |
| IGTI11 | 2,9887 | 3 | 0,0113 | 0,38% | 3 |
| ALUP11 | 2,9691 | 3 | 0,0309 | 1,03% | 3 |
| BRBI11 | 2,9586 | 3 | 0,0414 | 1,38% | 3 |
| BPAC11 | 2,9400 | 3 | 0,0600 | 2,00% | 3 |
| SANB11 | 2,0341 | 2 | 0,0341 | 1,70% | 2 |
| EQPA5 | 1,7912 | 2 | 0,2088 | 10,44% | 1 |

**A SAPR11 era recusada por 0,0001** — e é uma das duas ações que a
documentação da própria função nomeia como motivo de ela existir.

Os dois grupos se separam com folga: unit real em **2,40% ou menos**, falso
positivo mais próximo em **10,44%**. A tolerância relativa de 5% fica no meio,
com fator de quatro para cada lado, e nenhum outro ativo muda de fator.

Abaixo de `u = 2` a tolerância não decide nada — ONCO3 (17,09%), AZEV3
(14,62%), CVCB3 (13,94%), VSTE3 (13,74%), ISAE4 (16,47%), BPAC5 (17,61%) e
PMAM3 (21,95%) recebem 1,0 tanto aceitos quanto recusados.

## 3. A conferência: a unit contra a classe que a compõe

Nenhuma peça isolada enxerga este defeito. A razão de unidade só se verifica
confrontando **dois tickers da mesma empresa**: a unit e a classe que entra na
cesta descrevem o mesmo negócio, e só podem divergir pelo ágio entre ON e PN.

| raiz | unit | classe | distância |
|---|---:|---:|---:|
| KLBN | −59,6% | KLBN3 −63,0% | 3,4 p.p. |
| SANB | −27,8% | SANB4 −24,3% | 3,5 p.p. |
| TAEE | −4,0% | TAEE4 −1,1% | 2,9 p.p. |
| **SAPR (antes)** | **−58,4%** | **SAPR4 +115,6%** | **174,0 p.p.** |
| **SAPR (agora)** | **+108,0%** | **SAPR4 +115,6%** | **7,6 p.p.** |

A SAPR11 acusava a mesma empresa como cara e a SAPR4 como barata, ao mesmo
tempo. As outras três raízes já concordavam, e é por isso que a suíte de 414
testes passava: **o motor errava na costura entre dois tickers, e cada ticker
estava certo sozinho.**

## 4. O que isto não conserta

Corrigido `u`, a SAPR11 continua com as duas candidatas a divisor divergindo
por **2,93×** — 302.241.100 pelas demonstrações contra 103.226.074 implícitas
no valor de mercado —, e a regra do maior adota a contábil.

Isso é o resíduo já inventariado em [limitacoes.md §1.7](limitacoes.md), agora
medido. `reconciledShares` só pode confirmar a contagem **do exercício**: o
árbitro `N = lucro ÷ LPA` compara dois campos das **mesmas** demonstrações.
Um **grupamento** posterior reduz a contagem corrente sem tocar a do exercício,
de modo que a candidata contábil fica maior **sempre** — e, pela regra do
maior, vence **sempre**. Um desdobramento faz o contrário, e a regra o absorve
bem. O viés é assimétrico, e só contra grupamento.

**29 dos ativos com divisor apurado têm grupamento aparente** (exercício acima
de 1,5× a corrente), e em **27** a candidata contábil vence. O divisor fica
maior que o de mercado por praticamente o mesmo fator:

| ticker | exerc/corrente | divisor/mercado |
|---|---:|---:|
| MILS3 | 4.861,29× | 4.852,07× |
| MEAL3 | 933,77× | 858,06× |
| VIVR3 | 69,67× | 70,14× |
| AVLL3 | 25,00× | 27,08× |
| COGN3 | 11,16× | 11,49× |
| CPLE3 | 10,90× | 10,81× |
| SAPR3/4/11 | 3,00× | 2,93–2,98× |
| GGBR3/4 | 2,28× | 2,24–2,27× |
| CSAN3 | 2,02× | 2,02× |
| RENT3/4 | 1,78× | 1,76–1,82× |

**A regra não é trocada, e o motivo é que nada no dado arbitra.** O `close` da
fonte já vem ajustado por ação societária e não denuncia salto nenhum em dez
anos, de modo que não há terceiro observável para decidir. O motor **declara**
a escolha e o sentido do erro no aviso do resultado, e o preço justo desses 27
é conservador por construção.

## 5. O contrafactual, medido

```bash
dart run tool/divisor_contrafactual.dart   # grava divisor_contrafactual.json
```

Dos 127 avaliados hoje, **11 têm a candidata contábil vencendo a divergência**.
Trocá-la pela implícita no valor de mercado reescala o preço justo por
`N_adotado ÷ N_mercado`, e o potencial acompanha por identidade:

| ticker | divisor/mercado | justo adotado | justo p/ mercado | pot. adotado | pot. p/ mercado |
|---|---:|---:|---:|---:|---:|
| MILS3 | 4.852,07× | R$ 2,25 | R$ 10.917,17 | −85,8% | **+69.039,8%** |
| COGN3 | 11,49× | R$ 1,44 | R$ 16,55 | −41,0% | +578,4% |
| CPLE3 | 10,81× | R$ 6,26 | R$ 67,68 | −60,5% | +327,0% |
| IGTI11 | 7,28× | R$ 3,76 | R$ 27,39 | −85,8% | +3,6% |
| AZEV4 | 5,48× | R$ 0,11 | R$ 0,60 | −92,4% | −58,4% |
| ANIM3 | 4,91× | R$ 9,35 | R$ 45,88 | +219,1% | +1.466,0% |
| SAPR4 | 2,98× | R$ 14,75 | R$ 43,93 | +115,6% | +542,2% |
| SAPR11 | 2,93× | R$ 72,71 | R$ 212,89 | +108,0% | +509,1% |
| GGBR4 | 2,27× | R$ 9,69 | R$ 21,98 | −61,8% | −13,2% |
| RENT3 | 1,82× | R$ 16,80 | R$ 30,66 | −54,1% | −16,3% |
| RENT4 | 1,76× | R$ 15,15 | R$ 26,63 | −57,1% | −24,5% |

**Todos os onze se movem para cima, e o MILS3 mostra o que a alternativa
produz: +69.039,8% de potencial.** A regra do maior está fazendo exatamente o
que foi escrita para fazer — barrar o falso desconto —, e a medição a confirma.

**O que ela custa, e onde.** Três dos afetados estão no **topo** da ordenação
que o usuário lê:

| posição | ticker | adotado | pelo divisor de mercado |
|---:|---|---:|---:|
| 3º de 127 | ANIM3 | +219,1% | +1.466,0% |
| 7º | SAPR4 | +115,6% | +542,2% |
| 8º | SAPR11 | +108,0% | +509,1% |

Nesses três a **direção** é robusta — barato pelas duas contagens —, mas a
magnitude não é, e eles ocupam o topo da lista sobre a qual se decide. Os
outros oito ficam do 69º ao 125º, onde a escolha não muda decisão.

## 6. A validação fora da amostra não enxerga nada disto

Descoberto ao tentar medir o item anterior contra retornos realizados.

`tool/backtest_valuation.dart` reconstrói o valor de mercado de cada exercício
como `contagem do exercício × preço da coorte`. Isso é **correto** e
necessário: a fonte repete o valor de mercado de hoje em todos os exercícios, e
deixá-lo assim daria a uma avaliação de 2018 a capitalização de 2026.

Mas tem uma consequência que ninguém declarou. Com
`marketCap = N_exercício × P` e `sharesOutstanding = N_exercício`:

- `quotedUnitRatio` = `N·P ÷ (N·P)` = **1, sempre**;
- `sharesFromMarketCap` = `N·P ÷ P` = **`N_exercício`**, idêntica à candidata
  contábil.

As duas candidatas colapsam na mesma, e a razão de unidade nunca sai de 1.
Conferido em vez de suposto: **351 de 351 ativos**, sob a reescala do backtest,
saem com `u = 1` e sem divergência.

**Portanto:**

1. A correção da [decisão 61](../decisoes/061-a-tolerancia-da-razao-de-unidade-e-relativa.md)
   não tem — nem podia ter — evidência fora da amostra. O que a sustenta é a
   conferência entre unit e classe da §3, que é evidência de consistência
   interna, não de poder preditivo.
2. A regra do maior **nunca foi testada contra retorno realizado**, e não é
   testável por este instrumento.
3. Para os 11 ativos da §5, o potencial medido fora da amostra **não é** o
   potencial que a tela mostra.

Isso não invalida o backtest para o que ele mede — a ordenação do universo,
onde 116 dos 127 não são afetados. Invalida-o como evidência sobre a ponte por
papel, e é o que fica declarado em
[limitacoes.md §3.5](limitacoes.md).

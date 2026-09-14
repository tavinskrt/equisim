# A Fase 1 somada — o que cada peça do eixo A move

Medido em 14/09/2026, ao fim da Fase 1, por `tool/padrao_ligar.dart`. Dados em
[padrao_ligacao_2026-09-14.json](padrao_ligacao_2026-09-14.json).

## Por que numa execução só

Entre duas execuções com meia hora de intervalo, 26 ativos mudaram de valor na
montagem só de mercado — cache que venceu, Ibovespa sem cache
([cvm_trimestral.md §3.5](cvm_trimestral.md)). Comparar números de execuções
diferentes mistura o efeito do código com a deriva do dado. Aqui as sete
montagens de cada ativo saem da mesma execução, na mesma data e com os mesmos
dados, e cada uma soma uma peça à anterior:

| montagem | o que muda |
|---|---|
| mercado | fonte de preços, dois pontos do CDI, divisor da fonte — o motor de antes |
| +oficial | contagem oficial da B3 no divisor — decisão 83 |
| +curva | curva do Tesouro na taxa livre de risco — decisão 84 |
| +CVM | CVM anual mesclada — decisões 69 a 82 |
| +setor | classificação setorial oficial da B3, por emissor — decisão 87 |
| +prazo | prazo das outorgas do Formulário de Referência — decisão 88 |
| **+proventos** | beta sobre retorno total, com os proventos da B3 — decisão 89. **É a configuração do aplicativo** |

A data é a da consulta ao registro da B3: registro consultado depois da
avaliação não entra nela. A curva usada é a da data-base de 10/09/2026.

**Os números desta página substituem os da primeira medição da Fase 1**, feita
no mesmo dia antes do A5 ao A6: o dado de mercado derivou entre as duas, e as
peças antigas saem com números um pouco diferentes — a contagem oficial levava o
potencial mediano a −28,7% e agora leva a −31,5%.

## O efeito de cada peça

| peça | avaliados | potencial mediano | mediana do `\|Δ\|` | `\|Δ\|` > 10 p.p. | postos |
|---|---|---:|---:|---:|---:|
| contagem oficial | 128 → 128 | −37,6% → **−31,5%** | 1,1% | 11 | **0,981** |
| curva | 128 → 128 | −31,5% → **−45,7%** | 13,1% | 78 | **0,927** |
| CVM anual | 128 → 128 | −45,6% → −47,4% | 0,3% | 7 | **0,970** |
| setor da B3 | 128 → 128 | −47,7% → −45,5% | 0,0% | 3 | **0,967** |
| prazo das outorgas | 128 → 128 | −45,5% → −45,5% | 0,0% | 1 | **0,998** |
| beta de retorno total | 128 → 128 | −45,5% → −45,7% | 0,0% | 0 | **1,000** |
| **Fase 1 inteira** | **128 → 128** | **−37,5% → −45,3%** | **13,0%** | **78** | **0,849** |

As medianas de uma linha e da seguinte diferem um pouco porque cada comparação
usa os ativos avaliados nas duas montagens dela.

**A contagem oficial quase não reordena e sobe o nível.** Os que se movem são os
de divisor errado, e todos na mesma direção: com o capital autorizado no lugar das
ações emitidas, o preço justo estava deprimido — GGBR4 de −63,5% a −12,1%, RENT3
de −53,4% a −17,0%, COGN3 de −62,0% a −38,5%, AZEV4 de −92,1% a −56,8%.

**A curva move o nível e pouco a ordem**, como a decisão 74 mediu: a
perpetuidade dela fica acima da média decenal do CDI. BEEF3 de 526% a 346%,
GOAU4 de +1,8% a −66,0%, QUAL3 de −24,7% a −89,3%.

**A CVM anual quase não move nada**, e é o que se esperava desde o A1.7. O que
ela move são os bancos, onde a fonte de mercado não traz o resultado: BMGB4 de
+12,8% a −60,0%, BPAC11 de −28,7% a −71,9%, ITUB4 de −13,7% a −48,4%.

**O setor da B3 move três ativos, e todos pelo ciclo.** UNIP6 de −77,5% a −7,2%,
BRAP4 de −70,7% a −12,3% e FESA4 de −60,6% a −43,5%: classes que chegavam sem
setor da fonte e ganham a precedência do ciclo que as outras classes do mesmo
emissor já tinham. Os três bancos que escapavam da Porta 1 passam por ela sem
mudar de preço — ver [b3_classificacao.md](b3_classificacao.md).

**O prazo das outorgas move um ativo além de 10 p.p., nos dois sentidos.** O
contrato corta o excedente de retorno sobre o capital, e ele tem sinal:

| ativo | fim do contrato | sem prazo | com prazo |
|---|---|---:|---:|
| EGIE3 | 26/08/2033 | +3,6% | **−30,5%** |
| ALUP11 | 25/01/2042 | −32,8% | −28,3% |
| AXIA3 | 31/05/2042 | −81,2% | −77,5% |
| TAEE11 | 15/03/2035 | −42,4% | −39,7% |
| ENGI11 | 07/07/2045 | +51,7% | +50,5% |
| CPFE3 | 30/04/2040 | −45,2% | −45,4% |
| EQTL3 | 31/12/2028 | −26,5% | −26,7% |

Na EGIE3, o capital rende acima do custo e a projeção termina em 2033: o
excedente sai. Na ALUP11, na AXIA3 e na TAEE11, o capital apurado rende **abaixo**
do custo, e a devolução dele pelo contábil no fim do contrato vale mais do que
rendê-lo para sempre. Ver [outorgas.md](outorgas.md).

**O beta de retorno total não move nada além de 2 p.p.** — PETR4 de −37,0% a
−38,8%, o maior. A queda da data ex pesava pouco na covariância de cinco anos, e
é o que a teoria dizia; o que muda é que a regressão passa a comparar a mesma
convenção dos dois lados.

**Somadas, as seis peças levam o potencial mediano de −37,5% a −45,3%, com
correlação de postos de 0,849.** Em nível, a curva domina e a contagem oficial
compensa parte; em ordem, cada peça contribui pouco, e juntas movem um sétimo da
ordenação.

## Os que mais se moveram, da montagem de antes à do aplicativo

Com a contribuição de cada peça, em pontos percentuais, somadas na ordem da
tabela anterior:

| ativo | antes | aplicativo | oficial | curva | CVM | setor | prazo | proventos |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| BHIA3 | 351,3% | 107,7% | −88,5 | −155,1 | 0,0 | 0,0 | 0,0 | 0,0 |
| BEEF3 | 547,1% | 353,2% | −21,1 | −180,1 | +6,9 | 0,0 | 0,0 | +0,5 |
| BMGB4 | 32,2% | −60,0% | 0,0 | −19,4 | **−72,9** | 0,0 | 0,0 | 0,0 |
| EGIE3 | 50,2% | −30,7% | +1,5 | −48,1 | 0,0 | 0,0 | **−34,1** | −0,3 |
| POSI3 | 146,8% | 71,3% | −7,2 | −72,7 | +3,7 | 0,0 | 0,0 | +0,6 |
| ANIM3 | 154,1% | 82,8% | 0,0 | −86,6 | +15,5 | 0,0 | 0,0 | −0,3 |
| GOAU4 | 1,7% | −66,0% | +0,1 | −67,8 | 0,0 | 0,0 | 0,0 | 0,0 |
| QUAL3 | −22,7% | −89,3% | −2,0 | −64,7 | 0,0 | 0,0 | 0,0 | 0,0 |
| PGMN3 | 122,6% | 57,6% | −5,5 | −60,5 | +1,1 | 0,0 | 0,0 | 0,0 |
| PRIO3 | −80,6% | −17,9% | −0,5 | **+57,5** | +5,6 | 0,0 | 0,0 | 0,0 |
| BRAV3 | 140,6% | 78,9% | +10,9 | −72,5 | 0,0 | 0,0 | 0,0 | 0,0 |
| UNIP6 | −66,8% | −6,9% | −0,3 | −10,8 | +0,4 | **+70,3** | 0,0 | +0,2 |

**A PRIO3 vai no sentido contrário, e a razão é a migração de via.** A curva de
10/09/2026 fica acima dos dois pontos em quase todo ano e na perpetuidade — o
esperado era o potencial cair. Com a curva, a perpetuidade sobe, o capital
próprio cai para perto de 14% do valor da firma, e a cascata migra para a via do
acionista (decisão 43), que dá −23,5% em vez de −81,1%. **Não é defeito da curva;
é descontinuidade do método**: uma taxa maior troca a via, e a outra via vale
mais. Está no plano como B10, com a raiz no B13 — as duas vias discordam.

## O que isto não diz

Nada aqui é habilidade. É o que o motor **mostra** depois da Fase 1, e não se
ele ordena melhor o retorno — isso é o eixo C, com as coortes. A correlação de
postos de 0,849 entre antes e depois diz que a Fase 1 mudou a ordenação o
bastante para que a medição de habilidade de antes (§0 do plano) precise ser
refeita sobre o motor de agora.

# A Fase 1 somada — o que cada peça do eixo A move

Medido em 14/09/2026 por `tool/padrao_ligar.dart`. Dados em
[padrao_ligacao_2026-09-14.json](padrao_ligacao_2026-09-14.json).

## Por que numa execução só

Entre duas execuções com meia hora de intervalo, 26 ativos mudaram de valor na
montagem só de mercado — cache que venceu, Ibovespa sem cache
([cvm_trimestral.md §3.5](cvm_trimestral.md)). Comparar números de execuções
diferentes mistura o efeito do código com a deriva do dado. Aqui as quatro
montagens de cada ativo saem da mesma execução, na mesma data e com os mesmos
dados, e cada uma soma uma peça à anterior:

| montagem | o que muda |
|---|---|
| mercado | fonte de preços, dois pontos do CDI, divisor da fonte — o motor de antes |
| +oficial | contagem oficial da B3 no divisor — decisão 83 |
| +curva | curva do Tesouro na taxa livre de risco — decisão 84 |
| **padrão** | CVM anual mesclada — decisões 69 a 82. **É a configuração do aplicativo** |

A data é a da consulta ao registro da B3: registro consultado depois da
avaliação não entra nela. A curva usada é a da data-base de 10/09/2026.

## O efeito de cada peça

| peça | avaliados | potencial mediano | mediana do `\|Δ\|` | `\|Δ\|` > 10 p.p. | postos |
|---|---|---:|---:|---:|---:|
| contagem oficial | 128 → 128 | −37,6% → **−28,7%** | 1,0% | 8 | **0,982** |
| curva | 128 → 128 | −28,7% → **−46,0%** | 12,9% | 78 | **0,929** |
| CVM anual | 128 → 128 | −45,8% → −48,2% | 0,3% | 6 | **0,970** |
| **Fase 1 inteira** | **128 → 128** | **−37,5% → −48,2%** | **13,6%** | **76** | **0,884** |

**A contagem oficial quase não reordena e sobe o nível.** 236 dos 363 ativos têm
as contagens da fonte batendo com a B3 e não se movem. Os que se movem são os de
divisor errado, e todos na mesma direção: com o capital autorizado no lugar das
ações emitidas, o preço justo estava deprimido — GGBR4 de −63,0% a −15,7%, RENT3
de −53,7% a −17,5%, COGN3 de −38,2% a −9,9%, AZEV4 de −91,9% a −56,3%.

**A curva move o nível e pouco a ordem**, como a decisão 74 mediu: a
perpetuidade dela fica acima da média decenal do CDI. BEEF3 de 519% a 341%,
GOAU4 de −1,7% a −67,2%, QUAL3 de −25,0% a −89,5%.

**A CVM anual quase não move nada**, e é o que se esperava desde o A1.7: onde
ela e a fonte de mercado concordam — que é quase sempre —, trocar uma pela outra
não muda o número. O que ela move são os bancos, onde a fonte de mercado não
traz o resultado: BMGB4 de +12,6% a −60,1%, BPAC11 de −29,1% a −72,0%, ITUB4 de
−14,5% a −48,9%.

**Somadas, as três peças levam o potencial mediano de −37,5% a −48,2%, com
correlação de postos de 0,884.** Em nível, a curva domina e a contagem oficial
compensa parte; em ordem, as três contribuem pouco cada uma, e juntas movem um
oitavo da ordenação.

## Os que mais se moveram, da montagem de antes ao padrão

Com a contribuição de cada peça, em pontos percentuais, somadas na ordem da
tabela anterior:

| ativo | antes | padrão | oficial | curva | CVM |
|---|---:|---:|---:|---:|---:|
| BHIA3 | 351,3% | 121,1% | −65,8 | −164,5 | 0,0 |
| BEEF3 | 547,0% | 347,5% | −28,1 | −178,0 | +6,5 |
| BMGB4 | 32,0% | −60,1% | 0,0 | −19,4 | **−72,7** |
| ANIM3 | 218,4% | 132,8% | 0,0 | −100,7 | +15,0 |
| POSI3 | 146,7% | 70,5% | −6,3 | −73,1 | +3,2 |
| SAPR4 | 117,6% | 45,6% | 0,0 | −72,0 | 0,0 |
| GOAU4 | 1,9% | −67,2% | −3,6 | −65,4 | 0,0 |
| QUAL3 | −22,4% | −89,5% | −2,6 | −64,5 | 0,0 |
| PRIO3 | −80,6% | −18,3% | −0,5 | **+57,3** | +5,6 |

**A PRIO3 vai no sentido contrário, e a razão é a migração de via.** A curva de
10/09/2026 fica acima dos dois pontos em quase todo ano e na perpetuidade — o
esperado era o potencial cair. Com os dois pontos, a PRIO3 saía pela via da
firma com peso terminal de 1,48 e as ressalvas de terminal pesado e ponte
frágil. Com a curva, a perpetuidade sobe, o capital próprio cai para **14,4% do
valor da firma**, e a cascata migra para a via do acionista (decisão 43), que dá
−23,9% em vez de −80,6%. **Não é defeito da curva; é descontinuidade do
método**: uma taxa maior troca a via, e a outra via vale mais. Um motor de
referência não deveria responder a taxa maior com preço justo maior, e o caso
entra no plano.

## O que isto não diz

Nada aqui é habilidade. É o que o motor **mostra** depois da Fase 1, e não se
ele ordena melhor o retorno — isso é o eixo C, com as coortes. A correlação de
postos de 0,884 entre antes e depois diz que a Fase 1 mudou a ordenação o
bastante para que a medição de habilidade de antes (§0 do plano) precise ser
refeita sobre o motor de agora.

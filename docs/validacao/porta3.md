# A Porta 3 é a fatia mais bem ordenada do motor

Medido em 11/09/2026, sobre 8 coortes anuais (2018–2025) e 2.630 observações
*point-in-time*.

```bash
dart run tool/backtest_valuation.dart   # grava backtest_valuation.json
```

---

## 0. A proposta

A lente `metodo` apontou, como achado **estrutural**:

> Remover a condição de migração forçada de `fluxoSustentado` da lógica de
> designação da `ValuationLane` em `ValuationCascade._route`, barrando empresas
> operacionais insustentáveis precocemente. […] expondo os lucros operacionais
> insustentados à falha deliberada.

O argumento é que a via do acionista seria "leniente", e rotear para ela uma
empresa cujo lucro operacional não se sustenta lava um ativo ruim numa
avaliação. A proposta reverteria a
[decisão 38](../decisoes/038-transicao-continua-entre-as-vias.md).

**Nenhuma medição acompanhava o achado.** Esta é ela.

## 1. Os três grupos

Das 846 avaliações que o motor produziu nas 8 coortes:

| grupo | N | potencial mediano | ret. 12m | ret. 36m | **IC 12m** | **IC 36m** |
|---|---:|---:|---:|---:|---:|---:|
| via da firma | 716 | −47,9% | −1,4% | −0,5% | +0,0417 | +0,1279 |
| Porta 1 (banco) | 95 | +14,1% | +9,9% | +2,7% | +0,1127 | +0,1089 |
| **Porta 3** | **35** | **−9,8%** | **−0,6%** | **+0,3%** | **+0,4197** | **+0,3815** |

`IC` é a correlação de postos de Spearman entre o potencial apurado na coorte e
o retorno realizado depois.

**A Porta 3 tem o maior IC dos três grupos, em ambos os horizontes** — cerca de
três vezes o da via da firma em 36 meses, e dez vezes em 12.

## 2. O contrafactual da lente

Recusar a Porta 3, como a lente propõe, **piora** a ordenação do universo:

| | com a Porta 3 | recusando-a | perda |
|---|---:|---:|---:|
| IC 12m | +0,0845 (n=730) | +0,0650 (n=696) | **−0,0195** |
| IC 36m | +0,1486 (n=508) | +0,1343 (n=483) | **−0,0144** |

Trinta e cinco avaliações de 846 carregam uma parcela desproporcional do sinal.

## 3. A escada de quintis

| quintil | Porta 3: pot. → ret36 | via da firma: pot. → ret36 |
|---|---|---|
| Q1 | −90,2% → **−36,8%** | −88,5% → −10,6% |
| Q2 | −75,0% → +7,6% | −69,9% → −1,3% |
| Q3 | −9,8% → −3,3% | −50,5% → −4,5% |
| Q4 | +37,2% → +0,3% | −12,5% → +2,7% |
| Q5 | +281,1% → **+84,5%** | +96,7% → +6,0% |

A ponta ruim da Porta 3 perdeu 36,8% em três anos e a ponta boa ganhou 84,5%.
A via da firma separa muito menos: −10,6% contra +6,0%.

E onde a lente teme o pior — o ativo insustentável anunciado como oportunidade
—, o resultado é o inverso: das 7 avaliações de Porta 3 com potencial acima de
+50% e retorno de 36 meses apurável, **apenas 1 terminou negativa**. Na via da
firma, 31 de 66.

## 4. Isso resiste?

`n = 25` para o IC de 36 meses é pouco, e o relatório não finge o contrário.

| teste | resultado |
|---|---|
| composição | 35 avaliações, **14 tickers distintos**, presentes nas 8 coortes |
| permutação bicaudal do IC36 (20.000 sorteios) | **p = 0,0618** |
| permutação bicaudal do IC12 (n=34) | **p = 0,0136** |
| erro padrão aproximado, 1/√(n−1) | 0,2041 |
| deixa-um-ticker-de-fora (IC36) | entre **+0,3009** e **+0,4692** |
| deixa-uma-coorte-de-fora (IC36) | entre **+0,2707** e **+0,4964** |

Os tickers: AXIA3, AZEV3, AZEV4, BRSR6, ENEV3, GFSA3, HBSA3, LPSB3, LUPA3,
MILS3, PRIO3, ROMI3, SANB4, TEND3.

O horizonte de 36 meses fica **marginal** (p = 0,062); o de 12, com mais
observações, é significativo a 5% (p = 0,014). Nenhum ticker e nenhuma coorte
sustentam sozinhos o resultado: o pior caso de cada varredura ainda deixa o IC
acima de +0,27.

## 5. Conclusão

**A migração fica, e a proposta é recusada por medição.**

A leitura que a lente faz — "via leniente lava ativo ruim" — não se sustenta
nos dados. O que a Porta 3 faz é reconhecer que, quando o lucro **operacional**
não se sustenta mas o resultado do acionista existe, a pergunta certa passa a
ser sobre o fluxo do acionista. As guardas que já cercam essa via — trava de
saúde, base por ciclo, fração positiva mínima — continuam valendo, e o
resultado é a fatia mais bem ordenada do motor.

Recusar esses 35 casos não tornaria o motor mais honesto. Tornaria-o mais
silencioso, e mediria pior.

**A ressalva que fica:** 25 observações em 36 meses sustentam uma direção, não
uma magnitude. O `+0,3815` não deve ser citado como estimativa pontual do IC da
Porta 3 — deve ser citado como evidência de que ela **não é a fatia ruim** que
a proposta supunha.

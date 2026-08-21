# Divergência entre o fluxo de proventos e o `adjustedClose`

Gerado em 2026-08-20T14:52:02.

Reconstrói o fator de ajuste de proventos a partir dos eventos de `cashDividends` e compara com a razão `adjustedClose/close` observada no início da série.

Um desvio negativo significa que o fluxo de eventos implica **mais** provento do que o `adjustedClose` reflete — ou seja, a série do Yahoo subajusta. A auditoria já havia observado isso em quatro ativos; este relatório mede o fenômeno em escala.

| Ativo | Razão observada | Fator implícito | Desvio | Eventos | % JCP |
|---|---|---|---|---|---|
| TAEE11 | 0,3661 | 0,3662 | 0,0% | 70 | 41% |
| ITSA4 | 0,4769 | 0,4764 | -0,1% | 97 | 64% |
| ABEV3 | 0,6499 | 0,6490 | -0,1% | 25 | 52% |
| VALE3 | 0,4726 | 0,4710 | -0,3% | 34 | 50% |
| PETR4 | 0,2529 | 0,2583 | 2,1% | 77 | 38% |
| WEGE3 | 0,8394 | 0,7630 | -9,1% | 62 | 67% |
| CMIG4 | 0,5743 | 0,5130 | -10,7% | 38 | 68% |
| BBDC4 | 0,5515 | 0,4831 | -12,4% | 151 | 98% |
| ITUB4 | 0,5623 | 0,4577 | -18,6% | 168 | 56% |
| EGIE3 | 0,5526 | 0,4365 | -21,0% | 32 | 31% |
| BBAS3 | 0,5323 | 0,3275 | -38,5% | 113 | 66% |

## Síntese

- Desvio absoluto mediano: **9,1%**
- Desvio absoluto máximo: **38,5%**
- Ativos com desvio acima de 5%: **6 de 11**
- Ativos com maioria de JCP: desvio médio **11,2%** (8 ativos)
- Ativos com minoria de JCP: desvio médio **7,7%** (3 ativos)
- Correlação entre proporção de JCP e desvio: **0,19**

### Leitura

A conclusão robusta é a primeira: **o `adjustedClose` diverge de forma ampla e material do fluxo de proventos** — metade dos ativos acima de 9%. Isso basta para inviabilizá-lo como referência de cálculo, qualquer que seja a causa.

Sobre a **causa**, os dados são apenas sugestivos. O grupo com maioria de JCP desvia mais na média, mas a relação é ruidosa e há contraexemplos claros nos dois sentidos — PETR4 tem 38% de JCP e desvia 2,1%, enquanto EGIE3 tem 31% e desvia 21,0%. Com 11 ativos e correlação de 0,19, atribuir a lacuna exclusivamente ao tratamento de JCP seria ir além do que a amostra sustenta.

> **Para a monografia:** relatar a divergência como fato medido e a explicação por JCP como hipótese plausível não confirmada. A decisão de arquitetura — usar `cashDividends` como fonte de verdade — não depende de resolver a causa.

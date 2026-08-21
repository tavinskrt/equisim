# Conferência cruzada — Equisim × Python

Janela: 2021-08-20 a 2026-08-20  
Taxa livre de risco: 12.4840% a.a. (CDI observado)  
Desvio-padrão: amostral (n-1)  
Pregões por ano: 252

As métricas da coluna *Python* foram recalculadas de forma independente com `pandas` e `numpy` a partir das séries exportadas. Um desvio relativo acima de 1e-4 indica divergência entre as implementações.

**Resultado: 80 de 80 comparações dentro da tolerância.**

### ABEV3

| Métrica | Equisim (Dart) | Python | Desvio relativo | |
|---|---|---|---|---|
| retorno total | 0.06290784 | 0.06290784 | 6.62e-16 | ✅ |
| CAGR | 0.01227811 | 0.01227811 | 3.87e-07 | ✅ |
| volatilidade | 0.24086128 | 0.24086128 | 7.65e-09 | ✅ |
| max drawdown | -0.30015725 | -0.30015726 | 2.13e-08 | ✅ |
| Sharpe | -0.46732954 | -0.46732956 | 4.37e-08 | ✅ |
| Sortino | -0.70636445 | -0.70636447 | 3.47e-08 | ✅ |
| beta | 0.61342936 | 0.61342935 | 1.23e-08 | ✅ |
| correlação | 0.44986167 | 0.44986167 | 9.29e-09 | ✅ |

### BBAS3

| Métrica | Equisim (Dart) | Python | Desvio relativo | |
|---|---|---|---|---|
| retorno total | 1.18653672 | 1.18653672 | 1.87e-16 | ✅ |
| CAGR | 0.16939345 | 0.16939345 | 2.22e-08 | ✅ |
| volatilidade | 0.27835823 | 0.27835823 | 1.57e-08 | ✅ |
| max drawdown | -0.37911034 | -0.37911034 | 4.34e-09 | ✅ |
| Sharpe | 0.16005903 | 0.16005902 | 8.59e-08 | ✅ |
| Sortino | 0.22842705 | 0.22842703 | 1.08e-07 | ✅ |
| beta | 0.96841987 | 0.96841986 | 5.35e-09 | ✅ |
| correlação | 0.61392430 | 0.61392429 | 8.35e-09 | ✅ |

### BBDC4

| Métrica | Equisim (Dart) | Python | Desvio relativo | |
|---|---|---|---|---|
| retorno total | 0.23331525 | 0.23331525 | 1.19e-16 | ✅ |
| CAGR | 0.04283912 | 0.04283912 | 1.94e-08 | ✅ |
| volatilidade | 0.30934214 | 0.30934213 | 1.88e-08 | ✅ |
| max drawdown | -0.40529461 | -0.40529461 | 1.83e-09 | ✅ |
| Sharpe | -0.26508056 | -0.26508058 | 5.70e-08 | ✅ |
| Sortino | -0.38148423 | -0.38148424 | 3.91e-08 | ✅ |
| beta | 1.10624998 | 1.10624995 | 2.44e-08 | ✅ |
| correlação | 0.63113853 | 0.63113852 | 7.98e-09 | ✅ |

### CMIG4

| Métrica | Equisim (Dart) | Python | Desvio relativo | |
|---|---|---|---|---|
| retorno total | 0.44157801 | 0.44157801 | 1.26e-16 | ✅ |
| CAGR | 0.07590018 | 0.07590018 | 3.41e-08 | ✅ |
| volatilidade | 0.30026660 | 0.30026660 | 3.97e-09 | ✅ |
| max drawdown | -0.34659480 | -0.34659480 | 3.37e-09 | ✅ |
| Sharpe | -0.16298692 | -0.16298693 | 8.33e-08 | ✅ |
| Sortino | -0.22076181 | -0.22076182 | 5.26e-08 | ✅ |
| beta | 0.89409452 | 0.89409452 | 3.18e-09 | ✅ |
| correlação | 0.52552372 | 0.52552372 | 4.26e-09 | ✅ |

### EGIE3

| Métrica | Equisim (Dart) | Python | Desvio relativo | |
|---|---|---|---|---|
| retorno total | 0.43689320 | 0.43689320 | 2.54e-16 | ✅ |
| CAGR | 0.07519988 | 0.07519988 | 4.28e-08 | ✅ |
| volatilidade | 0.21608876 | 0.21608876 | 8.96e-09 | ✅ |
| max drawdown | -0.26821601 | -0.26821601 | 1.71e-08 | ✅ |
| Sharpe | -0.22971960 | -0.22971962 | 7.48e-08 | ✅ |
| Sortino | -0.34008360 | -0.34008362 | 6.28e-08 | ✅ |
| beta | 0.56670695 | 0.56670697 | 3.87e-08 | ✅ |
| correlação | 0.46291007 | 0.46291009 | 4.00e-08 | ✅ |

### ITUB4

| Métrica | Equisim (Dart) | Python | Desvio relativo | |
|---|---|---|---|---|
| retorno total | 1.30705101 | 1.30705101 | 0.00e+00 | ✅ |
| CAGR | 0.18201063 | 0.18201063 | 2.24e-08 | ✅ |
| volatilidade | 0.24377899 | 0.24377899 | 6.21e-09 | ✅ |
| max drawdown | -0.25247387 | -0.25247387 | 1.09e-08 | ✅ |
| Sharpe | 0.23451947 | 0.23451945 | 6.93e-08 | ✅ |
| Sortino | 0.35523635 | 0.35523633 | 5.24e-08 | ✅ |
| beta | 0.98033853 | 0.98033853 | 1.74e-10 | ✅ |
| correlação | 0.70970157 | 0.70970156 | 1.22e-08 | ✅ |

### PETR4

| Métrica | Equisim (Dart) | Python | Desvio relativo | |
|---|---|---|---|---|
| retorno total | 3.95510823 | 3.95510823 | 1.12e-16 | ✅ |
| CAGR | 0.37730353 | 0.37730353 | 4.33e-09 | ✅ |
| volatilidade | 0.36063677 | 0.36063677 | 1.13e-08 | ✅ |
| max drawdown | -0.43080594 | -0.43080594 | 9.87e-11 | ✅ |
| Sharpe | 0.70005016 | 0.70005015 | 1.61e-08 | ✅ |
| Sortino | 1.00480267 | 1.00480265 | 2.00e-08 | ✅ |
| beta | 0.84868114 | 0.84868115 | 1.23e-08 | ✅ |
| correlação | 0.41494074 | 0.41494074 | 4.60e-09 | ✅ |

### TAEE11

| Métrica | Equisim (Dart) | Python | Desvio relativo | |
|---|---|---|---|---|
| retorno total | 0.47833973 | 0.47833973 | 1.16e-16 | ✅ |
| CAGR | 0.08133310 | 0.08133310 | 4.34e-08 | ✅ |
| volatilidade | 0.19769506 | 0.19769506 | 2.35e-08 | ✅ |
| max drawdown | -0.19946158 | -0.19946159 | 3.58e-08 | ✅ |
| Sharpe | -0.22006925 | -0.22006927 | 8.98e-08 | ✅ |
| Sortino | -0.32034752 | -0.32034755 | 1.04e-07 | ✅ |
| beta | 0.50155183 | 0.50155182 | 1.64e-08 | ✅ |
| correlação | 0.44788668 | 0.44788668 | 9.43e-09 | ✅ |

### VALE3

| Métrica | Equisim (Dart) | Python | Desvio relativo | |
|---|---|---|---|---|
| retorno total | 0.19714373 | 0.19714373 | 4.22e-16 | ✅ |
| CAGR | 0.03664820 | 0.03664820 | 6.15e-08 | ✅ |
| volatilidade | 0.31376786 | 0.31376786 | 7.98e-09 | ✅ |
| max drawdown | -0.39147559 | -0.39147559 | 3.63e-09 | ✅ |
| Sharpe | -0.28107246 | -0.28107247 | 3.13e-08 | ✅ |
| Sortino | -0.42069324 | -0.42069325 | 3.09e-08 | ✅ |
| beta | 0.86088305 | 0.86088306 | 1.21e-08 | ✅ |
| correlação | 0.48365880 | 0.48365881 | 1.37e-08 | ✅ |

### WEGE3

| Métrica | Equisim (Dart) | Python | Desvio relativo | |
|---|---|---|---|---|
| retorno total | 0.45755674 | 0.45755674 | 0.00e+00 | ✅ |
| CAGR | 0.07827510 | 0.07827510 | 6.23e-08 | ✅ |
| volatilidade | 0.30359730 | 0.30359729 | 1.97e-08 | ✅ |
| max drawdown | -0.44343315 | -0.44343315 | 3.89e-09 | ✅ |
| Sharpe | -0.15337624 | -0.15337625 | 7.40e-08 | ✅ |
| Sortino | -0.22627912 | -0.22627914 | 9.96e-08 | ✅ |
| beta | 0.69891706 | 0.69891706 | 4.88e-09 | ✅ |
| correlação | 0.40939871 | 0.40939872 | 1.98e-08 | ✅ |

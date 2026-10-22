# Por que o lucro de partida foi normalizado

Gerado por `dart run tool/normalizacoes.dart` sobre a entrada congelada de 14/09/2026, na montagem do aplicativo. Pedido do orientador em 14/10/2026: o porquê de cada normalização e a direção dela. **Não edite à mão.**

## A regra, em uma frase

Um ano só pode ter sido um pico ou um vale, e o preço justo é proporcional ao lucro de partida. O motor compara o retorno sobre o capital do último exercício com o **retorno típico** da empresa — a mediana dos 8 exercícios anteriores — e, quando os dois destoam, parte do lucro que a empresa de hoje teria rendendo o típico:

```
fator = típico ÷ último   (limitado entre 0,33 e 3,00)
lucro de partida = lucro publicado × fator
```

- **Para cima** quando o último ano rendeu abaixo do típico (um vale); **para baixo** quando rendeu acima (um pico).
- **Destoa** quando o último ano dividido pelo típico sai de 0,75 a 1,33 (*razão*), ou quando a distância entre os dois passa de 1,5 desvios típicos da janela (*distância*).
- **Não normaliza** quando o retorno tem tendência que domina a volta ao típico (o último ano é o novo patamar) — exceto em commodity, onde a alta do ciclo tem cara de tendência —, nem para cima quando o lucro ou o EBITDA caiu mais de 50,0% em 3 anos.
- **Reconstrói** quando o último ano deu prejuízo: o típico sobre o capital de hoje, se ele é positivo e ao menos 60,0% da janela deu lucro.

O porquê de cada ativo também está no painel de logs, no passo "Base do fluxo", e na tela Editar valuation, no cartão do lucro de partida.

## Quantos, de 110 avaliados

| Resultado | Ativos |
|---|---|
| para cima | 18 |
| para baixo | 27 |
| dentro do normal | 47 |
| novo patamar (tendência) | 14 |
| reconstruída do ciclo | 3 |
| sem ciclo medível | 1 |

## Ativo a ativo

"Último" é o retorno sobre o capital (via da firma) ou sobre o patrimônio (via do acionista) do exercício mais recente; "típico" é a mediana dos anteriores. "Destoou por" diz qual critério decidiu.

| Ativo | Via | Resultado | Último | Típico (anos) | Razão | Desvios | Destoou por | Fator | Observação |
|---|---|---|---|---|---|---|---|---|---|
| PRIO3 | firma | para cima | 3,9% (2025) | 40,4% (2017–2024) | 0,10 | 1,3 | razão | 3,00× | fator limitado (pedia 10,49×); commodity: ciclo antes da tendência |
| BRAP4 | firma | para cima | 5,8% (2025) | 20,6% (2017–2024) | 0,28 | 1,0 | razão | 3,00× | fator limitado (pedia 3,57×); queda de 87,1%, isenta por ser commodity |
| FESA4 | firma | para cima | 1,4% (2025) | 15,4% (2017–2024) | 0,09 | 1,1 | razão | 3,00× | fator limitado (pedia 10,80×); queda de 82,2%, isenta por ser commodity |
| GOAU4 | firma | para cima | 4,9% (2025) | 11,5% (2017–2024) | 0,42 | 1,0 | razão | 2,37× | queda de 87,7%, isenta por ser commodity |
| GGBR4 | firma | para cima | 4,9% (2025) | 11,6% (2017–2024) | 0,42 | 1,0 | razão | 2,37× | queda de 87,6%, isenta por ser commodity |
| VALE3 | firma | para cima | 9,3% (2025) | 20,4% (2017–2024) | 0,46 | 1,4 | razão | 2,18× | queda de 87,7%, isenta por ser commodity |
| BRAV3 | firma | para cima | 7,7% (2025) | 15,2% (2015–2024) | 0,50 | 0,7 | razão | 1,99× | commodity: ciclo antes da tendência |
| SMTO3 | firma | para cima | 7,8% (2026) | 15,4% (2018–2025) | 0,50 | 1,8 | razão e distância | 1,98× |  |
| UNIP6 | firma | para cima | 15,6% (2025) | 30,6% (2017–2024) | 0,51 | 0,9 | razão | 1,96× | queda de 63,9%, isenta por ser commodity |
| EQTL3 | firma | para cima | 9,7% (2025) | 18,4% (2017–2024) | 0,53 | 2,1 | razão e distância | 1,89× |  |
| HYPE3 | firma | para cima | 8,4% (2025) | 14,9% (2017–2024) | 0,56 | 2,8 | razão e distância | 1,78× |  |
| BBAS3 | acionista | para cima | 9,1% (2025) | 16,1% (2017–2024) | 0,57 | 2,1 | razão e distância | 1,77× |  |
| SUZB3 | firma | para cima | 7,7% (2025) | 12,8% (2017–2024) | 0,60 | 1,1 | razão | 1,65× | commodity: ciclo antes da tendência |
| EGIE3 | firma | para cima | 15,3% (2025) | 23,7% (2017–2024) | 0,64 | 4,1 | razão e distância | 1,55× |  |
| FLRY3 | firma | para cima | 10,8% (2025) | 16,0% (2017–2024) | 0,67 | 1,4 | razão | 1,49× |  |
| ISAE4 | firma | para cima | 11,6% (2025) | 15,9% (2017–2024) | 0,73 | 1,8 | razão e distância | 1,37× |  |
| SAPR11 | firma | para cima | 11,2% (2025) | 13,5% (2017–2024) | 0,83 | 1,6 | distância | 1,21× |  |
| SAPR4 | firma | para cima | 11,2% (2025) | 13,5% (2017–2024) | 0,83 | 1,6 | distância | 1,21× |  |
| ITUB3 | acionista | para baixo | 20,7% (2025) | 18,4% (2017–2024) | 1,12 | 2,8 | distância | 0,89× |  |
| ITUB4 | acionista | para baixo | 20,7% (2025) | 18,4% (2017–2024) | 1,12 | 2,8 | distância | 0,89× |  |
| VIVT3 | firma | para baixo | 9,4% (2025) | 7,4% (2017–2024) | 1,27 | 2,3 | distância | 0,79× |  |
| BPAC11 | acionista | para baixo | 25,3% (2025) | 19,6% (2017–2024) | 1,29 | 2,4 | distância | 0,77× |  |
| TGMA3 | firma | para baixo | 29,1% (2025) | 21,2% (2017–2024) | 1,37 | 1,1 | razão | 0,73× |  |
| PSSA3 | acionista | para baixo | 24,2% (2025) | 17,6% (2017–2024) | 1,37 | 1,9 | razão e distância | 0,73× |  |
| BRSR6 | acionista | para baixo | 16,5% (2025) | 11,5% (2017–2024) | 1,43 | 1,2 | razão | 0,70× |  |
| SBSP3 | firma | para baixo | 16,1% (2025) | 11,0% (2017–2024) | 1,46 | 1,3 | razão | 0,68× |  |
| UGPA3 | firma | para baixo | 12,7% (2025) | 8,6% (2017–2024) | 1,48 | 0,8 | razão | 0,68× |  |
| CYRE3 | firma | para baixo | 15,9% (2025) | 10,3% (2017–2024) | 1,55 | 0,8 | razão | 0,65× |  |
| CYRE4 | firma | para baixo | 15,9% (2025) | 10,3% (2017–2024) | 1,55 | 0,8 | razão | 0,65× |  |
| LOGG3 | firma | para baixo | 10,5% (2025) | 6,5% (2017–2024) | 1,61 | 0,9 | razão | 0,62× |  |
| RAIL3 | firma | para baixo | 14,8% (2025) | 9,2% (2017–2024) | 1,61 | 6,4 | razão e distância | 0,62× |  |
| MULT3 | firma | para baixo | 15,6% (2025) | 9,5% (2017–2024) | 1,65 | 1,8 | razão e distância | 0,61× |  |
| ALOS3 | firma | para baixo | 11,1% (2025) | 6,8% (2017–2024) | 1,65 | 1,4 | razão | 0,61× |  |
| JHSF3 | firma | para baixo | 23,9% (2025) | 13,4% (2017–2024) | 1,78 | 1,8 | razão e distância | 0,56× |  |
| VLID3 | firma | para baixo | 12,7% (2025) | 7,1% (2017–2024) | 1,79 | 1,3 | razão | 0,56× |  |
| IGTI11 | firma | para baixo | 14,7% (2025) | 7,7% (2017–2024) | 1,90 | 4,7 | razão e distância | 0,53× |  |
| BMGB4 | acionista | para baixo | 13,3% (2025) | 7,0% (2018–2024) | 1,92 | 4,7 | razão e distância | 0,52× |  |
| TEND3 | firma | para baixo | 33,8% (2025) | 14,5% (2017–2024) | 2,33 | 1,4 | razão | 0,43× |  |
| DIRR3 | firma | para baixo | 39,8% (2025) | 16,1% (2017–2024) | 2,47 | 2,8 | razão e distância | 0,41× |  |
| EMBJ3 | firma | para baixo | 9,8% (2025) | 1,6% (2017–2024) | 5,95 | 1,6 | razão e distância | 0,33× | fator limitado (pedia 0,17×) |
| CEAB3 | firma | para baixo | 26,1% (2025) | 7,9% (2019–2024) | 3,32 | 1,5 | razão e distância | 0,33× | fator limitado (pedia 0,30×) |
| MDNE3 | firma | para baixo | 23,5% (2025) | 5,4% (2017–2024) | 4,38 | 2,4 | razão e distância | 0,33× | fator limitado (pedia 0,23×) |
| POMO3 | firma | para baixo | 21,1% (2025) | 6,2% (2017–2024) | 3,44 | 4,2 | razão e distância | 0,33× | fator limitado (pedia 0,29×) |
| POMO4 | firma | para baixo | 21,1% (2025) | 6,2% (2017–2024) | 3,44 | 4,2 | razão e distância | 0,33× | fator limitado (pedia 0,29×) |
| RIAA3 | firma | para baixo | 31,6% (2025) | 7,6% (2017–2024) | 4,17 | 5,0 | razão e distância | 0,33× | fator limitado (pedia 0,24×) |
| CMIG4 | firma | dentro do normal | 13,9% (2025) | 14,3% (2017–2024) | 0,97 | 0,0 | não destoou | 1,00× |  |
| BBSE3 | acionista | dentro do normal | 93,0% (2025) | 78,2% (2017–2024) | 1,19 | 0,6 | não destoou | 1,00× |  |
| BBDC3 | acionista | dentro do normal | 14,2% (2025) | 14,2% (2017–2024) | 1,00 | 0,0 | não destoou | 1,00× |  |
| IRBR3 | acionista | dentro do normal | 7,9% (2025) | 7,9% (2017–2024) | 1,00 | 0,0 | não destoou | 1,00× |  |
| ABEV3 | firma | dentro do normal | 27,8% (2025) | 26,9% (2017–2024) | 1,03 | 0,2 | não destoou | 1,00× |  |
| ITSA4 | firma | dentro do normal | 18,3% (2025) | 17,7% (2017–2024) | 1,03 | 0,4 | não destoou | 1,00× |  |
| ECOR3 | firma | dentro do normal | 14,2% (2025) | 14,2% (2017–2024) | 1,00 | 0,0 | não destoou | 1,00× |  |
| ALPA4 | firma | dentro do normal | 14,0% (2025) | 13,0% (2017–2024) | 1,07 | 0,1 | não destoou | 1,00× |  |
| EZTC3 | firma | dentro do normal | 8,0% (2025) | 8,0% (2017–2024) | 0,99 | 0,0 | não destoou | 1,00× |  |
| ENGI11 | firma | dentro do normal | 10,8% (2025) | 12,5% (2017–2024) | 0,86 | 0,4 | não destoou | 1,00× |  |
| CPFE3 | firma | dentro do normal | 16,2% (2025) | 15,3% (2017–2024) | 1,06 | 0,2 | não destoou | 1,00× |  |
| CPLE3 | firma | dentro do normal | 9,9% (2025) | 9,2% (2017–2024) | 1,07 | 0,3 | não destoou | 1,00× |  |
| LREN3 | firma | dentro do normal | 14,6% (2025) | 13,3% (2017–2024) | 1,10 | 0,2 | não destoou | 1,00× |  |
| MDIA3 | firma | dentro do normal | 7,8% (2025) | 10,1% (2017–2024) | 0,77 | 0,6 | não destoou | 1,00× |  |
| ALUP11 | firma | dentro do normal | 12,6% (2025) | 12,8% (2017–2024) | 0,99 | 0,0 | não destoou | 1,00× |  |
| MGLU3 | firma | dentro do normal | 11,9% (2025) | 14,7% (2017–2024) | 0,81 | 0,1 | não destoou | 1,00× |  |
| MOTV3 | firma | dentro do normal | 11,7% (2025) | 10,9% (2017–2024) | 1,07 | 0,2 | não destoou | 1,00× |  |
| SLCE3 | firma | dentro do normal | 17,4% (2025) | 14,3% (2017–2024) | 1,22 | 0,9 | não destoou | 1,00× |  |
| MYPK3 | firma | dentro do normal | 7,1% (2025) | 8,4% (2017–2024) | 0,85 | 0,7 | não destoou | 1,00× |  |
| NATU3 | firma | dentro do normal | 11,9% (2025) | 13,1% (2017–2024) | 0,91 | 0,5 | não destoou | 1,00× |  |
| PETR3 | firma | dentro do normal | 14,8% (2025) | 13,2% (2017–2024) | 1,12 | 0,1 | não destoou | 1,00× |  |
| PETR4 | firma | dentro do normal | 14,8% (2025) | 13,2% (2017–2024) | 1,12 | 0,1 | não destoou | 1,00× |  |
| ENEV3 | firma | dentro do normal | 10,1% (2025) | 8,5% (2017–2024) | 1,19 | 1,0 | não destoou | 1,00× |  |
| TAEE4 | firma | dentro do normal | 15,2% (2025) | 16,8% (2017–2024) | 0,90 | 0,9 | não destoou | 1,00× |  |
| SHUL4 | firma | dentro do normal | 14,5% (2025) | 16,9% (2017–2024) | 0,86 | 0,4 | não destoou | 1,00× |  |
| FRAS3 | firma | dentro do normal | 22,8% (2025) | 17,5% (2017–2024) | 1,30 | 0,7 | não destoou | 1,00× |  |
| AMER3 | firma | dentro do normal | 3,9% (2025) | 4,3% (2014–2021) | 0,91 | 0,1 | não destoou | 1,00× |  |
| YDUQ3 | firma | dentro do normal | 11,4% (2025) | 11,5% (2017–2024) | 0,99 | 0,0 | não destoou | 1,00× |  |
| VULC3 | firma | dentro do normal | 34,2% (2025) | 26,6% (2017–2024) | 1,28 | 1,4 | não destoou | 1,00× |  |
| CSMG3 | firma | dentro do normal | 11,2% (2025) | 9,4% (2017–2024) | 1,18 | 0,7 | não destoou | 1,00× |  |
| TAEE11 | firma | dentro do normal | 15,2% (2025) | 16,8% (2017–2024) | 0,90 | 0,9 | não destoou | 1,00× |  |
| BEEF3 | firma | dentro do normal | 24,5% (2025) | 25,6% (2012–2024) | 0,96 | 0,3 | não destoou | 1,00× |  |
| RANI3 | firma | dentro do normal | 15,4% (2025) | 15,2% (2017–2024) | 1,02 | 0,0 | não destoou | 1,00× |  |
| CXSE3 | acionista | dentro do normal | 33,3% (2025) | 33,1% (2017–2024) | 1,00 | 0,1 | não destoou | 1,00× |  |
| WEGE3 | firma | dentro do normal | 35,9% (2025) | 32,0% (2017–2024) | 1,12 | 0,3 | não destoou | 1,00× |  |
| SANB11 | acionista | dentro do normal | 10,8% (2025) | 13,7% (2017–2024) | 0,79 | 1,3 | não destoou | 1,00× |  |
| SANB3 | acionista | dentro do normal | 10,8% (2025) | 13,7% (2017–2024) | 0,79 | 1,3 | não destoou | 1,00× |  |
| SANB4 | acionista | dentro do normal | 10,8% (2025) | 13,7% (2017–2024) | 0,79 | 1,3 | não destoou | 1,00× |  |
| VBBR3 | firma | dentro do normal | 11,8% (2025) | 13,4% (2017–2024) | 0,88 | 0,2 | não destoou | 1,00× |  |
| BBDC4 | acionista | dentro do normal | 14,2% (2025) | 14,2% (2017–2024) | 1,00 | 0,0 | não destoou | 1,00× |  |
| SAUD3 | firma | dentro do normal | 63,5% (2025) | 52,9% (2017–2024) | 1,20 | 0,9 | não destoou | 1,00× |  |
| SBFG3 | firma | dentro do normal | 10,5% (2025) | 11,9% (2019–2024) | 0,88 | 0,8 | não destoou | 1,00× |  |
| TOTS3 | firma | dentro do normal | 18,8% (2025) | 17,7% (2017–2024) | 1,06 | 0,2 | não destoou | 1,00× |  |
| SEER3 | firma | dentro do normal | 23,6% (2025) | 18,9% (2017–2024) | 1,25 | 0,5 | não destoou | 1,00× |  |
| PNVL3 | firma | dentro do normal | 9,1% (2025) | 7,9% (2017–2024) | 1,15 | 0,8 | não destoou | 1,00× |  |
| ABCB4 | acionista | dentro do normal | 15,7% (2025) | 13,8% (2017–2024) | 1,14 | 0,8 | não destoou | 1,00× |  |
| KEPL3 | firma | dentro do normal | 23,6% (2025) | 27,5% (2017–2024) | 0,86 | 0,1 | não destoou | 1,00× |  |
| RDOR3 | firma | novo patamar (tendência) | 30,1% (2025) | 15,7% (2019–2024) | 1,92 | 2,5 | razão e distância | 1,00× |  |
| RADL3 | firma | novo patamar (tendência) | 23,2% (2025) | 20,7% (2017–2024) | 1,12 | 1,6 | distância | 1,00× |  |
| PGMN3 | firma | novo patamar (tendência) | 20,5% (2025) | 12,9% (2017–2024) | 1,59 | 2,1 | razão e distância | 1,00× |  |
| LEVE3 | firma | novo patamar (tendência) | 48,0% (2025) | 28,0% (2017–2024) | 1,72 | 1,2 | razão | 1,00× |  |
| HAPV3 | firma | novo patamar (tendência) | 2,1% (2025) | 3,5% (2019–2024) | 0,59 | 0,3 | razão | 1,00× |  |
| GRND3 | firma | novo patamar (tendência) | 10,5% (2025) | 14,6% (2017–2024) | 0,72 | 0,5 | razão | 1,00× |  |
| CVCB3 | firma | novo patamar (tendência) | 32,2% (2025) | 0,5% (2017–2024) | 59,05 | 0,9 | razão | 1,00× |  |
| COGN3 | firma | novo patamar (tendência) | 6,7% (2025) | 4,2% (2017–2024) | 1,59 | 0,5 | razão | 1,00× |  |
| BHIA3 | firma | novo patamar (tendência) | 9,6% (2025) | 4,8% (2017–2024) | 2,01 | 0,4 | razão | 1,00× |  |
| B3SA3 | acionista | novo patamar (tendência) | 25,0% (2025) | 17,6% (2017–2024) | 1,42 | 1,3 | razão | 1,00× |  |
| AZZA3 | firma | novo patamar (tendência) | 9,4% (2025) | 24,6% (2017–2024) | 0,38 | 1,9 | razão e distância | 1,00× |  |
| ANIM3 | firma | novo patamar (tendência) | 14,7% (2025) | 8,7% (2017–2024) | 1,68 | 1,6 | razão e distância | 1,00× |  |
| WIZC3 | acionista | novo patamar (tendência) | 31,8% (2025) | 85,2% (2017–2024) | 0,37 | 0,8 | razão | 1,00× |  |
| POSI3 | firma | novo patamar (tendência) | 9,5% (2025) | 16,5% (2017–2024) | 0,58 | 0,8 | razão | 1,00× |  |
| USIM3 | firma | reconstruída do ciclo | -3,9% (2025) | 4,4% (2017–2024) | -0,88 | 2,4 | razão e distância | 1,00× | 100,0% da janela no lucro |
| USIM5 | firma | reconstruída do ciclo | -3,9% (2025) | 4,4% (2017–2024) | -0,88 | 2,4 | razão e distância | 1,00× | 100,0% da janela no lucro |
| AZEV4 | acionista | reconstruída do ciclo | -453,4% (2025) | 10,2% (2011–2024) | -44,36 | 13,4 | razão e distância | 1,00× | 62,5% da janela no lucro |
| PINE4 | acionista | sem ciclo medível | 40,4% (2025) | -2,1% (2017–2024) | — | — | — | 1,00× |  |

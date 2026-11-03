# Por que o lucro de partida foi normalizado

Gerado por `npm run tool -- normalizations` sobre a entrada congelada de 14/09/2026, na montagem do aplicativo. Pedido do orientador em 14/10/2026: o porquê de cada normalização e a direção dela. **Não edite à mão.**

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

## Quantos, de 121 avaliados

| Resultado | Ativos |
|---|---|
| para cima | 13 |
| para baixo | 33 |
| dentro do normal | 53 |
| novo patamar (tendência) | 15 |
| travada pela queda | 4 |
| reconstruída do ciclo | 1 |
| sem ciclo medível | 2 |

## Ativo a ativo

"Último" é o retorno sobre o capital (via da firma) ou sobre o patrimônio (via do acionista) do exercício mais recente; "típico" é a mediana dos anteriores. "Destoou por" diz qual critério decidiu.

| Ativo | Via | Resultado | Último | Típico (anos) | Razão | Desvios | Destoou por | Fator | Observação |
|---|---|---|---|---|---|---|---|---|---|
| UNIP6 | firma | para cima | 12,4% (2026) | 30,0% (2018–2025) | 0,41 | 0,9 | razão | 2,43× | queda de 59,4%, isenta por ser commodity |
| MBRF3 | firma | para cima | 8,7% (2026) | 19,2% (2018–2025) | 0,46 | 0,5 | razão | 2,20× |  |
| PRIO3 | firma | para cima | 19,7% (2026) | 40,9% (2018–2025) | 0,48 | 0,7 | razão | 2,08× |  |
| SMTO3 | firma | para cima | 7,8% (2026) | 15,4% (2018–2025) | 0,50 | 1,8 | razão e distância | 1,98× |  |
| SUZB3 | firma | para cima | 6,5% (2026) | 11,7% (2018–2025) | 0,55 | 1,1 | razão | 1,81× |  |
| EGIE3 | firma | para cima | 13,9% (2026) | 22,4% (2018–2025) | 0,62 | 3,6 | razão e distância | 1,62× |  |
| RANI3 | firma | para cima | 9,9% (2026) | 15,9% (2018–2025) | 0,62 | 0,7 | razão | 1,60× | commodity: ciclo antes da tendência; queda de 73,7%, isenta por ser commodity |
| EQTL3 | firma | para cima | 11,1% (2026) | 16,7% (2018–2025) | 0,67 | 0,9 | razão | 1,50× |  |
| SHUL4 | firma | para cima | 12,1% (2026) | 17,6% (2018–2025) | 0,69 | 1,0 | razão | 1,45× |  |
| QUAL3 | firma | para cima | 8,7% (2026) | 12,4% (2018–2025) | 0,70 | 0,5 | razão | 1,43× |  |
| DXCO3 | firma | para cima | 6,4% (2026) | 8,8% (2018–2025) | 0,72 | 0,8 | razão | 1,38× | queda de 78,6%, isenta por ser commodity |
| HYPE3 | firma | para cima | 11,2% (2026) | 15,3% (2018–2025) | 0,73 | 1,7 | razão e distância | 1,37× |  |
| CMIG4 | firma | para cima | 11,0% (2026) | 15,0% (2018–2025) | 0,74 | 0,6 | razão | 1,36× |  |
| ITUB3 | acionista | para baixo | 22,5% (2026) | 18,6% (2018–2025) | 1,21 | 3,0 | distância | 0,83× |  |
| ITUB4 | acionista | para baixo | 22,5% (2026) | 18,6% (2018–2025) | 1,21 | 3,0 | distância | 0,83× |  |
| BPAC11 | acionista | para baixo | 25,1% (2026) | 20,2% (2018–2025) | 1,24 | 2,0 | distância | 0,80× |  |
| VIVT3 | firma | para baixo | 9,5% (2026) | 7,6% (2018–2025) | 1,26 | 1,6 | distância | 0,79× |  |
| PSSA3 | acionista | para baixo | 25,6% (2026) | 19,2% (2018–2025) | 1,33 | 1,9 | distância | 0,75× |  |
| BRAP4 | firma | para baixo | 20,5% (2026) | 15,1% (2018–2025) | 1,36 | 0,4 | razão | 0,73× |  |
| ALOS3 | firma | para baixo | 10,2% (2026) | 7,5% (2018–2025) | 1,37 | 0,6 | razão | 0,73× |  |
| PETR3 | firma | para baixo | 21,5% (2026) | 15,4% (2018–2025) | 1,39 | 0,6 | razão | 0,72× | commodity: ciclo antes da tendência |
| PETR4 | firma | para baixo | 21,5% (2026) | 15,4% (2018–2025) | 1,39 | 0,6 | razão | 0,72× | commodity: ciclo antes da tendência |
| IRBR3 | acionista | para baixo | 3,4% (2026) | 2,4% (2018–2025) | 1,40 | 0,0 | razão | 0,72× |  |
| MILS3 | firma | para baixo | 19,8% (2026) | 14,1% (2018–2025) | 1,40 | 0,4 | razão | 0,72× |  |
| USIM3 | firma | para baixo | 6,7% (2026) | 4,6% (2018–2025) | 1,48 | 0,4 | razão | 0,68× |  |
| USIM5 | firma | para baixo | 6,7% (2026) | 4,6% (2018–2025) | 1,48 | 0,4 | razão | 0,68× |  |
| VLID3 | firma | para baixo | 14,0% (2026) | 9,4% (2018–2025) | 1,49 | 0,9 | razão | 0,67× |  |
| JHSF3 | firma | para baixo | 22,7% (2026) | 15,0% (2018–2025) | 1,52 | 1,3 | razão | 0,66× |  |
| MULT3 | firma | para baixo | 17,5% (2026) | 11,4% (2018–2025) | 1,54 | 1,4 | razão | 0,65× |  |
| RAIL3 | firma | para baixo | 14,3% (2026) | 9,0% (2018–2025) | 1,59 | 2,8 | razão e distância | 0,63× |  |
| SMFT3 | firma | para baixo | 18,8% (2026) | 11,6% (2018–2025) | 1,61 | 0,6 | razão | 0,62× |  |
| IGTI11 | firma | para baixo | 14,2% (2026) | 8,3% (2018–2025) | 1,71 | 3,5 | razão e distância | 0,59× |  |
| DIRR3 | firma | para baixo | 34,5% (2026) | 19,6% (2018–2025) | 1,76 | 1,3 | razão | 0,57× |  |
| VBBR3 | firma | para baixo | 24,1% (2026) | 13,4% (2018–2025) | 1,80 | 2,0 | razão e distância | 0,56× |  |
| CEAB3 | firma | para baixo | 16,2% (2026) | 9,0% (2019–2025) | 1,81 | 0,5 | razão | 0,55× |  |
| BMGB4 | acionista | para baixo | 13,4% (2026) | 7,3% (2018–2025) | 1,84 | 2,2 | razão e distância | 0,54× |  |
| COGN3 | firma | para baixo | 7,9% (2026) | 4,2% (2018–2025) | 1,87 | 0,9 | razão | 0,53× |  |
| B3SA3 | acionista | para baixo | 36,4% (2026) | 19,0% (2018–2025) | 1,91 | 3,8 | razão e distância | 0,52× |  |
| SAUD3 | firma | para baixo | 106,5% (2026) | 53,0% (2018–2025) | 2,01 | 4,6 | razão e distância | 0,50× |  |
| POMO3 | firma | para baixo | 17,0% (2026) | 8,2% (2018–2025) | 2,07 | 1,8 | razão e distância | 0,48× |  |
| POMO4 | firma | para baixo | 17,0% (2026) | 8,2% (2018–2025) | 2,07 | 1,8 | razão e distância | 0,48× |  |
| UGPA3 | firma | para baixo | 20,2% (2026) | 8,6% (2018–2025) | 2,36 | 2,4 | razão e distância | 0,42× |  |
| TEND3 | firma | para baixo | 49,4% (2026) | 19,3% (2018–2025) | 2,57 | 1,7 | razão e distância | 0,39× |  |
| EMBJ3 | firma | para baixo | 12,5% (2026) | 1,7% (2018–2025) | 7,24 | 1,8 | razão e distância | 0,33× | fator limitado (pedia 0,14×) |
| MDNE3 | firma | para baixo | 29,5% (2026) | 6,6% (2018–2025) | 4,48 | 1,9 | razão e distância | 0,33× | fator limitado (pedia 0,22×) |
| PINE4 | acionista | para baixo | 44,0% (2026) | 3,1% (2018–2025) | 14,22 | 3,0 | razão e distância | 0,33× | fator limitado (pedia 0,07×) |
| ABCB4 | acionista | dentro do normal | 14,4% (2026) | 14,3% (2018–2025) | 1,01 | 0,1 | não destoou | 1,00× |  |
| ABEV3 | firma | dentro do normal | 26,0% (2026) | 26,7% (2018–2025) | 0,98 | 0,2 | não destoou | 1,00× |  |
| ALUP11 | firma | dentro do normal | 13,4% (2026) | 12,9% (2018–2025) | 1,04 | 0,2 | não destoou | 1,00× |  |
| BBDC3 | acionista | dentro do normal | 13,9% (2026) | 14,1% (2018–2025) | 0,99 | 0,1 | não destoou | 1,00× |  |
| BBDC4 | acionista | dentro do normal | 13,9% (2026) | 14,1% (2018–2025) | 0,99 | 0,1 | não destoou | 1,00× |  |
| BBSE3 | acionista | dentro do normal | 87,7% (2026) | 85,8% (2018–2025) | 1,02 | 0,1 | não destoou | 1,00× |  |
| BEEF3 | firma | dentro do normal | 24,9% (2026) | 25,6% (2013–2025) | 0,97 | 0,5 | não destoou | 1,00× |  |
| BRAV3 | firma | dentro do normal | 15,1% (2026) | 15,1% (2016–2025) | 1,00 | 0,0 | não destoou | 1,00× |  |
| BRSR6 | acionista | dentro do normal | 9,7% (2026) | 11,5% (2018–2025) | 0,85 | 0,4 | não destoou | 1,00× |  |
| CPFE3 | firma | dentro do normal | 17,1% (2026) | 17,4% (2018–2025) | 0,98 | 0,1 | não destoou | 1,00× |  |
| CPLE3 | firma | dentro do normal | 11,6% (2026) | 9,3% (2018–2025) | 1,24 | 1,3 | não destoou | 1,00× |  |
| CSMG3 | firma | dentro do normal | 9,4% (2026) | 10,0% (2018–2025) | 0,95 | 0,2 | não destoou | 1,00× |  |
| CXSE3 | acionista | dentro do normal | 34,1% (2026) | 33,1% (2018–2025) | 1,03 | 0,4 | não destoou | 1,00× |  |
| CYRE3 | firma | dentro do normal | 9,3% (2026) | 12,3% (2018–2025) | 0,75 | 0,5 | não destoou | 1,00× |  |
| CYRE4 | firma | dentro do normal | 9,3% (2026) | 12,3% (2018–2025) | 0,75 | 0,5 | não destoou | 1,00× |  |
| ENEV3 | firma | dentro do normal | 9,7% (2026) | 9,9% (2018–2025) | 0,98 | 0,1 | não destoou | 1,00× |  |
| ENGI11 | firma | dentro do normal | 9,9% (2026) | 12,5% (2018–2025) | 0,79 | 0,7 | não destoou | 1,00× |  |
| EQPA6 | firma | dentro do normal | 22,3% (2025) | 22,9% (2017–2024) | 0,98 | 0,1 | não destoou | 1,00× |  |
| FLRY3 | firma | dentro do normal | 13,9% (2026) | 14,0% (2018–2025) | 0,99 | 0,0 | não destoou | 1,00× |  |
| GGBR4 | firma | dentro do normal | 11,1% (2026) | 11,5% (2018–2025) | 0,97 | 0,1 | não destoou | 1,00× |  |
| GOAU4 | firma | dentro do normal | 11,0% (2026) | 11,4% (2018–2025) | 0,97 | 0,1 | não destoou | 1,00× |  |
| HAPV3 | firma | dentro do normal | 2,6% (2026) | 2,1% (2019–2025) | 1,23 | 0,1 | não destoou | 1,00× |  |
| ISAE4 | firma | dentro do normal | 12,6% (2026) | 15,4% (2018–2025) | 0,82 | 1,2 | não destoou | 1,00× |  |
| ITSA4 | firma | dentro do normal | 19,8% (2026) | 18,2% (2018–2025) | 1,09 | 0,9 | não destoou | 1,00× |  |
| LEVE3 | firma | dentro do normal | 38,4% (2026) | 36,7% (2018–2025) | 1,05 | 0,1 | não destoou | 1,00× |  |
| LOGG3 | firma | dentro do normal | 9,0% (2026) | 8,4% (2018–2025) | 1,06 | 0,1 | não destoou | 1,00× |  |
| LREN3 | firma | dentro do normal | 13,3% (2026) | 13,3% (2018–2025) | 1,00 | 0,0 | não destoou | 1,00× |  |
| MDIA3 | firma | dentro do normal | 6,7% (2026) | 8,9% (2018–2025) | 0,75 | 1,1 | não destoou | 1,00× |  |
| MGLU3 | firma | dentro do normal | 8,3% (2026) | 10,9% (2018–2025) | 0,76 | 0,2 | não destoou | 1,00× |  |
| MOTV3 | firma | dentro do normal | 12,0% (2026) | 10,9% (2018–2025) | 1,10 | 0,5 | não destoou | 1,00× |  |
| MOVI3 | firma | dentro do normal | 14,4% (2026) | 13,0% (2018–2025) | 1,11 | 0,3 | não destoou | 1,00× |  |
| MYPK3 | firma | dentro do normal | 7,5% (2026) | 8,4% (2018–2025) | 0,89 | 0,5 | não destoou | 1,00× |  |
| PGMN3 | firma | dentro do normal | 19,4% (2026) | 15,6% (2018–2025) | 1,25 | 0,6 | não destoou | 1,00× |  |
| PNVL3 | firma | dentro do normal | 9,2% (2026) | 7,9% (2018–2025) | 1,16 | 0,9 | não destoou | 1,00× |  |
| RADL3 | firma | dentro do normal | 19,1% (2026) | 21,0% (2018–2025) | 0,91 | 0,7 | não destoou | 1,00× |  |
| RENT3 | firma | dentro do normal | 12,9% (2026) | 12,3% (2018–2025) | 1,05 | 0,1 | não destoou | 1,00× |  |
| RENT4 | firma | dentro do normal | 12,9% (2026) | 12,3% (2018–2025) | 1,05 | 0,1 | não destoou | 1,00× |  |
| RIAA3 | firma | dentro do normal | 9,3% (2026) | 7,6% (2018–2025) | 1,23 | 0,4 | não destoou | 1,00× |  |
| SANB11 | acionista | dentro do normal | 12,8% (2026) | 13,7% (2018–2025) | 0,94 | 0,4 | não destoou | 1,00× |  |
| SANB4 | acionista | dentro do normal | 12,8% (2026) | 13,7% (2018–2025) | 0,94 | 0,4 | não destoou | 1,00× |  |
| SBFG3 | firma | dentro do normal | 13,2% (2026) | 11,7% (2019–2025) | 1,12 | 0,8 | não destoou | 1,00× |  |
| SBSP3 | firma | dentro do normal | 13,5% (2026) | 12,2% (2018–2025) | 1,10 | 0,3 | não destoou | 1,00× |  |
| SHUL3 | firma | dentro do normal | 14,5% (2025) | 16,9% (2017–2024) | 0,86 | 0,4 | não destoou | 1,00× |  |
| SLCE3 | firma | dentro do normal | 18,0% (2026) | 16,0% (2018–2025) | 1,12 | 0,4 | não destoou | 1,00× |  |
| TAEE11 | firma | dentro do normal | 16,8% (2026) | 17,0% (2018–2025) | 0,99 | 0,1 | não destoou | 1,00× |  |
| TAEE4 | firma | dentro do normal | 16,8% (2026) | 17,0% (2018–2025) | 0,99 | 0,1 | não destoou | 1,00× |  |
| TGMA3 | firma | dentro do normal | 27,2% (2026) | 22,3% (2018–2025) | 1,22 | 0,5 | não destoou | 1,00× |  |
| TIMS3 | firma | dentro do normal | 16,9% (2023) | 15,8% (2019–2022) | 1,07 | 0,3 | não destoou | 1,00× |  |
| TOTS3 | firma | dentro do normal | 20,2% (2026) | 18,9% (2018–2025) | 1,07 | 0,3 | não destoou | 1,00× |  |
| VALE3 | firma | dentro do normal | 15,6% (2026) | 20,3% (2018–2025) | 0,77 | 0,4 | não destoou | 1,00× |  |
| VAMO3 | firma | dentro do normal | 13,9% (2026) | 15,4% (2020–2025) | 0,90 | 0,5 | não destoou | 1,00× |  |
| WEGE3 | firma | dentro do normal | 40,1% (2026) | 34,6% (2018–2025) | 1,16 | 0,8 | não destoou | 1,00× |  |
| YDUQ3 | firma | dentro do normal | 11,8% (2026) | 11,3% (2018–2025) | 1,05 | 0,1 | não destoou | 1,00× |  |
| ALPA4 | firma | novo patamar (tendência) | 19,5% (2026) | 12,2% (2018–2025) | 1,60 | 0,8 | razão | 1,00× |  |
| AXIA3 | firma | novo patamar (tendência) | 11,3% (2026) | 7,8% (2018–2025) | 1,46 | 1,1 | razão | 1,00× |  |
| AXIA7 | firma | novo patamar (tendência) | 11,3% (2026) | 7,8% (2018–2025) | 1,46 | 1,1 | razão | 1,00× |  |
| AZZA3 | firma | novo patamar (tendência) | 4,1% (2026) | 20,2% (2018–2025) | 0,20 | 1,2 | razão | 1,00× |  |
| EZTC3 | firma | novo patamar (tendência) | 5,1% (2026) | 7,3% (2018–2025) | 0,69 | 0,7 | razão | 1,00× |  |
| FRAS3 | firma | novo patamar (tendência) | 14,6% (2026) | 20,2% (2018–2025) | 0,72 | 0,9 | razão | 1,00× |  |
| GRND3 | firma | novo patamar (tendência) | 4,4% (2026) | 12,1% (2018–2025) | 0,37 | 1,2 | razão | 1,00× |  |
| LWSA3 | firma | novo patamar (tendência) | 5,7% (2026) | 3,6% (2019–2025) | 1,61 | 0,7 | razão | 1,00× |  |
| NATU3 | firma | novo patamar (tendência) | 4,4% (2026) | 12,3% (2018–2025) | 0,35 | 4,0 | razão e distância | 1,00× |  |
| POSI3 | firma | novo patamar (tendência) | 9,7% (2026) | 16,0% (2018–2025) | 0,60 | 0,7 | razão | 1,00× |  |
| PRNR3 | firma | novo patamar (tendência) | 16,7% (2026) | 11,8% (2018–2025) | 1,41 | 0,6 | razão | 1,00× |  |
| RDOR3 | firma | novo patamar (tendência) | 33,5% (2026) | 17,7% (2019–2025) | 1,89 | 2,1 | razão e distância | 1,00× |  |
| SEER3 | firma | novo patamar (tendência) | 31,0% (2026) | 18,3% (2018–2025) | 1,69 | 1,3 | razão | 1,00× |  |
| VULC3 | firma | novo patamar (tendência) | 17,7% (2026) | 26,6% (2018–2025) | 0,66 | 1,6 | razão e distância | 1,00× |  |
| WIZC3 | acionista | novo patamar (tendência) | 24,1% (2026) | 50,5% (2018–2025) | 0,48 | 0,7 | razão | 1,00× |  |
| BBAS3 | acionista | travada pela queda | 6,6% (2026) | 16,1% (2018–2025) | 0,41 | 2,2 | razão e distância | 1,00× | queda de 61,6% em 3 anos (pedia 2,45×) |
| KEPL3 | firma | travada pela queda | 7,5% (2026) | 31,9% (2018–2025) | 0,23 | 0,7 | razão | 1,00× | fator limitado (pedia 4,26×); queda de 80,9% em 3 anos (pedia 4,26×) |
| SAPR11 | firma | travada pela queda | 10,9% (2026) | 13,4% (2018–2025) | 0,81 | 1,7 | distância | 1,00× | queda de 120,3% em 3 anos (pedia 1,23×) |
| SAPR4 | firma | travada pela queda | 10,9% (2026) | 13,4% (2018–2025) | 0,81 | 1,7 | distância | 1,00× | queda de 120,3% em 3 anos (pedia 1,23×) |
| FESA4 | firma | reconstruída do ciclo | -1,4% (2026) | 11,1% (2018–2025) | -0,12 | 1,1 | razão | 1,00× | 100,0% da janela no lucro |
| AZEV4 | acionista | sem ciclo medível | 4,1% (2026) | -24,8% (2012–2025) | — | — | — | 1,00× |  |
| HBSA3 | acionista | sem ciclo medível | 6,1% (2026) | -3,7% (2018–2025) | — | — | — | 1,00× |  |

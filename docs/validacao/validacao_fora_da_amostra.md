# Validação fora da amostra — arquitetura de portas

Executada em 2026-09-07 sobre 373 ativos do universo negociável.

## Distribuição de saídas

| Saída | Ativos | Fração |
|---|---:|---:|
| Porta 0 · liquidez | 187 | 50,1% |
| avaliado | 121 | 32,4% |
| Porta 0 · histórico | 34 | 9,1% |
| sem via aplicável | 13 | 3,5% |
| outra recusa | 9 | 2,4% |
| insumos indisponíveis | 5 | 1,3% |
| Porta 0 · solvência | 4 | 1,1% |

## Entre os avaliados

| Via | Ativos |
|---|---:|
| DCF sobre lucro distribuível | 49 |
| DCF por fluxo da firma | 72 |

| Origem do crescimento | Ativos |
|---|---:|
| fundamental | 66 |
| g = 0 | 8 |
| âncora | 47 |

| Terminal | Ativos |
|---|---:|
| estado estacionário (ROIC_inf = WACC_inf) | 113 |
| vantagem competitiva residual | 8 |

Com vantagem residual: ABEV3, BBSE3, KEPL3, LEVE3, QUAL3, SAUD3, VBBR3, WEGE3.

### Por que a vantagem residual foi barrada

Uma linha por condição, contando **todas** as que barraram cada ativo — os totais somam mais que o número de reprovados, e é essa a informação: quem reprova por duas condições continuaria reprovado se só uma fosse afrouxada.

| Condição | Barrou | Foi a primeira |
|---|---:|---:|
| rentabilidade insuficiente | 90 | 44 |
| crescimento inorgânico | 64 | 60 |
| retorno do ciclo não medido | 5 | 5 |
| capital externo não medido | 4 | 2 |
| histórico curto | 2 | 2 |

Dos reprovados, 44 falharam **apenas** na rentabilidade — cumprem crescimento orgânico e histórico. O excedente do ciclo sobre o custo de capital de equilíbrio nesses casos, contra o corte de 5,0%:

| Percentil | Excedente |
|---|---:|
| p25 | -4,2% |
| mediana | -2,3% |
| p75 | 0,6% |
| p90 | 2,7% |
| máximo | 4,7% |

### Normalização da base

| Base | Ativos |
|---|---:|
| mantida como observada | 68 |
| convergindo ao ciclo | 53 |
| das quais, com Φ acima do limiar | 13 |

Por que a base **não** foi normalizada, nos que ficaram como observados:

| Guarda que decidiu | Ativos |
|---|---:|
| Guarda 3: o exercício não destoa do ciclo | 51 |
| Guarda 1: a tendência domina a reversão | 17 |

Os 17 que **destoam do ciclo e ainda assim ficam como observados** são segurados pela Guarda 1: a tendência do retorno domina a reversão à média, e o modelo lê o nível corrente como estrutural em vez de cíclico. Os dez de maior potencial:

| Ativo | Retorno corrente | Ciclo | Φ | Potencial |
|---|---:|---:|---:|---:|
| SUZB3 | 41,5% | 18,4% | 0,77 | 259,1% |
| PGMN3 | 14,2% | 8,9% | 0,76 | 222,1% |
| WIZC3 | 33,2% | 170,8% | 10,93 | 141,2% |
| AZZA3 | 7,8% | 19,6% | 12,67 | -8,9% |
| MYPK3 | 4,3% | 9,3% | 0,61 | -9,9% |
| SANB4 | 10,8% | 13,5% | 0,12 | -27,7% |
| SANB11 | 10,8% | 13,5% | 0,12 | -31,7% |
| GRND3 | 7,2% | 10,3% | 0,31 | -32,9% |
| AMER3 | 3,9% | 6,6% | 3,74 | -36,8% |
| LEVE3 | 40,8% | 23,8% | 0,00 | -38,0% |

Os dez maiores fatores. **O DCF é homogêneo de grau 1 no fluxo-base**: um fator de 20x multiplica o preço justo por 20, e nada limita `f = ciclo / atual` quando o exercício corrente tem retorno próximo de zero.

| Ativo | Fator | Φ | Potencial |
|---|---:|---:|---:|
| MBRF3 | 21,37 | 18,25 | 406,1% |
| FESA4 | 10,80 | 0,80 | 23,5% |
| PRIO3 | 10,49 | 86,10 | -1,1% |
| DXCO3 | 10,47 | 0,11 | -39,4% |
| PRNR3 | 4,77 | 8,53 | -77,1% |
| IRBR3 | 3,66 | 0,91 | 74,3% |
| BRAP4 | 3,57 | 0,10 | -27,6% |
| RENT4 | 3,32 | 6,02 | -56,2% |
| RENT3 | 3,32 | 6,02 | -52,8% |
| JSLG3 | 3,31 | 0,68 | -19,1% |

Os 13 de base inorgânica normalizada são os que a precedência anterior deixava passar com o exercício corrente como patamar perene. Fator aplicado sobre o lucro observado:

| Ativo | Φ | Fator |
|---|---:|---:|
| AGRO3 | 1,30 | 2,567 |
| BRAV3 | 3,52 | 0,469 |
| EMBJ3 | 1,23 | 0,497 |
| EQTL3 | 4,76 | 1,940 |
| MBRF3 | 18,25 | 21,372 |
| MGLU3 | 8,69 | 2,426 |
| POSI3 | 1,47 | 1,738 |
| PRIO3 | 86,10 | 10,489 |
| PRNR3 | 8,53 | 4,773 |
| RAPT4 | 1,52 | 2,155 |
| RENT3 | 6,02 | 3,323 |
| RENT4 | 6,02 | 3,323 |
| SMFT3 | 12,71 | 2,120 |

## Dispersão do potencial de valorização

| Percentil | Potencial |
|---|---:|
| mínimo | -95,5% |
| p10 | -78,9% |
| p25 | -62,2% |
| mediana | -38,0% |
| p75 | -7,5% |
| p90 | 62,1% |
| máximo | 490,7% |

## Retorno esperado para otimização

`E[R_i] = CDI_spot + z(potencial) x prêmio`, com CDI à vista de 14,09%, prêmio de 5,50% e escore robusto confinado a 2,0 desvios sobre a seção dos 121 avaliados.

| Percentil | Transversal | Anualização do potencial |
|---|---:|---:|
| mínimo | 6,2% | -64,5% |
| p10 | 8,5% | -40,5% |
| p25 | 10,8% | -27,7% |
| mediana | 14,1% | -14,7% |
| p75 | 18,3% | -2,6% |
| p90 | 25,1% | 17,5% |
| máximo | 25,1% | 80,8% |

Pela anualização do potencial, 97 dos 121 avaliados entrariam num otimizador de média-variância com retorno esperado **negativo** — o que não é ordenação ruim, é ausência de alocação. Pelo estimador transversal, nenhum tocou o piso de zero, e a ordenação por potencial é preservada em toda a faixa.

## Ativo a ativo

| Ativo | Setor | Saída | Via | Crescimento | Justo | Preço | Potencial |
|---|---|---|---|---|---:|---:|---:|
| AALR3 | saude | Porta 0 · liquidez | — | — | — | — | — |
| ABCB10 | — | insumos indisponíveis | — | — | — | — | — |
| ABCB4 | servicos-financeiros | avaliado | DCF sobre lucro distribuível | fundamental | 26,33 | 24,58 | 7,1% |
| ABEV3 | consumo-nao-ciclico | avaliado | DCF por fluxo da firma | fundamental | 9,87 | 15,74 | -37,3% |
| AERI3 | bens-industriais | Porta 0 · liquidez | — | — | — | — | — |
| AFLT3 | energia | Porta 0 · liquidez | — | — | — | — | — |
| AGRO3 | consumo-nao-ciclico | avaliado | DCF sobre lucro distribuível | g = 0 | 23,00 | 19,27 | 19,4% |
| AGXY3 | consumo-nao-ciclico | Porta 0 · liquidez | — | — | — | — | — |
| ALLD3 | consumo-ciclico | Porta 0 · liquidez | — | — | — | — | — |
| ALOS3 | construcao-e-imobiliario | avaliado | DCF por fluxo da firma | âncora | 15,56 | 28,81 | -46,0% |
| ALPA3 | consumo-ciclico | Porta 0 · liquidez | — | — | — | — | — |
| ALPA4 |  | avaliado | DCF por fluxo da firma | âncora | 2,05 | 13,57 | -84,9% |
| ALPK3 | servicos | Porta 0 · liquidez | — | — | — | — | — |
| ALUP11 |  | avaliado | DCF por fluxo da firma | âncora | 26,76 | 33,64 | -20,5% |
| ALUP3 | energia | Porta 0 · liquidez | — | — | — | — | — |
| ALUP4 |  | Porta 0 · liquidez | — | — | — | — | — |
| AMAR3 | consumo-ciclico | Porta 0 · liquidez | — | — | — | — | — |
| AMBP3 | saneamento | Porta 0 · liquidez | — | — | — | — | — |
| AMER3 | consumo-ciclico | avaliado | DCF por fluxo da firma | fundamental | 3,51 | 5,55 | -36,8% |
| AMOB3 | consumo-ciclico | Porta 0 · liquidez | — | — | — | — | — |
| ANIM3 | educacao | avaliado | DCF sobre lucro distribuível | g = 0 | 2,69 | 2,93 | -8,2% |
| ARML3 | bens-industriais | Porta 0 · histórico | — | — | — | — | — |
| ARND3 | emp-adm-part-intermediacao-financeira | Porta 0 · liquidez | — | — | — | — | — |
| ASAI3 | consumo-nao-ciclico | Porta 0 · histórico | — | — | — | — | — |
| ATED3 | educacao | Porta 0 · liquidez | — | — | — | — | — |
| AUAU3 | consumo-ciclico | Porta 0 · histórico | — | — | — | — | — |
| AURE3 | energia | Porta 0 · histórico | — | — | — | — | — |
| AVLL3 | construcao-e-imobiliario | Porta 0 · liquidez | — | — | — | — | — |
| AXIA3 | emp-adm-part-energia-eletrica | avaliado | DCF sobre lucro distribuível | fundamental | 19,28 | 55,28 | -65,1% |
| AXIA7 |  | outra recusa | — | — | — | — | — |
| AZEV3 | construcao-e-imobiliario | Porta 0 · liquidez | — | — | — | — | — |
| AZEV4 |  | sem via aplicável | — | — | — | — | — |
| AZTE3 |  | outra recusa | — | — | — | — | — |
| AZUL3 |  | Porta 0 · solvência | — | — | — | — | — |
| AZUL97 | — | insumos indisponíveis | — | — | — | — | — |
| AZUL98 | — | insumos indisponíveis | — | — | — | — | — |
| AZUL99 | — | insumos indisponíveis | — | — | — | — | — |
| AZZA3 | consumo-ciclico | avaliado | DCF por fluxo da firma | âncora | 16,11 | 17,69 | -8,9% |
| B1003 |  | outra recusa | — | — | — | — | — |
| B3SA3 | servicos-financeiros | avaliado | DCF por fluxo da firma | fundamental | 3,26 | 17,37 | -81,2% |
| BALM3 | bens-industriais | Porta 0 · liquidez | — | — | — | — | — |
| BALM4 |  | Porta 0 · liquidez | — | — | — | — | — |
| BAUH4 |  | Porta 0 · liquidez | — | — | — | — | — |
| BAZA3 | servicos-financeiros | Porta 0 · liquidez | — | — | — | — | — |
| BBAS3 | servicos-financeiros | avaliado | DCF sobre lucro distribuível | fundamental | 31,53 | 22,52 | 40,0% |
| BBDC3 | servicos-financeiros | avaliado | DCF sobre lucro distribuível | fundamental | 12,73 | 15,81 | -19,5% |
| BBDC4 | servicos-financeiros | avaliado | DCF sobre lucro distribuível | fundamental | 12,48 | 17,90 | -30,3% |
| BBSE3 | servicos-financeiros | avaliado | DCF sobre lucro distribuível | âncora | 50,05 | 42,16 | 18,7% |
| BDLL3 | bens-industriais | Porta 0 · liquidez | — | — | — | — | — |
| BDLL4 |  | Porta 0 · liquidez | — | — | — | — | — |
| BEEF3 | consumo-nao-ciclico | avaliado | DCF por fluxo da firma | fundamental | 9,75 | 3,95 | 146,8% |
| BEES3 | servicos-financeiros | Porta 0 · liquidez | — | — | — | — | — |
| BEES4 |  | Porta 0 · liquidez | — | — | — | — | — |
| BGIP3 | servicos-financeiros | Porta 0 · liquidez | — | — | — | — | — |
| BGIP4 |  | Porta 0 · liquidez | — | — | — | — | — |
| BHIA3 | consumo-ciclico | sem via aplicável | — | — | — | — | — |
| BIED3 | educacao | Porta 0 · liquidez | — | — | — | — | — |
| BIOM3 | consumo-nao-ciclico | Porta 0 · liquidez | — | — | — | — | — |
| BLAU3 | consumo-nao-ciclico | Porta 0 · liquidez | — | — | — | — | — |
| BMEB3 | servicos-financeiros | Porta 0 · liquidez | — | — | — | — | — |
| BMEB4 |  | Porta 0 · liquidez | — | — | — | — | — |
| BMGB4 | servicos-financeiros | avaliado | DCF sobre lucro distribuível | fundamental | 7,44 | 5,98 | 24,4% |
| BMIN4 |  | Porta 0 · liquidez | — | — | — | — | — |
| BMKS3 | consumo-ciclico | Porta 0 · liquidez | — | — | — | — | — |
| BMOB3 | tecnologia | Porta 0 · histórico | — | — | — | — | — |
| BNBR3 | servicos-financeiros | Porta 0 · liquidez | — | — | — | — | — |
| BOBR4 |  | Porta 0 · liquidez | — | — | — | — | — |
| BPAC11 | servicos-financeiros | avaliado | DCF sobre lucro distribuível | fundamental | 46,01 | 59,24 | -22,3% |
| BPAC3 | servicos-financeiros | Porta 0 · liquidez | — | — | — | — | — |
| BPAC5 |  | Porta 0 · liquidez | — | — | — | — | — |
| BRAP3 | materiais-basicos | Porta 0 · liquidez | — | — | — | — | — |
| BRAP4 |  | avaliado | DCF por fluxo da firma | fundamental | 16,28 | 22,48 | -27,6% |
| BRAV3 | energia | avaliado | DCF sobre lucro distribuível | âncora | 6,73 | 17,88 | -62,4% |
| BRBI11 | servicos-financeiros | Porta 0 · histórico | — | — | — | — | — |
| BRKM3 | materiais-basicos | Porta 0 · liquidez | — | — | — | — | — |
| BRKM5 | materiais-basicos | Porta 0 · solvência | — | — | — | — | — |
| BRKM6 |  | Porta 0 · liquidez | — | — | — | — | — |
| BRSR3 | servicos-financeiros | Porta 0 · liquidez | — | — | — | — | — |
| BRSR5 |  | Porta 0 · liquidez | — | — | — | — | — |
| BRSR6 |  | avaliado | DCF sobre lucro distribuível | fundamental | 13,76 | 14,88 | -7,5% |
| BRST3 | telecomunicacoes | Porta 0 · liquidez | — | — | — | — | — |
| BSLI3 | servicos-financeiros | Porta 0 · liquidez | — | — | — | — | — |
| BSLI4 |  | Porta 0 · liquidez | — | — | — | — | — |
| CAMB3 | consumo-ciclico | Porta 0 · liquidez | — | — | — | — | — |
| CAML3 | consumo-nao-ciclico | avaliado | DCF sobre lucro distribuível | âncora | 2,58 | 4,94 | -47,8% |
| CASH3 | tecnologia | Porta 0 · histórico | — | — | — | — | — |
| CBAV3 | materiais-basicos | Porta 0 · histórico | — | — | — | — | — |
| CBEE3 | energia | Porta 0 · liquidez | — | — | — | — | — |
| CEAB3 | consumo-ciclico | avaliado | DCF por fluxo da firma | âncora | 3,55 | 9,21 | -61,5% |
| CEBR3 | energia | Porta 0 · liquidez | — | — | — | — | — |
| CEBR5 |  | Porta 0 · liquidez | — | — | — | — | — |
| CEBR6 |  | Porta 0 · liquidez | — | — | — | — | — |
| CEDO4 |  | Porta 0 · liquidez | — | — | — | — | — |
| CEEB3 | energia | Porta 0 · liquidez | — | — | — | — | — |
| CEED3 | energia | Porta 0 · liquidez | — | — | — | — | — |
| CEGR3 | energia | Porta 0 · liquidez | — | — | — | — | — |
| CGAS3 | energia | Porta 0 · liquidez | — | — | — | — | — |
| CGAS5 |  | Porta 0 · liquidez | — | — | — | — | — |
| CGRA3 | consumo-ciclico | Porta 0 · liquidez | — | — | — | — | — |
| CGRA4 |  | Porta 0 · liquidez | — | — | — | — | — |
| CLSC3 | energia | Porta 0 · liquidez | — | — | — | — | — |
| CLSC4 |  | Porta 0 · liquidez | — | — | — | — | — |
| CMIG3 | energia | Porta 0 · liquidez | — | — | — | — | — |
| CMIG4 | energia | avaliado | DCF por fluxo da firma | fundamental | 5,63 | 11,26 | -50,0% |
| CMIN3 | materiais-basicos | Porta 0 · histórico | — | — | — | — | — |
| COCE3 | energia | Porta 0 · liquidez | — | — | — | — | — |
| COCE5 |  | Porta 0 · liquidez | — | — | — | — | — |
| COGN3 | educacao | avaliado | DCF sobre lucro distribuível | âncora | 2,72 | 2,44 | 11,5% |
| CPFE3 | energia | avaliado | DCF por fluxo da firma | fundamental | 26,52 | 46,83 | -43,4% |
| CPLE3 | energia | avaliado | DCF por fluxo da firma | fundamental | 1,75 | 15,85 | -89,0% |
| CRPG5 |  | Porta 0 · liquidez | — | — | — | — | — |
| CRPG6 |  | Porta 0 · liquidez | — | — | — | — | — |
| CSAN3 | energia | sem via aplicável | — | — | — | — | — |
| CSED3 | educacao | Porta 0 · liquidez | — | — | — | — | — |
| CSMG3 | saneamento | Porta 0 · solvência | — | — | — | — | — |
| CSNA3 | materiais-basicos | sem via aplicável | — | — | — | — | — |
| CSUD3 | servicos-financeiros | Porta 0 · liquidez | — | — | — | — | — |
| CTAX3 |  | outra recusa | — | — | — | — | — |
| CTKA4 |  | Porta 0 · liquidez | — | — | — | — | — |
| CURY3 | construcao-e-imobiliario | Porta 0 · histórico | — | — | — | — | — |
| CVCB3 | consumo-ciclico | avaliado | DCF por fluxo da firma | âncora | 1,52 | 1,88 | -19,1% |
| CXSE3 | servicos-financeiros | avaliado | DCF por fluxo da firma | âncora | 8,26 | 19,98 | -58,7% |
| CYRE3 | construcao-e-imobiliario | avaliado | DCF por fluxo da firma | âncora | 8,53 | 25,60 | -66,7% |
| CYRE4 |  | avaliado | DCF por fluxo da firma | âncora | 7,48 | 24,11 | -69,0% |
| DASA3 | saude | sem via aplicável | — | — | — | — | — |
| DESK3 | telecomunicacoes | Porta 0 · histórico | — | — | — | — | — |
| DEXP3 | materiais-basicos | Porta 0 · liquidez | — | — | — | — | — |
| DEXP4 |  | Porta 0 · liquidez | — | — | — | — | — |
| DIRR3 | construcao-e-imobiliario | avaliado | DCF por fluxo da firma | fundamental | 1,81 | 11,46 | -84,2% |
| DMVF3 | consumo-nao-ciclico | Porta 0 · liquidez | — | — | — | — | — |
| DOHL4 |  | Porta 0 · liquidez | — | — | — | — | — |
| DOTZ3 | servicos | Porta 0 · liquidez | — | — | — | — | — |
| DTCY3 | servicos | Porta 0 · liquidez | — | — | — | — | — |
| DXCO3 | materiais-basicos | avaliado | DCF sobre lucro distribuível | fundamental | 3,42 | 5,64 | -39,4% |
| EALT3 | bens-industriais | Porta 0 · liquidez | — | — | — | — | — |
| EALT4 |  | Porta 0 · liquidez | — | — | — | — | — |
| ECOM3 | comunicacao-e-informatica | Porta 0 · liquidez | — | — | — | — | — |
| ECOR3 | infraestrutura | avaliado | DCF por fluxo da firma | fundamental | 17,62 | 7,92 | 122,5% |
| EGIE3 | energia | avaliado | DCF por fluxo da firma | fundamental | 42,60 | 30,14 | 41,3% |
| EKTR4 |  | Porta 0 · liquidez | — | — | — | — | — |
| EMAE4 |  | Porta 0 · liquidez | — | — | — | — | — |
| EMBJ3 | maquinas-equipamentos-veiculos-e-pecas | avaliado | DCF por fluxo da firma | fundamental | 9,19 | 94,98 | -90,3% |
| ENEV3 | energia | avaliado | DCF sobre lucro distribuível | âncora | 4,40 | 27,59 | -84,1% |
| ENGI11 | energia | avaliado | DCF sobre lucro distribuível | fundamental | 79,02 | 51,43 | 53,6% |
| ENGI3 | energia | Porta 0 · liquidez | — | — | — | — | — |
| ENGI4 |  | Porta 0 · liquidez | — | — | — | — | — |
| ENJU3 | tecnologia | Porta 0 · liquidez | — | — | — | — | — |
| ENMT3 | energia | Porta 0 · liquidez | — | — | — | — | — |
| ENMT4 |  | Porta 0 · liquidez | — | — | — | — | — |
| EPAR3 | consumo-ciclico | Porta 0 · liquidez | — | — | — | — | — |
| EQPA3 | energia | Porta 0 · liquidez | — | — | — | — | — |
| EQPA5 |  | Porta 0 · liquidez | — | — | — | — | — |
| EQTL3 | energia | avaliado | DCF por fluxo da firma | âncora | 18,18 | 39,16 | -53,6% |
| ESPA3 | consumo-ciclico | Porta 0 · liquidez | — | — | — | — | — |
| ESTR4 |  | Porta 0 · liquidez | — | — | — | — | — |
| ETER3 | construcao-e-imobiliario | Porta 0 · liquidez | — | — | — | — | — |
| EUCA3 | materiais-basicos | Porta 0 · liquidez | — | — | — | — | — |
| EUCA4 |  | Porta 0 · liquidez | — | — | — | — | — |
| EVEN3 | construcao-e-imobiliario | avaliado | DCF por fluxo da firma | âncora | 3,64 | 4,23 | -13,9% |
| EZTC3 | construcao-e-imobiliario | avaliado | DCF por fluxo da firma | âncora | 4,55 | 13,00 | -65,0% |
| FASA3 |  | outra recusa | — | — | — | — | — |
| FESA3 | materiais-basicos | Porta 0 · liquidez | — | — | — | — | — |
| FESA4 |  | avaliado | DCF por fluxo da firma | fundamental | 6,93 | 5,61 | 23,5% |
| FHER3 | materiais-basicos | Porta 0 · liquidez | — | — | — | — | — |
| FICT3 | outros | Porta 0 · liquidez | — | — | — | — | — |
| FIEI3 | construcao-e-imobiliario | Porta 0 · liquidez | — | — | — | — | — |
| FIQE3 | telecomunicacoes | Porta 0 · histórico | — | — | — | — | — |
| FLRY3 | saude | Porta 0 · solvência | — | — | — | — | — |
| FRAS3 | consumo-ciclico | avaliado | DCF por fluxo da firma | âncora | 5,54 | 22,65 | -75,5% |
| GEPA3 | energia | Porta 0 · liquidez | — | — | — | — | — |
| GEPA4 |  | Porta 0 · liquidez | — | — | — | — | — |
| GFSA3 | construcao-e-imobiliario | Porta 0 · liquidez | — | — | — | — | — |
| GGBR3 | materiais-basicos | Porta 0 · liquidez | — | — | — | — | — |
| GGBR4 | materiais-basicos | avaliado | DCF por fluxo da firma | âncora | 6,68 | 25,34 | -73,6% |
| GGPS3 | servicos | Porta 0 · histórico | — | — | — | — | — |
| GMAT3 | consumo-nao-ciclico | Porta 0 · histórico | — | — | — | — | — |
| GOAU3 | materiais-basicos | Porta 0 · liquidez | — | — | — | — | — |
| GOAU4 | materiais-basicos | avaliado | DCF por fluxo da firma | âncora | 25,40 | 11,17 | 127,4% |
| GRND3 | consumo-ciclico | avaliado | DCF por fluxo da firma | fundamental | 2,47 | 3,68 | -32,9% |
| GSHP3 | construcao-e-imobiliario | Porta 0 · liquidez | — | — | — | — | — |
| HAGA3 | construcao-e-imobiliario | Porta 0 · liquidez | — | — | — | — | — |
| HAGA4 |  | Porta 0 · liquidez | — | — | — | — | — |
| HAPV3 | saude | sem via aplicável | — | — | — | — | — |
| HBOR3 | construcao-e-imobiliario | Porta 0 · liquidez | — | — | — | — | — |
| HBRE3 | construcao-e-imobiliario | Porta 0 · liquidez | — | — | — | — | — |
| HBSA3 | bens-industriais | sem via aplicável | — | — | — | — | — |
| HOOT4 |  | Porta 0 · liquidez | — | — | — | — | — |
| HYPE3 | consumo-nao-ciclico | avaliado | DCF sobre lucro distribuível | fundamental | 10,16 | 23,16 | -56,1% |
| IFCM3 | tecnologia | Porta 0 · liquidez | — | — | — | — | — |
| IGTI11 | construcao-e-imobiliario | avaliado | DCF sobre lucro distribuível | fundamental | 4,46 | 26,43 | -83,1% |
| IGTI3 | construcao-e-imobiliario | Porta 0 · liquidez | — | — | — | — | — |
| IGTI4 |  | Porta 0 · liquidez | — | — | — | — | — |
| INEP3 | bens-industriais | Porta 0 · liquidez | — | — | — | — | — |
| INEP4 |  | Porta 0 · liquidez | — | — | — | — | — |
| INTB3 | tecnologia | Porta 0 · histórico | — | — | — | — | — |
| IRBR3 | servicos-financeiros | avaliado | DCF sobre lucro distribuível | âncora | 108,46 | 62,21 | 74,3% |
| ISAE3 | energia | Porta 0 · liquidez | — | — | — | — | — |
| ISAE4 | energia | avaliado | DCF por fluxo da firma | fundamental | 27,57 | 27,70 | -0,5% |
| ITSA3 | holdings | Porta 0 · liquidez | — | — | — | — | — |
| ITSA4 |  | avaliado | DCF por fluxo da firma | fundamental | 4,59 | 13,95 | -67,1% |
| ITUB3 | servicos-financeiros | avaliado | DCF sobre lucro distribuível | fundamental | 41,68 | 45,72 | -8,8% |
| ITUB4 | servicos-financeiros | avaliado | DCF sobre lucro distribuível | fundamental | 40,24 | 41,92 | -4,0% |
| JALL3 | consumo-nao-ciclico | Porta 0 · histórico | — | — | — | — | — |
| JFEN3 | construcao-e-imobiliario | Porta 0 · liquidez | — | — | — | — | — |
| JHSF3 | construcao-e-imobiliario | avaliado | DCF por fluxo da firma | âncora | 7,10 | 11,45 | -38,0% |
| JSLG3 | bens-industriais | avaliado | DCF sobre lucro distribuível | fundamental | 4,71 | 5,82 | -19,1% |
| KEPL3 | bens-industriais | avaliado | DCF por fluxo da firma | âncora | 4,74 | 6,68 | -29,0% |
| KLBN11 | materiais-basicos | avaliado | DCF sobre lucro distribuível | âncora | 10,75 | 19,47 | -44,8% |
| KLBN3 | materiais-basicos | avaliado | DCF sobre lucro distribuível | âncora | 2,14 | 4,03 | -46,9% |
| KLBN4 |  | avaliado | DCF sobre lucro distribuível | âncora | 2,16 | 3,85 | -43,9% |
| LAND3 | consumo-nao-ciclico | Porta 0 · liquidez | — | — | — | — | — |
| LAVV3 | construcao-e-imobiliario | Porta 0 · histórico | — | — | — | — | — |
| LEVE3 | consumo-ciclico | avaliado | DCF por fluxo da firma | fundamental | 20,35 | 32,81 | -38,0% |
| LIGT3 | energia | avaliado | DCF sobre lucro distribuível | fundamental | 1,85 | 3,57 | -48,2% |
| LJQQ3 | consumo-ciclico | Porta 0 · histórico | — | — | — | — | — |
| LOGG3 | construcao-e-imobiliario | avaliado | DCF sobre lucro distribuível | âncora | 9,35 | 24,71 | -62,2% |
| LOGN3 | bens-industriais | Porta 0 · liquidez | — | — | — | — | — |
| LPSB3 | construcao-e-imobiliario | Porta 0 · liquidez | — | — | — | — | — |
| LREN3 | consumo-ciclico | avaliado | DCF por fluxo da firma | fundamental | 6,88 | 11,35 | -39,4% |
| LUPA3 | bens-industriais | Porta 0 · liquidez | — | — | — | — | — |
| LUXM4 |  | Porta 0 · liquidez | — | — | — | — | — |
| LWSA3 | tecnologia | sem via aplicável | — | — | — | — | — |
| MAPT3 | outros | Porta 0 · liquidez | — | — | — | — | — |
| MATD3 | saude | Porta 0 · liquidez | — | — | — | — | — |
| MBRF3 | emp-adm-part-alimentos | avaliado | DCF sobre lucro distribuível | âncora | 89,53 | 17,69 | 406,1% |
| MDIA3 | consumo-nao-ciclico | avaliado | DCF por fluxo da firma | fundamental | 8,46 | 17,78 | -52,4% |
| MDNE3 | construcao-e-imobiliario | avaliado | DCF por fluxo da firma | âncora | 1,15 | 25,81 | -95,5% |
| MEAL3 | consumo-ciclico | Porta 0 · liquidez | — | — | — | — | — |
| MELK3 | construcao-e-imobiliario | Porta 0 · liquidez | — | — | — | — | — |
| MGEL4 |  | Porta 0 · liquidez | — | — | — | — | — |
| MGLU3 | consumo-ciclico | avaliado | DCF por fluxo da firma | âncora | 14,28 | 5,79 | 146,6% |
| MILS3 | bens-industriais | avaliado | DCF por fluxo da firma | âncora | 7,80 | 15,79 | -50,6% |
| MLAS3 | tecnologia | Porta 0 · histórico | — | — | — | — | — |
| MNDL3 | consumo-ciclico | Porta 0 · liquidez | — | — | — | — | — |
| MNPR3 | consumo-nao-ciclico | Porta 0 · liquidez | — | — | — | — | — |
| MOTV3 | infraestrutura | avaliado | DCF por fluxo da firma | fundamental | 11,49 | 16,78 | -31,5% |
| MOVI3 | consumo-ciclico | avaliado | DCF por fluxo da firma | fundamental | 35,39 | 8,11 | 336,4% |
| MRVE3 | construcao-e-imobiliario | sem via aplicável | — | — | — | — | — |
| MSPA4 |  | Porta 0 · liquidez | — | — | — | — | — |
| MTRE3 | construcao-e-imobiliario | Porta 0 · liquidez | — | — | — | — | — |
| MTSA4 |  | Porta 0 · liquidez | — | — | — | — | — |
| MULT3 | construcao-e-imobiliario | avaliado | DCF sobre lucro distribuível | fundamental | 6,25 | 30,18 | -79,3% |
| MWET3 | consumo-ciclico | Porta 0 · liquidez | — | — | — | — | — |
| MWET4 |  | Porta 0 · liquidez | — | — | — | — | — |
| MYPK3 | consumo-ciclico | avaliado | DCF sobre lucro distribuível | fundamental | 8,84 | 9,81 | -9,9% |
| NATU3 | consumo-nao-ciclico | Porta 0 · histórico | — | — | — | — | — |
| NEXP3 | construcao-e-imobiliario | Porta 0 · liquidez | — | — | — | — | — |
| NORD3 | bens-industriais | Porta 0 · liquidez | — | — | — | — | — |
| NUTR3 | materiais-basicos | Porta 0 · liquidez | — | — | — | — | — |
| OBTC3 |  | outra recusa | — | — | — | — | — |
| OFSA3 | consumo-nao-ciclico | Porta 0 · liquidez | — | — | — | — | — |
| ONCO11 | — | insumos indisponíveis | — | — | — | — | — |
| ONCO3 | saude | Porta 0 · histórico | — | — | — | — | — |
| OPCT3 | bens-industriais | Porta 0 · histórico | — | — | — | — | — |
| ORVR3 | saneamento | Porta 0 · histórico | — | — | — | — | — |
| OSXB3 | bens-industriais | Porta 0 · liquidez | — | — | — | — | — |
| PASS3 | energia | Porta 0 · histórico | — | — | — | — | — |
| PATI3 | materiais-basicos | Porta 0 · liquidez | — | — | — | — | — |
| PATI4 |  | Porta 0 · liquidez | — | — | — | — | — |
| PCAR3 | consumo-nao-ciclico | sem via aplicável | — | — | — | — | — |
| PDGR3 | construcao-e-imobiliario | Porta 0 · liquidez | — | — | — | — | — |
| PDTC3 | tecnologia | Porta 0 · liquidez | — | — | — | — | — |
| PEAB3 | construcao-e-imobiliario | Porta 0 · liquidez | — | — | — | — | — |
| PEAB4 |  | Porta 0 · liquidez | — | — | — | — | — |
| PETR3 | energia | avaliado | DCF por fluxo da firma | fundamental | 32,97 | 52,01 | -36,6% |
| PETR4 | energia | avaliado | DCF por fluxo da firma | fundamental | 34,79 | 47,11 | -26,2% |
| PFRM3 | consumo-nao-ciclico | Porta 0 · liquidez | — | — | — | — | — |
| PGMN3 | consumo-nao-ciclico | avaliado | DCF por fluxo da firma | fundamental | 12,37 | 3,84 | 222,1% |
| PINE3 | servicos-financeiros | Porta 0 · liquidez | — | — | — | — | — |
| PINE4 |  | avaliado | DCF sobre lucro distribuível | fundamental | 12,44 | 11,14 | 11,7% |
| PLAS3 | consumo-ciclico | Porta 0 · liquidez | — | — | — | — | — |
| PLPL3 | construcao-e-imobiliario | Porta 0 · histórico | — | — | — | — | — |
| PMAM3 | materiais-basicos | Porta 0 · liquidez | — | — | — | — | — |
| PNVL3 | consumo-nao-ciclico | avaliado | DCF sobre lucro distribuível | âncora | 4,53 | 13,16 | -65,6% |
| POMO3 | consumo-ciclico | avaliado | DCF sobre lucro distribuível | fundamental | 2,58 | 4,26 | -39,4% |
| POMO4 |  | avaliado | DCF sobre lucro distribuível | fundamental | 2,53 | 4,58 | -44,8% |
| POSI3 | tecnologia | avaliado | DCF por fluxo da firma | âncora | 8,04 | 3,42 | 135,1% |
| PRIO3 | energia | avaliado | DCF por fluxo da firma | âncora | 59,50 | 60,19 | -1,1% |
| PRNR3 | servicos | avaliado | DCF sobre lucro distribuível | âncora | 4,16 | 18,15 | -77,1% |
| PSSA3 | servicos-financeiros | avaliado | DCF sobre lucro distribuível | fundamental | 29,72 | 51,66 | -42,5% |
| PTBL3 | construcao-e-imobiliario | Porta 0 · liquidez | — | — | — | — | — |
| QUAL3 | saude | avaliado | DCF por fluxo da firma | fundamental | 8,86 | 1,50 | 490,7% |
| RADL3 | consumo-nao-ciclico | avaliado | DCF por fluxo da firma | fundamental | 5,41 | 19,99 | -72,9% |
| RAIL3 | bens-industriais | avaliado | DCF sobre lucro distribuível | g = 0 | 1,61 | 14,55 | -88,9% |
| RAIZ4 | consumo-nao-ciclico | Porta 0 · histórico | — | — | — | — | — |
| RANI3 | materiais | avaliado | DCF por fluxo da firma | fundamental | 5,60 | 7,66 | -26,9% |
| RAPT3 | consumo-ciclico | Porta 0 · liquidez | — | — | — | — | — |
| RAPT4 |  | avaliado | DCF por fluxo da firma | âncora | 5,73 | 4,80 | 19,4% |
| RCSL3 | consumo-ciclico | Porta 0 · liquidez | — | — | — | — | — |
| RCSL4 |  | Porta 0 · liquidez | — | — | — | — | — |
| RDOR3 | saude | avaliado | DCF por fluxo da firma | g = 0 | 13,02 | 37,13 | -64,9% |
| RECV3 | energia | Porta 0 · histórico | — | — | — | — | — |
| REDE3 | energia | Porta 0 · liquidez | — | — | — | — | — |
| RENT3 | consumo-ciclico | avaliado | DCF sobre lucro distribuível | âncora | 17,28 | 36,64 | -52,8% |
| RENT4 |  | avaliado | DCF sobre lucro distribuível | âncora | 15,45 | 35,29 | -56,2% |
| RIAA3 | textil-e-vestuario | avaliado | DCF por fluxo da firma | fundamental | 3,02 | 7,16 | -57,8% |
| RNEW3 | energia | Porta 0 · liquidez | — | — | — | — | — |
| RNEW4 |  | Porta 0 · liquidez | — | — | — | — | — |
| ROMI3 | bens-industriais | Porta 0 · liquidez | — | — | — | — | — |
| RPAD3 | servicos-financeiros | Porta 0 · liquidez | — | — | — | — | — |
| RSUL4 |  | Porta 0 · liquidez | — | — | — | — | — |
| RVEE3 |  | outra recusa | — | — | — | — | — |
| SANB11 | servicos-financeiros | avaliado | DCF sobre lucro distribuível | fundamental | 20,78 | 30,43 | -31,7% |
| SANB3 | servicos-financeiros | Porta 0 · liquidez | — | — | — | — | — |
| SANB4 |  | avaliado | DCF sobre lucro distribuível | fundamental | 10,87 | 15,03 | -27,7% |
| SAPR11 |  | avaliado | DCF por fluxo da firma | fundamental | 26,09 | 34,95 | -25,4% |
| SAPR3 | saneamento | Porta 0 · liquidez | — | — | — | — | — |
| SAPR4 |  | avaliado | DCF por fluxo da firma | fundamental | 5,25 | 6,84 | -23,2% |
| SAUD3 | servicos-medicos | avaliado | DCF por fluxo da firma | g = 0 | 6,88 | 14,69 | -53,2% |
| SBFG3 | consumo-ciclico | avaliado | DCF sobre lucro distribuível | âncora | 8,61 | 9,04 | -4,8% |
| SBSP3 | saneamento | avaliado | DCF por fluxo da firma | fundamental | 10,20 | 26,53 | -61,6% |
| SCAR3 | construcao-e-imobiliario | Porta 0 · liquidez | — | — | — | — | — |
| SEER3 | educacao | avaliado | DCF por fluxo da firma | âncora | 8,20 | 13,52 | -39,3% |
| SEQL3 |  | outra recusa | — | — | — | — | — |
| SHOW3 | consumo-ciclico | Porta 0 · liquidez | — | — | — | — | — |
| SHUL4 |  | avaliado | DCF por fluxo da firma | âncora | 2,85 | 4,47 | -36,2% |
| SIMH3 | holdings | Porta 0 · histórico | — | — | — | — | — |
| SLCE3 | consumo-nao-ciclico | avaliado | DCF por fluxo da firma | fundamental | 6,02 | 16,41 | -63,3% |
| SMFT3 | consumo-ciclico | avaliado | DCF sobre lucro distribuível | g = 0 | 11,24 | 17,97 | -37,5% |
| SMTO3 | consumo-nao-ciclico | avaliado | DCF por fluxo da firma | fundamental | 33,39 | 20,60 | 62,1% |
| SNSY5 |  | Porta 0 · liquidez | — | — | — | — | — |
| SOJA3 | consumo-nao-ciclico | Porta 0 · histórico | — | — | — | — | — |
| SOND5 |  | Porta 0 · liquidez | — | — | — | — | — |
| SOND6 |  | Porta 0 · liquidez | — | — | — | — | — |
| SUZB3 | materiais-basicos | avaliado | DCF sobre lucro distribuível | fundamental | 168,38 | 46,89 | 259,1% |
| SYNE3 | construcao-e-imobiliario | Porta 0 · liquidez | — | — | — | — | — |
| TAEE11 | energia | avaliado | DCF por fluxo da firma | fundamental | 15,70 | 41,53 | -62,2% |
| TAEE3 | energia | Porta 0 · liquidez | — | — | — | — | — |
| TAEE4 |  | avaliado | DCF por fluxo da firma | fundamental | 5,57 | 14,05 | -60,4% |
| TASA3 | bens-industriais | Porta 0 · liquidez | — | — | — | — | — |
| TASA4 |  | Porta 0 · liquidez | — | — | — | — | — |
| TCSA3 | construcao-e-imobiliario | Porta 0 · liquidez | — | — | — | — | — |
| TECN3 | consumo-ciclico | Porta 0 · liquidez | — | — | — | — | — |
| TELB3 | telecomunicacoes | Porta 0 · liquidez | — | — | — | — | — |
| TELB4 |  | Porta 0 · liquidez | — | — | — | — | — |
| TEND3 | construcao-e-imobiliario | avaliado | DCF por fluxo da firma | g = 0 | 6,03 | 34,63 | -82,6% |
| TFCO4 | consumo-ciclico | Porta 0 · histórico | — | — | — | — | — |
| TGMA3 | bens-industriais | avaliado | DCF por fluxo da firma | âncora | 14,46 | 33,66 | -57,0% |
| TIMS3 | telecomunicacoes | sem via aplicável | — | — | — | — | — |
| TOKY3 | comercio-atacado-e-varejo | Porta 0 · histórico | — | — | — | — | — |
| TOTS3 | tecnologia | avaliado | DCF por fluxo da firma | âncora | 7,18 | 34,50 | -79,2% |
| TPIS3 | infraestrutura | Porta 0 · liquidez | — | — | — | — | — |
| TRIS3 | construcao-e-imobiliario | Porta 0 · liquidez | — | — | — | — | — |
| TTEN3 | consumo-nao-ciclico | Porta 0 · histórico | — | — | — | — | — |
| TUPY3 | consumo-ciclico | outra recusa | — | — | — | — | — |
| UCAS3 | consumo-ciclico | Porta 0 · liquidez | — | — | — | — | — |
| UGPA3 | energia | avaliado | DCF sobre lucro distribuível | fundamental | 12,64 | 37,42 | -66,2% |
| UNIP3 | materiais-basicos | Porta 0 · liquidez | — | — | — | — | — |
| UNIP5 |  | Porta 0 · liquidez | — | — | — | — | — |
| UNIP6 |  | avaliado | DCF por fluxo da firma | âncora | 54,28 | 56,97 | -4,7% |
| USIM3 | materiais-basicos | sem via aplicável | — | — | — | — | — |
| USIM5 | materiais-basicos | sem via aplicável | — | — | — | — | — |
| USIM6 |  | Porta 0 · liquidez | — | — | — | — | — |
| VALE3 | materiais-basicos | avaliado | DCF por fluxo da firma | fundamental | 67,25 | 78,62 | -14,5% |
| VAMO3 | consumo-ciclico | avaliado | DCF sobre lucro distribuível | âncora | 1,50 | 3,50 | -57,1% |
| VBBR3 | energia | avaliado | DCF sobre lucro distribuível | fundamental | 36,35 | 36,99 | -1,7% |
| VITT3 | materiais-basicos | Porta 0 · liquidez | — | — | — | — | — |
| VIVA3 | consumo-ciclico | Porta 0 · histórico | — | — | — | — | — |
| VIVR3 | construcao-e-imobiliario | Porta 0 · liquidez | — | — | — | — | — |
| VIVT3 | telecomunicacoes | avaliado | DCF por fluxo da firma | g = 0 | 6,33 | 30,06 | -78,9% |
| VLID3 | servicos | avaliado | DCF por fluxo da firma | fundamental | 5,78 | 17,88 | -67,7% |
| VSTE3 | consumo-ciclico | Porta 0 · liquidez | — | — | — | — | — |
| VTRU3 | educacao | Porta 0 · histórico | — | — | — | — | — |
| VULC3 | consumo-ciclico | avaliado | DCF por fluxo da firma | fundamental | 8,91 | 13,01 | -31,5% |
| VVEO3 | consumo-nao-ciclico | Porta 0 · liquidez | — | — | — | — | — |
| WDCN3 | comercio-atacado-e-varejo | Porta 0 · liquidez | — | — | — | — | — |
| WEGE3 | bens-industriais | avaliado | DCF por fluxo da firma | fundamental | 12,37 | 51,74 | -76,1% |
| WEST3 | consumo-ciclico | Porta 0 · liquidez | — | — | — | — | — |
| WHRL3 | consumo-ciclico | Porta 0 · liquidez | — | — | — | — | — |
| WHRL4 |  | Porta 0 · liquidez | — | — | — | — | — |
| WIZC3 | servicos-financeiros | avaliado | DCF por fluxo da firma | âncora | 19,54 | 8,10 | 141,2% |
| WLMM4 |  | Porta 0 · liquidez | — | — | — | — | — |
| YDUQ3 | educacao | avaliado | DCF sobre lucro distribuível | âncora | 3,03 | 9,64 | -68,6% |

# A2 — a curva de juros observada

Medido em 14/09/2026.

```bash
python tool/tesouro_baixar.py              # data/tesouro/precotaxatesourodireto.csv
dart run tool/curva_ligar.dart 2026-09-04  # grava curva_ligacao_2026-09-04.json
```

---

## 1. A fonte

**Tesouro Transparente**, conjunto "Taxas dos Títulos Ofertados pelo Tesouro
Direto". Um CSV único, aberto, com 176.042 linhas de 31/12/2004 a 10/09/2026.

| título | uso |
|---|---|
| Tesouro Prefixado (LTN) | cupom zero nominal — taxa à vista exata |
| Tesouro Prefixado com Juros Semestrais (NTN-F) | prazos longos, até ~10 anos |
| Tesouro IPCA+ (NTN-B Principal) | curva real até ~24 anos — não usada ainda (B7) |

O endereço do CSV vem do catálogo CKAN a cada download: o identificador do
recurso muda quando o Tesouro republica o conjunto.

## 2. O alcance

| data-base | LTN | NTN-F | NTN-B Principal |
|---|---|---|---|
| 10/09/2026 | 0,3 a 5,3 anos | até 10,3 | até 23,9 |
| 02/09/2024 | 0,3 a 6,3 | até 10,3 | até 20,7 |
| 01/09/2020 | 0,3 a 5,3 | até 10,3 | até 24,7 |
| 01/09/2015 | 0,3 a 5,3 | até 9,3 | até 19,7 |

## 3. O motor contra a curva, por coorte

A perpetuidade do motor era a média decenal do CDI; a da curva é o forward
depois do décimo ano.

| coorte | motor | curva | diferença |
|---|---:|---:|---:|
| 2018 | 10,41% | 12,10% | +1,69 |
| 2019 | 9,92% | 7,81% | −2,11 |
| 2020 | 9,32% | 8,96% | −0,36 |
| 2021 | 8,46% | 11,96% | **+3,50** |
| 2022 | 8,61% | 12,36% | **+3,75** |
| 2023 | 9,21% | 12,11% | +2,90 |
| 2024 | 9,28% | 12,31% | +3,03 |
| 2025 | 9,36% | 13,84% | **+4,48** |

A forma também diverge. Em 2022 o motor fazia a taxa cair de 13,48% no ano 1 a
8,61% no ano 10; a curva ia de 12,37% a 12,36%.

## 4. A curva de hoje

Em 04/09/2026, oito vértices até 10,3 anos:

| ano | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | ∞ |
|---|---|---|---|---|---|---|---|---|---|---|---|
| forward | 13,6% | 14,1% | 14,5% | 14,5% | 14,7% | 14,6% | 14,5% | 14,4% | 14,4% | 14,3% | **14,3%** |

O motor de dois pontos ia de **14,1% a 9,4%**.

## 5. O efeito no universo

Mesmos fundamentos da fonte de mercado, mesmo preço, só a taxa trocada:

| | dois pontos | curva |
|---|---:|---:|
| avaliados | 127 | 127 |
| perdidos / ganhos | | AMER3, EVEN3 / CSAN3, KLBN4 |
| **potencial mediano** | **−37,6%** | **−48,6%** |
| fração com potencial positivo | 30,4% | 16,8% |
| mediana do Δ | | −12,2 p.p. |
| **correlação de postos** | | **0,9325** |

**Nível cai muito, ordenação quase não muda** — a curva reordena por duração,
e ativos com mais valor no terminal perdem mais.

### 5.1 Remedido com o prazo em dias úteis (decisão 79)

A primeira montagem media o prazo em dias corridos. Com dias úteis da
liquidação, pelo calendário conhecido na data-base — conferido contra o PU de
19.171 LTN, 99,13% ao dia —, o efeito isolado sobre o mesmo arquivo do Tesouro
é de **no máximo 4,7 bp** nos forwards anuais e **menos de 0,5 bp** na
perpetuidade, em onze datas-base de 2018 a 2026. Os forwards de hoje, com uma
casa, mudam em dois anos: 14,2% no ano 2 e 14,3% no ano 9.

Remedido em 04/09/2026, dentro da mesma execução:

| | dois pontos | curva |
|---|---:|---:|
| avaliados | 128 | 127 |
| potencial mediano | −33,1% | −53,2% |
| mediana do Δ | | −12,2 p.p. |
| correlação de postos | | **0,9174** |

**A tabela da §5 e esta não se comparam em nível.** A montagem de dois pontos
não usa a curva, e mesmo assim mudou entre as duas medições — deriva do dado de
mercado entre sessões, e as correções da camada de dados da decisão 77. A
comparação que vale é dentro de cada execução, e ela diz o mesmo nas duas: a
curva derruba o nível em cerca de 12 pontos e quase não reordena.

## 6. O que isto diz, e o que não diz

A curva é a taxa que o mercado atribui a cada prazo. Usá-la é o que um
avaliador profissional faria, e é o que o "valuation exemplar" pede.

Ela **piora o nível** que a §2.8 já registrava como deslocado. Isso não é
argumento contra a curva: é evidência de que a compressão do nível vem de outra
parte do motor — o terminal neutro, o prêmio de risco, o horizonte —, e que a
taxa de equilíbrio pelo CDI médio a vinha **mascarando** em 3 a 4,5 pontos.

**O padrão é decisão do usuário** (decisão 74), porque muda o que toda tela de
avaliação mostra.

# A1.7 — a ingestão ligada ao motor

Executado em 11/09/2026, sobre a base histórica completa: **DFP de 2010 a
2025**, 15.212 exercícios de 1.218 companhias.

```bash
python tool/cvm_baixar.py --de 2010 --ate 2025 --docs DFP,FCA
dart run tool/cvm_ponte.dart data/cvm
dart run tool/cvm_ingerir.dart data/cvm
dart run tool/cvm_ligar.dart          # grava cvm_ligacao.json
```

---

## 1. Como ficou ligado

O exercício chega ao motor **mesclado campo a campo**, e cada campo carrega de
onde veio ([decisão 69](../decisoes/069-a-mescla-carrega-a-procedencia.md)).

| a CVM fornece | o mercado fornece |
|---|---|
| receita, EBIT, resultado antes dos tributos, tributos, **lucro líquido**, LPA | preço, **valor de mercado**, **contagem corrente** |
| **ativo total**, circulante, passivo circulante, patrimônio, não controladores | EBITDA, `enterpriseToEbitda` |
| caixa, aplicações, dívida de curto e de longo prazo, imobilizado, intangível | o que a CVM não cobrir |
| caixa operacional e de investimento, CapEx, D&A | |
| **data de recebimento**, **fração em tesouraria** | |

Sobre 4.988 exercícios mesclados: **70.514 campos da CVM** contra **85.567 da
fonte de mercado**.

O leitor ganhou o nível 3 do balanço, e ele é padronizado: sobre os 293 CNPJs
do universo em 2023, cada código de `1.01.01` a `2.02.01` aparece em 246 a 260
companhias com **duas ou três grafias apenas**. Como no EBIT, cada um confere a
descrição antes de aceitar o código — banco tem outra estrutura, e ali a
resposta é `null`.

## 2. O que mudou no resultado

| | |
|---|---:|
| tickers com série da CVM | **360** de 375 |
| avaliados **antes** | 127 |
| avaliados **depois** | 127 |
| ganhos | 0 |
| perdidos | 0 |
| **mediana do `\|Δ potencial\|`** | **0,0%** |
| moveram mais de 1 p.p. | 9 |
| moveram mais de 10 p.p. | **7** |

**Nenhuma cobertura foi perdida e nenhuma foi inventada.** As duas fontes
concordam na quase totalidade — o que é a validação mútua que faltava.

E os sete que se movem são, cinco deles, **bancos**:

| ticker | antes | depois | Δ |
|---|---:|---:|---:|
| BMGB4 | +33,9% | −50,0% | −83,9 p.p. |
| MBRF3 | −83,8% | −8,1% | +75,7 p.p. |
| BPAC11 | −15,2% | −65,7% | −50,5 p.p. |
| SMTO3 | +92,0% | +46,8% | −45,2 p.p. |
| ITUB4 | +3,6% | −35,8% | −39,5 p.p. |
| ITUB3 | −1,8% | −39,3% | −37,6 p.p. |
| BRSR6 | −1,5% | +29,2% | +30,8 p.p. |

**É exatamente o que a §2.12 previa.** O ITUB4 era avaliado sem `netIncome` em
nenhum dos dezesseis exercícios, com o freio de reinvestimento desligado e a
vantagem residual barrada por "retorno do ciclo não medido". Com o lucro
publicado pela CVM, ele passa a ser avaliado como qualquer outro — e sai de
+3,6% para −35,8%.

**A §2.12 está fechada.** Não por parâmetro, como ela mesma dizia que não
seria, mas por fonte.

## 3. O defeito que a ligação criou, e como foi pego

Na primeira execução a **MILS3 saiu com +14.037,7% de potencial** — o falso
desconto que a regra do maior da decisão 66 existe para barrar.

A causa está na fonte. O `QT_ACAO_TOTAL_CAP_INTEGR` da CVM **não tem escala
declarada**, e ela varia por declarante. Medido sobre 2.081 pares comparáveis
contra a contagem da fonte de mercado:

| escala | exercícios |
|---|---:|
| unidades | 1.267 (**60,9%**) |
| **milhares** | 717 (**34,5%**) |
| outra | 97 (4,7%) |

A ABEV3 aparece com 15.757.657 contra 15.761.638.000 papéis; a MILS3, com
234.178 contra 234.178.210.

A correção é a [decisão 70](../decisoes/070-a-contagem-de-acoes-da-cvm-nao-tem-escala.md):
**só a fração `tesouraria ÷ integralizadas` entra**, porque as duas saem do
mesmo registro e erram juntas. A base continua sendo a do agregador, cuja
qualidade a §1.7 já mediu.

**O que pegou o defeito.** Não foi o `dart analyze`, não foram os 474 testes,
não foi o gate — nenhum deles tinha como saber que 234.178 não é a contagem da
MILS3. Foi a **comparação antes-depois** sobre o universo inteiro. Toda troca
de fonte precisa dela.

## 4. O estado do inventário depois desta rodada

| limitação | antes | agora |
|---|---|---|
| §1.1 granularidade anual | anual | **ITR disponível**; a série ligada segue anual |
| §1.3 viés de sobrevivência | sem saída | **9.570 exercícios** de companhias fora do universo vivo, ingeridos |
| §2.3 defasagem é premissa | 90 dias presumidos | **`DT_RECEB` observado** |
| §2.12 sem lucro de banco | sem saída | **fechada** — ITUB4 avaliado com lucro real |
| §2.17 sem conferência de balanço | impossível | **fecha em 15.160 de 15.163** |
| §3.7 tesouraria não tratada | sem dado | **tratada pela fração** |
| §1.7 duas contagens | sem árbitro | **inalterada** — a CVM não ajuda, ver §3 |

## 5. O que fica em aberto

- **A série ligada é anual.** O ITR está ingerido e conferido, mas misturá-lo
  na série do motor duplicaria períodos sem que a cascata saiba. Passar a
  trimestral é mudança de método — o motor presume um exercício por ano em
  quase toda guarda — e vale item próprio.
- **As 9.570 deslistadas não têm preço.** Estão na base e não entram na
  validação: sem série de cotações não há retorno a confrontar. É o A3.
- **A ligação vive na ferramenta, não no aplicativo.** `tool/cvm_ligar.dart`
  monta o repositório mesclado para a validação; o aplicativo continua lendo
  só o agregador. Levá-la ao aplicativo exige decidir como 10 MB de exercícios
  chegam ao dispositivo, e é item de infraestrutura, não de método.
- **Onde as fontes discordam, a CVM vence por regra.** A divergência campo a
  campo não foi medida.

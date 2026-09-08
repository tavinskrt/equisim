# Validação preditiva do motor de avaliação

Executada em 08/09/2026. Responde à única pergunta que separa um motor correto
de um motor em que se pode apoiar decisão: **o potencial que ele apura ordena o
retorno que veio depois?**

Reproduz-se com `dart run tool/backtest_valuation.dart`, que grava
`backtest_valuation.json`. As correções que este documento sustenta estão na
[decisão 32](../decisoes/032-validacao-preditiva-e-diagnosticos-do-resultado.md).

---

## 1. Desenho

Oito coortes anuais, de 30/09/2018 a 30/09/2025. A primeira é 2018 porque a
Porta 0 exige oito exercícios publicados, e o oitavo só se torna público ali.

Em cada coorte, para cada um dos 374 papéis do universo, a cascata roda **com o
que era público naquele dia**:

| Insumo | Recorte *point-in-time* |
|---|---|
| Exercícios | Filtrados por `PointInTimeView`, com a defasagem de publicação que ela já aplica |
| Preço e beta | Janela de cinco anos terminando na data da coorte |
| Âncoras macro | `ResolveMarketAnchors` resolvido naquela data, sobre dez anos de CDI, IPCA e IBC-Br |
| Valor de mercado | **Reconstruído.** A fonte repete a capitalização de hoje em todos os exercícios — conferido: ela não varia entre linhas em nenhum dos 363 ativos do cache. Sem reconstruir, uma avaliação de 2018 receberia a capitalização de 2026 no divisor da ponte e no peso do WACC. A reconstrução é `contagem do exercício × preço da coorte` |

O histórico macro precisou ser estendido para isso: o cache começava em 09/2016,
e a janela decenal do CDI numa coorte de 2018 tinha dois anos.
`tool/backfill_macro.dart` traz as três séries desde 2005.

**Contra o quê.** Um coeficiente de correlação sozinho não diz se a cascata se
paga. O potencial é medido lado a lado com dois ordenadores que usam os mesmos
dados e **nenhuma modelagem**:

- **valor patrimonial sobre preço** (`PL ÷ VM`), o fator de valor clássico;
- **lucro sobre preço** (`lucro líquido ÷ VM`).

Se o motor não os alcança, a cascata inteira está cobrando complexidade que não
entrega.

### Cobertura

| Coorte | Papéis com preço | Avaliados |
|---|---:|---:|
| 2018 | 273 | 78 |
| 2019 | 275 | 91 |
| 2020 | 298 | 102 |
| 2021 | 349 | 112 |
| 2022 | 352 | 116 |
| 2023 | 353 | 111 |
| 2024 | 354 | 102 |
| 2025 | 361 | 109 |

A diferença entre as duas colunas é a Porta 0 mais as recusas nomeadas, e é o
recorte que o projeto declara desde a decisão 25. **Ele não foi mexido:** a
filtragem existe para tornar a avaliação precisa, e medi-la é medir o motor tal
como ele é usado.

---

## 2. O resultado

### 2.1 Coeficiente de informação, 36 meses

Correlação de ordem de Spearman entre o ordenador e o retorno realizado, no
**mesmo subconjunto** de ativos — só onde os três existem, para que a comparação
seja entre ordenadores e não entre coberturas.

| Coorte | n | Potencial | PL/VM | Lucro/VM |
|---|---:|---:|---:|---:|
| 2018 | 70 | 0,168 | 0,135 | 0,161 |
| 2019 | 81 | 0,164 | 0,288 | 0,332 |
| 2020 | 90 | 0,365 | 0,203 | 0,347 |
| 2021 | 108 | 0,149 | 0,250 | 0,168 |
| 2022 | 113 | 0,006 | 0,188 | −0,078 |
| **média** | | **0,170** | **0,213** | **0,186** |
| **positivas** | | **5/5** | 5/5 | 4/5 |

O potencial tem sinal, e ele é consistente: positivo em todas as coortes
medidas. Um coeficiente de informação de 0,17 é respeitável — fator de ações
quantitativo costuma trabalhar entre 0,02 e 0,10.

Ele **não** supera os ordenadores ingênuos. Fica entre os dois.

### 2.2 Doze meses: quase nada, e é o esperado

| Ordenador | IC médio | Positivas |
|---|---:|---:|
| Potencial | 0,098 | 5/7 |
| PL/VM | 0,123 | 7/7 |
| Lucro/VM | 0,066 | 5/7 |

A [decisão 26](../decisoes/026-horizonte-de-convergencia-de-36-meses.md) fixou o
horizonte de convergência em 36 meses justamente por não acreditar em
convergência de um ano. A medição concorda: em doze meses o sinal é fraco para
os três.

### 2.3 Quintis, 36 meses

Retorno médio realizado por quintil do ordenador, agregado sobre as coortes.

| Ordenador | Q1 | Q2 | Q3 | Q4 | Q5 | Q5−Q1 | Monótono |
|---|---:|---:|---:|---:|---:|---:|:---:|
| **Potencial** | −9,0% | 11,5% | 13,7% | 21,2% | 40,8% | **49,8 p.p.** | **sim** |
| PL/VM | −6,2% | 7,1% | 14,1% | 8,7% | 53,6% | 59,7 p.p. | não |
| Lucro/VM | −8,8% | 10,9% | 12,2% | 13,7% | 50,1% | 59,0 p.p. | sim |

**É aqui que o motor tem algo próprio.** Os dois fatores espalham mais entre as
pontas, mas o valor patrimonial não é monótono — o quarto quintil dele rende
menos que o terceiro. Um ordenador não monótono serve para separar extremos e
não para **dosar posição**, que é o que decisão patrimonial exige.

### 2.4 Retorno do universo por coorte, para leitura de contexto

| Coorte | n | Retorno médio 36m | Mediano |
|---|---:|---:|---:|
| 2018 | 78 | 58,7% | 28,8% |
| 2019 | 91 | 6,5% | −15,3% |
| 2020 | 102 | 12,3% | 1,2% |
| 2021 | 112 | −8,4% | −15,7% |
| 2022 | 116 | 2,6% | −2,4% |

A coorte de 2022 é a que o potencial quase não ordena (IC 0,006). É também a
única em que o lucro sobre preço ordena ao contrário. Não há explicação medida.

---

## 3. A nota de confiança foi construída, medida e descartada

O resultado passou a carregar diagnósticos estruturados — peso do terminal,
participação do capital próprio, fator de normalização, origem do crescimento,
ressalvas. Sobre eles foi montada uma nota ordinal: alta sem ressalva, média com
uma ou duas, baixa com três ou mais.

**A medição a desmentiu.**

| Grupo | Coortes | n médio | IC 36m | Positivas |
|---|---:|---:|---:|---:|
| Sem ressalva alguma | 5 | 29 | **−0,007** | 2/5 |
| Uma ou duas ressalvas | 5 | 65 | **0,206** | 5/5 |
| Três ou mais | — | — | amostra insuficiente | — |

O grupo que a nota chamava de mais confiável não tem sinal nenhum. O grupo
rebaixado carrega o sinal inteiro.

A nota foi removida. Os **fatos** ficaram: eles descrevem o que a conta fez, e
isso continua verdadeiro e útil. O que saiu foi a promessa de que eles medem
confiabilidade.

Uma ressalva também saiu do conjunto — *custo da dívida estimado* —, porque
disparava em **469 das 821** avaliações. Ela deixou de ser exceção quando a
[decisão 31](../decisoes/031-escala-do-preco-tributo-e-invariancia-das-guardas.md)
tornou a classificação sintética o método.

### Frequência das ressalvas restantes

| Ressalva | Ocorrências |
|---|---:|
| Crescimento não identificável | 381 |
| Via migrada no meio do cálculo | 164 |
| Base com forte correção de um só exercício | 154 |
| Ponte por papel frágil | 62 |
| Valor terminal domina o preço justo | 55 |

---

## 4. O prêmio de risco: botão de nível, não de ordenação

As âncoras medem, na mesma janela, o CDI a 9,40% e o Ibovespa a 12,22% — um
prêmio *ex post* de **2,83 p.p.** O motor desconta com **5,50 p.p.**
parametrizados. A divergência estava silenciosa: `marketCagr` é calculado e só
alimenta o veredito de meta.

**Trocar um pelo outro seria trocar premissa declarada por ruído.** Dez anos de
índice, com volatilidade de ações da ordem de 25% ao ano, dão erro-padrão do
prêmio médio na casa de 8 pontos percentuais: o intervalo em torno de 2,83 cobre
folgadamente 5,50 e 7,00.

O que decide a questão para uso patrimonial é a sensibilidade, medida com
`tool/probe_premium.dart` sobre os 119 avaliados:

| Prêmio | p25 | Mediana | p75 | Potenciais positivos | ρ de ordem contra 5,50 |
|---|---:|---:|---:|---:|---:|
| 7,00 p.p. | −72,8% | −54,5% | −34,5% | 9 | 0,983 |
| **5,50 p.p.** | −68,6% | −47,5% | −26,3% | 10 | 1,000 |
| 4,00 p.p. | −71,2% | −45,4% | −15,0% | 18 | 0,968 |
| 2,83 p.p. | −67,7% | −43,2% | −4,7% | 25 | 0,931 |

Em todo o intervalo plausível, a **ordenação praticamente não muda** — e é a
ordenação que a §2 validou e que a
[decisão 27](../decisoes/027-recalibragem-apos-a-primeira-validacao.md) já
adotara como o uso do número. O nível muda 11 pontos percentuais de mediana, e
15 dos 119 trocam o sinal do potencial entre 5,50 e 2,83.

---

## 5. Os três vieses que esta medição não remove

Todos inflam o resultado, e nenhum é corrigível com o dado disponível.

1. **Sobrevivência.** O universo é o que está listado hoje. Quem fechou capital
   ou quebrou entre a coorte e o resgate não está aqui. Isso levanta o retorno
   de todas as carteiras medidas — e levanta **mais** o do valor patrimonial,
   que é o fator carregado em ativo em dificuldade.

2. **Reapresentação.** Os exercícios vêm como a fonte os publica hoje, não como
   estavam no dia da coorte. Reapresentação contábil entra como conhecimento
   futuro, para os três ordenadores igualmente.

3. **Provento.** O retorno de referência é de preço, pela
   [decisão 23](../decisoes/023-remocao-de-proventos.md). O valor que o motor
   apura **inclui** a distribuição, então a medição o penaliza em ativo de
   *payout* alto. Este viés é o único que trabalha contra o motor.

E uma limitação de amostra que não é viés: **cinco coortes de 36 meses não são
cinco observações independentes**. As janelas se sobrepõem. O `t` de 3,33 sobre
a média das cinco superestima a confiança; o que a medição sustenta é o sinal e
a consistência, não um nível de significância.

---

## 6. O que isto autoriza dizer, e o que não autoriza

**Autoriza:** o potencial do motor ordena o retorno de 36 meses, com sinal
positivo em todas as coortes medidas e quintis monótonos separando 49,8 pontos
percentuais entre as pontas. Ele é utilizável como ordenador para dosar posição.

**Não autoriza:** dizer que o preço justo prevê o preço futuro; que o motor é o
ordenador mais forte disponível — não é, e dois fatores de uma linha o alcançam;
nem que a filtragem, a cascata e os treze parâmetros se justificam pelo poder
preditivo. Eles se justificam pelo preço justo em reais, pela auditabilidade e
pela recusa nomeada, que fator de ordenação nenhum produz.

**Fica em aberto:** por que o grupo sem ressalvas não ordena. A hipótese — ativo
estável é o que o mercado já precifica bem, e a discordância informativa aparece
onde o modelo faz algo que o preço não fez — é plausível e não foi testada.

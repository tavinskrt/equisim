# Equisim — Parecer Técnico e Plano Arquitetural
### Auditoria de stack, viabilidade de dados e proposta de arquitetura para o TCC

**Data:** 19/08/2026 · **Base:** commit `99343e5` · Flutter 3.44.8 / Dart 3.12.2
**Documento anterior:** `RELATORIO_ANALISE.md` (auditoria de defeitos) — *não está mais no repositório*

---

> ## ⏸ DOCUMENTO CONGELADO
>
> **Este parecer não é mais mantido.** Ele é o registro do que se concluiu em
> **agosto de 2026**, e envelhece a partir daí — de propósito. Um documento
> datado que se sabe datado engana menos que um documento vivo que ninguém
> atualiza. Ver [decisão 19](docs/decisoes/019-registro-por-arquivo.md).
>
> **Onde procurar o que vale hoje:**
>
> | O que você quer | Onde está |
> |---|---|
> | Decisões **0 a 18** | Aqui mesmo — tabelas na §0 (linha 7) e na §7 (linha ~1264). Continuam válidas. |
> | Decisões **19 em diante** | [`docs/decisoes/`](docs/decisoes/), uma por arquivo |
> | O que está feito e o que não está | [`docs/estado.md`](docs/estado.md) — **gerado**, nunca escrito à mão |
> | Apontamento de orientador ou de dev | [`docs/apontamentos/`](docs/apontamentos/) |
>
> **O que sabidamente envelheceu neste texto:**
>
> - O roadmap da §6 marca as Fases 0 a 5 como concluídas em 19–20/08/2026. Nove
>   commits posteriores — as Ondas 1 a 4 de refatoração da UI — não têm lugar
>   nele. Ver [decisão 21](docs/decisoes/021-ondas-de-refatoracao-da-ui.md).
> - A cadeia de QA por agente e o barramento `lib/audit/` não existiam quando
>   isto foi escrito. Ver [decisão 20](docs/decisoes/020-cadeia-de-qa-por-agente.md).
> - As medições da §1 e o estudo de qualidade de dados da §0.4 têm data. Confira
>   a data antes de usar o número.
>
> **Não edite este arquivo para corrigi-lo.** Se uma decisão daqui deixou de
> valer, escreva uma nova em `docs/decisoes/` que a substitua — é assim que a
> mudança de rumo fica rastreável em vez de sumir num `git diff` de markdown.

---

> ### ✅ DECISÕES CONSOLIDADAS (19/08/2026)
>
> | # | Questão | Decisão |
> |---|---|---|
> | **0** | Escopo | **Apenas Escopo B.** Escopo A descartado por orientação: **sem FIIs** |
> | 1 | Backend Python/Go | **Não** — Dart puro; Cloud Function apenas como proxy de segredo/CORS |
> | 2 | FFI / Rust | **Não** — rejeitado por medição (§1) |
> | 3 | State management | **Riverpod** |
> | 4 | Cache local | **Drift** |
> | 5 | Fonte do IFIX | **Descartada** — sem FIIs, sem IFIX |
> | 6 | Prêmio de risco de mercado | **Parametrizado**, padrão 5–6% a.a. |
> | 7 | Cenários do DCF | **Monte Carlo a apresentar ao orientador** → engenharia suporta os dois modos sem retrabalho (§5.5a) |
> | 8 | `publicationLag` | **90 dias** |
>
> O TCC passa a ser de **engenharia de software**: *"é possível construir uma ferramenta de apoio à decisão fundamentada em DCF/CAPM?"*. A evidência acadêmica deixa de ser um achado empírico e passa a ser **a qualidade e a corretude verificável da construção** — o que redefine a Fase 5 (§6).
>
> **Seções deste documento afetadas pelo corte:** §2.4 (IFIX/FII), §3.2 (árvore), §4 (domínio), §6 (roadmap). §1 (stack), §2.1–2.3 (auditoria da API) e §5 (decisões de engenharia) permanecem válidas na íntegra.

---

## 0. IMPACTO DO CORTE DE ESCOPO

Remover FIIs e o experimento A não é uma subtração cosmética — **elimina a maior parte dos defeitos catalogados** em [`RELATORIO_ANALISE.md`](RELATORIO_ANALISE.md), porque o código que os continha deixa de existir.

### 0.1. Defeitos resolvidos por deleção

| Defeito reportado | Por que morre |
|---|---|
| Dividendos sintéticos fabricados (`:137-194`) | Sem reinvestimento explícito de proventos |
| Atribuição de dividendo à posição errada (data-ex) | idem |
| Dividendos somem sem reinvestimento (`:383-386`) | idem |
| Heurística de split que inventa cotas (`:957-988`) | Substituída por `adjustedClose` |
| Fallback de Graham com look-ahead (`:660-893`) | Motor deletado |
| Extrapolação de fundamentos a 6% a.a. | Valuation passa a ser prospectivo (hoje), não replay histórico |
| CAGR sobre aportes (`:899-904`) | **Não há aportes periódicos no Escopo B** |
| Volatilidade/Sharpe/DD sobre curva inflada por aportes | idem |
| `/v2/fii/indicators` com parsing quebrado | Sem FIIs |
| `fiiFundamentals` baixado e descartado | Sem FIIs |
| IFIX indisponível na API | Sem FIIs |

### 0.2. Defeitos que **sobrevivem** e continuam na fila

- Token da brapi embarcado no bundle + `corsproxy.io` recebendo o header `Authorization` (§5.3)
- Testes dependentes de rede / motor acoplado ao `StockService`
- Índice composto do Firestore ausente (se o histórico for mantido)
- `TimeoutException` sombreando a do `dart:async`

### 0.3. Simplificações técnicas de alto impacto

**a) Séries de preço: `close` é ajustado por split, `adjustedClose` é retorno total.** *(Revisado após as decisões nº 9 e nº 12.)*

Eu havia proposto usar `adjustedClose` como fonte única do backtest. **A decisão nº 12 (modelar IR sobre JCP) inviabiliza isso**, porque a série de retorno total embute reinvestimento de proventos **brutos** — não há como descontar imposto de dentro dela.

Verificação decisiva (19/08/2026): BBAS3 desdobrou 1:2 com data-ex em 15/04/2024 e WEGE3 em 27/04/2021. **Nenhuma das duas séries de `close` apresenta descontinuidade:**

| | véspera | data-ex |
|---|---|---|
| BBAS3 | 28,50 | 28,23 |
| WEGE3 | 37,32 | 37,01 |

Se `close` fosse bruto, haveria queda de ~50%. **Logo `close` já vem ajustado por desdobramentos e grupamentos, mas não por proventos** — convenção Yahoo. Esta é exatamente a série necessária:

| Série | Ajuste | Uso |
|---|---|---|
| `close` | split ✓ · provento ✗ | **Fonte única**: backtest, DY, beta, correlação — sempre combinada com `cashDividends` |
| `adjustedClose` | split ✓ · provento ⚠ **incompleto** | Apenas conferência grosseira. **Não usar onde precisão de provento importa** — ver §0.4 |

**A heurística de detecção de split continua morta** (o problema já vem resolvido pela API) — só o tratamento de proventos volta à cena, agora de forma controlada e com finalidade clara.

> ### ⛔ Retratação: o oráculo `adjustedClose` **não funciona** e foi removido do plano
>
> Eu havia proposto validar o motor em dois estágios contra `adjustedClose` (`TaxPolicy.zero` converge; `TaxPolicy.brasil` fica abaixo pelo IR). **Testei e a premissa é falsa.** Ver §0.4 — o desvio de base entre as duas fontes chega a 38,5%, o que sepultaria completamente o sinal de 15% que se pretendia medir.
>
> A estratégia de validação foi refeita sobre outra âncora, esta sim verificada (§0.4).

**b) TWR e XIRR voltam ao escopo.** *(Revertendo o que afirmei antes.)* Eu havia removido as duas alegando ausência de fluxos externos. **A decisão nº 9 introduziu aporte mensal**, então a distinção entre retorno ponderado por tempo e por dinheiro volta a existir e volta a importar:

- **TWR** — neutraliza os aportes. É a métrica correta para **comparar Principal vs Reserva**, porque isola a qualidade da composição do cronograma de aportes.
- **XIRR** — taxa interna dos fluxos datados. É o **retorno efetivo do investidor**, e é o número que deve ser confrontado com a rentabilidade requerida da meta.

Usar CAGR simples sobre capital aportado seria repetir exatamente o defeito §2.2.4 do relatório anterior.

**c) Proventos disponíveis com rótulo fiscal.** Verificado: `/v2/stocks/dividends` traz `label` por evento. Distribuição na amostra:

| Ticker | JCP | DIVIDENDO | RENDIMENTO |
|---|---|---|---|
| PETR4 | 70 | 57 | 41 |
| ITUB4 | 274 | 209 | — |
| BBAS3 | 132 | 58 | 65 |
| WEGE3 | 89 | 44 | — |

O volume de JCP é alto — em ITUB4 é a **maioria** dos eventos. Ignorar o IR de 15% produziria erro material nos proventos, o que confirma a decisão nº 12.

---

## 0.4. Estudo de qualidade dos dados de proventos *(decisão nº 17)*

A decisão nº 17 — *"utilizar as métricas atualmente disponibilizadas pela API"* — exigiu descobrir **o que a API de fato disponibiliza**. Fiz duas verificações; a segunda salvou a estratégia de validação que a primeira derrubou.

### Teste 1 — `cashDividends` × `adjustedClose`: **não reconciliam**

Reconstruí o fator de ajuste de proventos a partir do fluxo de eventos, `Π(1 − rate/close_véspera)`, e comparei com a razão `adjustedClose/close` observada em 22/08/2016:

| Ticker | razão observada | fator implícito dos proventos | eventos | desvio |
|---|---|---|---|---|
| PETR4 | 0,2529 | 0,2583 | 77 | **−2,1%** |
| WEGE3 | 0,8394 | 0,7630 | 62 | **−9,1%** |
| ITUB4 | 0,5623 | 0,4577 | 168 | **−18,6%** |
| BBAS3 | 0,5323 | 0,3275 | 113 | **−38,5%** |

O fluxo de eventos implica **mais** provento do que o `adjustedClose` reflete. Investiguei duplicação como causa: encontrei apenas 1 duplicata exata (PETR4, ex 01/06/2026) e vários casos legítimos de múltiplas tranches na mesma data-ex. **Duplicação não explica desvios dessa magnitude.**

### Teste 2 — `cashDividends` × `statistics.dividendYield`: **reconciliam**

Somei os proventos dos últimos 12 meses por data-ex e dividi pelo preço corrente, comparando com o DY que a própria API publica:

| Ticker | preço | TTM | DY calculado | DY da API | eventos |
|---|---|---|---|---|---|
| BBAS3 | 18,08 | 0,551 | 3,05% | 3,00% | 7 |
| PETR4 | 43,11 | 2,642 | 6,13% | 6,00% | 10 |
| ITUB4 | 38,37 | 3,165 | 8,25% | 8,00% | 16 |
| WEGE3 | 48,51 | 1,181 | 2,43% | 2,00% | 6 |
| TAEE11 | 37,17 | 2,406 | 6,47% | 6,00% | 5 |

Casamento em todos os casos, dentro do arredondamento de 2 casas do campo da API.

### Conclusão

**`cashDividends` é confiável; `adjustedClose` é que subajusta proventos brasileiros.** É uma limitação conhecida do Yahoo Finance com JCP — e o padrão dos desvios sustenta isso (BBAS3, forte pagadora de JCP, é a pior; PETR4 é a melhor).

**Consequências para a arquitetura:**

1. **Fonte única de verdade:** `close` + `cashDividends` + `TaxPolicy`. Uma só máquina de retorno total, usada para backtest, DY, beta, correlação e volatilidade.
2. **Não usar `adjustedClose` para beta/correlação**, como eu havia recomendado — introduziria a mesma distorção. Como a máquina de retorno total já precisa existir para o backtest, **reusá-la é mais preciso e ainda reduz código**.
3. **Portão de qualidade automatizado:** o Teste 2 vira verificação de runtime — se o DY calculado divergir de `statistics.dividendYield` além de uma tolerância, o ticker é sinalizado como tendo dados de provento suspeitos, **em vez de reportar número errado em silêncio**.
4. `adjustedClose` fica apenas como conferência grosseira, com a limitação documentada na monografia.

### O que a API **não** fornece

Nenhum campo indica se `rate` é **bruto ou líquido**, e não há campo de alíquota — o payload tem apenas `assetIssued, paymentDate, rate, relatedTo, approvedOn, isinCode, label, lastDatePrior, remarks`. Portanto "usar as métricas da API" significa, concretamente:

- **da API:** `label` para classificação fiscal e `statistics.dividendYield` como portão de qualidade;
- **parâmetro declarado:** a alíquota, porque a API não a carrega (`TaxPolicy`, §4.3).

`rate` é tratado como **valor bruto declarado** — convenção de divulgação da B3/CVM. É **premissa declarada, não fato verificado**: a conferência documental contra o "Aviso aos Acionistas" de RI segue pendente, e é a única fonte de verdade possível. A premissa é explícita no código (`DividendBasis.gross`) e reversível por uma linha (§ ponto 18).

> ⚠ **Achado adicional:** `remarks = "csv:payment_date_estimated"` aparece em 154 eventos de ITUB4, 21 de BBAS3 e 18 de PETR4. **A data de pagamento é estimada, não oficial**, em parte relevante da base. Como o motor credita provento na data de pagamento, isso desloca o caixa em alguns dias. Impacto pequeno no resultado final, mas precisa ser declarado — e o campo `remarks` deve ser preservado até a camada de domínio para permitir o filtro.

**c) `PointInTimeView` sobrevive, mas em papel reduzido.** Eu havia recomendado essa barreira como defesa nº 1 contra look-ahead. Honestamente: **no Escopo B ela perde a maior parte da importância**, porque não há replay histórico de decisões. O que resta é legítimo mas modesto — escolher qual balanço anual já estava publicado *hoje* (daí o `publicationLag` de 90 dias, decisão nº 8). Mantenho, sem o peso arquitetural que tinha antes.

**d) Universo de ativos simplifica — e a whitelist atual está errada.** Verificado em 19/08/2026: `/v2/tickers?type=stock` devolve **781 tickers**, dos quais 10 terminam em `11`, com **interseção zero** com os 332 FIIs de `type=fund&subType=fii`. O filtro da API já é limpo.

O `_stockUnitsWhitelist` hardcoded em `stock_service.dart:344` é obsoleto e **prejudicial**: exclui indevidamente **IGTI11, ONCO11 e BRBI11** (Units legítimas que a API classifica como stock) e mantém 5 tickers que a API não lista mais (`CPLE11`, `JALL11`, `PPLA11`, `RNEW11`, `UNIP11`). **Deletar a whitelist e confiar em `type=stock`.**

---

## 1. PARECER CRÍTICO SOBRE A STACK

Não vou opinar sobre desempenho — **medi**. Compilei um benchmark AOT (`dart compile exe`) reproduzindo a carga real do sistema, com guarda contra eliminação de código morto.

### 1.1. Resultados medidos (Dart AOT nativo, Windows x64)

```
[1] BACKTEST DIÁRIO MULTIATIVO COM BANDAS
  10 ativos × 5 anos  (1.260 pregões)   0,024 ms/execução
  10 ativos × 10 anos (2.520 pregões)   0,059 ms/execução
  30 ativos × 10 anos (2.520 pregões)   0,140 ms/execução
  ESTUDO EM LOTE: 500 carteiras × 5 anos    0,011 s

[2] MONTE CARLO DCF (projeção 10 anos + perpetuidade)
    1.000 cenários     0,34 ms
   10.000 cenários     2,63 ms
  100.000 cenários    17,82 ms

[3] MATRIZ DE COVARIÂNCIA / BETA / CORRELAÇÃO (5 anos)
  10 ativos (10×10)    0,490 ms
  30 ativos (30×30)    4,225 ms
  50 ativos (50×50)   11,859 ms

[4] List<double> vs Float64List — 1M elementos
  List<double>   0,839 ms   |   Float64List  0,678 ms   →  ganho 1,24×

[5] ISOLATES
  Isolate.run spawn (trabalho trivial)          0,176 ms
  Isolate.run + captura de 10×1250 doubles      1,977 ms
```

### 1.2. O outro lado da balança — rede (brapi, medida real)

```
10 ativos × 10 anos, UMA requisição em lote   3.460 ms  (24.800 pontos)
10 ativos × 10 anos, requisições sequenciais  6.417 ms
5 endpoints de fundamentos (1 ativo)          1.218 ms
```

### 1.3. Conclusão quantitativa

| | Tempo |
|---|---|
| Cálculo (30 ativos × 10 anos) | **0,14 ms** |
| Rede (10 ativos × 10 anos, em lote) | **3.460 ms** |
| **Razão** | **≈ 1 : 25.000** |

**O sistema é I/O-bound por quatro ordens de grandeza.** Toda discussão sobre desempenho de processamento numérico é, neste projeto, irrelevante diante da latência de rede. Isso decide as três perguntas da diretiva:

#### Dart é suficiente para a computação quantitativa?
**Sim, com folga absurda.** O backtest completo de 5 anos custa 0,024 ms — cerca de **700× mais rápido** que o orçamento de um único frame a 60 fps (16,7 ms). O estudo estatístico inteiro descrito no relatório anterior (centenas de carteiras × janelas móveis) roda em **11 milissegundos**. Monte Carlo de 100 mil cenários cabe em um frame.

Consequência de design pouco intuitiva mas importante: o **recálculo do drag-and-drop pode ser síncrono a cada frame de arrasto**, sem debounce, sem estado intermediário, sem *loading*. Upside ponderado, concentração setorial e aderência à meta recalculam em microssegundos. Isso simplifica radicalmente a camada de estado.

#### Limites do Event Loop e justificativa para Isolates/FFI

O Dart é single-threaded por isolate: qualquer trabalho síncrono acima de ~16 ms derruba frames. Mas medidos os tempos acima, **o motor financeiro nunca chega perto disso**. O gargalo real de CPU no cliente é outro, e é preciso nomeá-lo corretamente: **`jsonDecode` de payloads grandes**. As 24.800 cotações vêm num JSON de vários MB, e desserializar isso na main isolate trava a UI por centenas de milissegundos.

**Isolates justificam-se — mas para desserialização e para o estudo em lote, não para o backtest.** Escrever na monografia que "o backtest roda em Isolate por questão de desempenho" seria falso e uma banca atenta pode cobrar a medição.

**FFI (C/C++/Rust): recomendo NÃO adotar, e transformar a rejeição em capítulo.** Três razões:
1. **Não há gargalo a otimizar** — 0,14 ms. Adotar FFI aqui é otimização prematura contra evidência empírica.
2. **`dart:ffi` não existe no Flutter Web.** O projeto tem alvo web (há `web/`, e `kIsWeb` no código). FFI eliminaria essa plataforma.
3. Custo de build por plataforma (`.so` / `.a` / `.dll`), toolchain cruzada, e superfície de crash nativo.

O ganho acadêmico está em **medir e rejeitar com dados**. Uma seção "Avaliação de necessidade de otimização nativa" que apresenta o benchmark, calcula a razão I/O:CPU e conclui pela não-adoção demonstra maturidade de engenharia muito melhor do que FFI decorativo. Se quiser um capítulo de otimização de verdade, o alvo correto é **a camada de rede e cache**, onde estão os 3,4 segundos.

*(Nota lateral: `Float64List` rendeu só 1,24× sobre `List<double>` — o AOT já desboxeia listas monomórficas de double. Vale usar typed data por semântica e por interoperabilidade com Isolates, não por velocidade.)*

#### Client-side monolítico vs. backend dedicado

| Critério | Tudo no Flutter | Backend dedicado (Python/Go) |
|---|---|---|
| Desempenho | **Suficiente** (medido) | Desnecessário |
| Custo infra | **R$ 0** | Hosting + cold start |
| Segredo da API | ✗ **token embarcado no build** | ✓ custódia no servidor |
| CORS no web | ✗ hoje via `corsproxy.io` (terceiro recebe o header `Authorization`) | ✓ resolvido |
| Reprodutibilidade | Cache local por dispositivo | ✓ cache central versionado |
| Complexidade de deploy | Baixa | Alta (2 pipelines) |
| Risco de deriva de implementação | Nenhum | **Alto** — dois motores para manter |
| Defesa na banca | Precisa justificar | Precisa justificar |

O argumento honesto a favor do backend **não é desempenho** — é **custódia de segredo e reprodutibilidade**. Mas migrar o motor financeiro para Python cria o pior problema possível num TCC: dois motores (o do app e o do estudo) que divergem silenciosamente, e números na monografia que não vêm do software entregue.

**Proposta — arquitetura híbrida assimétrica:**

1. **Motor financeiro em Dart puro**, num pacote sem dependência de Flutter (`packages/equisim_core`).
2. **O mesmo pacote alimenta duas frentes:** o app Flutter e um **CLI de validação** (`tools/validation_harness`) que comprova a corretude do motor e gera os anexos da monografia. Argumento forte para a banca: *"as evidências apresentadas foram produzidas pelo mesmo código que executa no aplicativo, sem reimplementação."*
3. **Proxy mínimo em Firebase Cloud Functions** (~50 linhas) apenas para: custodiar o token da brapi, resolver CORS e cachear respostas. Zero fornecedor novo — o Firebase já está no projeto.

Isso captura o benefício real do backend sem duplicar a inteligência matemática.

### 1.4. Veredito

**Manter Flutter/Dart.** Não há gargalo intransponível — há uma margem de 4 ordens de grandeza. A base legada de autenticação, sessão e temas está sólida (ver §2.4 do relatório anterior: as regras do Firestore estão corretas) e reescrevê-la seria desperdiçar semanas em problema já resolvido.

**Roteiro de defesa perante a banca:**
1. Apresentar o benchmark e a razão I/O:CPU de 1:25.000 → a escolha de stack é irrelevante para desempenho neste domínio; o critério decisor passa a ser **produtividade e unicidade de codebase**.
2. Demonstrar que o motor é Dart puro, testável sem Flutter e sem rede, e que os números da monografia saem do mesmo código.
3. Apresentar a avaliação de FFI/backend com a medição que justifica a **não-adoção** — engenharia orientada a evidência.
4. Reconhecer a limitação honesta: Dart não tem ecossistema científico maduro (sem NumPy/SciPy/statsmodels). Os testes estatísticos precisarão ser implementados à mão **ou** exportados em CSV para validação cruzada em Python/R. *Recomendo a validação cruzada:* implementar em Dart e conferir contra `scipy` num notebook anexo à monografia. Isso vira evidência de corretude em vez de limitação.

---

## 2. AUDITORIA DA API E *DATA GAP ANALYSIS*

Todos os endpoints abaixo foram consultados ao vivo em 19/08/2026 com o token do projeto.

### 2.1. Matriz de compatibilidade de dados

| Módulo | Dado necessário | Endpoint / Campo na brapi | Status |
|---|---|---|---|
| **Classificação** | Setor / Indústria | `/v2/stocks/profile` → `sector`, `sectorKey`, `industry`, `industryKey` | **Presente** ⚠ taxonomia própria em PT-BR (ex.: `sector: "Energia"`, `industryKey: "petroleo-e-gas-integrado"`). **Não é GICS nem a classificação setorial oficial da B3** — precisa ser declarado na metodologia |
| **Gráficos & Backtest** | Cotações 5 anos ajustadas | `/v2/stocks/historical?range=10y&interval=1d` → `close`, `adjustedClose`, `volume` | **Presente** ⚠ ver §2.2 — semântica crítica |
| **Extremos** | Máx./Mín. 2 anos | `quote` → `fiftyTwoWeekHigh/Low` cobre só **1 ano** | **Parcial** → derivar de 504 pregões da série histórica (custo: ~0 ms) |
| **CAPM** | Beta (β) | `statistics` → `beta` = 0,3532 (PETR4). `beta3Year` **vazio** | **Parcial** ⚠ janela e índice de referência **não documentados** → calcular localmente |
| **CAPM** | Taxa livre de risco (Rf) | brapi `/v2/prime-rate?country=brazil` (Selic meta diária, 14,25%) · **BCB SGS 11/12/432** | **Presente** (preferir BCB) |
| **CAPM** | Retorno de mercado (Rm) | `/v2/stocks/historical?symbols=^BVSP&range=10y` → 2.490 pregões desde 08/2016 | **Presente** |
| **DCF** | FCFE / FCFF | `/v2/stocks/cash-flow?mode=history` → `operatingCashFlow`, `investmentCashFlow`, **`freeCashFlow`** | **Presente** (16 exercícios, 2010–2025) ⚠ CapEx e D&A não são campos diretos — ver §2.3 |
| **DCF** | Dívida líquida e caixa | `/v2/stocks/balance-sheet?mode=history` → `cash`, `shortTermInvestments`, `shortLongTermDebt`, `longTermDebt`, `loansAndFinancing`, `debentures` | **Presente** (16 exercícios, ~130 campos) |
| **DCF** | Ações em circulação | `statistics` → `sharesOutstanding`, `floatShares`, `impliedSharesOutstanding` | **Presente** |

**Bônus não solicitados, encontrados na auditoria:**
- `/v2/stocks/income-statement?mode=history` — 16 exercícios com `totalRevenue`, `ebit`, **`cleanEbitda`**, **`cleanNopat`**, `incomeTaxExpense`, `incomeBeforeTax`, `earningsPerShare`.
- `statistics` → **`enterpriseToEbitda`** (4,29 p/ PETR4) → viabiliza **valor terminal por múltiplo de saída de EBITDA**, alternativa ao Gordon pedida na §5 da diretiva.
- `statistics` → `lastSplitFactor`, `lastSplitDate` (vazios p/ PETR4, mas o campo existe).

### 2.2. ⚠ ACHADO CRÍTICO: `adjustedClose` é série de retorno total

Medição direta em PETR4, que **não teve desdobramento** no período:

| Data | `close` | `adjustedClose` | razão |
|---|---|---|---|
| 22/08/2016 | 12,35 | **3,1233** | 0,2529 |
| 23/08/2016 | 12,67 | **3,2042** | 0,2529 |
| 17/08/2026 | 42,47 | 42,47 | 1,0000 |

A razão constante de 0,2529 sem split no período prova que o ajuste é **por proventos reinvestidos**, não apenas por eventos societários. A brapi entrega uma série *total return* (padrão Yahoo Finance).

**Três consequências de arquitetura:**

1. **PROIBIDO** usar `adjustedClose` no motor de backtest junto com reinvestimento explícito de dividendos → **dupla contagem**. O motor deve usar `close` + eventos de proventos. *(O código atual usa `close` — está correto nesse ponto.)*
2. ⚠ **Recomendação revista.** Eu havia dito ser "obrigatório" usar `adjustedClose` para benchmark, beta, correlação e volatilidade, por exigirem retorno total. A exigência de retorno total continua valendo, mas **`adjustedClose` não é a forma correta de obtê-lo em ativos brasileiros** (§0.4). O retorno total deve ser construído de `close` + `cashDividends`. Para `^BVSP` a série já é de retorno total por construção do índice, então ali `close` basta.
3. ⛔ **Eu havia proposto `adjustedClose` como oráculo de validação. Testei e não funciona** — a série subajusta proventos brasileiros em até 38,5%. Ver §0.4 para o estudo completo e a estratégia de validação que a substituiu.

### 2.3. Limitações técnicas e quotas

**Rate limiting.** A API **não expõe nenhum cabeçalho** de rate limit (verificado: nenhum `X-RateLimit-*`, `Retry-After` ou equivalente). 12 requisições consecutivas em 2,5 s passaram sem `429`. **O limite é inobservável** → a estratégia precisa ser adaptativa, não baseada em quota declarada:
- **Lote sempre que possível:** `symbols=A,B,C,...` — medido **3.460 ms vs 6.417 ms** (1,85× mais rápido) e consome **1** requisição em vez de 10.
- Semáforo de concorrência (máx. 4–6 simultâneas).
- *Exponential backoff* com *jitter* em `429`/`5xx`.
- Cache local agressivo — série histórica de 10 anos muda uma vez por dia.

**Granularidade dos fundamentos.** ⚠ Todos os `mode=history` retornam **exclusivamente dados anuais** (16 registros, 2010–2025). Testei `type=quarterly` e a resposta continuou anual. Implicação séria para o DCF e para o backtest point-in-time: **não há fundamento trimestral**, então a granularidade máxima de revisão de valuation é anual, com defasagem de publicação. Isso deve constar nas limitações da monografia.

**CapEx e D&A ausentes como campos diretos.** Derivações válidas:
```
D&A            = cleanEbitda − cleanEbit                    (income-statement)
Alíquota efet. = incomeTaxExpense / incomeBeforeTax         (income-statement)
CapEx (proxy)  ≈ |investmentCashFlow|                        (cash-flow) — imperfeito:
                 inclui M&A e aplicações financeiras
FCFF           = operatingCashFlow − CapEx                   ou usar freeCashFlow direto
Dívida líquida = (shortLongTermDebt + longTermDebt) − (cash + shortTermInvestments)
```
**Recomendação:** usar o campo `freeCashFlow` da própria API como base primária e as derivações como validação cruzada, documentando a divergência quando houver.

**Viés de sobrevivência.** `/v2/tickers` lista apenas ativos vivos. Empresas deslistadas não aparecem — o backtest sofre viés de sobrevivência inevitável, que **deve ser declarado**. Mitigação parcial: `/v2/tickers/resolve?symbols=X` (⚠ o código atual usa `symbol=` singular e recebe HTTP 400 — bug já reportado) resolve renomeações.

### 2.4. Plano de contingência (*gap mitigation*)

**a) Beta calculado localmente — recomendo como fonte primária, não como contingência.**
O `beta` da brapi tem janela e índice de referência não documentados, o que é incompatível com reprodutibilidade acadêmica. Calcular localmente custa **0,49 ms** para 10 ativos (medido) — não há razão para não fazer.

$$\beta_i = \frac{\text{Cov}(R_i, R_m)}{\text{Var}(R_m)}$$

com $R_i$ construído pela máquina de retorno total própria (`close` + `cashDividends`, §0.4) e $R_m$ a partir de `^BVSP`, janela de 60 meses ou 252×5 pregões, **declarada explicitamente**. Dado o custo, nem precisa de Isolate — mas fica na camada de domínio pura, testável.

**b) Variáveis macroeconômicas — BCB SGS, sem chave de API (verificado):**

| Série | Endpoint | Uso |
|---|---|---|
| **12** — CDI diário | `api.bcb.gov.br/dados/serie/bcdata.sgs.12/dados?formato=json` | **Rf do CAPM** e taxa livre de risco do Sharpe |
| **11** — Selic diária | `...sgs.11/dados` | Rf alternativo |
| **433** — IPCA mensal | `...sgs.433/dados` | Retorno real |

Retorno verificado: `{"data":"02/01/2024","valor":"0.043739"}` (% ao dia). Preferir BCB à brapi para macro: fonte oficial, sem token, sem rate limit relevante, e citável na monografia.

**c) Prêmio de risco de mercado (Rm − Rf).** Ponto sensível: estimar Rm pela média histórica do IBOV produz valores instáveis e às vezes negativos em janelas ruins, o que quebra o CAPM. **Recomendação:** oferecer três modos, com o (i) como padrão e o modo escolhido registrado junto do resultado:
   1. **Prêmio parametrizado** pelo usuário (padrão: 5–6% a.a. para o Brasil, com citação da literatura — Damodaran).
   2. Média histórica do IBOV sobre janela longa declarada.
   3. Damodaran *country risk premium* embarcado como constante versionada.

**d) Modelagem alternativa de valuation.** Cascata de degradação quando faltarem demonstrativos:
```
1. DCF por FCFF     → exige cash-flow + balance-sheet + shares      (disponível p/ ações líquidas)
2. DCF por LPA      → exige apenas trailingEps + crescimento        (fallback do código atual)
3. Gordon (GGM)     → P = D₁/(Ke − g), exige só dividendos          (ideal p/ elétricas, bancos)
4. Múltiplos        → P/L ou EV/EBITDA setorial                     (último recurso)
```
Regra de engenharia: o modelo aplicado **é parte do resultado**, não um detalhe interno. Cada `DcfValuation` deve carregar qual modelo foi usado e por quê, e a UI deve exibir isso. Silenciosamente cair para um modelo inferior e apresentar como "preço justo" é o tipo de coisa que compromete o trabalho.

> **Nota (obsoleta após o corte de escopo):** FIIs não têm DRE/DFC nesses endpoints, o que tornaria o DCF inaplicável a eles. Com a decisão de **não envolver FIIs**, o problema deixa de existir — e o universo de ativos passa a ser exatamente o domínio onde o DCF por FCFF é válido. O corte de escopo, nesse aspecto, **aumentou a coerência metodológica do trabalho**: todo ativo elegível é avaliável pelo mesmo modelo.

---

## 3. DIAGNÓSTICO ARQUITETURAL E ESTRUTURA DE DIRETÓRIOS

### 3.1. Diagnóstico do estado atual

A base é **MVC nominal, sem camadas reais**. Os sintomas medidos:
- `BacktestEngine` instancia `StockService()` no corpo da classe → domínio acoplado a HTTP, impossível de testar sem rede (é a causa dos 2 testes que falham hoje por dependerem da internet).
- `runBacktest()` tem **940 linhas** num único método, com ~230 linhas duplicadas entre o laço principal e o fallback de Graham.
- Regra de negócio dentro de widget: `home_page.dart:1062-1085` monta o `BacktestConfig` e escolhe o método de valuation dentro de um `onPressed`.
- Nenhuma fronteira impede um widget de chamar a API diretamente.

### 3.2. Decisão estruturante: domínio como pacote Dart puro

A regra "domínio não importa Flutter" só é respeitada se for **impossível violá-la**. Colocando o domínio num pacote sem `flutter` no `pubspec.yaml`, a violação vira **erro de compilação**, não questão de disciplina. É a diferença entre convenção e garantia — e é o que permite o CLI do estudo reusar o motor.

```
equisim/
├── packages/
│   └── equisim_core/                    ← DART PURO (sem Flutter, sem HTTP)
│       ├── lib/
│       │   ├── domain/
│       │   │   ├── entities/            asset, portfolio, valuation, goal, simulation
│       │   │   ├── value_objects/       ticker, money, percent, date_range, weight
│       │   │   ├── repositories/        CONTRATOS (interfaces abstratas)
│       │   │   ├── services/            motor puro e determinístico
│       │   │   │   ├── valuation/       capm, beta, dcf_fcff, gordon, exit_multiple,
│       │   │   │   │                     scenario_engine (discreto + Monte Carlo)
│       │   │   │   ├── backtest/        weighted_series, base100_normalizer
│       │   │   │   ├── metrics/         returns, volatility, drawdown, sharpe,
│       │   │   │   │                     sortino, correlation
│       │   │   │   └── portfolio/       weight_policy, sector_concentration, goal_math
│       │   │   ├── usecases/            orquestração de caso de uso
│       │   │   └── failures/            tipos selados de erro
│       │   └── equisim_core.dart        ← única API pública do pacote
│       └── test/                        ← testes SEM rede, com fixtures
│
├── tools/
│   └── validation_harness/              ← CLI de validação do motor (ver §6, Fase 5)
│       └── bin/validate.dart               (portão de qualidade de proventos, varredura,
│                                            sensibilidade, export CSV p/ conferência)
│
├── lib/                                 ← APP FLUTTER
│   ├── data/
│   │   ├── datasources/
│   │   │   ├── remote/                  brapi_datasource, bcb_datasource
│   │   │   └── local/                   drift_cache_datasource
│   │   ├── dtos/                        espelham o JSON da API (nunca vazam p/ domínio)
│   │   ├── mappers/                     DTO ↔ entidade de domínio
│   │   └── repositories/                IMPLEMENTAÇÕES dos contratos do domínio
│   ├── presentation/
│   │   ├── auth/                        ← LEGADO PRESERVADO
│   │   ├── portfolio/                   dupla carteira + drag-and-drop
│   │   ├── valuation/                   DCF multicenário + upside
│   │   ├── backtest/                    Principal vs Reserva, base 100
│   │   ├── goals/                       planejamento patrimonial (hurdle rate)
│   │   └── shared/                      design system, charts, theme
│   ├── di/                              composition root (Riverpod providers)
│   └── main.dart
│
├── functions/                           ← Cloud Function proxy (custódia do token)
└── test/                                ← testes de widget e integração
```

**Regra de dependência (unidirecional, verificável em CI):**
```
presentation → domain ← data
```
`domain` não conhece ninguém. Sugiro travar isso com `import_lint` ou um teste que falhe se `packages/equisim_core` contiver `package:flutter` ou `package:http`.

---

## 4. MODELAGEM DE DOMÍNIO

### 4.1. Value objects — eliminando bugs por construção

O código atual usa `String` para ticker, `double` para dinheiro e `double` para quantidade de cotas. Os três são fontes de defeito.

```dart
extension type const Ticker(String value) {
  static final _re = RegExp(r'^[A-Z]{4}\d{1,2}$');
  factory Ticker.parse(String raw) {
    final t = raw.trim().toUpperCase();
    if (!_re.hasMatch(t)) throw FormatException('Ticker inválido: $raw');
    return Ticker(t);
  }
  // Sem inferência de classe: o universo é definido por /v2/tickers?type=stock,
  // que já exclui FIIs com interseção zero (verificado). Ver §0.3d.
}

/// Dinheiro em centavos inteiros — elimina erro de ponto flutuante acumulado.
extension type const Money(int cents) {
  factory Money.fromReais(double r) => Money((r * 100).round());
  double get reais => cents / 100.0;
  Money operator +(Money o) => Money(cents + o.cents);
  Money operator -(Money o) => Money(cents - o.cents);
}

/// Peso normalizado [0,1] com tolerância explícita a resíduo de ponto flutuante.
extension type const Weight(double value) {
  static const epsilon = 1e-9;
  static bool sumsToOne(Iterable<Weight> ws) =>
      (ws.fold(0.0, (a, w) => a + w.value) - 1.0).abs() < 1e-6;
}
```

> **Nota sobre quantidade de cotas:** o código atual guarda cotas em `double`. No Escopo B a carteira é definida por **pesos**, não por lotes — o backtest normaliza em base 100 e a alocação é percentual. Portanto `int shares` deixa de ser necessário no domínio; `Weight` é o primitivo. Contagem inteira de ações só reaparece se um dia houver simulação de compra real.

### 4.2. Barreira de look-ahead (papel reduzido no Escopo B)

No plano anterior esta era a defesa nº 1 — o Escopo A fazia replay histórico de decisões e o viés de look-ahead era o defeito mais grave do código. **No Escopo B o valuation é prospectivo (calculado para hoje) e o backtest é apenas retorno ponderado sem decisões**, então o risco praticamente desaparece.

O que resta é legítimo mas modesto: escolher qual demonstrativo anual **já estava publicado** na data de referência, respeitando o `publicationLag` de 90 dias (decisão nº 8). Mantenho o tipo — barato, e evita que alguém use o balanço de 2025 em 15/02/2026, quando ele ainda não foi divulgado.

```dart
/// Visão temporal restrita. Fisicamente incapaz de devolver dado
/// publicado depois de [asOf]. Não há como "esquecer" de filtrar.
final class PointInTimeView {
  final DateTime asOf;
  final Duration publicationLag; // ex.: 90 dias após o fechamento do exercício
  const PointInTimeView(this.asOf, {this.publicationLag = const Duration(days: 90)});

  /// Retorna o último fundamento JÁ PUBLICADO na data [asOf].
  FundamentalsSnapshot? latestPublished(List<FundamentalsSnapshot> all) {
    final cutoff = asOf.subtract(publicationLag);
    final visible = all.where((f) => !f.fiscalPeriodEnd.isAfter(cutoff)).toList()
      ..sort((a, b) => a.fiscalPeriodEnd.compareTo(b.fiscalPeriodEnd));
    return visible.isEmpty ? null : visible.last;
  }
}
```

O motor de simulação recebe apenas `PointInTimeView` — nunca a série completa. O `publicationLag` de 90 dias modela a defasagem real de divulgação à CVM e vira **parâmetro declarado da metodologia**, sujeito a análise de sensibilidade.

### 4.3. Entidades centrais

```dart
// ---------- ATIVO ----------
final class Asset {
  final Ticker ticker;
  final String name;
  final Sector? sector;             // de /v2/stocks/profile
  final String? industry;
}

// ---------- CARTEIRA ----------
final class Portfolio {
  final PortfolioId id;
  final PortfolioKind kind;              // principal | reserva
  final Map<Ticker, PortfolioEntry> entries;

  bool get isEquallyWeighted;
  /// Σw = 100% com tolerância explícita a resíduo de ponto flutuante
  bool get hasValidWeights => Weight.sumsToOne(entries.values.map((e) => e.weight));
  /// Redistribui igualmente: w = 1/N, com o resíduo da divisão
  /// absorvido pela maior posição (evita Σ = 99,99%)
  Portfolio equalize();
  Map<Sector, int> sectorCounts();
  /// Alerta reativo (§3.1 da diretiva) — não bloqueia a operação.
  List<Sector> concentratedSectors({int threshold = 2}) =>
      sectorCounts().entries.where((e) => e.value >= threshold).map((e) => e.key).toList();
  /// Upside ponderado — recalculado a cada frame de arrasto (custo < 0,1 ms)
  double weightedUpside(Map<Ticker, ValuationResult> vs);
}

enum PortfolioKind { principal, reserva }

final class PortfolioEntry {
  final Ticker ticker;
  final Weight weight;              // primitivo da carteira (não há lotes)
  final Sector? sector;             // cacheado p/ concentração sem I/O
}

// ---------- VALUATION ----------
sealed class ValuationResult {
  Money get fairValue;
  Money get marketPrice;
  ValuationModel get model;         // qual modelo foi efetivamente usado
  DateTime get asOf;
  double get upsidePercent => (fairValue.reais - marketPrice.reais) / marketPrice.reais * 100;
}

final class DcfValuation extends ValuationResult {
  final CapmInputs capm;
  final double ke;                  // custo de capital próprio
  final List<double> projectedFcf;
  final TerminalValueMethod terminalMethod;  // gordon | exitMultiple
  final Money terminalValue;
  final Money netDebt;
  final int sharesOutstanding;
  /// Os dois modos coexistem sem retrabalho (decisão nº 7):
  /// discreto → 3 conjuntos fixos de premissas;  estocástico → amostragem.
  final ScenarioMode mode;                 // discrete | monteCarlo
  final Map<ScenarioBand, Money>? discrete; // bear | base | bull
  final ValueDistribution? distribution;    // P5 / P50 / P95 + histograma
}

final class CapmInputs {
  final double riskFreeRate;        // BCB SGS
  final double beta;                // calculado localmente
  final double marketPremium;       // parametrizado, com modo declarado
  final BetaSource betaSource;      // computed | apiProvided — rastreabilidade
  double get costOfEquity => riskFreeRate + beta * marketPremium;
}

// ---------- META PATRIMONIAL ----------
final class FinancialGoal {
  final Money initialContribution;  // V0 — aporte inicial
  final Money monthlyContribution;  // PMT — aporte mensal
  final Duration horizon;           // t
  final Money targetWealth;         // Vf — valor desejado final
  // Ver bloco abaixo: com aporte mensal NAO ha forma fechada para a taxa.
}

// ---------- POLITICA FISCAL ----------
/// Aliquotas parametrizadas por rotulo e vigencia — NAO hardcoded.
/// A tributacao de proventos no Brasil esta em mudanca; fixar 15%/0% no
/// codigo tornaria o trabalho desatualizado por alteracao legislativa.
final class TaxPolicy {
  final List<TaxRule> rules;                    // (label, aliquota, vigencia)
  static final zero = TaxPolicy(rules: []);     // cenario sem tributacao (comparacao)
  static final brasil = TaxPolicy(rules: [      // regime vigente
    TaxRule(label: 'JCP',        rate: 0.15),   // IRRF retido na fonte
    TaxRule(label: 'DIVIDENDO',  rate: 0.00),   // isento (regra vigente)
    TaxRule(label: 'RENDIMENTO', rate: 0.00),   // ver ponto em aberto no 16
  ]);
  Money net(Money gross, String label, DateTime on);
}

// ---------- BACKTEST (Principal vs Reserva) ----------
/// Sem rebalanceamento (decisao no 9). Com aporte inicial + mensal, TWR e XIRR
/// sao ambos necessarios e medem coisas diferentes. Ver §0.3b.
final class BacktestResult {
  final DateRange period;
  final List<DateTime> dates;
  /// Curvas normalizadas em base 100 (comparacao visual de composicao)
  final Float64List principalBase100;
  final Float64List reservaBase100;
  /// Curvas patrimoniais com o plano de aportes (V0 + PMT mensal)
  final Float64List principalWealth;
  final Float64List reservaWealth;
  final List<CashFlow> cashFlows;   // aporte inicial + aportes mensais datados
  final Money grossDividends;
  final Money withheldTax;          // IR retido sobre JCP — exibido separadamente
  final PerformanceMetrics principal;
  final PerformanceMetrics reserva;
}

final class PerformanceMetrics {
  final double accumulatedReturn;
  /// TWR — neutraliza aportes. Metrica correta p/ COMPARAR Principal vs Reserva.
  final double timeWeightedReturn;
  /// XIRR — retorno efetivo do investidor. E o numero confrontado com a meta.
  final double moneyWeightedReturn;
  final double cagr;                // derivado do TWR
  final double volatility;          // anualizada, raiz(252), sobre retornos TWR
  final double maxDrawdown;         // sobre o indice TWR, nao sobre a curva bruta
  final double sharpe;              // vs Rf do BCB no periodo
  final double sortino;
  final double calmar;              // CAGR / |maxDrawdown|
  final double beta;                // vs ^BVSP
  final double netDividendYield;    // proventos liquidos de IR / patrimonio medio
}
```

> ### ✅ Semântica resolvida (decisão nº 9): **sem rebalanceamento**
>
> Os pesos são estipulados na constituição da carteira e **nunca são restaurados**. Cada ativo segue sua própria variação e a carteira é a soma ponderada pelas alocações originais de cada aporte:
>
> $$V_t = \sum_i \left[ \text{(capital alocado em } i\text{)} \times \frac{P_{i,t}}{P_{i,\text{compra}}} \right] + \text{proventos reinvestidos líquidos de IR}$$
>
> Consequência esperada e correta: **os pesos derivam ao longo do tempo**. Ativos que sobem passam a pesar mais. Isso é o comportamento desejado — a UI deve exibir peso-alvo × peso-corrente, porque essa divergência é justamente um dos sinais que motivam a troca de ativos.
>
> Cada aporte mensal é alocado segundo os percentuais estipulados, sem tentar corrigir o desvio acumulado.

> ### ⚠ A rentabilidade requerida **não tem forma fechada** com aporte mensal
>
> No plano anterior a meta era `(Vf/V0)^(1/t) − 1`. **Com PMT ≠ 0 essa fórmula fica incorreta** — ignora todo o capital aportado ao longo do caminho e superestima grosseiramente a rentabilidade necessária. É o mesmo defeito que apontei em §2.2.4 do relatório anterior, agora do lado prospectivo.
>
> A equação correta é o valor futuro de uma série uniforme:
>
> $$V_f = V_0(1+i)^n + \text{PMT} \cdot \frac{(1+i)^n - 1}{i}$$
>
> **Não é possível isolar $i$ algebricamente.** Exige método numérico:
>
> ```dart
> /// Newton-Raphson com bisseção de resguardo.
> /// f(i) = V0(1+i)^n + PMT*[((1+i)^n - 1)/i] - Vf
> /// Casos-limite: i -> 0 (serie aritmetica), PMT = 0 (forma fechada),
> /// Vf <= V0 + n*PMT (meta atingivel sem rentabilidade => i <= 0).
> double solveRequiredMonthlyRate(FinancialGoal g);
> ```
>
> Convergência típica em 4–6 iterações, custo desprezível. **Teste obrigatório:** conferir contra `TAXA`/`RATE` do Excel e `numpy_financial.rate`.

> ### ⚠ *Upside* e rentabilidade requerida estão em **unidades diferentes**
>
> O fluxo da decisão nº 9 — *"com a rentabilidade mensal podemos evidenciar ações com upside maior"* — esbarra num problema de unidade que precisa ser resolvido explicitamente:
>
> - **Upside do DCF** = valorização **total** até o preço justo (ex.: +40%), sem prazo.
> - **Rentabilidade requerida** = taxa **por período** (ex.: 12% a.a.).
>
> Comparar 40% com 12% a.a. não significa nada sem declarar **em quanto tempo** o preço converge ao valor justo. Proposta:
>
> $$r_i^{\text{esp}} = \underbrace{(1 + \text{upside}_i)^{1/H} - 1}_{\text{convergência de preço}} + \underbrace{DY_i^{\text{líq}}}_{\text{provento após IR}} \qquad r^{\text{cart}} = \sum_i w_i \cdot r_i^{\text{esp}}$$
>
> com **H = horizonte de convergência declarado** (sugiro 12–24 meses, configurável). Somar o *dividend yield* líquido é essencial — retorno total é apreciação **mais** provento —, e como o IR sobre JCP já está modelado (decisão nº 12), o DY líquido sai de graça e o conjunto fica coerente.

> **Nota histórica — decisão pendente anterior, agora encerrada:**
> Eu havia proposto implementar duas políticas (buy-and-hold × rebalanceamento periódico) e deixar o usuário escolher. A **decisão nº 9 encerrou a questão**: não há rebalanceamento de espécie alguma. `RebalancePolicy` foi removida do domínio.

### 4.4. Contratos de repositório

```dart
abstract interface class PriceRepository {
  Future<Result<PriceSeries>> daily(Ticker t, DateRange range);
  /// Lote — 1,85× mais rápido e consome 1 requisição (medido)
  Future<Result<Map<Ticker, PriceSeries>>> dailyBatch(List<Ticker> ts, DateRange range);
  /// adjustedClose bruto da API — APENAS conferencia grosseira, nunca calculo (§0.4).
  /// O retorno total de verdade e construido no dominio: close + cashDividends + TaxPolicy.
  Future<Result<PriceSeries>> adjustedCloseRaw(Ticker t, DateRange range);
}

abstract interface class FundamentalsRepository {
  /// Devolve a série COMPLETA; o filtro temporal é do PointInTimeView.
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker t);
  Future<Result<CompanyProfile>> profile(Ticker t);   // setor/indústria
}

abstract interface class MacroRepository {
  Future<Result<RateSeries>> riskFreeDaily(DateRange r); // BCB SGS 12 (CDI) — Rf do CAPM
  Future<Result<RateSeries>> ipcaMonthly(DateRange r);   // BCB SGS 433 — retorno real (opcional)
}

abstract interface class BenchmarkRepository {
  /// ^BVSP — usado para Rm e para o cálculo local de beta
  Future<Result<PriceSeries>> ibovespa(DateRange r);
}
```

> ✅ **IFIX deixou de ser problema.** Era o bloqueio nº 5 da lista de validação; com FIIs fora do escopo, a única série que a brapi não fornece adequadamente saiu do caminho crítico. **Todas as fontes de dados necessárias ao Escopo B estão verificadas e disponíveis.**

### 4.5. UseCases

```dart
final class ComputeDcfValuation {              // DCF + CAPM, discreto ou Monte Carlo
  Future<Result<DcfValuation>> call(Ticker t, DcfAssumptions a, PointInTimeView v);
}
final class ComputeBeta {                      // β local, vs ^BVSP, janela declarada
  Result<BetaEstimate> call(PriceSeries asset, PriceSeries market);
}
final class RunPortfolioBacktest {             // Principal vs Reserva, sem rebalanceamento
  Future<Result<BacktestResult>> call(Portfolio p, Portfolio r, DateRange range,
                                      ContributionPlan plan, TaxPolicy tax);
}
final class SolveRequiredReturn {              // meta: V0 + PMT + t -> Vf (Newton-Raphson)
  Result<RequiredReturn> call(FinancialGoal g);
}
final class AssessGoalFeasibility {            // warning e bloqueio (ponto 9)
  Result<FeasibilityVerdict> call(RequiredReturn r, MarketAnchors a);
}
final class SwapAssetBetweenPortfolios {       // drag-and-drop — SÍNCRONO
  Result<RebalanceOutcome> call(Portfolio principal, Portfolio reserva, Ticker moved);
}
final class EvaluateGoalAlignment {            // hurdle rate
  Result<GoalAlignment> call(Portfolio p, FinancialGoal g, Map<Ticker, ValuationResult> vs);
}
```

`SwapAssetBetweenPortfolios` é síncrono de propósito: recalcula upside ponderado, concentração setorial e aderência à meta em microssegundos (medido em §1.1), então o drag-and-drop atualiza a cada frame sem `Future`, sem debounce e sem estado de carregamento.

### 4.6. Limiares de viabilidade da meta — ancorados em dados, não arbitrários

A decisão nº 9 pede *"warning e bloqueio pra quando for extraordinário"*. Números redondos escolhidos a dedo seriam indefensáveis numa banca. Calculei as âncoras a partir das séries reais (19/08/2026, janela de 10 anos):

| Âncora | Valor | Fonte |
|---|---|---|
| **CDI** (10 anos) | **9,40% a.a.** — acumulado 144,5% | BCB SGS 12, 2.508 pregões |
| **IBOVESPA** (10 anos) | **11,26% a.a.** — 57.781 → 167.830 | `^BVSP` via brapi |

**Faixas propostas** (recalculadas em runtime a partir das séries, nunca hardcoded):

| Faixa | Veredito | Mensagem |
|---|---|---|
| `i < CDI` | ℹ️ **Informativo** | Meta atingível sem risco — renda fixa basta; carteira de ações é desnecessária |
| `CDI ≤ i ≤ IBOV` | ✅ **Plausível** | Dentro do retorno histórico do mercado |
| `IBOV < i ≤ 2×IBOV` | ⚠️ **Aviso** | Exige superar consistentemente o mercado; historicamente pouco frequente |
| `i > 2,5×IBOV` (~28% a.a.) | ⛔ **Bloqueio** | Nenhuma carteira diversificada sustentou isso na janela observada |

Duas vantagens: os limiares se **atualizam sozinhos** conforme o mercado muda, e a mensagem de bloqueio pode citar o número concreto ("28% a.a. supera em 2,5× o retorno histórico do Ibovespa"), o que é muito mais convincente do que um limite mágico. O caso `i < CDI` é o mais negligenciado e o mais útil de todos — é o único que pode poupar o usuário de correr risco à toa.

---

## 5. DECISÕES DE ENGENHARIA

### 5.1. Gerenciamento de estado — **Riverpod**

| Critério | Riverpod | Bloc |
|---|---|---|
| DI sem `BuildContext` | ✓ — funciona no CLI do estudo | ✗ acoplado à árvore de widgets |
| Loading/erro/dado | ✓ `AsyncValue` nativo | Manual (estados por evento) |
| Rebuild granular no drag-and-drop | ✓ `select` por campo | Rebuild do bloco inteiro |
| Simulações parametrizadas | ✓ `family` + `autoDispose` | Instanciação manual |
| Teste sem widget | ✓ `ProviderContainer` puro | `bloc_test` (mais cerimônia) |
| Rastreabilidade de eventos | Menor | ✓ log explícito de eventos |

**Escolha: Riverpod.** O fator decisivo é o mesmo que motiva o pacote de domínio puro: o CLI do estudo precisa injetar as mesmas dependências **sem Flutter**, e o `ProviderContainer` do Riverpod funciona fora da árvore de widgets. Bloc travaria isso.

A vantagem do Bloc (log de eventos auditável) é real, mas o problema de auditoria aqui é de **domínio**, não de UI — resolvido por `SimulationResult.decisions`, que registra cada decisão de alocação com sua justificativa.

### 5.2. Concorrência e Isolates — onde de fato importa

Com base nos números medidos:

| Tarefa | Custo | Isolate? |
|---|---|---|
| Backtest 30 ativos × 10 anos | 0,14 ms | **Não** |
| Recálculo do drag-and-drop | < 0,1 ms | **Não** — síncrono a cada frame |
| Monte Carlo 100k cenários | 17,8 ms | **Sim** — ~1 frame |
| Matriz de correlação 50×50 | 11,9 ms | Limítrofe — sim por segurança |
| **`jsonDecode` de 24.800 cotações** | **centenas de ms** | **Sim — é o gargalo real de CPU** |
| Varredura de validação (centenas de ativos) | ~ms | Só no CLI, com pool de isolates |

```dart
// Padrão para o gargalo real:
final parsed = await Isolate.run(() => _parsePriceSeries(rawJsonString));
```

Medições de custo de Isolate: **spawn 0,176 ms**; captura de 10×1250 doubles **1,98 ms** (custo de cópia). Para payloads grandes, usar `TransferableTypedData` (transferência zero-copy) em vez de deixar o closure capturar a estrutura.

Para o `validation_harness`, usar **pool persistente de isolates** (um por núcleo, comunicação por `SendPort`) em vez de `Isolate.run` por tarefa — evita pagar o spawn centenas de vezes ao varrer o universo de ativos.

### 5.3. Segurança e gestão de segredos

Estado atual (defeitos já reportados): token da brapi em `.env` declarado como **asset** no `pubspec.yaml` → embarcado no bundle; no web, servido publicamente. E `corsproxy.io` recebe o header `Authorization` em toda requisição.

**Correções, em ordem de eficácia:**

1. **`--dart-define-from-file`** em vez de `.env` como asset:
   ```bash
   flutter build apk --dart-define-from-file=config/prod.json
   ```
   ```dart
   static const brapiToken = String.fromEnvironment('BRAPI_TOKEN');
   ```
   ⚠ **Honestidade necessária:** isto **não** protege contra engenharia reversa — a constante fica no binário e é extraível com `strings`. Ganha-se apenas a saída do controle de versão e do bundle web. Afirmar o contrário na monografia seria incorreto.

2. **Única proteção real: custódia no servidor.** Cloud Function que injeta o token e repassa a requisição. O cliente nunca vê o segredo. Resolve simultaneamente o CORS (elimina o `corsproxy.io`) e permite cache central.

3. **`flutter_secure_storage`** para tokens de sessão do usuário (Keychain / Android Keystore).

4. Sanitização de logs — os `debugPrint` atuais imprimem a URL completa; com o token no header não vaza hoje, mas o interceptor deve mascarar credenciais por padrão.

5. `.env.example` versionado + instruções no README (hoje o clone não compila: `.env` é asset obrigatório e está no `.gitignore`).

### 5.4. Camada de rede (Dio) e cache local

**Dio** com a cadeia de interceptors:
```
AuthInterceptor       → injeta credencial (ou aponta p/ o proxy)
ThrottleInterceptor   → semáforo (máx. 4–6 concorrentes)
RetryInterceptor      → backoff exponencial + jitter em 429/5xx
CacheInterceptor      → consulta Drift antes da rede
LogInterceptor        → sanitizado, só em debug
```

**Cache: recomendo Drift, não Hive nem Isar.**

| | Drift (SQLite) | Isar | Hive |
|---|---|---|---|
| Manutenção ativa | ✓ | ⚠ **v3 estagnado, v4 em limbo** | ⚠ v2 parado, fragmentado em forks |
| Consulta por intervalo de datas | ✓ SQL nativo | ✓ índices | ✗ sem query engine |
| Migrações versionadas | ✓ | Parcial | Manual |
| Consulta externa (análise) | ✓ arquivo `.sqlite` abre em qualquer ferramenta | ✗ | ✗ |

Séries temporais são exatamente o caso de uso de SQL (`WHERE ticker = ? AND date BETWEEN ? AND ?`). E o `.sqlite` resultante pode ser aberto em Python/DBeaver para conferir os dados da monografia — vantagem concreta para o TCC. O risco de manutenção do Isar é sério para um projeto que precisa continuar compilando na data da defesa.

**Política de cache por tipo de dado:**

| Dado | TTL | Justificativa |
|---|---|---|
| Cotação histórica (D-1 p/ trás) | **imutável** | fato passado não muda |
| Cotação do dia | 15 min | intradiário |
| Fundamentos (`mode=history`) | 30 dias | atualiza 1×/ano |
| Perfil / setor | 90 dias | quase estático |
| CDI / IPCA | 1 dia | publicação diária |

Com séries históricas imutáveis em cache, a segunda execução de uma simulação cai de 3,4 s para praticamente zero — e, mais importante, **os resultados viram reprodutíveis**, que era o requisito acadêmico pendente.

### 5.5. Recomendações complementares

**a) Valor terminal — apresentar os dois métodos, sempre.**
O Gordon é hipersensível a `(Ke − g)`: com Ke = 11% e g = 4%, um erro de 1 p.p. em g move o valor terminal em ~17%. Como a API fornece `enterpriseToEbitda`, o múltiplo de saída é viável e serve de contraprova:
```
VT_gordon  = FCF_N × (1 + g) / (Ke − g)
VT_múltiplo = EBITDA_N × (EV/EBITDA setorial)
```
Divergência grande entre os dois é sinal diagnóstico de premissa irrealista — e vira uma boa discussão na monografia.

**b) Monte Carlo vs. "Bull/Base/Bear" — os dois modos, sem retrabalho** *(decisão nº 7: apresentar ao orientador)*.
Três cenários discretos são arbitrários (por que exatamente esses?). Com 100.000 cenários custando **17,8 ms** (medido), dá para sortear `g`, `Ke` e `gp` de distribuições declaradas e reportar **P5 / P50 / P95**.

**Como engenheirar a indecisão sem custo:** um único `ScenarioEngine` parametrizado por uma distribuição. O modo discreto é o caso degenerado em que a distribuição tem três pontos de massa (as premissas Bear/Base/Bull); o modo estocástico amostra de distribuições contínuas. **Mesmo caminho de código, mesma saída tipada** (`DcfValuation.mode`). Trocar um pelo outro vira um `enum` na UI, não uma refatoração — então o orientador pode decidir depois da demo sem custo de retrabalho.

**c) Análise de sensibilidade em tornado.** Ranquear qual premissa (g, Ke, margem, perpetuidade) mais move o preço justo. Custo desprezível, alto valor visual e argumentativo.

**d) Matriz de correlação + fronteira risco-retorno.** 11,9 ms para 50 ativos (medido). Dispersão volatilidade × retorno com a carteira plotada contra os ativos individuais demonstra o efeito de diversificação visualmente — argumento forte para a seção de resultados.

**e) Conjunto de métricas.** *(Revisado após a decisão nº 9.)* Com aporte mensal no plano, o conjunto adequado é **TWR, XIRR, retorno acumulado, CAGR, volatilidade, Max Drawdown, Sharpe, Sortino, Calmar, beta e DY líquido**. A regra que vale desde o primeiro relatório continua valendo: volatilidade, drawdown e Sharpe devem ser calculados sobre a **série TWR neutralizada de aportes**, nunca sobre a curva bruta de patrimônio — no dia do aporte a curva bruta salta, e esse salto seria contabilizado como retorno de mercado. *Tracking error* e *information ratio* seguem fora, por exigirem um índice de referência que o Escopo B não define.

**f) Validação cruzada com Python.** Exportar as séries em CSV e conferir Sharpe, beta, volatilidade e o resultado do DCF contra `scipy`/`numpy` num notebook anexo. Converte a ausência de ecossistema científico no Dart em evidência de corretude.

---

## 6. ROADMAP DE IMPLEMENTAÇÃO FASEADO (reformulado — Escopo B)

### 6.0. Estratégia de transição: corte limpo, não *strangler fig*

A tentação natural seria manter o app atual funcionando e migrar por partes. **Recomendo o oposto.** A funcionalidade legada é "1 ação × 1 FII com valuation binário" — ela não é um subconjunto do Escopo B, é um produto diferente que está sendo descontinuado. Manter os dois vivos durante a transição significa dar manutenção a ~4.300 linhas que serão deletadas.

**Preservar:** autenticação, sessão, tema, `app_colors`, `firebase_options`, shell de navegação.
**Descartar em bloco na Fase 0.** O que sobra de valor no legado é a camada de conta e a identidade visual — que é exatamente o que economiza semanas e justifica manter o Flutter (§1.4).

---

### ✅ Fase 0 — Demolição controlada e preparo do terreno — **CONCLUÍDA (19/08/2026)**
> Resultado: **−8.562 linhas / +338 linhas** em 24 arquivos. `flutter analyze` sem
> nenhum aviso (antes: 2), `flutter test` verde, `flutter build web` bem-sucedido.
> Legado congelado na tag git **`legado-escopo-a`** (`99343e5`).

Note que **a maior parte do antigo "estancamento" virou desperdício**: corrigir `symbol=`→`symbols=`, o parsing de `fiis` ou o `TimeoutException` em `stock_service.dart` é remendar código que será deletado na Fase 2. Esses defeitos serão resolvidos por reimplementação, não por patch.

**Removidos:**
- [x] `lib/services/backtest_engine.dart` (989) e `backtest_history_service.dart` (236)
- [x] `lib/views/backtest_results_page.dart` (1.699), `backtest_detail_page.dart` (1.117), `backtest_history_page.dart` (902)
- [x] `lib/controllers/backtest_controller.dart` (99) e `base_controller.dart` (29, morto)
- [x] `lib/models/backtest.dart` (291), `fii.dart`, `corporate_event.dart`
- [x] `lib/utils/financial_calculations.dart` (170, morto)
- [x] `lib/utils/audio_helper*.dart` (4 arquivos) — *decisão nº 13*
- [x] 4 suítes de teste do escopo A (725 linhas), incluindo as 2 que falhavam

**Reduzidos / limpos:**
- [x] `stock_service.dart` — removidos FIIs, eventos societários e a `_stockUnitsWhitelist` defeituosa; `symbol=` → `symbols=` corrigido; `dart:async` importado com prefixo para o timeout ser capturado
- [x] `exceptions.dart` — `TimeoutException` → **`RequestTimeoutException`** (não sombreia mais a do `dart:async`)
- [x] `home_page.dart` (1.721 → 337) — shell com identidade visual, navegação e verificação viva de conectividade
- [x] `home_controller.dart` (364 → 39) — apenas carga do universo de ativos
- [x] `main.dart` — `BacktestController` desregistrado

**Preparo:**
- [x] `.env.example` versionado (o clone não compilava sem `.env`)
- [x] README reescrito: estado do projeto, pré-requisitos, configuração, fontes de dados e limitações
- [x] Legado congelado na tag `legado-escopo-a`
- [x] Coleção `backtests` no Firestore **preservada com suas regras** — os dados legados seguem protegidos até a migração para `portfolios` na Fase 3

**Efeito colateral positivo:** com a remoção de `dart:js`, o `flutter build web` passa a reportar **Wasm dry run bem-sucedido** — `dart:js` é incompatível com compilação para WebAssembly.

**Pendências conscientemente não executadas** (fora do escopo da Fase 0):
- `Firebase.initializeApp()` sem `try/catch` em `main.dart` — será tratado na Fase 3, quando `main.dart` for reestruturado com Riverpod
- Token embarcado via asset `.env` e proxy `corsproxy.io` — Fase 2 (§5.3)
- `test/widget_test.dart` segue placeholder — a suíte real nasce na Fase 1, sem rede e sem Flutter

---

### ✅ Fase 1 — `equisim_core`: domínio puro — **CONCLUÍDA (19/08/2026)**
> **125 testes passando sem rede · cobertura 85,3% (848/994 linhas) · `dart analyze` sem issues.**
> App Flutter segue compilando (`flutter build web` ✓) com o pacote integrado por `path`.

- [x] Pacote Dart puro **sem nenhuma dependência de runtime** + `purity_test.dart` que falha o build se `package:flutter`, `package:http`, `dart:js`, Firebase ou Drift aparecerem no core
- [x] Value objects: `Ticker`, `Money` (centavos inteiros), `Weight` + `Weights` com absorção de resíduo, `DateRange`
- [x] Entidades: `Asset`, `Sector`, `Portfolio`, `PortfolioEntry`, `FinancialGoal`, `ValuationResult`, `FundamentalsSnapshot`, `PriceSeries`, `DividendEvent`
- [x] `PointInTimeView` com `publicationLag = 90 dias`
- [x] Contratos de repositório + `Result<T>` selado com `Ok`/`Err` e falhas tipadas
- [x] **CAPM** `Ke = Rf + β(Rm − Rf)`, prêmio parametrizado 5,5% com `BetaSource`/`MarketPremiumSource` registrados no resultado
- [x] **`TotalReturnEngine`** (`close` + eventos de provento + `TaxPolicy`) — fonte única para backtest, DY, beta e correlação
- [x] **Beta local** com pareamento por data e matriz de correlação
- [x] **DCF por FCFF descontado ao WACC** + `CostOfCapital` completo (ver correção abaixo)
- [x] Valor terminal: **Gordon e múltiplo de saída**, com guarda contra divergência quando `r → g`
- [x] **`ScenarioEngine` unificado** — `DiscreteScenarios` e `StochasticScenarios` pelo mesmo caminho de código, com semente fixa para reprodutibilidade
- [x] **`TaxPolicy`** parametrizada por rótulo **e vigência** — JCP 15%, dividendo isento
- [x] **`PortfolioBacktest` sem rebalanceamento**: aporte inicial + mensais alocados pelos pesos estipulados, proventos apurados na data-ex e reinvestidos líquidos de IR na data de pagamento, desempenho individual por ativo e deriva de peso
- [x] Métricas: **TWR e XIRR**, CAGR, volatilidade, max drawdown, Sharpe, Sortino, Calmar, DY líquido — todas sobre a série TWR
- [x] **`RequiredReturnSolver`** por Newton-Raphson com bisseção de resguardo e casos-limite (`i → 0`, PMT = 0, meta já coberta pelos aportes)
- [x] **`GoalFeasibility`** com limiares derivados de CDI/IBOV em runtime
- [x] `ExpectedReturn` — anualização do upside por horizonte `H` + DY líquido
- [x] `SectorConcentration` — alerta em ≥2, sem bloquear

**Pendência assumida:** a cascata de degradação do valuation (FCFF → LPA → GGM → múltiplos) tem as **quatro peças implementadas e testadas isoladamente** (`DcfCalculator.fcff`, `.earningsPerShare`, `.gordonGrowth` e o múltiplo de saída), mas o **orquestrador que escolhe automaticamente** o modelo conforme os dados disponíveis foi deixado para a Fase 3 — ele depende do repositório de fundamentos real para decidir, e escrevê-lo agora contra fakes seria adivinhar a forma dos dados.

#### ⚠ Correção metodológica aplicada durante a implementação

O plano previa descontar o FCFF ao **Ke** obtido pelo CAPM. **Isso está errado**: FCFF é o fluxo disponível a *todos* os provedores de capital e precisa ser descontado ao **WACC**; o Ke sozinho só é consistente com FCFE. Descontar FCFF ao Ke superestima a taxa e subavalia a empresa — erro clássico e facilmente cobrável em banca.

A auditoria da API já garantia os insumos para fazer certo, e a correção foi implementada:

```
Kd  = interestExpense / totalDebt            (income-statement + balance-sheet)
t   = incomeTaxExpense / incomeBeforeTax     (income-statement)
WACC = E/(E+D)·Ke + D/(E+D)·Kd·(1 − t)
EV  = Σ FCFF/(1+WACC)^t + VT/(1+WACC)^N   →   Equity = EV − dívida líquida
```

`CostOfCapital.unlevered` cobre o caso sem dívida, em que o WACC degenera para o Ke.

#### Testes que ancoram a corretude

| Verificação | Como é ancorada |
|---|---|
| TWR neutraliza aportes | Carteira parada que recebe R$ 10.000 tem retorno **zero**, não +9.900% |
| TWR composto | `[100, 110, 231]` com fluxos `[100, 0, 100]` → exatamente **31%** |
| XIRR | R$ 1.000 → R$ 1.100 em 365 dias → exatamente **10%** |
| Taxa requerida | PMT 100, n 12, alvo 1.268,25 → **1% a.m.** (equivale a `TAXA(12; −100; 0; 1268,25)`) |
| Taxa requerida (ida e volta) | Solução realimentada em `futureValue` reproduz a meta com erro < R$ 0,01 |
| Fórmula ingênua | Teste prova que `(Vf/V0)^(1/n) − 1` daria **mais que o dobro** da taxa correta |
| DCF FCFF | Valor por ação **144,6212** conferido contra cálculo manual passo a passo |
| Camada fiscal | JCP de R$ 1,00 sobre ação de R$ 10 rende **+8,5%**; dividendo igual rende **+10%**; diferença de exatamente **1,5 p.p.** |
| Sem rebalanceamento | 50/50 com um ativo dobrando → pesos derivam para **66,7% / 33,3%** |
| Monte Carlo | Mesma semente reproduz mediana e P95 idênticos |
| Money | Somar R$ 0,10 dez vezes dá **exatamente** R$ 1,00 |

**Critério de saída atingido:** `dart test` verde sem rede ✓ · cobertura 85,3% ≥ 80% ✓ · solver conferido contra `TAXA` do Excel ✓

---

### ✅ Fase 2 — Rede, API e cache — **CONCLUÍDA (19/08/2026)**
> **42 testes no app + 125 no core, todos offline · `flutter analyze` sem issues · `flutter build web` ✓**

- [x] Dio + cadeia de interceptors: auth → throttle (4 concorrentes) → retry com backoff exponencial e *jitter* → log sanitizado
- [x] `BrapiDatasource`: `historical` **em lote**, `statistics`, `income-statement`, `balance-sheet`, `cash-flow`, `profile`, `tickers?type=stock`, `tickers/resolve` *(com `symbols=`, plural)*, `^BVSP`
- [x] `BcbDatasource`: SGS 12 (CDI) e 433 (IPCA), com conversão de `dd/MM/yyyy` e de percentual para fração
- [x] Drift com 6 tabelas + TTL da §5.4 — histórico de pregão encerrado tratado como **imutável**
- [x] DTOs + mapeadores — a irregularidade da API fica confinada em `BrapiJson`; nenhum JSON atravessa para o domínio
- [x] `compute` no `jsonDecode` dos payloads grandes — o gargalo real de CPU (§5.2)
- [x] Cloud Function de custódia do token + `--dart-define-from-file`, com `ApiConfig` resolvendo proxy → define → `.env`
- [x] Cinco implementações de repositório (preços, proventos, fundamentos, benchmark, macro)
- [x] **Higienização de proventos**: duplicata exata descartada por identidade `(data-ex, pagamento, valor, rótulo)`; múltiplas tranches na mesma data-ex preservadas; `payment_date_estimated` propagado até o domínio
- [x] **Portão de qualidade em runtime**: DY calculado × `statistics.dividendYield`, com tolerância de 1 p.p. calibrada pelo arredondamento da fonte
- [x] **11 fixtures** de respostas reais da brapi e do BCB, versionadas — a suíte roda offline e é determinística

#### Achado adicional: a fonte mistura três provedores

O campo `remarks` de ITUB4 (483 eventos) revela a origem de cada registro: **280 vêm de pipeline CSV** e o restante de importações manuais rotuladas `manual:digrin-*` e `manual:twelvedata-*`. Isso **explica a divergência de §0.4**: `cashDividends` é uma consolidação de múltiplas fontes, enquanto o `adjustedClose` vem só do Yahoo. Reforça a decisão de usar `cashDividends` como verdade e manter o portão de qualidade — e é um parágrafo pronto para a seção de limitações da monografia.

#### Custódia do segredo — três modos, com honestidade sobre cada um

| Modo | Onde vive o token | Proteção real |
|---|---|---|
| `.env` como asset *(legado)* | dentro do bundle | **nenhuma** — no alvo web é servido publicamente |
| `--dart-define-from-file` | constante no binário | **parcial** — sai do git e do bundle web, mas é extraível com `strings` |
| **Cloud Function** *(recomendado)* | só no servidor | **efetiva** — o cliente não carrega credencial |

`ApiConfig.resolve()` tenta os três nessa ordem inversa de preferência e **emite alerta** quando cai no `.env`, para a transição não passar despercebida. A função também resolve o CORS do alvo web, eliminando o `corsproxy.io` — que recebia o header `Authorization` de um terceiro não controlado.

#### Testes que ancoram a camada de dados

| Verificação | Como é ancorada |
|---|---|
| Lote | Dois ativos em **uma** requisição, contada pelo adaptador de fixture |
| Cache de preços | Segunda leitura **não** vai à rede; contador permanece em 1 |
| Reprodutibilidade | Após `clearAll()`, a rede é consultada de novo — cache é a única diferença |
| Tranches legítimas | BBAS3 em 11/03/2025: dois JCP distintos sobrevivem, duplicata exata some |
| Fusão de demonstrativos | Um mesmo exercício reúne campos de DRE, DFC e Balanço |
| Modo proxy | Nenhum header `Authorization` é emitido |
| Log | Token em query string vira `token=****` |
| Diagnóstico | Nunca contém o token completo |
| Erros HTTP | 401 → credencial, 404 → dado insuficiente, 429 → limite |
| *Jitter* | Vinte esperas consecutivas não são idênticas |

---

### ✅ Fase 3 — Estado e orquestração — **CONCLUÍDA (19/08/2026)**
> **60 testes no app + 152 no core · cobertura do core 82,4% · `flutter analyze` sem issues · `flutter build web` ✓**

- [x] Riverpod + raiz de composição com providers escritos à mão (sem geração), todos sobrescrevíveis
- [x] Casos de uso: `ValuationCascade`, `PrepareValuationInputs`, `SwapAssetBetweenPortfolios`, `EvaluateGoalAlignment`, `ResolveMarketAnchors`
  - `BuildPortfolio` foi removido na auditoria de código morto: nunca teve
    chamador. A montagem de carteira acontece por `Portfolio.equalWeighted`,
    com a resolução de perfil feita na camada de dados.
- [x] Gestão da dupla carteira: adicionar, remover, equiponderar, pesos customizados com Σ=100%, **teto de 15 ativos**
- [x] `SwapAssetBetweenPortfolios` **síncrono** — sem `Future`, sem *debounce*, sem estado de carregamento
- [x] `ValuationRunner` com limiar de isolate **decidido por medição** (ver abaixo)
- [x] Fluxo da meta: V0 + PMT + t + Vf → taxa requerida → veredito com semáforo, exposto **enquanto o usuário digita**
- [x] Concentração setorial e aderência à meta derivadas reativamente do estado
- [x] Coleção **`portfolios`** com novo schema + `firestore.indexes.json` + regras atualizadas
- [x] `main.dart` com `ProviderScope` e **tratamento da falha de inicialização do Firebase** — a tela cinza silenciosa virou mensagem explicando o que houve

#### A cascata de valuation, pendência da Fase 1, foi implementada

Escolhe o modelo mais exigente que os dados sustentam e **carrega no resultado qual foi usado**, com os avisos acumulados:

```
1. DCF por FCFF   → descontado ao WACC     (fluxo + dívida + ações)
2. DCF sobre LPA  → descontado ao Ke       (só lucro por ação)
3. Gordon         → sobre dividendos       (só proventos)
4. Múltiplos      → EV/EBITDA, depois VPA  (último recurso)
```

Cair em silêncio para um modelo inferior e rotular o número como "preço justo" esconderia do usuário a qualidade real da estimativa — por isso a degradação é sempre visível.

#### `GrowthEstimator`: regressão log-linear, não CAGR ponta a ponta

O CAGR entre o primeiro e o último exercício depende inteiramente de dois pontos; sendo um deles atípico — comum em commodities — o resultado desanda. A inclinação de uma regressão log-linear usa todos os pontos. Somam-se duas salvaguardas: banda de sanidade de −5% a +20% (com o valor bruto registrado no aviso quando limitado) e perpetuidade travada no crescimento da economia, porque uma empresa crescendo acima do PIB para sempre acabaria maior que a economia inteira.

#### Isolate por evidência, não por dogma

O plano previa "Monte Carlo em Isolate". A medição da Fase 0 mostra que **10 mil cenários custam 2,6 ms** — muito abaixo do orçamento de 16,7 ms de um quadro. Abaixo do limiar, a troca de isolate custaria mais (0,18 ms de criação, ~2 ms de cópia) do que o cálculo. `ValuationRunner` roda em linha até 20 mil amostras e só então paga pela isolate. É a mesma disciplina que levou à rejeição do FFI em §1.3.

#### Testes que ancoram a orquestração

| Verificação | Como é ancorada |
|---|---|
| Escolha de modelo | Cada degrau da cascata tem teste que **remove** os dados do degrau acima |
| WACC × Ke | FCFF desconta abaixo do Ke; LPA desconta exatamente ao Ke |
| Barreira temporal | Exercício de 31/12/2025 é recusado em 30/01/2026 |
| `GrowthEstimator` | Série geométrica de 10% devolve **exatamente** 10% |
| Múltiplos | EV 2.400 − dívida líquida 400 ÷ 100 ações = **R$ 20,00** |
| Concentração reativa | Alerta aparece ao promover o segundo ativo do setor e some ao rebaixá-lo |
| Não bloqueio | Três ativos do mesmo setor entram sem erro — concentrar é decisão do investidor |
| Ida e volta | Carteira e meta sobrevivem à serialização; meta em centavos, sem perda |
| Documento corrompido | Entradas inválidas são descartadas sem derrubar a leitura |
| Falha ao salvar | Estado editado é preservado

---

### ✅ Fase 4 — UI, drag-and-drop e gráficos — **CONCLUÍDA (19/08/2026)**
> **72 testes no app + 152 no core · `flutter analyze` sem issues · `flutter build web` ✓**

- [x] Tema legado adaptado ao Riverpod **sem reescrever** as telas de autenticação (ver abaixo)
- [x] Tela de dupla carteira com `Draggable`/`DragTarget` e recálculo instantâneo
- [x] Alerta de concentração setorial, informativo e não bloqueante
- [x] Tela de valuation: preço justo × mercado, upside, **tornado de sensibilidade**, alternador discreto ↔ Monte Carlo
- [x] Tela de metas: V0, PMT, prazo, Vf → taxa mensal e anual, com **semáforo de quatro níveis** e limiares citando CDI e Ibovespa observados
- [x] Desempenho individual por ativo, ordenado por retorno
- [x] **Peso-alvo × peso-corrente** com barra de deriva
- [x] Painel de proventos: bruto, IR retido e líquido reinvestido, separados
- [x] **`fl_chart`**: comparação base 100, dispersão risco×retorno, mapa de calor de correlação; tornado em `CustomPaint` por ser forma específica
- [x] Exportação CSV para a área de transferência

#### Tema: instância única, duas árvores de estado

O `ThemeController` legado continua `ChangeNotifier` e continua servindo às seis telas de autenticação em Provider. A **mesma instância** é injetada nas duas árvores em `main.dart`, e um `_ThemeSync` espelha seu estado no provider observado pelas telas novas.

A alternativa seria converter ~3.200 linhas de telas legadas para `ConsumerWidget` só para ler um booleano. Preservá-las intactas mantém o risco onde ele deve estar: no código novo, não no que já funciona.

#### Decisões de interface que carregam método

| Decisão | Porquê |
|---|---|
| Arrastar-e-soltar **sem estado de carregamento** | O recálculo custa microssegundos; `Future` e *debounce* seriam cerimônia sem função |
| Alerta setorial **não bloqueia** | Concentrar pode ser decisão consciente; o sistema torna visível, não decide |
| Ressalvas do valuation exibidas na tela | A queda de modelo (FCFF → LPA → Gordon → múltiplos) é informação sobre a **qualidade** da estimativa |
| Interruptor "aplicar IR sobre JCP" | Rodar com e sem torna o custo fiscal do período mensurável, em vez de diluído |
| Deriva de peso com barra de progresso | O desvio do alvo é o sinal que motiva a troca de ativo — não um defeito a corrigir |
| CSV com `;` e vírgula decimal | É o que o Excel em português abre sem diálogo de importação |
| CSV para a área de transferência | Única via que funciona em todas as plataformas do projeto, web incluída |

#### Renomeação feita durante a fase

`ComparisonResult` colidia com o tipo homônimo do `flutter_test`, quebrando qualquer teste que importasse os dois. Renomeado para **`PortfolioComparison`** — nome que também descreve melhor o que a classe contém.

#### Testes de interface

| Verificação | Como é ancorada |
|---|---|
| Arrastar-e-soltar | Gesto real de arraste move o ativo entre as carteiras |
| Equiponderação visível | Dois ativos exibem **50,00%** cada |
| Alerta setorial | Aparece no segundo ativo do setor **e o ativo entra mesmo assim** |
| Tema | Ambos os modos renderizam sem exceção |
| CSV | Cabeçalho e separadores conferidos |

---

### ✅ Fase 5 — Validação e evidência acadêmica — **CONCLUÍDA (20/08/2026)**
> **224 testes · cobertura 82,6% no núcleo · 15 invariantes aprovadas · 80/80 na conferência em Python**

#### A camada de dados ficou livre de Flutter

Para o executor reusar **exatamente** o mesmo código do aplicativo — e não uma
reimplementação que poderia divergir em silêncio —, três dependências de
Flutter saíram de `lib/data`:

| Antes | Depois |
|---|---|
| `compute` no `jsonDecode` | `HeavyJsonDecoder` injetável |
| `debugPrint` / `kDebugMode` | `LogSink` injetável |
| `drift_flutter` no schema | executor injetado por quem constrói |

O aplicativo injeta as versões de Flutter; o executor injeta as de linha de
comando. `dart run tool/validate.dart` carrega datasources, mapeadores e
repositórios idênticos aos que rodam em produção.

#### A conferência cruzada encontrou um defeito real

Foi exatamente para isto que ela existe. Na primeira execução, **51 de 80**
comparações passaram. As falhas se dividiam em duas causas distintas:

**Defeito no motor — semidesvio de Sortino.** A implementação dividia a soma
dos quadrados por `(negativos − 1)` e media desvios a partir da média dos
negativos. A definição de Sortino e Satchell divide pelo **total** de
observações e mede a partir do alvo. O erro chegava a **32%** e distorcia a
ordenação entre ativos: penalizava demais séries que caem pouco e raramente.
Corrigido em `risk_metrics.dart`.

**Divergência de especificação — pareamento do beta.** O motor calcula retornos
entre datas em que **ambas** as séries negociaram; o script conferia retornos
calculados em calendários próprios e depois pareados. Quando um ativo não
negocia num dia, seu retorno seguinte cobre dois dias enquanto o do mercado
cobre um — o beta resultante mistura co-movimento com ruído de calendário. A
convenção do motor é a correta; o script foi alinhado a ela.

Após as duas correções: **80 de 80 dentro de 1e-4**.

#### O oráculo previsto foi substituído por invariantes

O plano original validaria o motor contra o `adjustedClose`. A auditoria já
havia mostrado que aquela série é inconsistente; esta fase **mediu o fenômeno
em escala**: desvio mediano de 9,1%, máximo de 38,5%, seis de onze ativos acima
de 5%.

No lugar entraram **15 invariantes matemáticas** que não dependem de fonte
externa alguma. As mais fortes ligam caminhos de código independentes:

- carteira de ativo único ≡ motor de retorno total (diferença < 1e-9)
- aporte único ⇒ XIRR ≡ CAGR
- Σ valores por ativo ≡ patrimônio da carteira
- tributação reduz o resultado exatamente pelo IR retido
- aporte não vira retorno
- taxa requerida reproduz a meta na ida e volta

Uma falha aqui é prova de defeito, não indício.

#### Sobre a causa da divergência, os dados não fecham

O grupo com maioria de JCP desvia mais na média (11,2% contra 7,7%), mas a
correlação entre proporção de JCP e desvio é de apenas **0,19**, com
contraexemplos nos dois sentidos: PETR4 tem 38% de JCP e desvia 2,1%; EGIE3 tem
31% e desvia 21,0%.

O relatório foi ajustado para relatar **a divergência como fato medido e a
explicação por JCP como hipótese plausível não confirmada** — a versão inicial
afirmava com mais confiança do que a amostra sustenta. A decisão de arquitetura
não depende de resolver a causa.

#### Entregas

| Arquivo | Conteúdo |
|---|---|
| `tool/validate.dart` | Executor com cinco comandos e cache em arquivo |
| `docs/validacao/invariantes.md` | 15 identidades verificadas |
| `docs/validacao/qualidade_proventos.md` | 11/11 consistentes, desvio mediano 0,39 p.p. |
| `docs/validacao/divergencia_adjusted_close.md` | Divergência medida com análise de causa |
| `docs/validacao/sensibilidade.md` | Três eixos de premissa |
| `docs/validacao/cross_validation.py` | Recálculo independente em `pandas`/`numpy` |
| `docs/validacao/conferencia_python.md` | 80/80 dentro de 1e-4 |
| `docs/validacao/limitacoes.md` | 20 limitações catalogadas com efeito e remédio |

---

### Escopo original da fase, para referência
> **Depende de: Fases 1–2. Peso: médio.**

Com o experimento empírico fora, **muda a natureza da evidência do TCC**. Antes, a contribuição seria um achado ("a estratégia supera/não supera o benchmark"). Agora é a **construção verificável**. Isso não é um downgrade — mas exige que a corretude seja *demonstrada*, não afirmada. Esta fase é o que substitui o capítulo de resultados.

- [ ] `tools/validation_harness` reusando `equisim_core` (era `study_runner`)
- [ ] **Portão de qualidade de proventos** (§0.4, Teste 2): varrer o universo comparando o DY calculado de `cashDividends` contra `statistics.dividendYield`; reportar distribuição do desvio e listar os tickers fora de tolerância. Substitui o oráculo `adjustedClose` descartado.
- [ ] **Conferência manual de amostra** (~10 eventos) contra "Aviso aos Acionistas" de RI — confirma ou reverte a premissa de base bruta (ponto nº 18, decidido como premissa declarada)
- [ ] Quantificar o desvio `cashDividends` × `adjustedClose` no universo, para documentar a limitação do Yahoo com JCP
- [ ] Validação de `solveRequiredMonthlyRate` contra `TAXA` (Excel) e `numpy_financial.rate`
- [ ] **Validação cruzada em Python:** exportar séries em CSV e conferir beta, Sharpe, volatilidade e DCF contra `scipy` / `numpy_financial` em notebook anexo à monografia
- [ ] Análise de sensibilidade do DCF (tornado) e do `publicationLag`
- [ ] Relatório de cobertura de testes
- [ ] Seção de limitações: viés de sobrevivência (`/v2/tickers` só lista ativos vivos), **granularidade anual dos fundamentos**, CapEx aproximado por `investmentCashFlow`, taxonomia setorial própria da brapi (não GICS/B3), **subajuste de proventos no `adjustedClose` do Yahoo** (§0.4), datas de pagamento estimadas em parte da base, base bruta do `rate` como premissa declarada (ponto nº 18)

---

### 6.6. Caminho crítico e paralelização

```
Fase 0 ──► Fase 1 (core) ──┬──► Fase 3 ──► Fase 4
                           │
           Fase 2 (dados) ─┘
                           └──► Fase 5 (validação)
```

- **Caminho crítico:** 0 → 1 → 3 → 4. É o que define o prazo.
- A **Fase 2 paralelíza com a Fase 1** assim que os contratos de repositório estiverem definidos (primeira semana da Fase 1) — a Fase 1 usa fakes e não espera a rede.
- A **Fase 5 começa junto com a Fase 2**: o portão de qualidade de proventos só precisa do core e dos datasources de preço e dividendos.
- A Fase 4 é a maior em esforço de UI, mas a de menor risco técnico — todo o risco está concentrado nas Fases 1 e 2.

**Recomendação de sequenciamento:** priorize entregar uma **vertical fina** ao fim da Fase 3 — um ativo, valuation DCF, exibido numa tela — antes de expandir horizontalmente. Isso valida a arquitetura inteira ponta a ponta cedo, e dá algo demonstrável ao orientador antes da Fase 4.

---

## PONTOS EM ABERTO

### Resolvidos (9–13)

| # | Questão | Decisão |
|---|---|---|
| 9 | Política de rebalanceamento | **Nenhuma.** Pesos estipulados, sem restauração; pesos derivam. Carteira definida por V0 + PMT + t + Vf, com taxa requerida calculada |
| 10 | Coleção `backtests` no Firestore | **Migrar para `portfolios`** |
| 11 | Máximo de ativos por carteira | **15** |
| 12 | IR sobre JCP | **Modelar** — 15% retido na fonte |
| 13 | Feedback sonoro (`audio_helper`) | **Remover sem substituto** |

### Resolvidos (14–17)

| # | Questão | Decisão |
|---|---|---|
| 14 | Horizonte de convergência `H` do upside | **12 meses**, configurável e declarado no resultado |
| 15 | Backtest com ou sem plano de aportes | **Ambos** — TWR compara composições; XIRR responde "eu bateria a meta?" |
| 16 | Tratamento fiscal de `RENDIMENTO` | **Isento**, como dividendo |
| 17 | Regime tributário / métricas de provento | **Usar o que a API fornece**: `label` para classificação e `statistics.dividendYield` como portão de qualidade. Alíquota permanece parâmetro declarado (`TaxPolicy`), porque a API não a carrega — ver §0.4 |

### Último ponto, agora decidido

| # | Questão | Recomendação | Bloqueia |
|---|---|---|---|
### Ponto 18 — resolvido como premissa declarada (20/08/2026)

| # | Questão | Decisão |
|---|---|---|
| **18** | O campo `rate` é bruto ou líquido? A API não informa e não há campo que permita deduzir | **Base bruta**, por ser a convenção de divulgação da B3/CVM |

A decisão foi implementada como **parâmetro explícito**, não como aritmética
implícita: `DividendBasis.gross` na `TaxPolicy`. Três consequências:

1. A premissa aparece no tipo, e não escondida numa multiplicação — quem lê o
   código sabe que existe uma escolha ali.
2. Reverter é trocar `TaxPolicy.brasil` por `TaxPolicy.brasilBaseLiquida`. Em
   base líquida o imposto passa a ser deduzido por reversão
   (`valor × taxa / (1 − taxa)`), sem tocar em nenhum cálculo.
3. O comportamento das duas bases está coberto por testes, então a reversão é
   verificável e não um salto de fé.

**A conferência documental continua pendente** — ~10 eventos contra o "Aviso
aos Acionistas" de RI. Até lá, isto é premissa a declarar na monografia, não
fato verificado. Sob base bruta, R$ 1,00 de JCP rende R$ 0,85; se a fonte já
informasse líquido, os proventos estariam subestimados em 15%.

**Todas as decisões estruturais estão fechadas.** O ponto 18 é conferência documental, não decisão de arquitetura — pode correr em paralelo ao desenvolvimento, e o `TaxPolicy` parametrizado absorve qualquer que seja o resultado sem retrabalho.

O plano está completo e validado. **Pronto para iniciar a Fase 0 (demolição controlada) e a Fase 1 (`equisim_core`) quando você autorizar.**

---

### Anexo — Reprodutibilidade das medições

Benchmark: `dart compile exe`, Windows x64, Dart 3.12.2 AOT, com acumulador-guarda contra eliminação de código morto (valores de checksum não-nulos confirmados em todas as execuções). Medições de rede: token do projeto, 19/08/2026, conexão residencial — devem ser tratadas como ordem de grandeza, não como valor absoluto. Endpoints da brapi e do BCB verificados individualmente na mesma data.

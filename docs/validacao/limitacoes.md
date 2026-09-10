# Limitações do trabalho

Documento de referência para a seção de limitações da monografia. Cada item
traz o que foi observado, o efeito prático e o que seria necessário para
resolver.

---

## 1. Fonte de dados

### 1.1. Granularidade dos fundamentos é apenas anual

A brapi entrega **16 exercícios anuais** (2010–2025) nos quatro demonstrativos.
Testado: `mode=history&type=quarterly` devolve dados anuais do mesmo jeito.

**Efeito.** A avaliação não pode ser revista trimestralmente. Entre a
divulgação de um exercício e a do seguinte, o preço justo permanece congelado
enquanto o preço de mercado se move — o *upside* muda por variação de preço,
não por revisão de fundamento.

**Para resolver.** Fonte com dados trimestrais (CVM, B3 ou provedor pago).

### 1.2. `adjustedClose` diverge de forma material

Medido sobre 11 ativos em janela de 10 anos: **desvio mediano de 9,1%** entre o
fator de ajuste implícito no fluxo de proventos publicado pela fonte e a razão
`adjustedClose/close` observada. Máximo de 38,5% (BBAS3). Seis dos onze ativos
acima de 5%. A medição é de 20/08/2026, quando o fluxo de proventos ainda
estava no projeto.

**Efeito.** A série de retorno total da fonte é inutilizável para cálculo. Todo
cálculo do sistema parte de `close`, que a fonte ajusta apenas por
desdobramento e grupamento.

**Sobre a causa.** Ativos com maioria de JCP desviam mais na média (11,2%
contra 7,7%), mas a correlação entre proporção de JCP e desvio é de apenas
**0,19**, e há contraexemplos nos dois sentidos — PETR4 tem 38% de JCP e desvia
2,1%; EGIE3 tem 31% e desvia 21,0%. **A divergência é fato medido; a explicação
pelo tratamento de JCP é hipótese plausível não confirmada.**

### 1.3. Viés de sobrevivência

`/v2/tickers?type=stock` lista **781 ações vivas**. Empresas deslistadas não
aparecem.

**Efeito.** Qualquer análise histórica sobre o universo herda viés de
sobrevivência. O sistema mitiga parcialmente resolvendo renomeações
(`/v2/tickers/resolve`), mas não recupera deslistagens.

### 1.4. Limite de requisições inobservável

A API **não expõe nenhum cabeçalho de rate limit** — verificado: nenhum
`X-RateLimit-*`, nenhum `Retry-After`.

**Mitigação adotada.** Concorrência contida na origem (4 simultâneas), busca em
lote sempre que possível, espera exponencial com ruído em caso de `429`, e
cache agressivo.

### 1.5. Taxonomia setorial própria

O campo `sector` usa taxonomia da brapi em português (`energia`,
`petroleo-e-gas-integrado`). **Não é GICS nem a classificação setorial oficial
da B3.**

**Efeito.** O alerta de concentração setorial depende dessa classificação. Uma
taxonomia diferente produziria agrupamentos diferentes.

### 1.6. IFIX indisponível

`historical?symbols=IFIX` devolve **um único ponto**. Sem consequência para
este trabalho, já que fundos imobiliários estão fora do escopo — mas registrado
porque foi levantado na auditoria.

### 1.7. Duas contagens de ações, que divergem em 14% dos ativos

A fonte publica uma contagem **corrente** e uma **do exercício**. Medido em
07/09/2026 sobre 334 ativos com as duas preenchidas: **47 divergem** além de
1,5×, e a divergência chega a **4.868×** — o MILS3 vem com 48.172 ações
correntes contra 234.178.210 do exercício.

**Efeito.** A ponte de equity divide o valor da firma pela contagem. Com a
corrente crua, o MILS3 saía com preço justo de R$ 37.708,72 contra R$ 15,79 de
mercado. O mesmo campo alimenta o lucro por unidade negociada e o peso do equity
no WACC.

**Mitigação implementada.** A contagem é conciliada com o lucro por ação
publicado, por `N = lucro ÷ LPA`. Nos 38 divergentes com LPA utilizável, o
árbitro confirmou a contagem do exercício em 34 e a corrente em nenhum.

**O que sobra.** A contagem do exercício tem a idade do último encerramento.
Grupamento ou desdobramento posterior a ele não aparece nela, e o preço já o
reflete.

### 1.8. O universo devolvido é parcial

`/v2/tickers?type=stock&limit=1000` devolveu **373 ações** em 07/09/2026, contra
as 781 registradas em medição anterior. A causa não foi isolada — teto do plano
ou mudança da fonte.

**Efeito.** A cobertura da validação fora da amostra é do que a fonte devolve no
dia, e não do universo da B3. Números de cobertura entre execuções só são
comparáveis se o tamanho do universo for igual.

---

## 2. Modelagem

### 2.1. CapEx aproximado

A fonte não entrega CapEx isolado. O sistema usa `investmentCashFlow` como
aproximação, que **inclui fusões, aquisições e aplicações financeiras**, não só
imobilizado.

**Mitigação.** O reinvestimento **não passa mais por aqui.** A soma que ele pede
— `CapEx − Depreciação + ΔNKG` — é, por identidade de balanço, a variação do
capital investido, que se obtém do próprio balanço sem o CapEx isolado. Medido,
as duas rotas concordam dentro de 3 p.p. em 7 de 9 ativos. O `investmentCashFlow`
segue impróprio para conta de reinvestimento: contra `Δ(imobilizado) + D&A` ele
erra por fatores de 0,25× a 2,42×, e para os dois lados.

### 2.2. Prêmio de risco de mercado é parâmetro, não observação

O CAPM usa prêmio parametrizado (padrão 5,5%). Estimá-lo pela média histórica
do Ibovespa produz valores instáveis e às vezes negativos em janelas ruins, o
que quebraria o modelo.

**Efeito.** A avaliação depende de uma escolha metodológica declarada. A
[análise de sensibilidade](sensibilidade.md) quantifica o impacto.

### 2.3. Defasagem de publicação é premissa

Assume-se que um exercício se torna público **90 dias** após o encerramento.
É aproximação: a divulgação real varia por empresa.

**Efeito.** Medido na análise de sensibilidade, variando de 0 a 365 dias.

### 2.4. Beta com índice de referência único

O beta é calculado contra o Ibovespa. O beta publicado pela fonte foi
descartado de propósito: sua janela e seu índice de referência não são
documentados, o que é incompatível com reprodutibilidade.

### 2.5. Backtest sem custos de transação

O motor não modela corretagem, emolumentos nem *spread* de compra e venda.

**Efeito.** Os retornos simulados são otimistas em relação ao que o investidor
obteria. Como o modelo **não rebalanceia**, o número de operações é baixo — o
aporte inicial mais um por mês —, o que limita a distorção.

### 2.6. Caixa parado entre aportes

Desde a [decisão 23](../decisoes/023-remocao-de-proventos.md), a simulação
compra **ações inteiras**: a fatia de cada aporte que não completa mais uma
ação fica em caixa, sem render, até o aporte seguinte.

**Efeito.** É o comportamento da corretora, e não uma aproximação — mas o caixa
real ficaria em conta remunerada ou no CDI, e aqui não rende nada. Numa carteira
de papel caro diante de um aporte pequeno, isso subestima levemente o
patrimônio. O saldo é exibido na tela, e não fica implícito.

### 2.7. Nenhum provento é modelado

O retorno apurado é de **preço**. Dividendo, JCP e a tributação deles saíram do
projeto pela [decisão 23](../decisoes/023-remocao-de-proventos.md), depois de a
premissa de base bruta do campo `rate` permanecer sem conferência documental.

**Efeito.** O resultado é conservador por construção: o acionista que recebe
provento obtém mais que o simulado. Um papel de *dividend yield* alto é
sistematicamente subestimado em relação a um de yield baixo com a mesma
valorização — o que importa quando duas carteiras são comparadas.

**Efeito colateral na comparação com o índice.** O Ibovespa é de retorno total
por construção; o `close` dos ativos não. Beta e correlação misturam as duas
convenções. O efeito é de segunda ordem, porque essas medidas olham
covariância de variações e não nível.

### 2.8. O terminal neutro comprime o valor — mas não é ele que desloca o nível

> **Correção de 09/09/2026.** Esta seção atribuía ao terminal neutro o
> deslocamento do nível do potencial. O [DCF reverso](dcf_reverso.md) mediu, e
> **não é ele**: o retorno terminal é *inatingível* em 73 dos 122 avaliados —
> nem 200% ao ano perpétuo alcança o preço de mercado — e não é explicação
> exclusiva em ativo nenhum, contra 56 ativos em que o nível da curva de
> desconto resolve e o terminal não. O que se lê abaixo continua verdadeiro
> como **mecanismo**: o múltiplo terminal cai de `1/(r − g_∞)` para `1/r`, e
> isso comprime. O que deixou de se sustentar é a atribuição do nível
> observado a ele. Ver a [decisão 35](../decisoes/035-dcf-reverso-e-regressao-condicional.md).


A [decisão 25](../decisoes/025-reconstrucao-do-motor-de-avaliacao.md) adotou
`ROIC_∞ = WACC` e `ROE_∞ = Ke`: nenhuma empresa preserva retorno excedente na
perpetuidade. O terminal vira `NOPAT/WACC`, imune a `g_∞` — que era o defeito
que motivou a decisão.

**Efeito, medido.** O múltiplo terminal passa de `1/(r − g_∞)` para `1/r`. A um
desconto ilustrativo de 15% com `g_∞ = 6,86%`, isso é **6,7× contra 12,3×**, e o
terminal carrega a maior parte do valor.

**Parcialmente compensado em 07/09/2026** pela estrutura a termo do desconto
(ver [2.9](#29-a-estrutura-a-termo-é-linear-e-de-dois-pontos-não-uma-curva-observada))
e pela exceção de vantagem competitiva residual. A mediana do potencial passou de
**−55,1% para −39,4%**, e a fração com potencial positivo de 10,9% para **15,8%**.

**A compressão não desapareceu.** Em 07/09/2026 a mediana estava em −38,0% e o
p75 em −7,5%, sobre 121 avaliados. Se o deslocamento remanescente é comum a todos
os ativos, a **ordenação** relativa continua informativa e o **nível** não deve
ser lido como preço-alvo.

**A escolha entre nível e ordem foi feita, e é assimétrica.** Pela
[decisão 27](../decisoes/027-recalibragem-apos-a-primeira-validacao.md), o preço
justo do ativo individual continua sendo o do DCF, com o nível intacto; o que
deixou de usar o nível é o retorno esperado **da carteira**, que passou a ser
`E[R_i] = CDI_spot + z(potencial) · prêmio`. Pelo caminho antigo, 97 dos 121
avaliados entravam numa otimização de média-variância com retorno esperado
negativo. **A limitação continua existindo onde sempre esteve** — no nível do
potencial —; o que mudou é que ela não se propaga mais para a meta.

**Isso troca uma limitação por outra, e a nova precisa ser lida junto.** O
retorno esperado da carteira deixou de ser uma previsão de rentabilidade e virou
uma afirmação de posição relativa: o ativo mediano da seção recebe o CDI por
construção. Uma seção estreita — a carteira medida contra ela mesma — centra tudo
no CDI e não informa nada. O resultado carrega o tamanho da seção junto, e é
contra a seção dos avaliados que a leitura faz sentido.

**A exceção de *moat* ativa em 7 dos 121 avaliados** (ABEV3, BBSE3, EGIE3,
LEVE3, SAUD3, VBBR3 e WEGE3), contra 2 antes da recalibragem. O passo é
instrumentado desde 07/09/2026, e a
[decisão 28](../decisoes/028-travas-de-ciclo-saturacao-e-saude.md) usou a medição
para elevar o corte de capital externo a `Φ ≤ 0,60` — que admitiu a EGIE3 — e
para acrescentar um filtro de saúde operacional, que reprova quem teve lucro ou
EBITDA caindo mais de 50% no triênio. Foi ele que tirou a QUAL3 (queda de 83,2%)
e a KEPL3 (59,1%). Ver §14.3 do [refinamento](../refinamento-do-valuation.md).

**O ITUB4 não entra na exceção por falta de dado, não por calibragem.** A fonte
não publica `netIncome` para ele em nenhum dos dezesseis exercícios; sem lucro
não há série de retorno, sem retorno não há mediana de ciclo, e sem ela o *moat*
não tem excedente a preservar. A avaliação sai pelo LPA publicado, com o freio de
reinvestimento desligado — o que o resultado declara. É lacuna de cobertura, e
nenhum parâmetro a resolve.

**O fator de normalização da base é saturado em `[0,33; 3,00]`, e o limite é de
política.** Sem teto, `f = ciclo / atual` explode quando o exercício corrente tem
retorno próximo de zero, e o DCF é homogêneo de grau 1 no fluxo-base: a MBRF3
chegou a receber 21,4x e sair a +406,1% de potencial. Não há teste que diga onde
um exercício deixa de ser atípico — a §2 da
[normalizacao_fluxo_base.md](normalizacao_fluxo_base.md) já mostrava isso para
`τ`. O que a banda afirma é **quanta autoridade um único exercício tem sobre a
avaliação inteira**. Quatorze ativos foram confinados na consolidação de
07/09/2026, onze no teto e três no piso; o preço justo deles é conservador por
essa escolha, e o aviso traz o fator bruto que teria sido aplicado.

**O maior potencial do universo continua sendo o da QUAL3, em +477,3%.** O filtro
de saúde retirou dela a vantagem residual e **não** tocou na avaliação: o número
sai da mediana de ROIC de oito anos, que ainda carrega os exercícios anteriores à
queda. Levar o sinal de deterioração também para a Porta 0 ou para a janela do
ciclo é pergunta aberta, registrada na §14.6.

### 2.9. A estrutura a termo é linear e de dois pontos, não uma curva observada

Até 07/09/2026 a taxa livre de risco do CAPM era o **CDI corrente** para todos os
períodos, inclusive a perpetuidade — um indexador *overnight* precificando fluxo
perpétuo. Num pico de ciclo monetário isso esmagava o valor terminal; num vale, o
inflava.

**O que passou a valer.** A taxa decai linearmente do CDI corrente ao CDI médio
decenal ao longo dos dez anos de projeção, e a perpetuidade é descontada à taxa
de equilíbrio. Como `Ke` e `WACC` são afins na taxa livre de risco, decair o
custo de capital equivale a decair a taxa e remontar o custo a cada ano. O fator
de desconto **acumula** as taxas ano a ano.

**A limitação que sobra, e não é pequena.** Isto não é uma curva de juros: é uma
interpolação entre dois pontos, ambos medidos do CDI. Não vem da estrutura a
termo negociada, não tem vértices, e a forma do decaimento — linear — é escolha,
não observação. O CDI médio decenal é uma média histórica usada como **proxy** de
taxa de equilíbrio, e ela não é uma previsão.

**Para resolver.** Curva da ANBIMA ou do Tesouro (NTN-B), com desconto por
vértice.

### 2.10. As primitivas estatísticas do núcleo, e sua conferência externa

O [`cross_validation.py`](cross_validation.py) existe porque o Dart não tem NumPy
nem SciPy: ele recalcula as métricas em Python e reporta a diferença. Ele cobre
volatilidade, *drawdown*, CAGR, beta, correlação, semidesvio e Sortino.

**Não cobre `inference.dart`**, introduzido pela decisão 25 — OLS, erro-padrão
Newey-West com núcleo de Bartlett, quantil da t de Student e R² crítico, todos
escritos à mão.

**Resolvido em 07/09/2026.** `tool/validation/inference_export.dart` gera séries
sintéticas determinísticas, roda as primitivas e grava os dados **junto** dos
resultados; `inference_cross_validation.py` recalcula com `statsmodels` e
`scipy.stats` sobre os mesmos números. Nenhum gerador pseudoaleatório é
compartilhado entre os dois lados — se cada um gerasse a própria amostra, a
comparação dependeria de duas sequências coincidirem.

**Resultado: 99 de 99 comparações dentro da tolerância**, incluindo as seis do
erro-padrão HAC, que concordam com o `statsmodels` na ordem de `1e-14` relativo.
Ver [conferencia_inferencia.md](conferencia_inferencia.md).

**O que sobra.** A tolerância dos quantis da t é de `1e-5`, não de igualdade em
ponto flutuante: o núcleo os obtém por bisseção sobre a beta incompleta, e o que
se confere é concordância dentro do erro do método.

### 2.11. Sem imposto de espécie alguma

Não há IRRF sobre provento — não há provento —, e ganho de capital na venda
também não é modelado. O segundo é coerente com uma estratégia sem
rebalanceamento, em que não há venda, mas a limitação existe se o usuário
interpretar o resultado como líquido de tributos.

### 2.12. A fonte não publica lucro líquido de instituição financeira

**Registro formal de uma lacuna de cobertura, não de método.**

O `/v2/stocks/financial-data` da brapi devolve `netIncome` nulo para bancos ao
longo de **toda** a série. Verificado no ITUB4 em 07/09/2026: dezesseis
exercícios, de 2010 a 2025, com `netIncome` ausente em todos, enquanto
`bookValuePerShare` e `earningsPerShare` vêm preenchidos.

**O que isso faz na cascata.** A série de capital mede o retorno por
`lucro_t ÷ base_{t−1}`, e o lucro que ela usa é o `netIncome`. Sem ele:

| O que depende | O que acontece |
|---|---|
| Série de retorno (ROE) | fica **vazia** |
| Mediana do ciclo | não é medível |
| Guardas 1 e 3 | não avaliáveis; a base fica como observada |
| Freio de reinvestimento `b_t = g_t/ROE` | **desligado** — `returnOnCapital = 0` |
| Vantagem competitiva residual | barrada por `retorno do ciclo não medido` |
| Filtro de saúde operacional | não medível; não reprova |

**O ativo continua sendo avaliado, por caminho alternativo declarado.** O
fluxo-base sai do `earningsPerShare` publicado — é a via B, sobre o LPA — e o
crescimento sai da variação do patrimônio, que não depende de lucro. O ITUB4 sai
a R$ 40,24 contra R$ 41,92 de mercado.

**A leitura que isso exige.** Com o freio desligado, o fluxo descontado é o lucro
inteiro, sem retenção — o que é conservador na direção oposta à usual: subestima
o crescimento financiável e superestima o fluxo distribuível do mesmo exercício.
O resultado declara a degradação nos avisos, mas quem compara um banco com uma
empresa não financeira está comparando duas montagens diferentes.

**Nenhum parâmetro resolve isso**, e não é candidato a calibragem: a
[decisão 28](../decisoes/028-travas-de-ciclo-saturacao-e-saude.md) elevou o corte
de capital externo a `Φ ≤ 0,60` justamente pensando em bancos, e o ITUB4
continuou fora da exceção — porque o que o barra é a ausência do dado, não o
limiar. Sanar exigiria segunda fonte para a demonstração de resultado de
instituição financeira, ou preencher `netIncome` por `LPA × ações
reconciliadas`, que é identidade contábil mas introduz um valor derivado onde a
série espera um publicado.

---

## 3. Escopo e método

### 3.1. Ferramenta, não experimento

O trabalho é de **engenharia de software**: constrói e valida uma ferramenta de
apoio à decisão. Não testa a hipótese de que alguma estratégia supere o
mercado, e nada aqui deve ser lido como recomendação de investimento.

### 3.2. O *upside* precisa de horizonte declarado

O DCF produz valorização **total** até o preço justo, sem prazo. A meta exige
taxa **por período**. A conversão assume convergência em horizonte declarado —
**36 meses** desde a [decisão 25](../decisoes/025-reconstrucao-do-motor-de-avaliacao.md),
antes 12. Continua sendo premissa forte: nada garante que o preço convirja, nem
nesse prazo nem em outro.

Com 12 meses a anualização era a identidade, e o retorno esperado da carteira
era o *upside* cru — o que fazia um potencial de −55% virar retorno esperado de
−55% ao ano. Com 36 a conversão é `(1+u)^{1/3}−1`, e a premissa fica explícita
em vez de embutida.

### 3.3. Amostra de validação reduzida

Os relatórios de invariantes, sensibilidade e conferência cobrem **11 a 20
ativos**. A limitação é de quota de API, não de capacidade: `--limit` aceita
qualquer valor, e o cache torna reexecuções baratas.

A **validação fora da amostra** é a exceção: cobre as 373 ações que a fonte
devolveu, das quais 119 chegam a ser avaliadas. Ver a [1.8](#18-o-universo-devolvido-é-parcial)
sobre por que 373 e não 781.

### 3.4. Dart sem ecossistema científico

Não há NumPy nem SciPy. Toda a estatística foi implementada à mão.

**Mitigação.** [Conferência cruzada em Python](cross_validation.py) recalcula
tudo de forma independente. A conferência **encontrou um defeito real** no
semidesvio de Sortino — divisor errado, desvio de até 32% — que foi corrigido.
As 80 comparações atuais estão dentro de 1e-4.

---

## 4. O que foi verificado, e como

| Evidência | Método | Resultado |
|---|---|---|
| Corretude do motor | invariantes matemáticas sem fonte externa | [aprovadas](invariantes.md) |
| Estatística | Recálculo independente em `pandas`/`numpy` | [80/80 dentro de 1e-4](conferencia_python.md) |
| Robustez às premissas | Varredura em três eixos | [medida](sensibilidade.md) |
| Cobertura de testes | 457 testes automatizados, 84,2% no núcleo | — |

> O oráculo `adjustedClose` previsto no plano original **não pôde ser usado**:
> a própria auditoria mostrou que aquela série é inconsistente com o fluxo de
> proventos publicado. As invariantes matemáticas o substituíram, e são
> evidência mais forte — não dependem de nenhuma fonte externa de verdade.

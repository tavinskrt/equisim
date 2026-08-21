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

### 1.2. Datas de pagamento estimadas

O campo `remarks` marca parte dos eventos como `csv:payment_date_estimated`.
Medido na amostra: **280 de 483** eventos de ITUB4, **226 de 457** de BBDC4,
**90 de 255** de BBAS3.

**Efeito.** O motor credita o provento na data de pagamento; uma data estimada
desloca o reinvestimento em alguns dias. O impacto no resultado final é
pequeno, mas não nulo.

**Mitigação adotada.** A marca é propagada até o domínio e exibida na
interface, para que o usuário saiba quando está olhando data estimada.

### 1.3. A fonte consolida três provedores

O campo `remarks` de ITUB4 revela a origem: **280 registros de pipeline CSV** e
o restante de importações `manual:digrin-*` e `manual:twelvedata-*`.

**Efeito.** O fluxo de proventos não vem de uma fonte única auditável. Registros
duplicados existem e precisam ser higienizados — o motor descarta duplicatas
exatas por identidade `(data-ex, pagamento, valor, rótulo)`.

### 1.4. `adjustedClose` diverge de forma material

Medido sobre 11 ativos em janela de 10 anos: **desvio mediano de 9,1%** entre o
fator de ajuste implícito no fluxo de proventos e a razão `adjustedClose/close`
observada. Máximo de 38,5% (BBAS3). Seis dos onze ativos acima de 5%.

**Efeito.** A série de retorno total da fonte é inutilizável para cálculo. Todo
retorno total do sistema é construído internamente, a partir de `close` mais
eventos de provento.

**Sobre a causa.** Ativos com maioria de JCP desviam mais na média (11,2%
contra 7,7%), mas a correlação entre proporção de JCP e desvio é de apenas
**0,19**, e há contraexemplos nos dois sentidos — PETR4 tem 38% de JCP e desvia
2,1%; EGIE3 tem 31% e desvia 21,0%. **A divergência é fato medido; a explicação
pelo tratamento de JCP é hipótese plausível não confirmada.**

Relatório completo: [`divergencia_adjusted_close.md`](divergencia_adjusted_close.md).

### 1.5. `rate` bruto ou líquido — premissa declarada

O payload de proventos traz `assetIssued, paymentDate, rate, relatedTo,
approvedOn, isinCode, label, lastDatePrior, remarks`. **Nenhum campo indica se
o valor é bruto ou líquido**, e nenhum campo permite deduzir.

**Premissa adotada: base bruta.** `rate` é tratado como o valor bruto
declarado, por ser a convenção de divulgação da B3 e da CVM nos avisos aos
acionistas. A premissa é explícita no código (`DividendBasis.gross`), não
implícita na aritmética.

**Efeito prático.** Sob base bruta, R$ 1,00 de JCP rende R$ 0,85 ao investidor.
Se a fonte informasse valores já líquidos, aplicar 15% de novo subestimaria os
proventos em 15%.

**Reversibilidade.** A base é parâmetro da `TaxPolicy`, não constante espalhada
pelos cálculos. Reverter a premissa é trocar `TaxPolicy.brasil` por
`TaxPolicy.brasilBaseLiquida` — uma linha de configuração. Em base líquida, o
imposto passa a ser deduzido por reversão (`valor × taxa / (1 − taxa)`), e o
comportamento das duas bases está coberto por testes.

**Conferência pendente.** ~10 eventos contra o "Aviso aos Acionistas" de
relações com investidores. É a única forma de confirmar, e não depende de
código. Enquanto não for feita, a premissa deve ser **declarada como tal na
monografia** — não apresentada como fato verificado.

### 1.6. Viés de sobrevivência

`/v2/tickers?type=stock` lista **781 ações vivas**. Empresas deslistadas não
aparecem.

**Efeito.** Qualquer análise histórica sobre o universo herda viés de
sobrevivência. O sistema mitiga parcialmente resolvendo renomeações
(`/v2/tickers/resolve`), mas não recupera deslistagens.

### 1.7. Limite de requisições inobservável

A API **não expõe nenhum cabeçalho de rate limit** — verificado: nenhum
`X-RateLimit-*`, nenhum `Retry-After`.

**Mitigação adotada.** Concorrência contida na origem (4 simultâneas), busca em
lote sempre que possível, espera exponencial com ruído em caso de `429`, e
cache agressivo.

### 1.8. Taxonomia setorial própria

O campo `sector` usa taxonomia da brapi em português (`energia`,
`petroleo-e-gas-integrado`). **Não é GICS nem a classificação setorial oficial
da B3.**

**Efeito.** O alerta de concentração setorial depende dessa classificação. Uma
taxonomia diferente produziria agrupamentos diferentes.

### 1.9. IFIX indisponível

`historical?symbols=IFIX` devolve **um único ponto**. Sem consequência para
este trabalho, já que fundos imobiliários estão fora do escopo — mas registrado
porque foi levantado na auditoria.

---

## 2. Modelagem

### 2.1. CapEx aproximado

A fonte não entrega CapEx isolado. O sistema usa `investmentCashFlow` como
aproximação, que **inclui fusões, aquisições e aplicações financeiras**, não só
imobilizado.

**Mitigação.** O `freeCashFlow` publicado é usado como base primária quando
disponível; a derivação entra apenas como alternativa.

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

### 2.6. Cotas fracionárias

A carteira é definida por pesos, e o backtest aloca frações de ação. O mercado
negocia unidades inteiras (ou lotes).

**Efeito.** Superestima levemente a aderência aos pesos-alvo, sobretudo em
carteiras pequenas com ações de preço alto.

### 2.7. Sem imposto sobre ganho de capital

Modela-se apenas o IRRF de 15% sobre JCP. Ganho de capital na venda não é
modelado — coerente com uma estratégia sem rebalanceamento, em que não há
venda, mas a limitação existe se o usuário interpretar o resultado como
líquido de todos os tributos.

### 2.8. Regime tributário sujeito a mudança

A tributação de proventos no Brasil está em revisão legislativa. As alíquotas
são **parâmetro declarado com vigência** (`TaxPolicy`), não constante de
código, justamente para que uma mudança de lei não invalide o trabalho.

---

## 3. Escopo e método

### 3.1. Ferramenta, não experimento

O trabalho é de **engenharia de software**: constrói e valida uma ferramenta de
apoio à decisão. Não testa a hipótese de que alguma estratégia supere o
mercado, e nada aqui deve ser lido como recomendação de investimento.

### 3.2. O *upside* precisa de horizonte declarado

O DCF produz valorização **total** até o preço justo, sem prazo. A meta exige
taxa **por período**. A conversão assume convergência em horizonte declarado
(padrão 12 meses) — premissa forte: nada garante que o preço convirja, nem
nesse prazo nem em outro.

### 3.3. Amostra de validação reduzida

Os relatórios cobrem **11 a 20 ativos**, não as 781 ações do universo. A
limitação é de quota de API, não de capacidade: `--limit` aceita qualquer
valor, e o cache torna reexecuções baratas.

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
| Corretude do motor | 15 invariantes matemáticas sem fonte externa | [aprovadas](invariantes.md) |
| Estatística | Recálculo independente em `pandas`/`numpy` | [80/80 dentro de 1e-4](conferencia_python.md) |
| Fluxo de proventos | DY calculado × publicado pela fonte | [11/11 consistentes](qualidade_proventos.md) |
| Robustez às premissas | Varredura em três eixos | [medida](sensibilidade.md) |
| Cobertura de testes | 224 testes automatizados, 82,6% no núcleo | — |

> O oráculo `adjustedClose` previsto no plano original **não pôde ser usado**:
> a própria auditoria mostrou que aquela série é inconsistente com o fluxo de
> proventos. As invariantes matemáticas o substituíram, e são evidência mais
> forte — não dependem de nenhuma fonte externa de verdade.

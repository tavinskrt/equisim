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

### 2.8. Sem imposto de espécie alguma

Não há IRRF sobre provento — não há provento —, e ganho de capital na venda
também não é modelado. O segundo é coerente com uma estratégia sem
rebalanceamento, em que não há venda, mas a limitação existe se o usuário
interpretar o resultado como líquido de tributos.

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
| Corretude do motor | invariantes matemáticas sem fonte externa | [aprovadas](invariantes.md) |
| Estatística | Recálculo independente em `pandas`/`numpy` | [80/80 dentro de 1e-4](conferencia_python.md) |
| Robustez às premissas | Varredura em três eixos | [medida](sensibilidade.md) |
| Cobertura de testes | 457 testes automatizados, 84,2% no núcleo | — |

> O oráculo `adjustedClose` previsto no plano original **não pôde ser usado**:
> a própria auditoria mostrou que aquela série é inconsistente com o fluxo de
> proventos publicado. As invariantes matemáticas o substituíram, e são
> evidência mais forte — não dependem de nenhuma fonte externa de verdade.

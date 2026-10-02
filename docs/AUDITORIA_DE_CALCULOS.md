# Painel de logs de cálculo: o que cada passo mostra

O aplicativo registra cada avaliação passo a passo, com a fórmula, os números
que entraram e o resultado de cada conta. Este documento explica como abrir o
painel, o que há nele, e — para cada passo que aparece lá — o que ele calcula e
onde estudar o assunto.

> O painel mostra **a conta que foi feita**: desde 28/09/2026 (itens B35 e B39)
> o rastro da via da firma descreve o desconto ao custo do capital próprio, e a
> soma das parcelas fecha com o preço justo. Os [casos de estudo](estudo/casos/)
> refazem cada passo com os números.

---

## 1. Como abrir

Menu do perfil → **"Abrir Painel de Logs de Cálculo"**. O painel abre numa aba
separada (`#/logs`) e recebe os eventos da janela principal por um canal entre
janelas; na mesma janela, a entrega é local. Ele não autentica, não lê carteira
e não calcula nada — só observa ([logs_page.dart](../lib/presentation/audit/logs_page.dart),
[audit_bus.dart](../lib/audit/audit_bus.dart)).

Com o painel aberto, use o aplicativo normalmente: cada ativo aberto na aba de
avaliação gera um evento.

## 2. O que há no painel

| Elemento | O que faz |
|---|---|
| Filtros **Todos / Cálculos / Rede** | cálculos são as avaliações; rede são as requisições às fontes de dados (payload bruto) |
| Busca | filtra por ativo ou por nome de fórmula |
| Cada evento | três seções: **Requisição & Resposta** (insumos que entraram no motor e o resultado), **Fórmulas e Equações** (cada expressão, na ordem), **Substituição de Variáveis e Decomposição** (o valor de cada símbolo e cada passo intermediário) |
| Exportar Auditoria (JSON) | baixa os eventos, para anexar a um relatório ou conferir fora |
| Limpar, pausar rolagem, recarregar histórico, modo claro/escuro | utilidades |

O formato de cada passo é `CalculationTrace`: nome, fórmula em LaTeX, variáveis,
passos intermediários, resultado e unidade
([calculation_trace.dart](../packages/equisim_core/lib/src/audit/calculation_trace.dart)).

## 3. Os passos, na ordem em que aparecem

Nem toda avaliação tem todos: bancos não têm WACC nem projeção da firma; uma
recusa para no passo em que a conta parou.

| # | Nome no painel | O que calcula | Onde estudar | Onde está a regra |
|---:|---|---|---|---|
| 1 | **Razão da unidade negociada** | quantas ações há em cada papel negociado (1, ou 5 numa unit como a SAPR11) | [guia 2.8](estudo/02-a-empresa-em-numeros.md) | [motor 1.4](motor/01-insumos-e-dados.md) |
| 2 | **Custo do capital próprio (CAPM)** | `Ke = Rf + β × prêmio` com o CDI de hoje; o passo 0 diz de onde vem o prêmio (a média de dez anos do prêmio implícito, 1,21% em 14/09/2026, ou os 5,5% de recuo, sem pacote); o passo 3 avisa que cada ano da projeção usa o forward daquele ano | [guia 3.8](estudo/03-risco-e-retorno.md) | [motor 4.1](motor/04-custo-de-capital.md) |
| 3 | **Contagem de papéis da ponte** | por quantos papéis o capital próprio é dividido: mercado, demonstrações, registro oficial da B3 | [guia 2.8](estudo/02-a-empresa-em-numeros.md) | [motor 1.4](motor/01-insumos-e-dados.md) |
| 4 | **Roteamento por porta** | financeira? NOPAT positivo em 60% dos anos? → via da firma ou do acionista | [guia 4.2](estudo/04-fluxo-de-caixa-descontado.md) | [motor 2](motor/02-cascata-e-portas.md) |
| 5 | **Base do fluxo: normalização pelo ciclo** | retorno atual × ciclo; as três guardas; fator de normalização (e "queda no triênio": negativa quer dizer que o lucro subiu) | [guia 4.4](estudo/04-fluxo-de-caixa-descontado.md), [6.2](estudo/06-estatistica.md), [6.5](estudo/06-estatistica.md) | [motor 3.2](motor/03-base-e-crescimento.md) |
| 6 | **Crescimento explícito** | `g` pela mediana, conferido pela regressão do logaritmo; identificado, âncora de inflação ou zero | [guia 4.5](estudo/04-fluxo-de-caixa-descontado.md), [6.6](estudo/06-estatistica.md) | [motor 3.3](motor/03-base-e-crescimento.md) |
| 7 | **Custo médio ponderado de capital (WACC)** | o WACC de hoje: pesos, custo da dívida sintético, escudo, caixa a Rf (só na via da firma) | [guia 3.9 e 3.10](estudo/03-risco-e-retorno.md) | [motor 4.3 e 4.4](motor/04-custo-de-capital.md) |
| — | **Taxa de desconto — degeneração para o Ke** | aparece quando não há valor de mercado para ponderar: o desconto vira o Ke | [guia 3.10](estudo/03-risco-e-retorno.md) | [motor 4.4](motor/04-custo-de-capital.md) |
| 8 | **Crescimento na perpetuidade** | `g∞ = min(g, teto nominal)`, limitado a [−5%; teto] | [guia 4.6](estudo/04-fluxo-de-caixa-descontado.md) | [motor 3.4](motor/03-base-e-crescimento.md) |
| 9 | **Estrutura a termo da taxa de desconto** | o forward de cada ano da curva e o custo de capital montado sobre ele, com a estrutura de hoje; quando o custo é resolvido ano a ano, este caminho é o ponto de partida | [guia 3.6](estudo/03-risco-e-retorno.md) | [motor 4.5](motor/04-custo-de-capital.md) |
| 10 | **Vantagem competitiva residual na perpetuidade** | as condições do "moat", a persistência φ e o retorno terminal `ROIC∞` | [guia 4.7](estudo/04-fluxo-de-caixa-descontado.md), [6.7](estudo/06-estatistica.md) | [motor 5.3](motor/05-projecao-desconto-e-terminal.md) |
| 11a | **Projeção do fluxo da firma (NOPAT)** (via da firma) | ano a ano: `g`, ROIC convergindo ao WACC do ano, retenção, NOPAT e fluxo da firma; o WACC aqui é o alvo do retorno, e não desconta nada | [guia 4.6](estudo/04-fluxo-de-caixa-descontado.md) | [motor 5.1 e 5.2](motor/05-projecao-desconto-e-terminal.md) |
| 11b | **Fluxo do acionista e desconto ao K_e (período explícito)** (via da firma) | ano a ano: fluxo da firma − serviço da dívida = fluxo do acionista; Ke do ano, fator acumulado, meio de ano, valor presente; a soma | [guia 4.8 e 4.9](estudo/04-fluxo-de-caixa-descontado.md) | [motor 5.5](motor/05-projecao-desconto-e-terminal.md) |
| 11 | **Projeção e desconto do período explícito (LPA)** (via do acionista) | ano a ano: lucro por papel, retenção, distribuível, Ke do ano, valor presente | [guia 5.4](estudo/05-bancos.md) | [motor 5.4](motor/05-projecao-desconto-e-terminal.md) |
| 12 | **Valor terminal (…)** | a forma aplicada (retorno neutro, Gordon com reinvestimento, contrato com prazo); na via da firma, "convertido para o acionista": fluxo da firma do ano 11 → serviço da dívida → fluxo do acionista → capitalizado ao Ke∞ → valor presente | [guia 4.7](estudo/04-fluxo-de-caixa-descontado.md), [1.7](estudo/01-dinheiro-no-tempo.md) | [motor 5.3 e 5.5](motor/05-projecao-desconto-e-terminal.md) |
| 13a | **Capital próprio pelo fluxo do acionista derivado** (via da firma) | explícito + terminal − minoritários (+ capital posterior) ÷ papéis | [guia 4.9](estudo/04-fluxo-de-caixa-descontado.md) | [motor 5.5](motor/05-projecao-desconto-e-terminal.md) |
| 13b | **Preço justo por papel (DCF sobre o lucro)** (via do acionista) | explícito + terminal (+ capital posterior por papel) | [guia 5.4](estudo/05-bancos.md) | [motor 5.4](motor/05-projecao-desconto-e-terminal.md) |
| 14 | **Margem de segurança e potencial de valorização** | preço com margem e upside `(justo − preço) ÷ preço` | [guia 4.10](estudo/04-fluxo-de-caixa-descontado.md) | [motor 5.6](motor/05-projecao-desconto-e-terminal.md) |

Os passos da montagem dos insumos (busca de fundamentos, beta, eventos de
ações) aparecem como eventos próprios, de [prepare_valuation_inputs.dart](../packages/equisim_core/lib/src/usecases/prepare_valuation_inputs.dart).

## 4. Como conferir uma avaliação pelo painel

1. Abra o passo **13a** (ou **13b**): o preço justo é a soma das parcelas dividida
   pelos papéis.
2. As parcelas vêm do resultado do passo **11b** (ou **11**) e do passo **12**.
3. Em **11b**, cada linha diz `fluxo × meio de ano ÷ fator = valor presente`;
   refaça uma com calculadora.
4. O Ke de cada ano em **11b** é o forward do ano (passo 9) mais beta × prêmio (passo 2), com
   o beta recalculado pela dívida do ano quando há ponto fixo.
5. As premissas de 11a — `g` e ROIC — vêm dos passos 5, 6 e 10.

O [caso WEGE3](estudo/casos/wege3.md) faz exatamente esse percurso.

## 5. O que o painel não mostra

- As regras de tela (qual cartão aparece, como a faixa é desenhada).
- Os cenários e o Monte Carlo passo a passo: eles rodam a mesma conta com as
  premissas deslocadas, e o rastro é o do cenário base.
- A faixa calibrada: ela sai de um pacote medido nas coortes
  ([motor 6.3](motor/06-resultado.md)).

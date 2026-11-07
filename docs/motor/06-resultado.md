# 6. O resultado e a tela de avaliação

O que a avaliação devolve além do preço justo, e como cada número da tela é
calculado. Estudo: [guia, cap. 4, seções 4.10 a 4.15](../estudo/04-fluxo-de-caixa-descontado.md).

Tela: [asset-xray.tsx](../../src/features/asset/asset-xray.tsx);
montagem dos insumos no aplicativo: [valuation.ts](../../src/app/valuation.ts);
a avaliação roda fora da linha da interface ([valuation-runner.ts](../../src/data/runner/valuation-runner.ts)).

---

## 6.1 Os cartões

| Cartão | Conteúdo | Origem |
|---|---|---|
| Preço | preço de mercado, preço justo (pelas premissas do motor), upside total sem prazo, e o botão Simular minhas premissas, preço com margem | `ValuationResult` |
| Modelo aplicado | "DCF sobre fluxo da firma" ou "DCF sobre lucro distribuível"; taxa de desconto do ano 1 (WACC ou custo do capital próprio) | `ValuationResult.model`, `discountRate` |
| Faixa calibrada | 80% nominal, em 12 e 36 meses, com a cobertura fora da amostra | 6.3 |
| Sensibilidade | os três conjuntos fixos — "Premissas mais duras", "Premissas do motor", "Premissas mais brandas", com o quanto foi mexido em nota — ou o Monte Carlo (chave), e a barra do menor ao maior com o preço justo marcado, num cartão só | 6.2 |
| Múltiplos de pares | as três leituras e a consolidada | 6.4 |
| Ressalvas | ressalvas estruturadas e avisos em texto | 6.5 |

---

## 6.2 Cenários e Monte Carlo

| Regra | Código | Evidência |
|---|---|---|
| Fixos: pessimista `g − 3 p.p.` e desconto `+2 p.p.` nas duas taxas; otimista `g + 3 p.p.` e `−2 p.p.` (a taxa terminal não desce abaixo de `g∞ + 0,5 p.p.`) | [scenario-engine.ts, `DiscreteScenarios.around`](../../src/core/services/valuation/scenario-engine.ts) | deslocar as duas taxas: com a terminal parada a banda ficava metade |
| Monte Carlo: 10.000 sorteios triangulares — `g ± 4 p.p.`, desconto `± 2 p.p.` (em paralelo nas duas taxas), `g∞ ± 1 p.p.` (piso 0) —, semente fixa | `StochasticScenarios.around`; `ValuationSettings.samples` | determinismo |
| Via do acionista: o deslocamento alcança o caminho de Ke inteiro | `discountFromBalanceSheet` | — |
| Via da firma: o deslocamento vai ao Ke um a um (e ao desconto do terminal da firma); o alvo do retorno sobre o capital fica parado | `discountFromBalanceSheet`, `scenarioFactor` | as três traduções possíveis estão medidas em [cenario.md](../validacao/cenario.md) |
| O cenário base é sempre o preço justo | teste `cenario-via-acionista.test.ts` | — |
| **São sensibilidade, não probabilidade**: a banda entre as premissas mais duras e as mais brandas conteve 8% dos resultados nas coortes, contra 90% nominais | título e rodapé do cartão | [cobertura_banda.md](../validacao/cobertura_banda.md) |
| **Nomeados pelas premissas, e não pelo resultado**: a nota sai de `DiscreteScenarios.defaultGrowthDelta` e `defaultDiscountDelta`; a cor de cada valor, da posição dele contra o preço justo | [domain-copy.ts](../../src/copy/domain-copy.ts), [asset-xray.tsx, `SensitivityCard`](../../src/features/asset/asset-xray.tsx) | [sensibilidade.md](../validacao/sensibilidade.md) |
| **A inversão é declarada**: quando as premissas mais brandas dão preço menor que as mais duras, o cartão diz que a empresa rende abaixo do custo e que crescer destrói valor | `SensitivityCard` | — |

O conjunto mais brando soma crescimento, e crescer destrói valor quando o
retorno fica abaixo do custo. Com o motor de 02/10/2026, ele sai abaixo do mais
duro em 14 dos 90 da via da firma e em nenhum dos 20 da via do acionista (com o
prêmio de 5,5%, eram 17 de 77, e só o crescimento +3 p.p. baixava o preço justo
em 53 dos 97). O desconto sozinho nunca inverte. A conta está certa, e por
isso o cartão se chama "Sensibilidade" e nomeia cada conjunto pelas premissas:
nenhum rótulo supõe que crescer é bom.

---

## 6.3 Faixa calibrada

```
faixa = P × exp(a + b·ln(V ÷ P) + σ·z)
P = preço de hoje;  V = preço justo;  σ = volatilidade anual do papel
```

| Regra | Código | Evidência |
|---|---|---|
| `σ` = desvio-padrão amostral dos retornos log diários dos últimos 252 pregões × √252 (≥ 120 retornos) | [calibrated-band.ts, `trailingVolatility`](../../src/core/services/valuation/calibrated-band.ts) | — |
| `a`, `b`, `z` por horizonte e nominal, do pacote [banda_calibrada.json](../../public/assets/validacao/banda_calibrada.json), medidos nas coortes trimestrais (12 meses: 2018–2025; 36 meses: 2018–2023) | `VolatilityBandTable`, [tool/cobertura_banda.py](../../tool/cobertura_banda.py) | [cobertura_banda.md](../validacao/cobertura_banda.md): a forma replica sobre o motor atual, com desvio máximo de 2,6 p.p. contra o limite de 5 |
| 12 meses: `a = 0,0781`, `b = 0,0202`; 36 meses: `a = 0,1318`, `b = 0,0615` — o preço converge pouco ao justo | pacote | [cobertura_banda.md](../validacao/cobertura_banda.md) |
| A tela afirma "8 de cada 10" só se a cobertura fora da amostra estiver a até 5 p.p. de 80% nos dois horizontes (medida em 03/11/2026: 79,0% e 79,1%) | `CalibratedBandCard.criterionMargin` | critério do R2 |

---

## 6.4 Múltiplos de pares

| Regra | Código | Evidência |
|---|---|---|
| P/L × lucro por papel; P/VP × patrimônio por papel; (EV/EBITDA × EBITDA − dívida líquida) ÷ papéis — sobre o mesmo exercício e o mesmo divisor do DCF | [peer-multiples.ts, `PeerValuation`](../../src/core/services/valuation/peer-multiples.ts) | [multiplos.md](../validacao/multiplos.md) |
| Mediana do subsetor; sem 5 pares, do setor; sem isso, do mercado — por múltiplo | [tool/multiples-package.ts](../../tool/multiples-package.ts), [multiplos_setoriais.json](../../public/assets/mercado/multiplos_setoriais.json) | [multiplos.md](../validacao/multiplos.md) |
| **Pares são outras companhias**: uma por companhia (mediana das classes dela), sem a do ativo avaliado | `valores` no empacotador | sem isso, uma companhia com três classes entraria três vezes entre os próprios pares, e a leitura devolveria o preço dela |
| EV/EBITDA recusado para financeira | `PeerValuation` | depósito e captação são insumo, e não financiamento |
| Consolidada = mediana das leituras aplicadas; aviso se divergir mais de 50% do DCF; **não muda o preço justo** | `PeerTriangulation`, `divergenceLimit` | [multiplos.md](../validacao/multiplos.md) |

---

## 6.5 Ressalvas e avisos

| Ressalva | Gatilho | Código |
|---|---|---|
| Terminal pesado | terminal > 80% do capital próprio | `diagnose` |
| Crescimento não identificado | `g` da âncora de inflação ou zero | `diagnose` |
| Escala incerta | contagens divergem e não há oficial | `diagnose` |
| Base normalizada forte | fator > 2 ou < ½ | `diagnose` |
| Prazo determinado | concessão | `diagnose` |
| Base reconstruída | base veio do ciclo | `diagnose` |
| Ponte frágil | capital próprio < 35% do valor da firma | `diagnose` |
| Controle estatal | a companhia é de controle estatal na data, pelo Formulário Cadastral da CVM; **não muda o preço** | `diagnose`, [shareholder-control.ts](../../src/core/services/cvm/shareholder-control.ts) |

Os rótulos de tela estão em [domain-copy.ts](../../src/copy/domain-copy.ts)
(o rótulo mora na apresentação, e não no núcleo). Os avisos em texto saem do
núcleo e dizem a regra aplicada e o número.

---

## 6.6 O rastro de auditoria

Cada avaliação emite um evento com os insumos, a saída e uma lista de passos de
cálculo (`CalculationTrace`: nome, fórmula em LaTeX, variáveis, passos
intermediários, resultado e unidade), via `AuditRecorder`
([audit/](../../src/core/audit/)). O aplicativo os mostra no
painel de logs; o que cada passo quer dizer está em
[AUDITORIA_DE_CALCULOS.md](../AUDITORIA_DE_CALCULOS.md). O gabarito da cascata
grava o rastro junto com o resultado: um passo que muda sem o número mudar é
detectado.

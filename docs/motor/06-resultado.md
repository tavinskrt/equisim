# 6. O resultado e a tela de avaliação

O que a avaliação devolve além do preço justo, e como cada número da tela é
calculado. Estudo: [guia, cap. 4, seções 4.10 a 4.15](../estudo/04-fluxo-de-caixa-descontado.md).

Tela: [valuation_page.dart](../../lib/presentation/valuation/valuation_page.dart);
montagem dos insumos no aplicativo: [valuation_providers.dart](../../lib/presentation/valuation/valuation_providers.dart);
a avaliação roda fora da linha da interface ([valuation_runner.dart](../../lib/data/isolate/valuation_runner.dart)).

---

## 6.1 Os cartões

| Cartão | Conteúdo | Origem |
|---|---|---|
| Preço | preço de mercado, preço justo (cenário base), upside total sem prazo, preço com margem | `ValuationResult` |
| Modelo aplicado | "DCF sobre fluxo da firma" ou "DCF sobre lucro distribuível"; taxa de desconto do ano 1 (WACC ou custo do capital próprio) | `ValuationResult.model`, `discountRate` |
| Faixa calibrada | 80% nominal, em 12 e 36 meses, com a cobertura fora da amostra | 6.3 |
| Cenários | três fixos, ou Monte Carlo (chave) | 6.2 |
| Sensibilidade | barra do pessimista ao otimista, com o base marcado | 6.2 |
| Múltiplos de pares | as três leituras e a consolidada | 6.4 |
| Ressalvas | ressalvas estruturadas e avisos em texto | 6.5 |

---

## 6.2 Cenários e Monte Carlo

| Regra | Código | Evidência |
|---|---|---|
| Fixos: pessimista `g − 3 p.p.` e desconto `+2 p.p.` nas duas taxas; otimista `g + 3 p.p.` e `−2 p.p.` (a taxa terminal não desce abaixo de `g∞ + 0,5 p.p.`) | [scenario_engine.dart, `DiscreteScenarios.around`](../../packages/equisim_core/lib/src/services/valuation/scenario_engine.dart) | deslocar as duas taxas: com a terminal parada a banda ficava metade |
| Monte Carlo: 10.000 sorteios triangulares — `g ± 4 p.p.`, desconto `± 2 p.p.` (em paralelo nas duas taxas), `g∞ ± 1 p.p.` (piso 0) —, semente fixa | `StochasticScenarios.around`; `ValuationSettings.samples` | determinismo |
| Via do acionista: o deslocamento alcança o caminho de Ke inteiro | `_descontarDoBalanco` | item B36 |
| Via da firma: o deslocamento vai ao Ke um a um (e ao desconto do terminal da firma); o alvo do retorno sobre o capital fica parado | `_descontarDoBalanco`, `_fatorDoCenario` | decisão 121 (as três traduções medidas) |
| O cenário base é sempre o preço justo | teste `cenario_via_acionista_test.dart` | decisão 105 |
| **São sensibilidade, não probabilidade**: a banda pessimista–otimista conteve 8% dos resultados nas coortes, contra 90% nominais | subtítulo do cartão | decisão 92 |

**Pendente (item B38):** o otimista soma crescimento, e crescer destrói valor
quando o retorno fica abaixo do custo. Com o motor de 01/10/2026, o otimista
sai abaixo do pessimista em 15 dos 88 da via da firma e em nenhum dos 20 da via
do acionista (com o prêmio de 5,5%, eram 17 de 77, e só o crescimento +3 p.p.
baixava o preço justo em 53 dos 97). O desconto sozinho nunca inverte. A conta
está certa; o rótulo supõe que crescer é bom.

---

## 6.3 Faixa calibrada

```
faixa = P × exp(a + b·ln(V ÷ P) + σ·z)
P = preço de hoje;  V = preço justo;  σ = volatilidade anual do papel
```

| Regra | Código | Evidência |
|---|---|---|
| `σ` = desvio-padrão amostral dos retornos log diários dos últimos 252 pregões × √252 (≥ 120 retornos) | [calibrated_band.dart, `trailingVolatility`](../../packages/equisim_core/lib/src/services/valuation/calibrated_band.dart) | — |
| `a`, `b`, `z` por horizonte e nominal, do pacote [banda_calibrada.json](../../assets/validacao/banda_calibrada.json), medidos nas coortes trimestrais (12 meses: 2018–2025; 36 meses: 2018–2023) | `VolatilityBandTable`, [tool/cobertura_banda.py](../../tool/cobertura_banda.py) | decisões 100 e 124 |
| 12 meses: `a = 0,0729`, `b = 0,0205`; 36 meses: `a = 0,1217`, `b = 0,0658` — o preço converge pouco ao justo | pacote | [cobertura_banda.md](../validacao/cobertura_banda.md) |
| A tela afirma "8 de cada 10" só se a cobertura fora da amostra estiver a até 5 p.p. de 80% nos dois horizontes (medida em 01/10/2026: 79,7% e 79,6%) | `_CalibratedBandCard.folgaDoCriterio` | critério do R2 |

---

## 6.4 Múltiplos de pares

| Regra | Código | Evidência |
|---|---|---|
| P/L × lucro por papel; P/VP × patrimônio por papel; (EV/EBITDA × EBITDA − dívida líquida) ÷ papéis — sobre o mesmo exercício e o mesmo divisor do DCF | [peer_multiples.dart, `PeerValuation`](../../packages/equisim_core/lib/src/services/valuation/peer_multiples.dart) | decisão 118 |
| Mediana do subsetor; sem 5 pares, do setor; sem isso, do mercado — por múltiplo | [tool/multiplos_empacotar.dart](../../tool/multiplos_empacotar.dart), [multiplos_setoriais.json](../../assets/mercado/multiplos_setoriais.json) | decisão 118 |
| **Pares são outras companhias**: uma por companhia (mediana das classes dela), sem a do ativo avaliado | `_valores` no empacotador | **item B41, corrigido em 28/09/2026**: a Sanepar entrava três vezes entre os próprios sete pares, e duas leituras devolviam o preço dela na data do pacote |
| EV/EBITDA recusado para financeira | `PeerValuation` | decisão 102 |
| Consolidada = mediana das leituras aplicadas; aviso se divergir mais de 50% do DCF; **não muda o preço justo** | `PeerTriangulation`, `divergenceLimit` | decisão 118 |

---

## 6.5 Ressalvas e avisos

| Ressalva | Gatilho | Código |
|---|---|---|
| Terminal pesado | terminal > 80% do capital próprio | `_diagnose` |
| Crescimento não identificado | `g` da âncora de inflação ou zero | `_diagnose` |
| Escala incerta | contagens divergem e não há oficial | `_diagnose` |
| Base normalizada forte | fator > 2 ou < ½ | `_diagnose` |
| Prazo determinado | concessão | `_diagnose` |
| Base reconstruída | base veio do ciclo | `_diagnose` |
| Ponte frágil | capital próprio < 35% do valor da firma | `_diagnose` |

Os rótulos de tela estão em [domain_copy.dart](../../lib/presentation/shared/domain_copy.dart)
(decisão 125: o rótulo mora na apresentação). Os avisos em texto saem do núcleo
e dizem a regra aplicada e o número (decisão 122).

---

## 6.6 O rastro de auditoria

Cada avaliação emite um evento com os insumos, a saída e uma lista de passos de
cálculo (`CalculationTrace`: nome, fórmula em LaTeX, variáveis, passos
intermediários, resultado e unidade), via `AuditRecorder`
([audit/](../../packages/equisim_core/lib/src/audit/)). O aplicativo os mostra no
painel de logs; o que cada passo quer dizer está em
[AUDITORIA_DE_CALCULOS.md](../AUDITORIA_DE_CALCULOS.md). O gabarito da cascata
grava o rastro junto com o resultado: um passo que muda sem o número mudar é
detectado.

# Invariantes do motor

Gerado em 2026-09-02T16:23:33.

Estas verificações não dependem de fonte externa de verdade: são identidades que o motor precisa satisfazer. Substituem o oráculo `adjustedClose` descartado na auditoria (§0.4), que se mostrou inconsistente com o fluxo de proventos publicado em até 38,5%. O domínio não modela provento desde a decisão 023.

**Resultado: 12 de 12 aprovadas.**

| Invariante | Situação | Detalhe |
|---|---|---|
| PETR4: aportado ≡ alocado + caixa | ✅ | aportado 2750000¢ · destinado 2750000¢ · alocado 2747295¢ + caixa 2705¢ = 2750000¢ |
| PETR4: aporte único ⇒ XIRR ≡ CAGR | ✅ | XIRR 14,11% · CAGR 14,12% · diferença 0,0103% |
| PETR4: Σ ativos ≡ patrimônio da carteira | ✅ | Σ 30798,06 · carteira 30798,06 · diferença 0,0000 |
| ITUB4: aportado ≡ alocado + caixa | ✅ | aportado 2750000¢ · destinado 2750000¢ · alocado 2748442¢ + caixa 1558¢ = 2750000¢ |
| ITUB4: aporte único ⇒ XIRR ≡ CAGR | ✅ | XIRR 19,59% · CAGR 19,61% · diferença 0,0147% |
| ITUB4: Σ ativos ≡ patrimônio da carteira | ✅ | Σ 30589,23 · carteira 30589,23 · diferença 0,0000 |
| WEGE3: aportado ≡ alocado + caixa | ✅ | aportado 2750000¢ · destinado 2750000¢ · alocado 2748182¢ + caixa 1818¢ = 2750000¢ |
| WEGE3: aporte único ⇒ XIRR ≡ CAGR | ✅ | XIRR 12,07% · CAGR 12,08% · diferença 0,0087% |
| WEGE3: Σ ativos ≡ patrimônio da carteira | ✅ | Σ 27769,79 · carteira 27769,79 · diferença 0,0000 |
| Aporte não é confundido com retorno | ✅ | carteira parada que recebe R$ 10.000 rende 0,00% (esperado 0,00%) |
| Pesos equiponderados somam exatamente 100% | ✅ | verificado de 1 a 15 ativos |
| Rentabilidade requerida reproduz a meta (ida e volta) | ✅ | 3 casos com erro abaixo de R$ 0,01 |

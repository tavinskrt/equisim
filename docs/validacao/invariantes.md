# Invariantes do motor

Gerado em 2026-09-07T22:08:28.

Estas verificações não dependem de fonte externa de verdade: são identidades que o motor precisa satisfazer. Substituem o oráculo `adjustedClose` descartado na auditoria (§0.4), que se mostrou inconsistente com o fluxo de proventos publicado em até 38,5%. O domínio não modela provento desde a decisão 023.

**Resultado: 12 de 12 aprovadas.**

| Invariante | Situação | Detalhe |
|---|---|---|
| PETR4: aportado ≡ alocado + caixa | ✅ | aportado 2800000¢ · destinado 2800000¢ · alocado 2795621¢ + caixa 4379¢ = 2800000¢ |
| PETR4: aporte único ⇒ XIRR ≡ CAGR | ✅ | XIRR 12,13% · CAGR 12,14% · diferença 0,0088% |
| PETR4: Σ ativos ≡ patrimônio da carteira | ✅ | Σ 30490,02 · carteira 30490,02 · diferença 0,0000 |
| ITUB4: aportado ≡ alocado + caixa | ✅ | aportado 2800000¢ · destinado 2800000¢ · alocado 2796717¢ + caixa 3283¢ = 2800000¢ |
| ITUB4: aporte único ⇒ XIRR ≡ CAGR | ✅ | XIRR 21,05% · CAGR 21,06% · diferença 0,0158% |
| ITUB4: Σ ativos ≡ patrimônio da carteira | ✅ | Σ 31704,47 · carteira 31704,47 · diferença 0,0000 |
| WEGE3: aportado ≡ alocado + caixa | ✅ | aportado 2800000¢ · destinado 2800000¢ · alocado 2796362¢ + caixa 3638¢ = 2800000¢ |
| WEGE3: aporte único ⇒ XIRR ≡ CAGR | ✅ | XIRR 13,47% · CAGR 13,47% · diferença 0,0098% |
| WEGE3: Σ ativos ≡ patrimônio da carteira | ✅ | Σ 28890,41 · carteira 28890,41 · diferença 0,0000 |
| Aporte não é confundido com retorno | ✅ | carteira parada que recebe R$ 10.000 rende 0,00% (esperado 0,00%) |
| Pesos equiponderados somam exatamente 100% | ✅ | verificado de 1 a 15 ativos |
| Rentabilidade requerida reproduz a meta (ida e volta) | ✅ | 3 casos com erro abaixo de R$ 0,01 |

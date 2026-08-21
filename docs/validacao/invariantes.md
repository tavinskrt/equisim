# Invariantes do motor

Gerado em 2026-08-20T15:15:38.

Estas verificações não dependem de fonte externa de verdade: são identidades que o motor precisa satisfazer. Substituem o oráculo `adjustedClose` descartado na auditoria (§0.4), que se mostrou inconsistente com o fluxo de proventos em até 38,5%.

**Resultado: 15 de 15 aprovadas.**

| Invariante | Situação | Detalhe |
|---|---|---|
| PETR4: carteira de ativo único ≡ retorno total | ✅ | backtest 93,66% · motor 93,66% · diferença 0,000000000 |
| PETR4: aporte único ⇒ XIRR ≡ CAGR | ✅ | XIRR 12,23% · CAGR 12,24% · diferença 0,0089% |
| PETR4: Σ ativos ≡ patrimônio da carteira | ✅ | Σ 34838,88 · carteira 34838,88 · diferença 0,0000 |
| PETR4: tributação reduz o resultado | ✅ | bruto 19731,49 · líquido 19366,13 · IR retido 278,74 |
| ITUB4: carteira de ativo único ≡ retorno total | ✅ | backtest 97,79% · motor 97,79% · diferença 0,000000000 |
| ITUB4: aporte único ⇒ XIRR ≡ CAGR | ✅ | XIRR 16,72% · CAGR 16,73% · diferença 0,0124% |
| ITUB4: Σ ativos ≡ patrimônio da carteira | ✅ | Σ 33338,16 · carteira 33338,16 · diferença 0,0000 |
| ITUB4: tributação reduz o resultado | ✅ | bruto 20097,23 · líquido 19778,73 · IR retido 251,39 |
| WEGE3: carteira de ativo único ≡ retorno total | ✅ | backtest 41,44% · motor 41,44% · diferença 0,000000000 |
| WEGE3: aporte único ⇒ XIRR ≡ CAGR | ✅ | XIRR 10,22% · CAGR 10,23% · diferença 0,0073% |
| WEGE3: Σ ativos ≡ patrimônio da carteira | ✅ | Σ 27989,68 · carteira 27989,68 · diferença 0,0000 |
| WEGE3: tributação reduz o resultado | ✅ | bruto 14185,46 · líquido 14143,78 · IR retido 36,42 |
| Aporte não é confundido com retorno | ✅ | carteira parada que recebe R$ 10.000 rende 0,00% (esperado 0,00%) |
| Pesos equiponderados somam exatamente 100% | ✅ | verificado de 1 a 15 ativos |
| Rentabilidade requerida reproduz a meta (ida e volta) | ✅ | 3 casos com erro abaixo de R$ 0,01 |

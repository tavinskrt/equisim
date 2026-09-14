---
numero: 87
titulo: O setor é o da classificação oficial da B3, por emissor, e a Porta 1 entra por subsetor
status: aceita
origem: voce
data: 2026-09-14
citacao: >
  Vamos finalizar os últimos 4 itens, de A3.4 até A6.
afeta:
  - packages/equisim_core/lib/src/services/b3/b3_registry.dart
  - packages/equisim_core/lib/src/services/valuation/financial_sectors.dart
  - packages/equisim_core/lib/src/usecases/compute_valuation.dart
  - packages/equisim_core/lib/equisim_core.dart
  - packages/equisim_core/test/b3_registry_test.dart
  - packages/equisim_core/test/financial_sectors_test.dart
  - packages/equisim_core/test/valuation_guards_test.dart
  - lib/data/repositories/b3_registry_repository.dart
  - lib/di/providers.dart
  - assets/b3/emissores.json
  - tool/b3_complemento_baixar.py
  - tool/b3_empacotar.dart
  - tool/padrao_ligar.dart
  - tool/backtest_valuation.dart
  - test/data/b3_tesouro_package_asset_test.dart
  - docs/validacao/b3_classificacao.md
substitui: []
---

## Contexto

O item A5 do plano: a taxonomia setorial vinha da fonte de preços, que não é a
classificação oficial da B3 (limitações §1.5) e classifica **papel a papel**.
BRSR6, PINE4 e SANB4 chegavam sem setor e escapavam da Porta 1 (§2.14), com a
SANB11 classificada e a SANB4 não. A medição mostrou 51 tickers do universo que
mudam de porta quando o setor passa a ser o da B3 — 45 deles sem setor nenhum na
fonte.

## Decisão

1. **O setor de todo ativo é o da B3, por emissor.** `GetDetail` dá
   `Setor / Subsetor / Segmento`; o registro empacotado (`B3RegistryCodec`
   versão 2) guarda a classificação, e `OfficialSectorFundamentalsRepository`
   a põe no perfil — chave do setor econômico, e subsetor e segmento como o
   subsetor que o motor lê. A taxonomia da fonte fica como recuo, para emissor
   que a B3 não classifica, e o nome do ativo continua o da fonte.
2. **A classificação sobrevive à falha do perfil.** Um banco não pode ir à via da
   firma porque a fonte de preços não entregou o perfil naquele dia.
3. **A Porta 1 entra por subsetor, e não pelo setor Financeiro inteiro.**
   `FinancialSectors` aceita Intermediários Financeiros, Previdência e Seguros e
   Serviços Financeiros Diversos. A B3 põe em Financeiro a exploração de imóveis
   e as holdings diversificadas — ALOS3, MULT3, ITSA4 —, cujo passivo é
   financiamento de verdade.
4. **As regras de ciclo e de concessão ficam como estão.** Os termos de
   `CyclicalSectors` e `ConcessionSectors` já eram nomes de subsetor e segmento
   da B3, que a fonte copiava; a chave `materiais-basicos` é a do setor econômico
   Materiais Básicos.

## Consequências aceitas

**Seis ativos mudam de regime por mudar de taxonomia, e não por ganhar setor:**
HAGA3, RAIZ4, RANI3, LUPA3, OPCT3 e OSXB3 ganham a precedência do ciclo. RANI3,
de embalagens, entra porque o setor econômico dela é Materiais Básicos — e
embalagem de papel é tão cíclica quanto o papel.

**O preço de três ativos se move além de 10 p.p.** UNIP6, BRAP4 e FESA4 ganham a
precedência do ciclo que as outras classes do mesmo emissor já tinham. O
potencial mediano vai de −47,7% a −45,5%, com correlação de postos de 0,967. Os
números finais estão em [fase1_padrao.md](../validacao/fase1_padrao.md).

**Os três bancos não se movem**, e o defeito era real. A Porta 3 já os mandava à
via do acionista, e a isenção de realavancagem da Porta 1 só age com o beta
desalavancado, que o aplicativo não resolve — divergência registrada como item
B11 do plano.

**O prior setorial do beta passa a agrupar pelos 11 setores econômicos da B3**
onde é calculado. A classificação é a de 14/09/2026, e envelhece com o pacote.

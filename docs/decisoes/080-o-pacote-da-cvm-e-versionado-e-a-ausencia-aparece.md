---
numero: 80
titulo: O pacote da CVM é versionado, e a avaliação que segue sem ele diz isso
status: aceita
origem: voce
data: 2026-09-14
afeta:
  - assets/cvm/documentos.json
  - assets/cvm/LEIAME.txt
  - .gitignore
  - pubspec.yaml
  - lib/data/repositories/cvm_fundamentals_repository.dart
  - lib/di/providers.dart
  - lib/presentation/valuation/valuation_providers.dart
  - packages/equisim_core/lib/src/entities/valuation.dart
  - test/data/cvm_package_asset_test.dart
  - test/data/cvm_fundamentals_repository_test.dart
  - packages/equisim_core/test/portfolio_test.dart
substitui: []
---

## Contexto

A [decisão 76](076-a-cvm-chega-ao-aplicativo-por-pacote.md) levou a CVM ao
aplicativo por um pacote gerado a partir da base ingerida, e deixou o pacote
fora do git. Ela mesma registrou o preço: **compilar sem rodar o empacotador
saía sem a CVM, em silêncio** — o repositório ficava transparente, e nada na
tela dizia que a avaliação tinha voltado a ser só de mercado. Era o item A1.10
do plano.

Regerar o pacote exige a base ingerida, que exige os arquivos anuais da CVM:
750 MB que só existem na máquina de quem os baixou. Um clone novo não tinha
como produzir o pacote antes do build.

## Decisão

**Tomada pelo usuário em 14/09/2026, entre versionar e gerar no build.**

1. **O pacote é versionado.** `assets/cvm/documentos.json` sai do
   `.gitignore`: qualquer clone compila com a CVM. Git comprime o JSON para
   cerca de 1,5 MB por versão.
2. **Pacote ausente ou quebrado reprova a suíte.**
   `test/data/cvm_package_asset_test.dart` confere que o arquivo existe, que o
   codec deste build o lê, que cobre ao menos 95% do universo e que todo
   documento dele é legível.
3. **No aplicativo, a ausência vira ressalva.** O repositório passa a
   distinguir pacote ausente, pacote ilegível — JSON inválido, versão
   desconhecida, nenhum ativo —, ativo sem documento e pacote defasado, com
   mais de cem dias. Cada situação produz um aviso no cartão de ressalvas da
   avaliação, por `ValuationResult.withWarnings`, sem mudar número nenhum.

## Consequências aceitas

Cada regeneração do pacote soma cerca de 1,5 MB ao histórico do repositório.
Com uma regeneração por ciclo de entrega da CVM — quatro por ano —, são 6 MB
por ano.

O limite de cem dias para declarar defasagem é arbitrário na unidade, e não na
ordem de grandeza: é o intervalo em que um ciclo de entrega — DFP até março, ITR
45 dias depois do trimestre — foi com certeza perdido.

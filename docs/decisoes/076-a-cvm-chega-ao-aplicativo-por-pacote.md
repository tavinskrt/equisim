---
numero: 76
titulo: A CVM chega ao aplicativo por pacote empacotado, e sem ele o repositório é transparente
status: aceita
origem: parecer
data: 2026-09-14
afeta:
  - packages/equisim_core/lib/src/services/cvm/cvm_series.dart
  - packages/equisim_core/lib/src/services/cvm/cvm_document_codec.dart
  - lib/data/repositories/cvm_fundamentals_repository.dart
  - lib/di/providers.dart
  - pubspec.yaml
  - tool/cvm_empacotar.dart
  - tool/cvm/documentos.dart
  - test/data/cvm_fundamentals_repository_test.dart
substitui: []
---

## Contexto

Até o A1.8 a ligação da CVM ao motor vivia em `tool/cvm_ligar.dart`: a
validação avaliava com ela, e o aplicativo não. Levá-la ao aplicativo (A1.9)
tinha dois obstáculos.

**A montagem não podia ser copiada.** A regra que junta a CVM com a fonte de
mercado já teve três correções — exercício fora de dezembro, série com buraco e
mescla olhando para a frente. Uma cópia na camada de dados divergiria na
próxima.

**A ingestão não cabe no dispositivo.** A CVM publica arquivos anuais de
centenas de megabytes; o aplicativo precisa de 375 tickers.

## Decisão

- **A montagem vai para o núcleo**, em `CvmSeries.build`, e é a mesma chamada
  na ferramenta e no aplicativo.
- **Um formato compacto**, `CvmDocumentCodec`, com chaves curtas, sem campo
  nulo e com número inteiro sem casas, também no núcleo — a ferramenta que
  escreve e o repositório que lê têm de concordar byte a byte.
- **`tool/cvm_empacotar.dart`** gera `assets/cvm/documentos.json` com os
  tickers do universo: **371 de 375, 19.080 documentos, 8,87 MB — 1,51 MB
  comprimido**.
- **`CvmFundamentalsRepository`** decora o repositório de mercado no
  `fundamentalsRepositoryProvider`. Lê o pacote uma vez, e monta a série por
  `CvmSeries` com a série ancorada **desligada** (decisão 73).
- **Sem pacote, é transparente.** Ausente, corrompido ou de versão desconhecida,
  o repositório devolve a série de mercado intacta — que é o estado de antes.

## Consequências aceitas

**O pacote fica fora do git**, e é o diretório `assets/cvm/` que se declara no
`pubspec.yaml`, não o arquivo. Declarar o arquivo faria um clone sem ele deixar
de compilar — foi o que o primeiro `flutter test` mostrou. O preço é que uma
compilação sem rodar o empacotador sai sem a CVM, **em silêncio**: o
repositório transparente não avisa ninguém. Se o aplicativo for distribuído, o
empacotador tem de entrar no processo de build.

**Quase 9 MB de JSON no aplicativo** quando gerado. Comprimido, é 1,5 MB, e os
empacotadores de Android e web comprimem; o desktop não. O pacote leva ITR
junto para que a série ancorada possa ser ligada sem regenerá-lo; só com DFP
ele teria cerca de um terço.

**A data da avaliação vem do relógio na camada de aplicativo** (`DateTime.now`
no provider), e é recebida por função pelo repositório — o núcleo segue
recebendo a data pronta.

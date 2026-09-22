---
numero: 128
titulo: A coorte lê a versão do documento que era pública na data dela
status: aceita
origem: voce
data: 2026-09-22
citacao: >
  Seus itens de escopo para esta rodada são B8, B21 (pode finalizar a
  reescrita das outras duas metades), C4 e D3.
afeta:
  - tool/cvm_versoes_baixar.py
  - tool/cvm_ingerir.dart
  - tool/cvm/documentos.dart
  - tool/backtest_valuation.dart
  - tool/coortes/deslistadas.dart
  - tool/reapresentacao_efeito.py
  - packages/equisim_core/lib/src/services/cvm/cvm_series.dart
  - docs/validacao/reapresentacao.md
  - docs/validacao/backtest_trimestral.json
substitui: []
---

## Contexto

A ingestão da CVM adotava a **última versão** de cada documento, e o próprio
comentário dela dizia o custo: número corrigido depois entra na avaliação datada
como se fosse o original. Era o item B8, medido pela metade em 21/09/2026
([reapresentacao.md](../validacao/reapresentacao.md) §0 a §3): a metade (a), o
documento que **some** porque a única versão chegou depois da coorte, era
pequena; a metade (b), o número **reapresentado** entrando antes de existir, não
era medível sem as versões antigas — e os CSVs anuais da CVM trazem, nos
demonstrativos, só a última.

## O que foi feito

1. **As versões antigas vêm do RAD.** O índice da CVM lista cada versão com o
   `ID_DOC`, e o RAD entrega o pacote dela. `tool/cvm_versoes_baixar.py` baixa
   só a versão que estava vigente em alguma data de coorte e não é a última —
   626 no universo das coortes — e a converte para o layout dos CSVs. A
   conversão foi conferida conta a conta contra os CSVs em quatro documentos,
   nos dois formatos que o RAD usou, com zero divergência.
2. **A ingestão grava as antigas à parte**, em `data/cvm_versoes.json`, cada uma
   com a data de recebimento dela. `data/cvm_exercicios.json` continua com a
   última versão — e ficou idêntico em conteúdo ao de antes —, porque é o que o
   pacote do aplicativo e as ferramentas de conferência leem.
3. **O núcleo escolhe a versão vigente.** `CvmSeries.vigentes` fica, por tipo e
   data de referência, com a versão publicada de recebimento mais recente. Com
   uma versão por documento — o aplicativo — é o filtro de publicados de
   sempre, e o gabarito confere isso.
4. **Só o backtest lê as versões antigas** (`carregarDocumentos(...,
   comVersoesAntigas: true)`), e avisa quando o arquivo falta.

## O que foi medido

Duas execuções do backtest sobre o mesmo motor:

- **o preço justo muda em 84 de 3.045 observações avaliadas (2,8%)**, com
  mediana de 21% e p90 de 83% entre as que mudam; 6 passam a ser avaliadas e 16
  deixam de ser; o exercício mais recente muda em 61;
- **a leitura do R3 não muda**: o potencial condicionado ao book-to-market dá
  0,028 com `t` corrigido de 0,15, e nenhuma ordenação passa;
- **a faixa calibrada continua replicando**: 87,8% e 88,4% contra 90%.

## Decisão

**A coorte lê a versão que era pública na data dela.** O item B8 fecha, nas duas
metades. As dez versões que o RAD não entregou — nove recusas de download e um
pacote sem demonstrativo — caem na última versão, e ficam declaradas.

## Consequências aceitas

**O efeito é raro e grande**, e é por isso que ele importava sem mudar a
conclusão: a coorte média não se move, e as poucas que se movem se movem muito —
a ENAT3 de R$ 3,81 a R$ 20,16 em 31/03/2022, a MRVE3 perdendo mais de 80% ao
longo de 2022. Uma amostra com esses erros e outra sem eles dão o mesmo IC
porque 97% das observações são as mesmas.

**A reconstrução depende do RAD**, que reseta conexão longa. O download retoma
de onde parou, e a sequência do item C5 manda repeti-lo até nada faltar. Sem as
versões, tudo funciona como antes do B8, com aviso.

**O pacote do aplicativo não muda.** O aplicativo avalia hoje, e hoje a versão
vigente de todo documento é a última.

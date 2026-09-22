/// A série de exercícios que o motor consome, montada da CVM com o mercado.
///
/// **Por que mora no núcleo.** Até o A1.8 esta montagem vivia dentro de
/// `tool/cvm_ligar.dart`, e levar a ligação ao aplicativo (A1.9) exigiria
/// copiá-la para a camada de dados. Duas cópias da mesma regra divergem na
/// primeira correção — e esta regra já teve três: exercício fora de dezembro,
/// série com buraco e mescla olhando para a frente. Uma só, testada aqui.
library;

import '../../entities/fundamentals.dart';
import 'fundamentals_merge.dart';
import 'trailing_twelve_months.dart';

/// Resultado da montagem: a série e o que se sabe dela.
class CvmSeriesResult {
  /// Exercícios em ordem cronológica, prontos para a cascata.
  final List<FundamentalsSnapshot> series;

  /// `true` quando a série terminou ancorada em trimestre.
  final bool anchoredOnQuarter;

  /// Quantos campos vieram de cada fonte, somados sobre a série.
  final Map<FieldSource, int> provenance;

  /// Declara o resultado.
  const CvmSeriesResult({
    required this.series,
    required this.anchoredOnQuarter,
    required this.provenance,
  });
}

/// Montagem da série.
abstract final class CvmSeries {
  /// Folga, em dias, para casar o fim de um ponto da CVM com o exercício de
  /// mercado que o completa.
  static const int folgaDias = 4;

  /// A versão vigente de cada documento: das já publicadas, a de recebimento
  /// mais recente, por tipo e data de referência (item B8).
  ///
  /// A CVM republica o documento reapresentado com outra versão, e cada versão
  /// tem a sua data de recebimento. Com todas elas na lista, a pergunta da
  /// coorte deixa de ser «o documento era público?» e passa a ser «**qual**
  /// versão era pública?» — a original até a reapresentação chegar, a
  /// reapresentada depois. Sem isso o número corrigido em 2021 entra numa
  /// avaliação de 2019, que é conhecimento futuro pela porta da frente.
  ///
  /// Com uma versão por documento — o pacote do aplicativo, que só traz a
  /// última —, devolve os publicados, e nada muda. Em empate de data, fica a
  /// que vem depois na lista. Documento sem data de recebimento conta como
  /// recebido no fecho, que é o mais cedo que ele pode ter sido.
  static List<CvmPeriodDocument> vigentes(
    List<CvmPeriodDocument> documentos,
    bool Function(FundamentalsSnapshot) publicado,
  ) {
    DateTime dia(DateTime d) => DateTime.utc(d.year, d.month, d.day);
    final porChave = <(CvmDocumentKind, DateTime), CvmPeriodDocument>{};
    for (final d in documentos) {
      if (!publicado(d.current)) continue;
      final k = (d.kind, dia(d.periodEnd));
      final atual = porChave[k];
      if (atual == null ||
          !dia(d.current.receiptDate ?? d.periodEnd)
              .isBefore(dia(atual.current.receiptDate ?? atual.periodEnd))) {
        porChave[k] = d;
      }
    }
    return porChave.values.toList()
      ..sort((a, b) => a.periodEnd.compareTo(b.periodEnd));
  }

  /// Monta a série de [documentos] da CVM, mesclada com [mercado].
  ///
  /// - [ancorada]: `true` para a série de doze meses no trimestre mais recente
  ///   (A1.8); `false` para a série de DFPs (A1.7).
  /// - [publicado]: a regra de publicidade da cascata — `PointInTimeView.
  ///   isPublished` — para que ela seja uma só.
  ///
  /// **A mescla nunca olha para a frente.** Um ponto terminado em junho é
  /// completado com o último exercício de mercado encerrado **até** junho; o de
  /// dezembro do mesmo ano ainda não existia.
  ///
  /// **Na série anual**, o exercício que só o mercado tem continua entrando.
  /// **Na ancorada, não**: um dezembro no meio de junhos é a mistura de âncoras
  /// que a série existe para evitar.
  ///
  /// Sem documento da CVM utilizável, devolve a série de mercado intacta.
  static CvmSeriesResult build({
    required List<CvmPeriodDocument> documentos,
    required List<FundamentalsSnapshot> mercado,
    required DateTime asOf,
    required bool Function(FundamentalsSnapshot) publicado,
    required bool ancorada,
  }) {
    final doMercado = [...mercado]
      ..sort((a, b) => a.fiscalPeriodEnd.compareTo(b.fiscalPeriodEnd));

    // **Só documento publicado na data**, nas duas séries. A DFP recebida
    // depois de [asOf] ocupava o ano na mescla: o exercício de mercado daquele
    // ano, publicado de fato, era descartado, e a cascata depois removia o
    // ponto mesclado por ser do futuro — o ano sumia. USIM3 em 04/09/2024:
    // DFP de 2023 reapresentada, com a versão ingerida recebida em 16/01/2025,
    // e avaliação feita sobre 2022 (decisão 78).
    //
    // **E só a versão vigente de cada um** (item B8): com as versões antigas
    // na lista, a coorte lê o número que era público na data, e não o
    // reapresentado depois.
    final emVigor = vigentes(documentos, publicado);
    final daCvm = ancorada
        ? TrailingTwelveMonths.serieAncorada(emVigor,
            asOf: asOf, publicado: publicado)
        : [
            for (final d in emVigor)
              if (d.kind == CvmDocumentKind.dfp) d.current,
          ];
    if (daCvm.isEmpty) {
      return CvmSeriesResult(
        series: doMercado,
        anchoredOnQuarter: false,
        provenance: const {},
      );
    }
    daCvm.sort((a, b) => a.fiscalPeriodEnd.compareTo(b.fiscalPeriodEnd));

    FundamentalsSnapshot? mercadoAte(DateTime fim) {
      FundamentalsSnapshot? m;
      final limite = fim.add(const Duration(days: folgaDias));
      for (final s in doMercado) {
        if (!s.fiscalPeriodEnd.isAfter(limite)) m = s;
      }
      return m;
    }

    final out = <FundamentalsSnapshot>[];
    final anos = <int>{};
    final origem = <FieldSource, int>{};
    for (final c in daCvm) {
      final merged =
          FundamentalsMerge.merge(cvm: c, mercado: mercadoAte(c.fiscalPeriodEnd));
      if (merged == null) continue;
      out.add(merged.snapshot);
      anos.add(c.fiscalPeriodEnd.year);
      merged.provenance.contagem
          .forEach((k, v) => origem[k] = (origem[k] ?? 0) + v);
    }

    final ancoradaEmTrimestre =
        ancorada && TrailingTwelveMonths.isAnchoredOnQuarter(daCvm, documentos);
    if (!ancoradaEmTrimestre) {
      for (final s in doMercado) {
        if (!anos.contains(s.fiscalPeriodEnd.year)) out.add(s);
      }
      out.sort((a, b) => a.fiscalPeriodEnd.compareTo(b.fiscalPeriodEnd));
    }

    return CvmSeriesResult(
      series: List.unmodifiable(out),
      anchoredOnQuarter: ancoradaEmTrimestre,
      provenance: Map.unmodifiable(origem),
    );
  }
}

/// Quem é instituição financeira, para a Porta 1.
library;

import 'cyclical_sectors.dart';

/// Setores cujo passivo oneroso é insumo do negócio, e não financiamento.
///
/// **A lista é declarada, não inferida**, como a de [CyclicalSectors]. Aceita
/// as duas taxonomias que chegam ao motor:
///
/// - a **oficial da B3** (item A5, decisão 87): setor `Financeiro` e um dos
///   subsetores de [officialSubsectors];
/// - a da **fonte de preços**, que ainda é o recuo quando a B3 não classifica o
///   emissor: a chave [sourceKey].
///
/// **O setor `Financeiro` inteiro não serve.** A B3 põe nele a exploração de
/// imóveis — shopping centers como ALOS3 e MULT3, cujo passivo é financiamento
/// de verdade — e as holdings diversificadas, como ITSA4, que não captam
/// depósito. Mandá-las à via do acionista sem ponte de dívida seria o erro que
/// a Porta 1 existe para evitar, ao contrário.
abstract final class FinancialSectors {
  /// Chave do setor financeiro na taxonomia do perfil da fonte de preços.
  static const String sourceKey = 'servicos-financeiros';

  /// Chave do setor econômico `Financeiro` da B3.
  static const String officialSectorKey = 'financeiro';

  /// Subsetores da B3 em que depósito, captação, reserva técnica ou caixa de
  /// clientes são matéria-prima: bancos, seguradoras, resseguradora, bolsa e
  /// serviços financeiros.
  static const List<String> officialSubsectors = [
    'intermediarios financeiros',
    'previdencia e seguros',
    'servicos financeiros diversos',
  ];

  /// `true` quando o ativo entra na Porta 1.
  ///
  /// - [sectorKey]: chave setorial, já em minúsculas.
  /// - [industry]: subsetor, como publicado — na taxonomia oficial,
  ///   "Subsetor / Segmento".
  static bool isFinancial({String? sectorKey, String? industry}) {
    final chave = sectorKey?.trim().toLowerCase();
    if (chave == sourceKey) return true;
    if (chave != officialSectorKey) return false;
    final sub = CyclicalSectors.normalize(industry);
    for (final s in officialSubsectors) {
      if (sub.startsWith(s)) return true;
    }
    return false;
  }
}

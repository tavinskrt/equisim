import 'dart:convert';

import 'package:equisim_core/equisim_core.dart';

/// Fundamentos do aplicativo com a demonstração da CVM mesclada (item A1.9).
///
/// **Decora** o repositório de mercado em vez de substituí-lo: preço, valor de
/// mercado e a contagem corrente continuam vindo de lá, e a CVM entra campo a
/// campo por `CvmSeries` — a mesma montagem que a validação usa, e não uma
/// cópia dela.
///
/// **De onde vêm os documentos.** De um pacote versionado com o aplicativo,
/// gerado por `tool/cvm_empacotar.dart` a partir da base ingerida (decisão 80).
/// A CVM não é API de tempo real — publica arquivos anuais de centenas de
/// megabytes —, e levar a ingestão ao dispositivo seria baixar 750 MB para ler
/// 375 tickers.
///
/// **Sem pacote, a avaliação segue — e diz que seguiu sem ele.** Pacote
/// ausente, corrompido ou de versão desconhecida não derruba a avaliação: ela
/// volta a ter só a fonte de mercado. Mas isso deixou de ser silencioso
/// (item A1.10): [coverageNote] devolve a ressalva que a tela mostra.
class CvmFundamentalsRepository implements FundamentalsRepository {
  /// Repositório de mercado decorado.
  final FundamentalsRepository market;

  /// Lê o conteúdo do pacote. No aplicativo, `rootBundle.loadString`; em teste,
  /// uma string fixa.
  final Future<String> Function() loadPackage;

  /// Data da avaliação. Recebida por função para que o repositório não chame
  /// o relógio por conta própria.
  final DateTime Function() today;

  /// Usa a série ancorada no trimestre (decisão 73).
  ///
  /// **Desligada por padrão**, e a razão está medida: a série ancorada move a
  /// ordenação de metade do universo (correlação de postos de 0,683 contra a
  /// anual, decisão 78), e se isso é informação ou ruído só a coorte
  /// trimestral dirá.
  final bool anchored;

  /// Idade, em dias, a partir da qual o pacote é declarado defasado.
  ///
  /// A DFP sai até o fim de março e o ITR até 45 dias depois do trimestre: um
  /// pacote com mais de cem dias perdeu, com certeza, um ciclo de entrega.
  static const int maxAgeDays = 100;

  /// Declara o repositório.
  CvmFundamentalsRepository({
    required this.market,
    required this.loadPackage,
    required this.today,
    this.anchored = false,
  });

  /// A **leitura em curso**, e não o resultado dela: avaliações pedidas ao
  /// mesmo tempo esperam a mesma leitura, em vez de cada uma decodificar os
  /// 9 MB do pacote na thread da interface.
  Future<_Package>? _package;

  Future<_Package> _loaded() => _package ??= _read();

  Future<_Package> _read() async {
    final String raw;
    try {
      raw = await loadPackage();
    } on Object {
      return const _Package.missing();
    }
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        return const _Package.unreadable('o conteúdo não é um objeto JSON');
      }
      if (json['versao'] != CvmDocumentCodec.version) {
        return _Package.unreadable(
          'versão ${json['versao']}, e este leitor conhece a '
          '${CvmDocumentCodec.version}',
        );
      }
      final documents = CvmDocumentCodec.decodePackage(json);
      if (documents.isEmpty) {
        return const _Package.unreadable('o pacote não traz ativo nenhum');
      }
      final generated = DateTime.tryParse('${json['geradoEm']}');
      return _Package(documents, generated);
    } on FormatException {
      return const _Package.unreadable('o JSON é inválido');
    }
  }

  /// A ressalva que a avaliação de [ticker] deve levar, ou `null`.
  ///
  /// Texto de narrativa, como os avisos da cascata: é o que a tela de
  /// avaliação mostra no cartão de ressalvas.
  Future<String?> coverageNote(Ticker ticker) async {
    final p = await _loaded();
    final t = ticker.value;
    if (p.missing) {
      return 'Este build não trouxe o pacote de demonstrações da CVM: os '
          'fundamentos de $t vêm só da fonte de mercado, sem a data de '
          'recebimento observada nem a ação em tesouraria.';
    }
    if (p.reason != null) {
      return 'O pacote de demonstrações da CVM deste build não pôde ser lido '
          '— ${p.reason}. Os fundamentos de $t vêm só da fonte de mercado.';
    }
    final docs = p.documents[t];
    final date = p.generatedAt == null ? null : _fmt(p.generatedAt!);
    if (docs == null || docs.isEmpty) {
      return 'O pacote da CVM${date == null ? '' : ' de $date'} não traz '
          'demonstração de $t: os fundamentos vêm só da fonte de mercado.';
    }
    final generated = p.generatedAt;
    if (generated != null) {
      final age = _day(today()).difference(_day(generated)).inDays;
      if (age > maxAgeDays) {
        return 'O pacote da CVM é de $date, há $age dias: demonstrações de '
            '$t entregues depois disso não entram nesta avaliação.';
      }
    }
    return null;
  }

  static DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker ticker) async {
    final base = await market.history(ticker);
    if (base.isErr) return base;
    final documents = (await _loaded()).documents[ticker.value];
    if (documents == null || documents.isEmpty) return base;

    final assembled = CvmSeries.build(
      documents: documents,
      market: base.unwrap(),
      published: PointInTimeView(today()).isPublished,
      anchored: anchored,
    );
    return Ok(assembled.series);
  }

  @override
  Future<Result<Asset>> profile(Ticker ticker) => market.profile(ticker);

  @override
  Future<Result<List<Ticker>>> universe() => market.universe();
}

/// O pacote lido, ou o motivo de não ter sido.
class _Package {
  final Map<String, List<CvmPeriodDocument>> documents;
  final DateTime? generatedAt;
  final bool missing;
  final String? reason;

  const _Package(this.documents, this.generatedAt)
      : missing = false,
        reason = null;

  const _Package.missing()
      : documents = const {},
        generatedAt = null,
        missing = true,
        reason = null;

  const _Package.unreadable(String this.reason)
      : documents = const {},
        generatedAt = null,
        missing = false;
}

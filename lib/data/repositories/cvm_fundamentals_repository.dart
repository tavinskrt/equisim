import 'dart:convert';

import 'package:equisim_core/equisim_core.dart';

/// Situação do pacote da CVM para um ativo.
enum CvmCoverage {
  /// O pacote foi lido e traz documentos do ativo.
  coberto,

  /// O pacote foi lido, e não traz o ativo — sem ponte ticker↔CNPJ.
  semDocumentos,

  /// O pacote existe e não pôde ser lido: JSON inválido ou versão que este
  /// leitor não conhece.
  pacoteIlegivel,

  /// O build não trouxe o pacote.
  pacoteAusente,
}

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
  final FundamentalsRepository mercado;

  /// Lê o conteúdo do pacote. No aplicativo, `rootBundle.loadString`; em teste,
  /// uma string fixa.
  final Future<String> Function() carregarPacote;

  /// Data da avaliação. Recebida por função para que o repositório não chame
  /// o relógio por conta própria.
  final DateTime Function() hoje;

  /// Usa a série ancorada no trimestre (decisão 73).
  ///
  /// **Desligada por padrão**, e a razão está medida: a série ancorada move a
  /// ordenação de metade do universo (correlação de postos de 0,683 contra a
  /// anual, decisão 78), e se isso é informação ou ruído só a coorte
  /// trimestral dirá.
  final bool ancorada;

  /// Idade, em dias, a partir da qual o pacote é declarado defasado.
  ///
  /// A DFP sai até o fim de março e o ITR até 45 dias depois do trimestre: um
  /// pacote com mais de cem dias perdeu, com certeza, um ciclo de entrega.
  static const int idadeMaximaDias = 100;

  /// Declara o repositório.
  CvmFundamentalsRepository({
    required this.mercado,
    required this.carregarPacote,
    required this.hoje,
    this.ancorada = false,
  });

  /// A **leitura em curso**, e não o resultado dela: avaliações pedidas ao
  /// mesmo tempo esperam a mesma leitura, em vez de cada uma decodificar os
  /// 9 MB do pacote na thread da interface.
  Future<_Pacote>? _pacote;

  Future<_Pacote> _lido() => _pacote ??= _ler();

  Future<_Pacote> _ler() async {
    final String bruto;
    try {
      bruto = await carregarPacote();
    } on Object {
      return const _Pacote.ausente();
    }
    try {
      final json = jsonDecode(bruto);
      if (json is! Map<String, dynamic>) {
        return const _Pacote.ilegivel('o conteúdo não é um objeto JSON');
      }
      if (json['versao'] != CvmDocumentCodec.versao) {
        return _Pacote.ilegivel(
          'versão ${json['versao']}, e este leitor conhece a '
          '${CvmDocumentCodec.versao}',
        );
      }
      final documentos = CvmDocumentCodec.decodePackage(json);
      if (documentos.isEmpty) {
        return const _Pacote.ilegivel('o pacote não traz ativo nenhum');
      }
      final gerado = DateTime.tryParse('${json['geradoEm']}');
      return _Pacote(documentos, gerado);
    } on FormatException {
      return const _Pacote.ilegivel('o JSON é inválido');
    }
  }

  /// Situação do pacote para [ticker].
  Future<CvmCoverage> coverageOf(Ticker ticker) async {
    final p = await _lido();
    if (p.ausente) return CvmCoverage.pacoteAusente;
    if (p.motivo != null) return CvmCoverage.pacoteIlegivel;
    final docs = p.documentos[ticker.value];
    return docs == null || docs.isEmpty
        ? CvmCoverage.semDocumentos
        : CvmCoverage.coberto;
  }

  /// A ressalva que a avaliação de [ticker] deve levar, ou `null`.
  ///
  /// Texto de narrativa, como os avisos da cascata: é o que a tela de
  /// avaliação mostra no cartão de ressalvas.
  Future<String?> coverageNote(Ticker ticker) async {
    final p = await _lido();
    final t = ticker.value;
    if (p.ausente) {
      return 'Este build não trouxe o pacote de demonstrações da CVM: os '
          'fundamentos de $t vêm só da fonte de mercado, sem a data de '
          'recebimento observada nem a ação em tesouraria.';
    }
    if (p.motivo != null) {
      return 'O pacote de demonstrações da CVM deste build não pôde ser lido '
          '— ${p.motivo}. Os fundamentos de $t vêm só da fonte de mercado.';
    }
    final docs = p.documentos[t];
    final data = p.geradoEm == null ? null : _fmt(p.geradoEm!);
    if (docs == null || docs.isEmpty) {
      return 'O pacote da CVM${data == null ? '' : ' de $data'} não traz '
          'demonstração de $t: os fundamentos vêm só da fonte de mercado.';
    }
    final gerado = p.geradoEm;
    if (gerado != null) {
      final idade = _dia(hoje()).difference(_dia(gerado)).inDays;
      if (idade > idadeMaximaDias) {
        return 'O pacote da CVM é de $data, há $idade dias: demonstrações de '
            '$t entregues depois disso não entram nesta avaliação.';
      }
    }
    return null;
  }

  static DateTime _dia(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker ticker) async {
    final base = await mercado.history(ticker);
    if (base.isErr) return base;
    final documentos = (await _lido()).documentos[ticker.value];
    if (documentos == null || documentos.isEmpty) return base;

    final asOf = hoje();
    final montada = CvmSeries.build(
      documentos: documentos,
      mercado: base.unwrap(),
      asOf: asOf,
      publicado: PointInTimeView(asOf).isPublished,
      ancorada: ancorada,
    );
    return Ok(montada.series);
  }

  @override
  Future<Result<Asset>> profile(Ticker ticker) => mercado.profile(ticker);

  @override
  Future<Result<List<Ticker>>> universe() => mercado.universe();
}

/// O pacote lido, ou o motivo de não ter sido.
class _Pacote {
  final Map<String, List<CvmPeriodDocument>> documentos;
  final DateTime? geradoEm;
  final bool ausente;
  final String? motivo;

  const _Pacote(this.documentos, this.geradoEm)
      : ausente = false,
        motivo = null;

  const _Pacote.ausente()
      : documentos = const {},
        geradoEm = null,
        ausente = true,
        motivo = null;

  const _Pacote.ilegivel(String this.motivo)
      : documentos = const {},
        geradoEm = null,
        ausente = false;
}

/// Formato compacto dos documentos da CVM, para empacotar no aplicativo.
///
/// **Por que existe.** A base ingerida tem 43 MB para 1.224 companhias, e o
/// aplicativo precisa só das 375 do universo, só dos campos que o motor lê. O
/// formato usa chaves curtas, omite campo nulo e grava número sem casas quando
/// ele é inteiro — os valores da CVM são inteiros em milhares de reais.
///
/// **Por que mora no núcleo.** A ferramenta que empacota e o repositório que lê
/// no aplicativo precisam concordar byte a byte sobre o formato. Duas cópias
/// divergiriam na primeira mudança de campo, e a divergência não quebraria
/// nada: o campo sumiria em silêncio.
library;

import '../../entities/fundamentals.dart';
import '../../value_objects/ticker.dart';
import 'trailing_twelve_months.dart';

/// Leitura e escrita do formato compacto.
abstract final class CvmDocumentCodec {
  /// Versão do formato. Muda quando uma chave muda de significado.
  static const int versao = 1;

  /// Chave curta → leitor do campo no snapshot.
  static final Map<String, double? Function(FundamentalsSnapshot)> _leitores = {
    'rev': (s) => s.totalRevenue,
    'ebit': (s) => s.ebit,
    'ebitda': (s) => s.ebitda,
    'ni': (s) => s.netIncome,
    'ibt': (s) => s.incomeBeforeTax,
    'tax': (s) => s.incomeTaxExpense,
    'ocf': (s) => s.operatingCashFlow,
    'icf': (s) => s.investmentCashFlow,
    'cash': (s) => s.cash,
    'sti': (s) => s.shortTermInvestments,
    'std': (s) => s.shortTermDebt,
    'ltd': (s) => s.longTermDebt,
    'eq': (s) => s.totalStockholderEquity,
    'ppe': (s) => s.propertyPlantEquipment,
    'intg': (s) => s.intangibleAssets,
    'tca': (s) => s.totalCurrentAssets,
    'cl': (s) => s.currentLiabilities,
    'mi': (s) => s.minorityInterest,
    'ta': (s) => s.totalAssets,
    'tf': (s) => s.treasuryFraction,
  };

  static String _dia(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime? _data(Object? v) {
    if (v is! String || v.length < 10) return null;
    final p = v.substring(0, 10).split('-');
    if (p.length != 3) return null;
    final y = int.tryParse(p[0]), m = int.tryParse(p[1]), d = int.tryParse(p[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime.utc(y, m, d);
  }

  /// Tolerância para gravar um valor como inteiro.
  ///
  /// Os valores da CVM são reais inteiros por origem — o arquivo publica em
  /// milhares, e a ingestão multiplica. Um bilionésimo de real fica ordens de
  /// grandeza abaixo do centavo, e absorve o resíduo de ponto flutuante da
  /// multiplicação sem comparar `double` por igualdade.
  static const double toleranciaInteiro = 1e-9;

  /// Número compacto: inteiro quando é inteiro, e com casas só quando precisa.
  static Object _num(double v) =>
      v.abs() < 9e15 && (v - v.roundToDouble()).abs() < toleranciaInteiro
          ? v.round()
          : v;

  static Map<String, Object> _campos(FundamentalsSnapshot s) => {
        for (final e in _leitores.entries)
          if (e.value(s) case final double v when v.isFinite) e.key: _num(v),
      };

  static FundamentalsSnapshot _snapshot(
    Ticker t,
    DateTime fim,
    Map<String, dynamic> c, {
    DateTime? recebido,
  }) {
    double? n(String k) => (c[k] as num?)?.toDouble();
    return FundamentalsSnapshot(
      ticker: t,
      fiscalPeriodEnd: fim,
      receiptDate: recebido,
      totalRevenue: n('rev'),
      ebit: n('ebit'),
      ebitda: n('ebitda'),
      netIncome: n('ni'),
      incomeBeforeTax: n('ibt'),
      incomeTaxExpense: n('tax'),
      operatingCashFlow: n('ocf'),
      investmentCashFlow: n('icf'),
      cash: n('cash'),
      shortTermInvestments: n('sti'),
      shortTermDebt: n('std'),
      longTermDebt: n('ltd'),
      totalStockholderEquity: n('eq'),
      propertyPlantEquipment: n('ppe'),
      intangibleAssets: n('intg'),
      totalCurrentAssets: n('tca'),
      currentLiabilities: n('cl'),
      minorityInterest: n('mi'),
      totalAssets: n('ta'),
      treasuryFraction: n('tf'),
    );
  }

  /// Um documento no formato compacto.
  static Map<String, Object> encode(CvmPeriodDocument d) => {
        'k': d.kind == CvmDocumentKind.dfp ? 'D' : 'I',
        's': _dia(d.periodStart),
        'e': _dia(d.periodEnd),
        if (d.current.receiptDate != null) 'r': _dia(d.current.receiptDate!),
        'c': _campos(d.current),
        if (d.prior != null) 'p': _campos(d.prior!),
        if (d.priorStart != null) 'ps': _dia(d.priorStart!),
      };

  /// Lê um documento, ou `null` quando ele não tem o mínimo para existir.
  static CvmPeriodDocument? decode(Ticker t, Map<String, dynamic> m) {
    final ini = _data(m['s']);
    final fim = _data(m['e']);
    final c = m['c'];
    if (ini == null || fim == null || c is! Map<String, dynamic>) return null;
    final kind = switch (m['k']) {
      'D' => CvmDocumentKind.dfp,
      'I' => CvmDocumentKind.itr,
      _ => null,
    };
    if (kind == null) return null;
    final p = m['p'];
    return CvmPeriodDocument(
      kind: kind,
      periodStart: ini,
      periodEnd: fim,
      current: _snapshot(t, fim, c, recebido: _data(m['r'])),
      prior: p is Map<String, dynamic>
          ? _snapshot(t, DateTime.utc(fim.year - 1, fim.month, fim.day), p)
          : null,
      priorStart: _data(m['ps']),
    );
  }

  /// O pacote inteiro: versão, data de geração e documentos por ticker.
  static Map<String, Object> encodePackage(
    Map<String, List<CvmPeriodDocument>> porTicker, {
    required DateTime geradoEm,
  }) =>
      {
        'versao': versao,
        'geradoEm': _dia(geradoEm),
        'tickers': {
          for (final e in porTicker.entries)
            e.key: [for (final d in e.value) encode(d)],
        },
      };

  /// Lê o pacote. Devolve mapa vazio para versão desconhecida — um formato que
  /// o leitor não entende não é lido pela metade.
  static Map<String, List<CvmPeriodDocument>> decodePackage(
    Map<String, dynamic> pacote,
  ) {
    if (pacote['versao'] != versao) return const {};
    final tickers = pacote['tickers'];
    if (tickers is! Map<String, dynamic>) return const {};
    final out = <String, List<CvmPeriodDocument>>{};
    for (final e in tickers.entries) {
      final t = Ticker.tryParse(e.key);
      final docs = e.value;
      if (t == null || docs is! List) continue;
      out[e.key] = [
        for (final d in docs)
          if (d is Map<String, dynamic>)
            if (decode(t, d) case final CvmPeriodDocument doc) doc,
      ];
    }
    return out;
  }
}

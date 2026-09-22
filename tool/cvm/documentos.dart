// Leitura da base ingerida (`data/cvm_exercicios.json`) para documentos do
// núcleo.
//
// Compartilhado por `cvm_ligar.dart` e `cvm_empacotar.dart`: a conversão da
// linha da ingestão para `CvmPeriodDocument` já teve dois defeitos — a contagem
// absoluta de ações (decisão 70) e o "anual é dezembro" (decisão 72) —, e duas
// cópias dela voltariam a divergir.
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

DateTime? _data(Object? s) => s is String && s.length >= 10
    ? DateTime.tryParse('${s.substring(0, 10)}T00:00:00Z')
    : null;

double? _n(Map<String, dynamic> e, String k) => (e[k] as num?)?.toDouble();

FundamentalsSnapshot _snap(
  Ticker t,
  DateTime fim,
  Map<String, dynamic> e, {
  DateTime? recebido,
  double? fracaoTesouraria,
}) {
  final ebit = _n(e, 'ebit');
  final da = _n(e, 'depreciacaoEAmortizacao');
  return FundamentalsSnapshot(
    ticker: t,
    fiscalPeriodEnd: fim,
    receiptDate: recebido,
    totalRevenue: _n(e, 'receita'),
    ebit: ebit,
    // EBITDA da própria CVM, para que o D&A dos doze meses se some junto.
    ebitda: (ebit != null && da != null) ? ebit + da : null,
    netIncome: _n(e, 'lucroLiquido'),
    incomeBeforeTax: _n(e, 'resultadoAntesDosTributos'),
    incomeTaxExpense: _n(e, 'tributos'),
    operatingCashFlow: _n(e, 'caixaOperacional'),
    investmentCashFlow: _n(e, 'caixaDeInvestimento'),
    cash: _n(e, 'caixa'),
    shortTermInvestments: _n(e, 'aplicacoesFinanceiras'),
    shortTermDebt: _n(e, 'dividaDeCurtoPrazo'),
    longTermDebt: _n(e, 'dividaDeLongoPrazo'),
    totalStockholderEquity: _n(e, 'patrimonioLiquido'),
    propertyPlantEquipment: _n(e, 'imobilizado'),
    intangibleAssets: _n(e, 'intangivel'),
    totalCurrentAssets: _n(e, 'ativoCirculante'),
    currentLiabilities: _n(e, 'passivoCirculante'),
    minorityInterest: _n(e, 'naoControladores'),
    totalAssets: _n(e, 'ativoTotal'),
    treasuryFraction: fracaoTesouraria,
  );
}

/// As versões anteriores de cada documento, gravadas por `cvm_ingerir.dart`.
const versoesAntigas = 'data/cvm_versoes.json';

/// Documentos por ticker, da base ingerida.
///
/// - [tickersPorCnpj]: tickers a mais para cada CNPJ. A ingestão só liga
///   ticker à companhia do universo de hoje; as deslistadas (item C1b) chegam
///   com a lista vazia, e o ticker delas vem da ponte do COTAHIST.
///
/// - [comVersoesAntigas]: acrescenta as versões anteriores de cada documento,
///   de `data/cvm_versoes.json` (item B8), cada uma com a data de recebimento
///   dela. Quem lê a lista precisa escolher a vigente — `CvmSeries.build` o
///   faz por `CvmSeries.vigentes`. Sem o arquivo, avisa e segue com a última
///   versão, que é o comportamento anterior ao B8.
///
/// Encerra o processo com código 2 quando a base não existe, dizendo o que
/// rodar antes.
Map<String, List<CvmPeriodDocument>> carregarDocumentos(
  String caminho, {
  Set<String>? soTickers,
  Map<String, List<String>>? tickersPorCnpj,
  bool comVersoesAntigas = false,
}) {
  final f = File(caminho);
  if (!f.existsSync()) {
    stderr.writeln('$caminho não existe. Rode antes:');
    stderr.writeln('  dart run tool/cvm_ingerir.dart data/cvm');
    exit(2);
  }
  final linhas = [
    ...(jsonDecode(f.readAsStringSync()) as List).cast<Map<String, dynamic>>(),
  ];
  if (comVersoesAntigas) {
    final v = File(versoesAntigas);
    if (v.existsSync()) {
      linhas.addAll(
          (jsonDecode(v.readAsStringSync()) as List).cast<Map<String, dynamic>>());
    } else {
      stderr.writeln('AVISO: $versoesAntigas não existe — as coortes leem a '
          'última versão de cada documento (item B8). Rode antes:');
      stderr.writeln('  python tool/cvm_versoes_baixar.py');
      stderr.writeln('  dart run tool/cvm_ingerir.dart data/cvm');
    }
  }
  final out = <String, List<CvmPeriodDocument>>{};
  for (final e in linhas) {
    final tickers = [
      ...(e['tickers'] as List).cast<String>(),
      ...?tickersPorCnpj?[e['cnpj']],
    ];
    if (tickers.isEmpty) continue;
    final fim = _data(e['fimDoExercicio']);
    final ini = _data(e['inicioDoPeriodo']);
    if (fim == null || ini == null) continue;
    final kind =
        e['documento'] == 'DFP' ? CvmDocumentKind.dfp : CvmDocumentKind.itr;

    final integ = _n(e, 'acoesIntegralizadas');
    final tes = _n(e, 'acoesEmTesouraria');
    // Decisão 70: só a fração, porque a escala da contagem varia por
    // declarante.
    final fracao =
        (integ != null && integ > 0 && tes != null && tes >= 0 && tes < integ)
            ? tes / integ
            : null;
    final ant = e['anterior'] as Map<String, dynamic>?;

    for (final t in tickers) {
      if (soTickers != null && !soTickers.contains(t)) continue;
      final tk = Ticker.parse(t);
      out.putIfAbsent(t, () => []).add(CvmPeriodDocument(
            kind: kind,
            periodStart: ini,
            periodEnd: fim,
            current: _snap(tk, fim, e,
                recebido: _data(e['recebidoEm']), fracaoTesouraria: fracao),
            prior: ant == null
                ? null
                : _snap(tk, DateTime.utc(fim.year - 1, fim.month, fim.day), ant),
            priorStart: _data(ant?['inicioDoPeriodo']),
          ));
    }
  }
  return out;
}

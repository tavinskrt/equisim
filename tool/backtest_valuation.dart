// Validação preditiva do motor de avaliação, *point-in-time*.
//
// **A pergunta.** O potencial que o motor apura ordena o retorno que veio
// depois? Sem essa medição, o motor tem consistência interna e cobertura
// declarada — e nenhuma evidência de que serve para decidir.
//
// **Como.** Para cada data de coorte, a cascata roda com o que era público
// naquele dia: exercícios filtrados por `PointInTimeView`, preço e beta na
// janela que termina ali, âncoras macro resolvidas naquela data. O potencial
// resultante é confrontado com o retorno realizado nos 12 e nos 36 meses
// seguintes — 36 é o horizonte de convergência da decisão 26.
//
// **Contra o quê.** Sozinho, um coeficiente de correlação não diz se a
// sofisticação se paga. O potencial é medido lado a lado com dois fatores
// ingênuos que usam os mesmos dados e nenhuma modelagem: o valor patrimonial
// sobre o preço e o lucro sobre o preço. Se o motor não os supera, a cascata
// inteira está cobrando um custo de complexidade que não entrega.
//
// **Vieses que esta medição NÃO remove**, e que o relatório declara:
//
// 1. *Sobrevivência.* Sem `--com-deslistadas`, o universo é o que está listado
//    hoje. Com ele, entram as companhias da ponte do A3.2 (item C1b) — e as que
//    a fonte de preços não traz, como a Tupy (item C1d).
// 2. *Reapresentação.* Os exercícios vêm como a fonte os publica hoje, não
//    como estavam no dia da coorte (B8).
// 3. *Provento.* O retorno de referência continua o de preço, e ao lado dele
//    sai o **retorno total** — `ret12tot` e `ret36tot` —, com os proventos da
//    B3 reinvestidos na data ex (item A4, decisão 89).
//
// **Duas montagens.** `mercado` é a das medições de 11/09/2026: só a fonte de
// preços, com a taxa de dois pontos — e com o defeito de base descrito abaixo,
// mantido para reproduzir aquelas medições. `aplicativo` é a montagem do
// aplicativo **na data de cada coorte**, peça a peça:
//
// - a curva do Tesouro daquele dia (decisão 74);
// - a CVM mesclada, com os documentos recebidos até ali (decisões 69 a 81) —
//   pela série de DFPs, que é o padrão, e pela ancorada no trimestre ao lado;
// - o setor da B3 (decisão 87);
// - o prazo das outorgas do Formulário de Referência recebido até ali
//   (decisão 88, `tool/cvm/outorgas_por_data.dart`);
// - o beta sobre retorno total, com os proventos da B3 (decisão 89);
// - **o preço, a contagem e o valor de mercado na base da data** (item C3,
//   `tool/coortes/base_da_data.dart`): a série da fonte vem ajustada por todo
//   evento até hoje, e a coorte a multiplicava pela contagem do exercício, na
//   base daquele ano. Agora a série é levada à base da data pelo COTAHIST, a
//   contagem é a do Formulário de Referência na data — corrente e oficial, o
//   papel do registro da B3 no aplicativo — e o valor de mercado é o da
//   companhia, espécie a espécie, que é o que a razão de unidade mede.
//
// Na montagem `aplicativo` cada linha leva também o que o C2 e o C0 medem: a
// banda dos cenários discretos, os quantis da distribuição de Monte Carlo com
// os sorteios padrão do aplicativo (só nas coortes de 30/09), a liquidez da
// Porta 0 e, para ativo recusado, o potencial sem o corte de liquidez.
//
// **Coortes.** Anuais, em 30/09 de 2018 a 2025, ou trimestrais com
// `--trimestral` (item C1c): o último dia de cada trimestre, de 31/03/2018 a
// 30/09/2025. A primeira é 2018 porque a Porta 0 exige oito exercícios
// publicados, e a CVM começa em 2010.
//
// Uso:
//   dart run tool/backtest_valuation.dart                        # mercado
//   dart run tool/backtest_valuation.dart --montagem aplicativo
//   dart run tool/backtest_valuation.dart --montagem aplicativo \
//       --com-deslistadas --trimestral [--contrafactual-base] [--amostra N]
//
// `--amostra N` limita o universo e as deslistadas aos N primeiros, para
// conferir a montagem em minutos antes da execução inteira; a saída vai para
// `docs/validacao/backtest_amostra.json` e não substitui nenhuma medição.
//
// **A medição do item B46**, sobre a montagem do aplicativo:
//
//   dart run tool/backtest_valuation.dart --montagem aplicativo \
//       --com-deslistadas --trimestral --premio-estatal 0.005,0.01,0.02,0.03
//   python tool/estatais_backtest.py
//
// `--premio-estatal` avalia de novo cada observação de companhia de controle
// estatal na data (`assets/cvm/controle.json`) com cada prêmio a mais no custo
// do capital próprio, e grava o potencial de cada um no campo
// `potencialComPremioEstatal`; o resto da observação é o da montagem padrão.
// Para conferir em minutos, `--so-estatais` observa só elas — o prior do beta
// continua resolvido sobre o universo inteiro — e não lê deslistadas; exige
// `--saida`, que troca o arquivo de destino, para não sobrescrever a medição
// oficial.
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'package:equisim/data/repositories/b3_registry_repository.dart';

import 'b3/proventos.dart';
import 'coortes/base_da_data.dart';
import 'coortes/contagem_conferida.dart';
import 'coortes/deslistadas.dart';
import 'coortes/eventos_de_acoes.dart';
import 'curva_ligar.dart' show readTreasury;
import 'cvm/codigos_fca.dart';
import 'cvm/documentos.dart';
import 'cvm/emissoes_fre.dart';
import 'cvm/outorgas_por_data.dart';
import 'validation/context.dart';

/// CVM mesclada à série de mercado já reescalada, com o que era público na
/// data da coorte.
class _CvmAtDate implements FundamentalsRepository {
  _CvmAtDate(
    this.inner,
    this.hist,
    this.docs,
    this.date, {
    this.anchored = false,
  });
  final FundamentalsRepository inner;
  final List<FundamentalsSnapshot> hist;
  final List<CvmPeriodDocument>? docs;
  final DateTime date;

  /// Série de doze meses ancorada no trimestre mais recente (A1.8, C1c).
  final bool anchored;

  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker t) async {
    final ownDocs = docs;
    if (ownDocs == null || ownDocs.isEmpty) return Ok(hist);
    return Ok(
      CvmSeries.build(
        documents: ownDocs,
        market: hist,
        published: PointInTimeView(date).isPublished,
        anchored: anchored,
      ).series,
    );
  }

  @override
  Future<Result<Asset>> profile(Ticker t) => inner.profile(t);

  @override
  Future<Result<List<Ticker>>> universe() => inner.universe();
}

/// Sorteios da distribuição, iguais ao padrão do aplicativo.
const _draws = 10000;

/// Índice buscado uma vez e reaproveitado.
///
/// `BenchmarkRepositoryImpl` vai à rede a cada chamada, e o backtest a faria
/// milhares de vezes.
class _MemoBenchmark implements BenchmarkRepository {
  _MemoBenchmark(this.inner);
  final BenchmarkRepository inner;
  PriceSeries? _full;

  @override
  Future<Result<PriceSeries>> ibovespa(DateRange range) async {
    if (_full == null) {
      final r = await inner.ibovespa(
        DateRange(DateTime(2000, 1, 1), DateTime(2100, 1, 1)),
      );
      if (r.isErr) return r;
      _full = r.unwrap();
    }
    return Ok(
      PriceSeries(
        ticker: _full!.ticker,
        points: _full!.points.where((p) => range.contains(p.date)).toList(),
      ),
    );
  }
}

/// Fundamentos buscados uma vez por ativo e reaproveitados entre coortes.
class _MemoFundamentals implements FundamentalsRepository {
  _MemoFundamentals(this.inner);
  final FundamentalsRepository inner;
  final _hist = <String, Result<List<FundamentalsSnapshot>>>{};
  final _prof = <String, Result<Asset>>{};
  Result<List<Ticker>>? _uni;

  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker t) async =>
      _hist[t.value] ??= await inner.history(t);

  @override
  Future<Result<Asset>> profile(Ticker t) async =>
      _prof[t.value] ??= await inner.profile(t);

  @override
  Future<Result<List<Ticker>>> universe() async =>
      _uni ??= await inner.universe();
}

/// Preços buscados uma vez por ativo, na janela inteira, e recortados em
/// memória para cada coorte.
class _MemoPrices implements PriceRepository {
  _MemoPrices(this.inner);
  final PriceRepository inner;
  final _all = <String, PriceSeries?>{};

  Future<PriceSeries?> _load(Ticker t) async {
    if (_all.containsKey(t.value)) return _all[t.value];
    final r = await inner.daily(
      t,
      DateRange(DateTime(2010, 1, 1), DateTime(2026, 9, 4)),
    );
    return _all[t.value] = r.isOk ? r.unwrap() : null;
  }

  @override
  Future<Result<PriceSeries>> daily(Ticker t, DateRange range) async {
    final s = await _load(t);
    if (s == null) {
      return Err(
        InsufficientData('sem preços de ${t.value}', subject: t.value),
      );
    }
    return Ok(
      PriceSeries(
        ticker: s.ticker,
        points: s.points.where((p) => range.contains(p.date)).toList(),
      ),
    );
  }

  @override
  Future<Result<Map<Ticker, PriceSeries>>> dailyBatch(
    List<Ticker> tickers,
    DateRange range,
  ) async {
    final out = <Ticker, PriceSeries>{};
    for (final t in tickers) {
      final r = await daily(t, range);
      if (r.isOk) out[t] = r.unwrap();
    }
    return Ok(out);
  }

  @override
  Future<Result<PriceSeries>> adjustedCloseRaw(Ticker t, DateRange range) =>
      inner.adjustedCloseRaw(t, range);
}

/// Uma série já montada — a da fonte na base da data da coorte —, recortada
/// pela janela pedida.
class _FixedSeries implements PriceRepository {
  _FixedSeries(this.series);
  final PriceSeries series;

  PriceSeries _slice(DateRange range) => PriceSeries(
    ticker: series.ticker,
    points: series.points.where((p) => range.contains(p.date)).toList(),
  );

  @override
  Future<Result<PriceSeries>> daily(Ticker t, DateRange range) async =>
      Ok(_slice(range));

  @override
  Future<Result<Map<Ticker, PriceSeries>>> dailyBatch(
    List<Ticker> tickers,
    DateRange range,
  ) async => Ok({for (final t in tickers) t: _slice(range)});

  @override
  Future<Result<PriceSeries>> adjustedCloseRaw(Ticker t, DateRange range) =>
      daily(t, range);
}

/// Reescreve o valor de mercado de cada exercício para a escala da data da
/// coorte, **na montagem `mercado`**.
///
/// A fonte repete o valor de mercado **de hoje** em todos os exercícios —
/// conferido: ele não varia entre linhas em nenhum dos 363 ativos do cache.
/// Deixá-lo assim daria ao motor, numa avaliação de 2018, a capitalização de
/// 2026. A reconstrução usa a contagem do exercício vezes o preço da coorte.
///
/// **Carrega o defeito de base do item C3**: o preço da fonte está na base de
/// ações de hoje, e a contagem, na do exercício. Fica assim para reproduzir as
/// medições de 11/09/2026; a montagem `aplicativo` usa [_rescaleAtDate].
List<FundamentalsSnapshot> _rescale(
  List<FundamentalsSnapshot> snaps,
  double priceAtDate,
) => _withMarket(
  snaps,
  current: (s) => s.sharesOutstandingAsOf,
  value: (s) =>
      (s.sharesOutstandingAsOf != null &&
          s.sharesOutstandingAsOf! > 0 &&
          priceAtDate > 0)
      ? s.sharesOutstandingAsOf! * priceAtDate
      : null,
);

/// O valor de mercado e a contagem corrente **da data** em todo exercício
/// (item C3): a contagem do Formulário de Referência e o valor de mercado da
/// companhia espécie a espécie. Sem contagem da data, recua para a contagem do
/// exercício vezes o preço bruto da data — na base certa, e com a razão de
/// unidade de volta a 1 por construção, o que a linha declara.
List<FundamentalsSnapshot> _rescaleAtDate(
  List<FundamentalsSnapshot> snaps, {
  required double? sharesAtDate,
  required double? marketValueOf,
  required double rawPrice,
}) => _withMarket(
  snaps,
  current: (s) => sharesAtDate ?? s.sharesOutstandingAsOf,
  value: (s) {
    if (marketValueOf != null) return marketValueOf;
    final n = s.sharesOutstandingAsOf;
    return (n != null && n > 0 && rawPrice > 0) ? n * rawPrice : null;
  },
);

List<FundamentalsSnapshot> _withMarket(
  List<FundamentalsSnapshot> snaps, {
  required double? Function(FundamentalsSnapshot) current,
  required double? Function(FundamentalsSnapshot) value,
}) {
  return [
    for (final s in snaps)
      FundamentalsSnapshot(
        ticker: s.ticker,
        fiscalPeriodEnd: s.fiscalPeriodEnd,
        totalRevenue: s.totalRevenue,
        ebit: s.ebit,
        ebitda: s.ebitda,
        netIncome: s.netIncome,
        incomeBeforeTax: s.incomeBeforeTax,
        incomeTaxExpense: s.incomeTaxExpense,
        interestExpense: s.interestExpense,
        earningsPerShare: s.earningsPerShare,
        nopat: s.nopat,
        cash: s.cash,
        shortTermInvestments: s.shortTermInvestments,
        shortTermDebt: s.shortTermDebt,
        longTermDebt: s.longTermDebt,
        totalStockholderEquity: s.totalStockholderEquity,
        bookValuePerShare: s.bookValuePerShare,
        propertyPlantEquipment: s.propertyPlantEquipment,
        intangibleAssets: s.intangibleAssets,
        totalCurrentAssets: s.totalCurrentAssets,
        currentLiabilities: s.currentLiabilities,
        realizedShareCapital: s.realizedShareCapital,
        profitReserves: s.profitReserves,
        operatingCashFlow: s.operatingCashFlow,
        investmentCashFlow: s.investmentCashFlow,
        freeCashFlow: s.freeCashFlow,
        // A contagem corrente da fonte sai: ela é de hoje, e na coorte não
        // existia.
        sharesOutstanding: current(s),
        sharesOutstandingAsOf: s.sharesOutstandingAsOf,
        marketCap: value(s),
        enterpriseToEbitda: null,
      ),
  ];
}

double? _priceAt(PriceSeries s, DateTime date) {
  double? last;
  for (final p in s.points) {
    if (p.date.isAfter(date)) break;
    last = p.close;
  }
  return last;
}

double? _adjustedAt(PriceSeries s, DateTime date) {
  double? last;
  for (final p in s.points) {
    if (p.date.isAfter(date)) break;
    last = p.adjustedClose ?? p.close;
  }
  return last;
}

/// Contagem por data e divisão entre espécies de cada listada, gravadas por
/// `tool/b3_deslistadas_contagem.dart` (item C3), com a conferência contra o
/// salto do preço (item B43, decisão 143).
class _ListedCount {
  _ListedCount(this.raw, this.classes);
  final List<CountEntry> raw;
  final CapitalClasses classes;

  ({
    List<({DateTime since, double shares})> accepted,
    List<DiscardedCount> discarded,
  })?
  _checked;

  /// A contagem conferida contra o salto do preço dos [securities] da companhia,
  /// com âncora na mais recente até [until]. A primeira chamada fixa o
  /// resultado: os papéis de uma companhia são os mesmos em toda coorte.
  ({
    List<({DateTime since, double shares})> accepted,
    List<DiscardedCount> discarded,
  })
  checked(Iterable<List<TradingDay>> securities, DateTime until) =>
      _checked ??= checkCount(raw, securities, until: until);

  static Map<String, _ListedCount>? read() {
    final f = File('data/b3/listadas_contagem.json');
    if (!f.existsSync()) return null;
    final out = <String, _ListedCount>{};
    for (final e
        in (jsonDecode(f.readAsStringSync()) as Map<String, dynamic>).entries) {
      final v = e.value as Map<String, dynamic>;
      out[e.key] = _ListedCount([
        for (final p in (v['contagem'] as List).cast<Map<String, dynamic>>())
          (
            since: DateTime.parse('${p['desde']}T00:00:00Z'),
            shares: (p['acoes'] as num).toDouble(),
            source: p['fonte'] as String?,
          ),
      ], CapitalClasses.fromJson(v['classes'] as List?));
    }
    return out;
  }
}

/// A data `meses` depois de [t], no mesmo dia — ou no último dia do mês, quando
/// ele não existe: 31/03 mais três meses é 30/06, e não 01/07.
DateTime _addMonths(DateTime t, int months) {
  final total = t.month - 1 + months;
  final year = t.year + total ~/ 12;
  final month = total % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, t.day > lastDay ? lastDay : t.day);
}

String _day(DateTime d) => d.toIso8601String().substring(0, 10);

/// Arredonda os `double` a seis algarismos significativos, para que a saída
/// trimestral caiba no repositório; nenhuma medição usa mais que isso.
Object? _compact(Object? v) {
  if (v is double) {
    // Zero passa pelo mesmo caminho: `toStringAsPrecision` o devolve zero.
    if (!v.isFinite) return v;
    return double.parse(v.toStringAsPrecision(6));
  }
  if (v is List) return [for (final x in v) _compact(x)];
  if (v is Map) return {for (final e in v.entries) e.key: _compact(e.value)};
  return v;
}

/// Primeira coorte da réplica fora da amostra (decisão 129).
final firstC7Cohort = DateTime(2025, 12, 31);

/// As coortes do C7: o último dia de cada trimestre, de 31/12/2025 até o
/// último que o fim dos dados cobre.
List<DateTime> c7Cohorts(DateTime dataEnd) => [
  for (
    var d = firstC7Cohort;
    !d.isAfter(dataEnd);
    d = DateTime(d.year, d.month + 4, 0)
  )
    d,
];

Future<void> main(List<String> args) async {
  final assemblyIndex = args.indexOf('--montagem');
  final app = assemblyIndex >= 0 && args[assemblyIndex + 1] == 'aplicativo';
  final withDelisted = args.contains('--com-deslistadas');
  final quarterly = args.contains('--trimestral');
  final counterfactualBase = args.contains('--contrafactual-base');
  final sampleIndex = args.indexOf('--amostra');
  final sample = sampleIndex >= 0 ? int.parse(args[sampleIndex + 1]) : null;
  // A medição do item B46: prêmios a mais no Ke das estatais.
  final stateOwnedPremiumIndex = args.indexOf('--premio-estatal');
  final stateOwnedPremiums = stateOwnedPremiumIndex >= 0
      ? [for (final x in args[stateOwnedPremiumIndex + 1].split(',')) double.parse(x)]
      : const <double>[];
  final stateOwnedOnly = args.contains('--so-estatais');
  final outputIndex = args.indexOf('--saida');
  final output = outputIndex >= 0 ? args[outputIndex + 1] : null;
  // **A réplica fora da amostra** (item C7, decisões 129 e 133): as coortes a
  // partir de 31/12/2025, que nenhuma decisão do motor viu, na mesma montagem
  // da amostra do R3. Saem em `data/c7/coortes.json`, e quem as sela é
  // `tool/c7_selar.dart` — este modo não escreve nada versionado.
  final c7 = args.contains('--c7');
  // O fim dos dados é o da base restaurada; a leitura do C7, anos depois,
  // passa a data da base de então para que os retornos das coortes novas
  // existam.
  final endIndex = args.indexOf('--fim-dos-dados');
  final dataEnd = endIndex >= 0
      ? DateTime.parse(args[endIndex + 1])
      : DateTime(2026, 9, 4);
  if ((withDelisted || quarterly || counterfactualBase) && !app) {
    stderr.writeln(
      '--com-deslistadas, --trimestral e --contrafactual-base '
      'exigem --montagem aplicativo',
    );
    exit(2);
  }
  if ((stateOwnedPremiums.isNotEmpty || stateOwnedOnly) && !app ||
      stateOwnedOnly && output == null) {
    stderr.writeln(
      '--premio-estatal e --so-estatais exigem --montagem aplicativo, e '
      '--so-estatais exige --saida',
    );
    exit(2);
  }
  if (c7 && !(app && quarterly && withDelisted) ||
      c7 && (counterfactualBase || sample != null)) {
    stderr.writeln(
      '--c7 é a montagem da amostra do R3: exige --montagem '
      'aplicativo --com-deslistadas --trimestral, e nada mais',
    );
    exit(2);
  }
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  final prices = _MemoPrices(ctx.prices);
  final fundamentals = _MemoFundamentals(ctx.fundamentals);
  final benchmark = _MemoBenchmark(ctx.benchmark);

  // Peças da montagem do aplicativo, lidas uma vez.
  final treasury = app
      ? readTreasury('data/tesouro/precotaxatesourodireto.csv')
      : null;
  final cvmDocs = app
      ? loadDocuments('data/cvm_exercicios.json', withOldVersions: true)
      : null;
  final registry = app
      ? B3RegistryCodec.decodePackage(
          jsonDecode(File('assets/b3/emissores.json').readAsStringSync())
              as Map<String, dynamic>,
        )
      : null;
  // **O prêmio de mercado de cada coorte** (decisão 142): a média de dez anos
  // do prêmio implícito, do pacote que o aplicativo lê. A série é medida
  // trimestre a trimestre, cada um com o dado da data dele, e a média de cada
  // coorte usa só os trimestres até ela.
  final premiumPackage = app
      ? ImpliedPremiumCodec.decode(
          jsonDecode(
                File('assets/mercado/premio_implicito.json').readAsStringSync(),
              )
              as Map<String, dynamic>,
        )
      : null;
  if (app && premiumPackage == null) {
    stderr.writeln(
      'sem assets/mercado/premio_implicito.json utilizável: rode '
      'dart run tool/premio_implicito.dart --so-serie',
    );
    exit(2);
  }
  // O controle acionário de cada emissor, do FCA (item B46): a ressalva da
  // montagem do aplicativo, na data de cada coorte, e a medição do item.
  final control = app && File('assets/cvm/controle.json').existsSync()
      ? ShareholderControlHistory.decode(
          jsonDecode(File('assets/cvm/controle.json').readAsStringSync())
              as Map<String, dynamic>,
        )?.byIssuer
      : null;
  bool stateOwnedAtDate(Ticker x, DateTime d) {
    final p = control?[x.value.substring(0, 4)];
    return p != null &&
        ShareholderControlHistory.at(p, d) == ShareholderControl.state;
  }

  final dividendsPackage = app
      ? CashDividendsCodec.decode(
          jsonDecode(File('assets/b3/proventos.json').readAsStringSync())
              as Map<String, dynamic>,
        )
      : null;
  final grants = app ? GrantsByDate.read() : null;
  if (app && grants == null) {
    stderr.writeln(
      'sem data/cvm/fre: rode python tool/cvm_baixar.py --docs FRE',
    );
    exit(2);
  }
  if (app) {
    // O prazo lido na data de montagem do pacote tem de ser o do pacote.
    final package = ConcessionTermsCodec.decode(
      jsonDecode(File('assets/cvm/outorgas.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    var equal = 0;
    for (final e in package.entries) {
      final parsed = grants!.atDate(e.key, DateTime(2026, 9, 14));
      if (parsed != null && parsed.end == e.value.end) equal++;
    }
    stderr.writeln(
      'outorgas por data contra o pacote: $equal de '
      '${package.length} iguais em 14/09/2026',
    );
  }
  B3Classification? shareClass(Ticker t) =>
      registry?[t.value.length >= 4 ? t.value.substring(0, 4) : '']
          ?.classification;

  // A base da data das listadas (item C3): a ponte ticker → CNPJ, os códigos
  // que a FCA declara e a contagem por data do Formulário de Referência.
  final listedBridge = app
      ? ((jsonDecode(File('docs/validacao/ponte_cvm.json').readAsStringSync())
                    as Map<String, dynamic>)['ponte']
                as Map<String, dynamic>)
            .cast<String, String>()
      : const <String, String>{};
  final fca = app ? FcaCodes.read() : null;
  final listedCounts = app ? _ListedCount.read() : null;
  // Entradas descartadas pela conferência da contagem, por companhia (B43).
  final discardedByCnpj = <String, int>{};
  if (app && listedCounts == null) {
    stderr.writeln(
      'sem data/b3/listadas_contagem.json: rode '
      'dart run tool/b3_deslistadas_contagem.dart',
    );
    exit(2);
  }

  // As deslistadas (item C1b), com o setor da B3 ou o representante do setor da
  // CVM, medido nas listadas.
  Delisted? delisted;
  if (withDelisted) {
    final byCnpj = <String, B3Classification>{};
    for (final e in listedBridge.entries) {
      final c = registry![e.key.length >= 4 ? e.key.substring(0, 4) : '']
          ?.classification;
      if (c != null) byCnpj[e.value] = c;
    }
    delisted = Delisted.read(byCnpj, until: dataEnd);
    if (delisted == null) {
      stderr.writeln(
        'sem data/b3/deslistadas_contagem.json: rode '
        'dart run tool/b3_deslistadas_contagem.dart',
      );
      exit(2);
    }
    final origin = <String, int>{};
    for (final p in delisted.securities.values) {
      origin[p.sectorOrigin] = (origin[p.sectorOrigin] ?? 0) + 1;
    }
    final c = delisted.cvmSector?.agreement();
    stderr.writeln(
      'deslistadas: ${delisted.securities.length} papéis; setor $origin; '
      '${delisted.discardedCounts} entradas da contagem descartadas '
      'pela conferência contra o preço (B43)',
    );
    if (c != null) {
      stderr.writeln(
        'setor da CVM nas listadas, sem a companhia: '
        '${c.listed} listadas, ${c.withoutReference} sem referência; '
        'Porta 1 ${c.financial}, ciclo ${c.cyclical}, '
        'concessão ${c.concession}, as três ${c.totalCount}',
      );
    }
  }

  final cohorts = c7
      ? c7Cohorts(dataEnd)
      : quarterly
      ? [
          for (var year = 2018; year <= 2025; year++)
            for (final month in const [3, 6, 9, 12])
              if (!(year == 2025 && month > 9)) DateTime(year, month + 1, 0),
        ]
      : [for (var year = 2018; year <= 2025; year++) DateTime(year, 9, 30)];

  try {
    final wholeUniverse = (await fundamentals.universe()).unwrap();
    final universe = sample == null
        ? wholeUniverse
        : wholeUniverse.take(sample).toList();
    stderr.writeln(
      'universo: ${universe.length} ativos, '
      '${cohorts.length} coortes',
    );
    // Proventos da B3 e fechamento bruto do COTAHIST: o retorno total (A4) e,
    // na montagem do aplicativo, a base da data de cada papel e de cada espécie
    // da companhia (C3).
    final dividends = readDividends();
    // Os códigos de cada companhia: os tickers do universo ligados ao CNPJ, os
    // que a FCA declara e as espécies da raiz de cada um.
    final tickersOfCnpj = <String, Set<String>>{};
    for (final e in listedBridge.entries) {
      (tickersOfCnpj[e.value] ??= <String>{}).add(e.key);
    }
    final tickerCodes = <String, Set<String>>{
      for (final t in universe)
        t.value: companyCodes({
          t.value,
          ...?tickersOfCnpj[listedBridge[t.value]],
          ...?fca?.byCnpj[listedBridge[t.value]],
        }),
    };
    final raw = readRawCotahist({
      for (final c in tickerCodes.values) ...c,
    });
    // Pregões de cada código encadeados pelos códigos anteriores da companhia.
    final chained = <String, List<TradingDay>>{};
    List<TradingDay> rawOf(String code, Set<String> ofCompany) =>
        chained[code] ??= chain(code, ofCompany, raw);

    // **Os eventos de ações e as emissões por valor** (itens B28, B29 e B30).
    // Os eventos corrigem a série da fonte onde ela não ajustou e a contagem
    // do FRE onde ela não absorveu; as emissões entram no patrimônio da ponte.
    final freIssuances = app ? FreIssuances.read() : null;
    final shareEvents = app
        ? ShareEvents.read(issuances: freIssuances)
        : null;
    if (app && freIssuances == null) {
      stderr.writeln(
        'sem data/cvm/fre: as emissões por valor ficam de fora — '
        'rode python tool/cvm_baixar.py --docs FRE --destino data/cvm/fre',
      );
    }
    final eventsOf = <String, List<ShareEvent>>{};
    List<ShareEvent> securityEvents(String ticker) =>
        eventsOf[ticker] ??= shareEvents!.ofSecurity(
          cnpj: listedBridge[ticker],
          ticker: ticker,
          rawSessions: rawOf(ticker, tickerCodes[ticker] ?? {ticker}),
        );
    final completeSeries = <String, PriceSeries>{};
    final unadjustedOf = <String, List<ShareEvent>>{};
    // As emissões por valor conhecidas na data: o quadro de aumentos do FRE,
    // até 2023, e a variação do capital integralizado que nenhum evento de
    // ações explica no preço, depois (item B28).
    List<ShareIssue> issuancesOf(
      String? cnpj,
      DateTime t, {
      required List<TradingDay> rawSessions,
      required List<ShareEvent> events,
    }) {
      if (cnpj == null || freIssuances == null) return const [];
      return [
        ...freIssuances.known(cnpj, t),
        ...issuancesWithoutEvent(
          freIssuances.byCapitalChange(cnpj, t),
          rawSessions,
          events,
        ),
      ];
    }

    final declaredEventsOf = <String, List<ShareEvent>>{};

    final rows = <Map<String, dynamic>>[];
    final listedTickers = <String>{};
    final withoutBase = <String, int>{};
    for (final t in cohorts) {
      final annual = t.month == 9;
      final anchors = (await ResolveMarketAnchors.call(
        macro: ctx.macro,
        benchmark: benchmark,
        asOf: t,
      )).getOrElse(MarketAnchors.fallback2026);
      final cohortCurve = app ? TreasuryCurve.at(treasury!, t) : null;
      if (app && cohortCurve == null) {
        stderr.writeln('  ${_day(t)}: sem curva do Tesouro na data');
      }
      final cohortPremium = premiumPackage?.normalizedAt(t);
      if (app && cohortPremium == null) {
        stderr.writeln(
          '  ${_day(t)}: sem a média do prêmio implícito; '
          'vale o parametrizado de 5,5%',
        );
      }
      final premium = cohortPremium ?? CapmInputs.defaultMarketPremium;
      final premiumOrigin = cohortPremium == null
          ? MarketPremiumSource.parameterized
          : MarketPremiumSource.impliedNormalized;

      var evaluated = 0, evaluatedDelisted = 0;
      final valueByCnpj = <String, MarketValue?>{};

      // **O prior transversal do beta da coorte** (item B11). Sem ele não há
      // beta desalavancado, e a montagem padrão media um motor — beta cru e
      // WACC estático — que não é o que as decisões 40 a 46 descrevem. É
      // resolvido **na data da coorte**, sobre o universo listado dela: um
      // prior de hoje seria conhecimento futuro.
      final cohortPrior = app
          ? await ResolveBetaPrior.call(
              tickers: universe,
              prices: prices,
              fundamentals: fundamentals,
              benchmark: benchmark,
              asOf: t,
              dividendsFor: (x) => dividendsOf(dividends, x.value),
            )
          : null;
      if (app && cohortPrior == null) {
        stderr.writeln('  ${_day(t)}: sem prior do beta');
      }

      // A medição de uma observação, para listada e deslistada: o que muda
      // entre as duas é de onde vêm o preço, os fundamentos e os proventos.
      Future<void> observe({
        required Ticker ticker,
        required PriceSeries series,
        required double p0,
        required double priceAtDate,
        required FundamentalsRepository source,
        required FundamentalsRepository? anchoredSource,
        required PriceRepository prices,
        required List<TradingDay>? securityRaw,
        required List<CashDividend> securityDividendsList,
        required List<CashDividend>? betaDividends,
        required DateTime? contractEnd,
        required OfficialShareCount? officialCount,
        required int? sharesInUnit,
        required void Function() count,
        bool Function(DateTime from, DateTime until)? invalidWindow,
        Map<String, Object?> extras = const {},
        Future<Map<String, Object?>> Function()? counterfactual,
        List<ShareIssue> issuances = const [],
      }) async {
        Future<Result<ValuationInputs>> prepare(double marketPremium) =>
            PrepareValuationInputs.call(
              ticker: ticker,
              prices: prices,
              fundamentals: source,
              benchmark: benchmark,
              riskFreeRate: anchors.currentRiskFreeRate,
              asOf: t,
              marketPremium: marketPremium,
              premiumSource: premiumOrigin,
              perpetualGrowthCap: anchors.nominalEconomyGrowth,
              inflation: anchors.inflationCagr,
              terminalRiskFreeRate: anchors.riskFreeCagr,
              projectionYears: 10,
              riskFreeCurve: cohortCurve,
              officialShares: officialCount,
              concessionEnd: contractEnd,
              dividends: betaDividends,
              betaPrior: cohortPrior,
              declaredSharesPerUnit: sharesInUnit,
              // As emissões por valor do FRE conhecidas na data (item B28).
              shareIssues: issuances,
              // O controle estatal na data: só a ressalva (item B46).
              stateControlled: stateOwnedAtDate(ticker, t),
            );
        final prep = await prepare(premium);
        if (prep.isErr) return;
        final inputs = prep.unwrap();

        final r = ValuationCascade.evaluate(inputs);
        final upside = r.isOk ? r.unwrap().upside : null;
        if (upside != null) count();

        // **O prêmio a mais das estatais** (item B46). Soma-se ao prêmio de
        // mercado na proporção do beta — `β × (prêmio + x ÷ β) = β × prêmio +
        // x` —, o que é exato no Ke de hoje; no caminho realavancado, o
        // acréscimo anda com `β_t ÷ β`.
        final withStateOwnedPremium = <String, double?>{};
        // Beta perto de zero faria `x ÷ β` explodir: a observação fica sem
        // a variante, e não com um prêmio infinito.
        if (stateOwnedPremiums.isNotEmpty &&
            stateOwnedAtDate(ticker, t) &&
            inputs.capm.beta.abs() > 0.01) {
          for (final x in stateOwnedPremiums) {
            final other = await prepare(premium + x / inputs.capm.beta);
            final otherResult = other.isErr
                ? null
                : ValuationCascade.evaluate(other.unwrap());
            withStateOwnedPremium['$x'] = otherResult?.valueOrNull?.upside;
          }
        }

        // Banda de Monte Carlo com os sorteios do aplicativo — só nas
        // coortes de 30/09, as que o C2 mediu —, e o potencial do recusado
        // sem o corte de liquidez.
        List<double>? quantiles;
        if (app && annual && r.isOk) {
          final mc = ValuationCascade.evaluate(
            inputs,
            scenarioBuilder: StochasticScenarios.around,
            monteCarloSamples: _draws,
          );
          final dist = mc.isOk ? mc.unwrap().distribution : null;
          if (dist != null && !dist.isEmpty) {
            quantiles = [for (var q = 0; q <= 100; q++) dist.percentile(q / 100)];
          }
        }
        final scenarios = r.isOk ? r.unwrap().discreteScenarios : null;
        double? withoutLiquidity;
        if (app && r.isErr) {
          final counter = ValuationCascade.evaluate(_withoutSeries(inputs));
          if (counter.isOk) withoutLiquidity = counter.unwrap().upside;
        }
        final windowSeries = inputs.prices;
        final liquidity = windowSeries == null
            ? null
            : EligibilityGate.medianTradedValue(windowSeries);
        // Fração dos últimos pregões da janela de liquidez sem negócio.
        double? withoutTrading;
        if (windowSeries != null && windowSeries.points.length >= 20) {
          final pts = windowSeries.points;
          final ini = pts.length > EligibilityGate.liquidityWindowDays
              ? pts.length - EligibilityGate.liquidityWindowDays
              : 0;
          final window = pts.sublist(ini);
          withoutTrading =
              window.where((p) => (p.volume ?? 0) <= 0).length / window.length;
        }

        // Fatores ingênuos, sobre o mesmo exercício que o motor usou — na
        // montagem do aplicativo, a série mesclada com a CVM.
        final view = PointInTimeView(t);
        ({double? bm, double? ey, FundamentalsSnapshot? last}) factors(
          List<FundamentalsSnapshot> fundamentalsSeries,
        ) {
          final pub = view.published(fundamentalsSeries);
          final last = pub.isEmpty ? null : pub.last;
          final pl = last?.equityBookValue;
          final marketValue = last?.marketCap;
          return (
            bm: (pl != null && marketValue != null && marketValue > 0) ? pl / marketValue : null,
            ey: (last?.netIncome != null && marketValue != null && marketValue > 0)
                ? last!.netIncome! / marketValue
                : null,
            last: last,
          );
        }

        final naiveFactors = factors(inputs.fundamentals);
        final pub = view.published(inputs.fundamentals);

        // A ponte por papel como o motor a faz, pelas funções públicas dele
        // (item C3): a razão de unidade e a origem do divisor.
        double? unitRatio;
        QuotedShares? divisor;
        final last = naiveFactors.last;
        if (app && last != null) {
          unitRatio = ValuationCascade.quotedUnitRatio(
            sharesOutstanding: last.sharesOutstanding,
            marketCap: last.marketCap,
            marketPrice: inputs.marketPrice,
          );
          divisor = ValuationCascade.quotedShares(
            latest: last,
            marketPrice: inputs.marketPrice,
            sharesPerQuote: unitRatio,
            published: pub,
            official: inputs.officialShares,
            asOf: t,
          );
        }

        // A série ancorada no trimestre, sobre os mesmos insumos (item C1c).
        Map<String, Object?> anchored = const {};
        if (anchoredSource != null) {
          final h = await anchoredSource.history(ticker);
          if (h.isOk) {
            final anchoredSeries = h.unwrap();
            final anchoredInputs = _withFundamentals(inputs, anchoredSeries);
            final anchoredResult = ValuationCascade.evaluate(anchoredInputs);
            final anchoredFactors = factors(anchoredSeries);
            final pubA = view.published(anchoredSeries);
            anchored = {
              'upsideAncorada': anchoredResult.isOk ? anchoredResult.unwrap().upside : null,
              'justoAncorada': anchoredResult.isOk ? anchoredResult.unwrap().fairValue.reais : null,
              'recusaAncorada': anchoredResult.isOk ? null : anchoredResult.failureOrNull?.message,
              'fimDoExercicioAncorada': pubA.isEmpty
                  ? null
                  : _day(pubA.last.fiscalPeriodEnd),
              'bookToMarketAncorada': anchoredFactors.bm,
              'earningsYieldAncorada': anchoredFactors.ey,
            };
          }
        }

        double? returnRate(int months, {bool adjusted = false}) {
          final d = _addMonths(t, months);
          if (d.isAfter(dataEnd)) return null;
          if (invalidWindow != null && invalidWindow(t, d)) return null;
          final priceStart = adjusted ? _adjustedAt(series, t) : p0;
          final priceEnd = adjusted ? _adjustedAt(series, d) : _priceAt(series, d);
          if (priceStart == null || priceEnd == null || priceStart <= 0) return null;
          return priceEnd / priceStart - 1;
        }

        // Retorno de preço vezes o reinvestimento dos proventos da classe no
        // fechamento bruto da data ex. Sem COTAHIST do papel, não há total.
        double? total(int months) {
          final price = returnRate(months);
          if (price == null || securityRaw == null) return null;
          final r = TotalReturn.factor(
            dividends: securityDividendsList,
            from: t,
            until: _addMonths(t, months),
            closeOnExDate: (d) =>
                tradingDayFrom(securityRaw, d, marginDays: 5)?.close,
          );
          return (1 + price) * r.factor - 1;
        }

        // O mesmo retorno total **começando um mês depois** da coorte (C0). O
        // sinal escalado pelo preço — B/M, potencial — divide pelo mesmo
        // fechamento em que o retorno começa, e em papel ilíquido esse
        // fechamento é ruído: quem saiu barato por acaso volta, e qualquer sinal
        // que dependa do preço "prevê" a volta. Pular o mês separa a reversão do
        // fechamento do que o sinal sabe.
        double? totalSkippingOneMonth(int months) {
          if (securityRaw == null) return null;
          final from = _addMonths(t, 1);
          final until = _addMonths(t, months);
          if (until.isAfter(dataEnd)) return null;
          if (invalidWindow != null && invalidWindow(t, until)) return null;
          final priceStart = _priceAt(series, from);
          final priceEnd = _priceAt(series, until);
          if (priceStart == null || priceEnd == null || priceStart <= 0) return null;
          final r = TotalReturn.factor(
            dividends: securityDividendsList,
            from: from,
            until: until,
            closeOnExDate: (d) =>
                tradingDayFrom(securityRaw, d, marginDays: 5)?.close,
          );
          return priceEnd / priceStart * r.factor - 1;
        }

        // Roteamento, para separar quem chegou ao acionista por qual porta.
        // A Porta 1 é setorial; a Porta 3 é o fluxo da firma não sustentado.
        final sector = inputs.sectorKey;
        final gate1 = FinancialSectors.isFinancial(
          sectorKey: sector,
          industry: inputs.industry,
        );
        final sustained = GrowthGuards.firmFlowIsSustained(pub);

        rows.add({
          'coorte': app ? _day(t) : t.year,
          'ticker': ticker.value,
          ...extras,
          'preco': priceAtDate,
          'upside': upside,
          if (withStateOwnedPremium.isNotEmpty)
            'potencialComPremioEstatal': withStateOwnedPremium,
          'setor': sector,
          'porta1': gate1,
          'fluxoSustentado': sustained,
          'porta3': !gate1 && !sustained,
          'ressalvas': r.isOk
              ? [for (final c in r.unwrap().diagnostics!.caveats) c.key]
              : null,
          'pesoTerminal': r.isOk ? r.unwrap().diagnostics!.terminalShare : null,
          'modelo': r.isOk ? r.unwrap().model.name : null,
          'recusa': r.isOk ? null : r.failureOrNull?.message,
          'bookToMarket': naiveFactors.bm,
          'earningsYield': naiveFactors.ey,
          // **Os ingredientes do múltiplo de pares** (item B22, decisão 123).
          // `bookToMarket` é `1 ÷ (P/VP)` e `earningsYield` é `1 ÷ (P/L)`:
          // dois dos três já estavam aqui, e faltava a firma sobre EBITDA.
          //
          // **A mediana é de quem calcula, e não daqui**: ela tem de sair da
          // seção transversal **da própria coorte**, ou o sinal carrega o
          // múltiplo de 2026 numa observação de 2018 — conhecimento futuro
          // pela porta da frente. Por isso o que a coorte grava é o
          // ingrediente, e `regressao_condicional.dart` monta a mediana.
          'firmaSobreEbitda': () {
            final u = naiveFactors.last;
            final marketValue = u?.marketCap;
            final ebitda = u?.ebitda;
            if (u == null || marketValue == null || marketValue <= 0) return null;
            if (ebitda == null || ebitda <= 0) return null;
            return (marketValue + u.netDebt) / ebitda;
          }(),
          'ebitda': naiveFactors.last?.ebitda,
          'dividaLiquida': naiveFactors.last?.netDebt,
          'lucro': naiveFactors.last?.netIncome,
          'patrimonio': naiveFactors.last?.equityBookValue,
          'valorDeMercado': naiveFactors.last?.marketCap,
          'ret12': returnRate(12),
          'ret36': returnRate(36),
          'ret12aj': returnRate(12, adjusted: true),
          'ret36aj': returnRate(36, adjusted: true),
          'ret12tot': total(12),
          'ret36tot': total(36),
          if (app) ...{
            'justo': r.isOk ? r.unwrap().fairValue.reais : null,
            'pessimista': scenarios == null
                ? null
                : scenarios[ScenarioBand.bear]?.reais,
            'otimista': scenarios == null
                ? null
                : scenarios[ScenarioBand.bull]?.reais,
            'ke': r.isOk ? r.unwrap().diagnostics!.costOfEquity : null,
            'premioDeMercado': inputs.capm.marketPremium,
            'mcQuantis': quantiles,
            // A janela que a série de fato deu ao beta (item B17): a fonte
            // devolve dez anos, e a coorte de 2018 pede cinco que ela não
            // tem. Sem isto, a janela curta entrava sem aparecer.
            'janelaDoBeta': inputs.betaWindowYears,
            'liquidez': liquidity,
            'upsideSemLiquidez': withoutLiquidity,
            'semNegocio': withoutTrading,
            // A escala da forma do C2b, pela mesma função que o aplicativo
            // usa sobre a mesma janela (`cobertura_banda.md` §9).
            'volatilidade': windowSeries == null
                ? null
                : CalibratedBand.trailingVolatility(windowSeries),
            'ret12totPulo': totalSkippingOneMonth(12),
            'ret36totPulo': totalSkippingOneMonth(36),
            'fimDoContrato': inputs.concessionEnd?.toIso8601String().substring(
              0,
              10,
            ),
            'fimDoExercicio': pub.isEmpty
                ? null
                : _day(pub.last.fiscalPeriodEnd),
            'acoesNaData': officialCount?.total,
            // O capital emitido depois do balanço que entrou na ponte (B28).
            'capitalPosterior': r.isOk
                ? r.unwrap().diagnostics?.postStatementCapital
                : null,
            'valorDeMercado': last?.marketCap,
            'razaoDeUnidade': unitRatio,
            'origemDoDivisor': divisor?.source.name,
            'divisorDiverge': divisor?.diverge,
            ...anchored,
            if (counterfactual != null) ...await counterfactual(),
          },
        });
      }

      final listedCnpjsAtDate = <String>{};
      final tickersAtDate = <String>{};
      var i = 0;
      for (final ticker in universe) {
        i++;
        if (i % 50 == 0) {
          stderr.write('  ${_day(t)}: $i/${universe.length}   \r');
        }
        if (stateOwnedOnly && !stateOwnedAtDate(ticker, t)) continue;

        final seriesResult = await prices.daily(
          ticker,
          DateRange(DateTime(2010, 1, 1), dataEnd),
        );
        if (seriesResult.isErr) continue;
        // **O ajuste que a fonte deixou de fazer** (item B29): a bonificação
        // que ela não ajustou é uma queda que não aconteceu, e entrava no
        // retorno de toda janela que a atravessa, no beta e na volatilidade. O
        // fator entre o bruto e a fonte diz, sem ruído, quais ficaram assim.
        final sourceSeries = seriesResult.unwrap();
        final series = !app
            ? sourceSeries
            : completeSeries[ticker.value] ??= () {
                final without = notAdjustedBySource(
                  sourceSeries,
                  rawOf(
                    ticker.value,
                    tickerCodes[ticker.value] ?? {ticker.value},
                  ),
                  securityEvents(ticker.value),
                );
                unadjustedOf[ticker.value] = without;
                return CorporateEvents.applyToSeries(sourceSeries, without);
              }();
        final p0 = _priceAt(series, t);
        if (p0 == null || p0 <= 0) continue;

        final historyResult = await fundamentals.history(ticker);
        if (historyResult.isErr) continue;

        if (!app) {
          final hist = _rescale(historyResult.unwrap(), p0);
          await observe(
            ticker: ticker,
            series: series,
            p0: p0,
            priceAtDate: p0,
            source: _ScaledFundamentals(fundamentals, hist),
            anchoredSource: null,
            prices: prices,
            securityRaw: raw[ticker.value],
            securityDividendsList: dividendsOf(dividends, ticker.value),
            betaDividends: null,
            contractEnd: null,
            officialCount: null,
            // A montagem antiga não passa pela FCA, e a razão de unidade dela
            // continua sendo a medida — é o ponto de comparação.
            sharesInUnit: null,
            count: () => evaluated++,
          );
          continue;
        }

        // A base da data (item C3). Sem pregão do papel no COTAHIST até dez
        // dias antes, não há preço da data, e a observação sai.
        final ofCompany = tickerCodes[ticker.value] ?? {ticker.value};
        final rawSessions = rawOf(ticker.value, ofCompany);
        final base = baseFactorOf(source: series, rawSessions: rawSessions, date: t);
        if (base == null) {
          withoutBase[_day(t)] = (withoutBase[_day(t)] ?? 0) + 1;
          continue;
        }
        final rawPrice = base.tradingDay.close;
        final seriesAtDate = seriesOnDateBasis(series, rawSessions, base.factor);
        final cnpj = listedBridge[ticker.value];
        final count = cnpj == null ? null : listedCounts![cnpj];
        final companySecurities = {
          for (final c in ofCompany)
            if (kindOf(c) == ShareKind.common ||
                kindOf(c) == ShareKind.preferred)
              c: rawOf(c, ofCompany),
        };
        // A contagem do FRE conferida contra o salto do preço (B43): a
        // correção que repete a contagem de antes de um grupamento sai, e o
        // grupamento que só a correção registrou passa a valer no dia do salto.
        final checked = count?.checked(
          companySecurities.values,
          dataEnd,
        );
        if (cnpj != null && checked != null) {
          discardedByCnpj[cnpj] = checked.discarded.length;
        }
        // A contagem com o evento que o FRE ainda não absorveu (B30): o quadro
        // de eventos parou em 2022, e o desdobramento de 2024 do BB só entrou
        // no formulário em 2025.
        final withEvents = checked == null
            ? null
            : sharesWithEvents(
                checked.accepted,
                t,
                securityEvents(ticker.value),
              );
        final shares = withEvents?.shares;
        final value = (cnpj == null || shares == null)
            ? null
            : valueByCnpj.putIfAbsent(
                cnpj,
                () => MarketValue.atDate(
                  shares: shares,
                  commonFraction: count!.classes.at(t),
                  securities: companySecurities,
                  date: t,
                ),
              );
        final hist = _rescaleAtDate(
          historyResult.unwrap(),
          sharesAtDate: shares,
          marketValueOf: value?.value,
          rawPrice: rawPrice,
        );
        final docs = cvmDocs![ticker.value];
        FundamentalsRepository sourceOf({required bool anchored}) =>
            OfficialSectorFundamentalsRepository(
              inner: _CvmAtDate(
                fundamentals,
                hist,
                docs,
                t,
                anchored: anchored,
              ),
              classification: (x) async => shareClass(x),
            );
        final betaDividends = CashDividendsCodec.forTicker(
          dividendsPackage!,
          ticker.value,
        );
        final contractEnd = grants!.atDate(ticker.value, t)?.end;

        // O contrafactual da base (item C3): a montagem da rodada anterior —
        // preço e volume da fonte, contagem do exercício, sem contagem oficial —
        // sobre o mesmo ativo e a mesma data, só nas coortes de 30/09.
        Future<Map<String, Object?>> counterfactual() async {
          final oldSeries = _rescale(historyResult.unwrap(), p0);
          final prep = await PrepareValuationInputs.call(
            ticker: ticker,
            prices: prices,
            fundamentals: OfficialSectorFundamentalsRepository(
              inner: _CvmAtDate(fundamentals, oldSeries, docs, t),
              classification: (x) async => shareClass(x),
            ),
            benchmark: benchmark,
            riskFreeRate: anchors.currentRiskFreeRate,
            asOf: t,
            marketPremium: premium,
            premiumSource: premiumOrigin,
            perpetualGrowthCap: anchors.nominalEconomyGrowth,
            inflation: anchors.inflationCagr,
            terminalRiskFreeRate: anchors.riskFreeCagr,
            projectionYears: 10,
            riskFreeCurve: cohortCurve,
            concessionEnd: contractEnd,
            dividends: betaDividends,
          );
          if (prep.isErr) return const {'recusaBaseAntiga': 'sem insumos'};
          final ins = prep.unwrap();
          final r = ValuationCascade.evaluate(ins);
          final pub = PointInTimeView(t).published(ins.fundamentals);
          final u = pub.isEmpty ? null : pub.last;
          final pl = u?.equityBookValue, marketValue = u?.marketCap;
          return {
            'upsideBaseAntiga': r.isOk ? r.unwrap().upside : null,
            'recusaBaseAntiga': r.isOk ? null : r.failureOrNull?.message,
            'bookToMarketBaseAntiga': (pl != null && marketValue != null && marketValue > 0)
                ? pl / marketValue
                : null,
            'liquidezBaseAntiga': ins.prices == null
                ? null
                : EligibilityGate.medianTradedValue(ins.prices!),
          };
        }

        listedTickers.add(ticker.value);
        tickersAtDate.add(ticker.value);
        if (cnpj != null) listedCnpjsAtDate.add(cnpj);
        await observe(
          ticker: ticker,
          series: series,
          p0: p0,
          priceAtDate: rawPrice,
          source: sourceOf(anchored: false),
          anchoredSource: quarterly ? sourceOf(anchored: true) : null,
          prices: _FixedSeries(seriesAtDate),
          securityRaw: rawSessions,
          securityDividendsList: dividendsOf(dividends, ticker.value),
          betaDividends: betaDividends,
          contractEnd: contractEnd,
          officialCount: shares == null
              ? null
              : OfficialShareCount(total: shares, asOf: t),
          // A composição declarada da unit na FCA vigente na data (item B16).
          sharesInUnit: cnpj == null
              ? null
              : UnitCompositionCodec.at(
                  fca?.unitsByCnpj[cnpj] ?? const [],
                  t,
                )?.shares,
          count: () => evaluated++,
          issuances: issuancesOf(
            cnpj,
            t,
            rawSessions: rawSessions,
            events: declaredEventsOf[ticker.value] ??= shareEvents!
                .ofSecurity(
                  cnpj: cnpj,
                  ticker: ticker.value,
                  rawSessions: rawSessions,
                  withCount: false,
                ),
          ),
          extras: {
            if (delisted != null) 'deslistada': false,
            'fatorDeBase': base.factor,
            // Os eventos que a fonte não ajustou e foram ajustados (B29), e se
            // a contagem da data recebeu evento que o FRE não tinha (B30).
            'eventosSemAjusteNaFonte': unadjustedOf[ticker.value]?.length ?? 0,
            if (withEvents != null && withEvents.applied.isNotEmpty)
              'contagemComEvento': [
                for (final e in withEvents.applied)
                  '${_day(e.exDate)}×${e.factor}',
              ],
            // O pregão da data veio de um código anterior da companhia.
            if (!(raw[ticker.value]?.contains(base.tradingDay) ?? false))
              'pregaoDeOutroCodigo': true,
            'origemDoValorDeMercado':
                value?.origin ??
                (shares == null ? 'contagemDoExercicio' : 'semPregaoDeEspecie'),
          },
          counterfactual: counterfactualBase && annual ? counterfactual : null,
        );
      }

      // As deslistadas da ponte (item C1b): só o papel que negociava na data,
      // e sem evento declarado e não localizado, nem salto que a série ajustada
      // não explica, na janela do beta — ela não estaria ajustada por eles. No
      // horizonte do retorno, a janela que os atravessa fica sem retorno. O
      // papel que já entrou como listado nesta coorte não entra de novo.
      var excludedByEvent = 0, delistedAtDate = 0, repeated = 0;
      final delistedSecurities =
          delisted?.securities.values ?? const <DelistedSecurity>[];
      for (final security
          in stateOwnedOnly
              ? const <DelistedSecurity>[]
              : sample == null
              ? delistedSecurities
              : delistedSecurities.take(sample)) {
        final tradingDay = tradingDayUntil(security.tradingDays, t, marginDays: sessionMargin);
        if (tradingDay == null || tradingDay.close <= 0) continue;
        if (tickersAtDate.contains(security.ticker.value) ||
            listedCnpjsAtDate.contains(security.cnpj)) {
          repeated++;
          continue;
        }
        delistedAtDate++;
        if (security.suspiciousWindow(DateTime.utc(t.year - 5, t.month, t.day), t)) {
          excludedByEvent++;
          continue;
        }
        final finalSeries = security.series(
          DateRange(DateTime(2010, 1, 1), dataEnd),
          until: dataEnd,
        );
        final p0 = _priceAt(finalSeries, t);
        if (p0 == null || p0 <= 0) continue;
        final value = delisted!.marketValueOf(security, t);
        final shares = security.sharesAt(t);
        final docs = delisted.documents[security.ticker.value] ?? const [];
        await observe(
          ticker: security.ticker,
          series: finalSeries,
          p0: p0,
          priceAtDate: tradingDay.close,
          source: DelistedFundamentals(
            security,
            docs,
            t,
            tradingDay.close,
            marketValueOf: value?.value,
          ),
          anchoredSource: quarterly
              ? DelistedFundamentals(
                  security,
                  docs,
                  t,
                  tradingDay.close,
                  marketValueOf: value?.value,
                  anchored: true,
                )
              : null,
          prices: DelistedPrices(security, t),
          securityRaw: security.tradingDays,
          securityDividendsList: security.dividends,
          betaDividends: security.dividends,
          contractEnd: grants!.atDateByCnpj(security.cnpj, t)?.end,
          officialCount: shares == null
              ? null
              : OfficialShareCount(total: shares, asOf: t),
          sharesInUnit: UnitCompositionCodec.at(
            fca?.unitsByCnpj[security.cnpj] ?? const [],
            t,
          )?.shares,
          count: () => evaluatedDelisted++,
          invalidWindow: security.suspiciousWindow,
          issuances: issuancesOf(
            security.cnpj,
            t,
            rawSessions: security.tradingDays,
            events: security.events,
          ),
          extras: {
            'deslistada': true,
            'cnpj': security.cnpj,
            'origemDoSetor': security.sectorOrigin,
            'origemDoValorDeMercado': value?.origin ?? 'contagemVezesPreco',
          },
        );
      }
      if (delisted != null) {
        stderr.writeln(
          '  ${_day(t)}: deslistadas negociando $delistedAtDate, '
          '$excludedByEvent fora por evento não localizado ou salto, '
          '$repeated já listadas, $evaluatedDelisted avaliadas',
        );
      }
      stderr.writeln(
        '  ${_day(t)}: $evaluated avaliados de ${universe.length}'
        '${app ? ', ${withoutBase[_day(t)] ?? 0} sem pregão na data' : ''}'
        '   (rf=${(anchors.currentRiskFreeRate * 100).toStringAsFixed(2)}%, '
        'rf_inf=${(anchors.riskFreeCagr * 100).toStringAsFixed(2)}%, '
        'prêmio=${(premium * 100).toStringAsFixed(2)}%)',
      );
    }
    if (discardedByCnpj.isNotEmpty) {
      final withDiscard = discardedByCnpj.values.where((n) => n > 0);
      stderr.writeln(
        'contagem conferida contra o preço (B43): '
        '${withDiscard.length} de ${discardedByCnpj.length} listadas com '
        '${withDiscard.fold(0, (a, b) => a + b)} entradas descartadas',
      );
    }

    final destination =
        output ??
        (c7
            ? 'data/c7/coortes.json'
            : sample != null
            ? 'docs/validacao/backtest_amostra.json'
            : !app
            ? 'docs/validacao/backtest_valuation.json'
            : quarterly
            ? 'docs/validacao/backtest_trimestral.json'
            : withDelisted
            ? 'docs/validacao/backtest_aplicativo_deslistadas.json'
            : 'docs/validacao/backtest_aplicativo.json');
    File(destination)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        app
            ? jsonEncode(_compact(rows))
            : const JsonEncoder.withIndent(' ').convert(rows),
      );
    stderr.writeln('escrito $destination (${rows.length} observações)');
    if (app &&
        quarterly &&
        withDelisted &&
        sample == null &&
        !c7 &&
        output == null) {
      // O universo que as coortes observam como listado: é o que a ponte das
      // deslistadas (`tool/b3_ponte.py`) exclui, para não dar duas pontas à
      // mesma companhia (item C1d).
      File('docs/validacao/universo_coortes.json').writeAsStringSync(
        const JsonEncoder.withIndent(' ').convert({
          'geradoPor': 'tool/backtest_valuation.dart',
          'tickers': listedTickers.toList()..sort(),
        }),
      );
    }
  } finally {
    await ctx.dispose();
  }
}

/// Os mesmos insumos com outra série de exercícios — a ancorada no trimestre
/// (item C1c). O beta, a curva, a série de preço e a contagem ficam.
///
/// **Pela cópia do núcleo** (item B27): a versão à mão perdia a composição
/// declarada da unit, a taxa de referência do crédito e a janela do beta, e a
/// leitura ancorada saía com outro divisor nas units.
ValuationInputs _withFundamentals(
  ValuationInputs b,
  List<FundamentalsSnapshot> fundamentals,
) => b.withFundamentals(fundamentals);

/// Os mesmos insumos sem a série de cotações: a Porta 0 omite o corte de
/// liquidez sem ela, e nada mais na cascata lê a série.
ValuationInputs _withoutSeries(ValuationInputs b) => b.withoutPrices();

/// Devolve o histórico já reescalado, mantendo o resto do repositório.
class _ScaledFundamentals implements FundamentalsRepository {
  _ScaledFundamentals(this.inner, this.hist);
  final FundamentalsRepository inner;
  final List<FundamentalsSnapshot> hist;

  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker t) async =>
      Ok(hist);

  @override
  Future<Result<Asset>> profile(Ticker t) => inner.profile(t);

  @override
  Future<Result<List<Ticker>>> universe() => inner.universe();
}

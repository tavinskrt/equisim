// O prêmio de risco implícito no preço do mercado, e a versão normalizada —
// medição, sem ligar nada no motor.
//
// **A pergunta.** O prêmio histórico (`tool/premio_historico.dart`) sai
// negativo na maior parte das datas: o que aconteceu não é o que o investidor
// esperava. O método que olha para a frente é o de Damodaran: a taxa de
// retorno que faz o valor de mercado das ações igualar o dinheiro que elas vão
// distribuir, menos a taxa livre de risco.
//
// **A conta, em cada data `t`.**
//
//     P      = valor de mercado somado das companhias
//     CF₀    = dividendos e JCP pagos nos doze meses anteriores, somados
//     g      = crescimento nominal da economia na data (o teto de `g∞` do motor)
//     r      = CF₀·(1 + g) ÷ P + g                 (Gordon)
//     prêmio = (1 + r) ÷ (1 + prefixado de 10 anos) − 1
//
// O modelo de Damodaran projeta cinco anos com o crescimento dos analistas e
// depois uma perpetuidade; sem consenso de analistas, os dois estágios usam o
// mesmo `g`, e o de dois estágios colapsa no de Gordon.
//
// **A versão normalizada** é a média dos prêmios implícitos trimestrais dos
// últimos cinco e dos últimos dez anos até a data — o que suaviza o ciclo, como
// a média de dez anos que Damodaran publica ao lado do implícito do mês.
//
// **De onde vem cada peça**, em datas trimestrais desde 31/03/2011:
//
// - valor de mercado: a contagem de ações do Formulário de Referência na data,
//   corrigida pelos eventos que ele não absorveu (B30), vezes o fechamento
//   bruto do COTAHIST de cada espécie — `MarketValue.atDate`, o mesmo do
//   backtest;
// - caixa distribuído: os proventos em dinheiro da B3 (`data/b3/complemento`),
//   pela soma dos rendimentos de cada provento na classe mais negociada
//   (`valor ÷ preço com direito`), vezes o valor de mercado da companhia;
// - crescimento: `ResolveMarketAnchors` na data (IPCA e IBC-Br de dez anos);
// - taxa livre de risco: o prefixado de dez anos da curva do Tesouro na data.
//
// **As companhias são as listadas hoje** (as dos proventos da B3). As que saíram
// da bolsa não têm os proventos no arquivo, e somar o valor delas sem o caixa
// derrubaria o rendimento. O agregado das datas antigas é, portanto, o das
// sobreviventes — declarado no relatório.
//
//   dart run tool/premio_implicito.dart              # grava premio_implicito.json
//   dart run tool/premio_implicito.dart --so-serie   # só a série e o pacote
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

import 'b3/proventos.dart';
import 'coortes/base_da_data.dart';
import 'coortes/contagem_conferida.dart';
import 'coortes/eventos_de_acoes.dart';
import 'curva_ligar.dart' show readTreasury;
import 'cvm/codigos_fca.dart';
import 'cvm/emissoes_fre.dart';
import 'validation/congelado.dart';
import 'validation/ibovespa_longo.dart';
import 'validation/regression.dart';

const _output = 'docs/validacao/premio_implicito.json';

/// O pacote que o aplicativo e o backtest leem (decisão 142).
const _package = 'assets/mercado/premio_implicito.json';
const _reference = CapmInputs.defaultMarketPremium;

/// Fração mínima de trimestres presentes para uma média normalizada valer.
const _minCoverage = 0.8;

String _pct(double v, [int decimals = 2]) =>
    '${(v * 100).toStringAsFixed(decimals)}%';

/// A mediana de [v], ou `null` sem valor — o JSON não grava NaN.
double? _median(List<double> v) {
  final o = [...v]..sort();
  if (o.isEmpty) return null;
  final m = o.length ~/ 2;
  return o.length.isOdd ? o[m] : (o[m - 1] + o[m]) / 2;
}

/// Uma entrada da contagem que o preço não confirmou, com a companhia.
typedef _Discarded = ({
  String cnpj,
  DateTime since,
  double shares,
  double previous,
  String? source,
});

/// A contagem por data de uma listada, como veio de
/// `data/b3/listadas_contagem.json`, com a fonte de cada entrada.
class _Count {
  _Count(this.raw, this.classes);
  final List<({DateTime since, double shares, String? source})> raw;
  final CapitalClasses classes;

  static Map<String, _Count> read() {
    final f = File('data/b3/listadas_contagem.json');
    if (!f.existsSync()) {
      throw StateError(
        'sem data/b3/listadas_contagem.json: rode '
        'dart run tool/b3_deslistadas_contagem.dart',
      );
    }
    return {
      for (final e
          in (jsonDecode(f.readAsStringSync()) as Map<String, dynamic>).entries)
        e.key: _Count(
          [
            for (final p
                in ((e.value as Map<String, dynamic>)['contagem'] as List)
                    .cast<Map<String, dynamic>>())
              (
                since: DateTime.parse('${p['desde']}T00:00:00Z'),
                shares: (p['acoes'] as num).toDouble(),
                source: p['fonte'] as String?,
              ),
          ]..sort((a, b) => a.since.compareTo(b.since)),
          CapitalClasses.fromJson(
            (e.value as Map<String, dynamic>)['classes'] as List?,
          ),
        ),
    };
  }
}

/// Uma companhia listada, com o que a conta precisa dela.
class _Company {
  _Company(
    this.cnpj,
    this.root,
    this.accepted,
    this.firstRaw,
    this.classes,
    this.securities,
    this.events,
  );
  final String cnpj;

  /// Raiz de quatro letras de hoje: é por ela que os proventos são lidos.
  final String root;

  /// A contagem conferida contra o preço, de `checkCount` (item B43).
  final List<({DateTime since, double shares})> accepted;

  /// A data da primeira contagem do formulário, conferida ou não.
  final DateTime? firstRaw;
  final CapitalClasses classes;

  /// Pregões brutos de cada código de espécie, já encadeados.
  final Map<String, List<TradingDay>> securities;
  final List<ShareEvent> events;
}

/// O último pregão de [s] até [date], a até [sessionMargin] dias.
TradingDay? _tradingDayUntil(List<TradingDay> s, DateTime date) =>
    tradingDayUntil(s, date, marginDays: sessionMargin);

/// Volume financeiro dos 21 pregões até [date].
double _tradedValue(List<TradingDay> s, DateTime date) {
  var sum = 0.0;
  var n = 0;
  for (var i = s.length - 1; i >= 0 && n < 21; i--) {
    if (s[i].date.isAfter(date)) continue;
    sum += s[i].tradedValue ?? 0;
    n++;
  }
  return sum;
}

/// O agregado de uma data.
class _Aggregate {
  _Aggregate(
    this.valueInCents,
    this.cashInCents,
    this.companies,
    this.withDividend,
    this.isGreater,
    this.byCompany,
    this.excludedByCount,
  );

  /// Valor de mercado somado, em centavos.
  final int valueInCents;

  /// Dinheiro distribuído nos doze meses, somado, em centavos.
  final int cashInCents;

  /// Em reais, só para a saída.
  double get marketValueOf => valueInCents / 100;
  double get cash => cashInCents / 100;
  final int companies;
  final int withDividend;

  /// A companhia de maior valor na data, para conferir a escala.
  final ({String root, double value})? isGreater;

  /// Valor e rendimento de cada companhia, para a conferência de `--datas`.
  final List<({String root, double value, double income})> byCompany;

  /// Raízes das companhias fora da soma porque a contagem da data não
  /// concorda com o preço.
  final List<String> excludedByCount;
  double get income => cashInCents / valueInCents;
}

/// O agregado da data [t].
///
/// Proventos, contagem e pregões vêm em meia-noite UTC; a data do trimestre é
/// local, como a do motor (a curva e as âncoras leem [t]). As comparações com
/// os dados da ferramenta usam o mesmo dia em UTC, [day].
_Aggregate _aggregate(
  DateTime t,
  List<_Company> companies,
  Map<String, List<CashDividend>> dividends,
) {
  final day = DateTime.utc(t.year, t.month, t.day);
  // As somas em centavos inteiros: o valor de uma companhia cabe com folga
  // num `int` de 64 bits (R$ 1 trilhão são 10¹⁴ centavos).
  var value = 0, cash = 0;
  var n = 0, withDividend = 0;
  ({String root, double value})? isGreater;
  final byCompany = <({String root, double value, double income})>[];
  final excludedByCount = <String>[];
  // Doze meses de calendário, e não 365 dias: no ano bissexto o dia do ano
  // anterior sairia da janela.
  final start = DateTime.utc(day.year - 1, day.month, day.day);
  for (final c in companies) {
    final shares = sharesWithEvents(c.accepted, day, c.events).shares;
    if (shares == null || !(shares > 0)) {
      // Havia contagem no formulário, e nenhuma que o preço confirmasse.
      if (c.firstRaw != null &&
          !c.firstRaw!.isAfter(day) &&
          c.securities.values.any((s) => _tradingDayUntil(s, day) != null)) {
        excludedByCount.add(c.root);
      }
      continue;
    }
    final marketValue = MarketValue.atDate(
      shares: shares,
      commonFraction: c.classes.at(day),
      securities: c.securities,
      date: day,
    );
    if (marketValue == null || !(marketValue.value > 0)) continue;

    // A classe mais negociada na data é a que dá o rendimento: dividendo por
    // ação dividido pelo preço daquela ação.
    String? principal;
    var best = -1.0;
    for (final e in c.securities.entries) {
      if (_tradingDayUntil(e.value, day) == null) continue;
      final f = _tradedValue(e.value, day);
      if (f > best) {
        best = f;
        principal = e.key;
      }
    }
    if (principal == null) continue;
    final shareClass = principal.substring(4);
    final events = dividendsOf(dividends, '${c.root}$shareClass');
    var income = 0.0;
    for (final p in events) {
      if (!p.exDate.isAfter(start) || p.exDate.isAfter(day)) continue;
      // Preço com direito publicado pela B3; sem ele, o fechamento bruto do
      // último pregão antes da data ex — as duas grandezas na base de ações
      // da época, como o valor do provento.
      final price =
          p.closeWithRights ??
          _tradingDayUntil(
            c.securities[principal]!,
            p.exDate.subtract(const Duration(days: 1)),
          )?.close;
      if (price == null || !(price > 0) || !(p.amount > 0)) continue;
      income += p.amount / price;
    }
    value += (marketValue.value * 100).round();
    cash += (income * marketValue.value * 100).round();
    byCompany.add((root: c.root, value: marketValue.value, income: income));
    if (isGreater == null || marketValue.value > isGreater.value) {
      isGreater = (root: c.root, value: marketValue.value);
    }
    n++;
    if (income > 0) withDividend++;
  }
  return _Aggregate(
    value,
    cash,
    n,
    withDividend,
    isGreater,
    byCompany,
    excludedByCount,
  );
}

/// O prefixado de dez anos da curva: a média geométrica dos forwards anuais.
double? _fixedRate10(YieldCurve? curve) {
  if (curve == null) return null;
  final fw = curve.annualForwards(10);
  if (fw.isEmpty) return null;
  var factor = 1.0;
  for (final f in fw) {
    factor *= 1 + f;
  }
  return math.pow(factor, 1 / fw.length).toDouble() - 1;
}

/// Os trimestres do pacote gravado que a série medida agora devolve diferentes.
///
/// Compara o retorno implícito e o prefixado de cada trimestre presente nos
/// dois, com folga de 1e-9; sem pacote gravado, nada mudou.
List<String> _changedQuarters(ImpliedPremiumPackage newPackage) {
  final file = File(_package);
  if (!file.existsSync()) return const [];
  final saved = ImpliedPremiumCodec.decode(
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
  if (saved == null) return const [];
  final byDate = {for (final q in saved.quarters) q.date: q};
  return [
    for (final q in newPackage.quarters)
      if (byDate[q.date] case final g?)
        if ((g.impliedReturn - q.impliedReturn).abs() > 1e-9 ||
            (g.riskFree - q.riskFree).abs() > 1e-9)
          q.date.toIso8601String().substring(0, 10),
  ];
}

/// As datas: o último dia de cada trimestre, de 31/03/2011 a 30/06/2026, e a
/// data da entrada congelada.
List<DateTime> _dates() => [
  for (var year = 2011; year <= 2026; year++)
    for (final month in const [3, 6, 9, 12])
      if (!(year == 2026 && month > 6)) DateTime(year, month + 1, 0),
  frozenToday,
];

class _Reading {
  _Reading(this.label, this.premium);
  final String label;
  final double premium;
  final Map<String, int> fairValue = {};
  final Map<String, double> upside = {};
}

Future<void> main(List<String> args) async {
  final c = await Frozen.build();
  try {
    // -------------------------------------------------------------------
    // As companhias
    // -------------------------------------------------------------------
    final bridge =
        ((jsonDecode(File('docs/validacao/ponte_cvm.json').readAsStringSync())
                    as Map<String, dynamic>)['ponte']
                as Map<String, dynamic>)
            .cast<String, String>();
    final discarded = <_Discarded>[];
    final counts = _Count.read();
    final fca = FcaCodes.read();
    final dividends = readDividends();
    final shareEvents = ShareEvents.read(issuances: FreIssuances.read());

    final tickersOfCnpj = <String, Set<String>>{};
    for (final e in bridge.entries) {
      (tickersOfCnpj[e.value] ??= <String>{}).add(e.key);
    }
    final codesOf = <String, Set<String>>{
      for (final e in tickersOfCnpj.entries)
        e.key: companyCodes({...e.value, ...?fca.byCnpj[e.key]}),
    };
    final raw = readRawCotahist({for (final s in codesOf.values) ...s});

    final companies = <_Company>[];
    var withoutDividend = 0, withoutCount = 0;
    for (final e in tickersOfCnpj.entries) {
      final cnpj = e.key;
      final count = counts[cnpj];
      if (count == null) {
        withoutCount++;
        continue;
      }
      // A raiz dos proventos é a de hoje: entre os códigos da companhia, a que
      // tem arquivo na B3.
      final root = [
        for (final t in e.value.toList()..sort()) t.substring(0, 4),
      ].where(dividends.containsKey).firstOrNull;
      if (root == null) {
        withoutDividend++;
        continue;
      }
      final codes = codesOf[cnpj]!;
      final securities = <String, List<TradingDay>>{
        for (final code in codes)
          if (kindOf(code) == ShareKind.common ||
              kindOf(code) == ShareKind.preferred)
            code: chain(code, codes, raw),
      }..removeWhere((_, v) => v.isEmpty);
      if (securities.isEmpty) continue;
      final principal = (e.value.toList()..sort()).first;
      final events = shareEvents.ofSecurity(
        cnpj: cnpj,
        ticker: principal,
        rawSessions: chain(principal, codes, raw),
      );
      final checked = checkCount(
        count.raw,
        securities.values,
        until: DateTime.utc(
          frozenToday.year,
          frozenToday.month,
          frozenToday.day,
        ),
      );
      for (final d in checked.discarded) {
        discarded.add((
          cnpj: cnpj,
          since: d.since,
          shares: d.shares,
          previous: d.acceptedAfter,
          source: d.source,
        ));
      }
      companies.add(
        _Company(
          cnpj,
          root,
          checked.accepted,
          count.raw.firstOrNull?.since,
          count.classes,
          securities,
          events,
        ),
      );
    }
    stderr.writeln(
      'contagem: ${discarded.length} entradas sem o salto do preço',
    );
    if (args.contains('--contagens')) {
      final rootOf = {for (final c in companies) c.cnpj: c.root};
      for (final d in discarded) {
        stdout.writeln(
          '  ${rootOf[d.cnpj]}  ${d.since.toIso8601String().substring(0, 10)}  '
          '${d.previous.toStringAsExponential(3)} -> '
          '${d.shares.toStringAsExponential(3)}  ${d.source}',
        );
      }
      for (final c in companies) {
        final a = c.accepted;
        final large = [
          for (var i = 1; i < a.length; i++)
            if (a[i].shares / a[i - 1].shares > largeCountChange ||
                a[i - 1].shares / a[i].shares > largeCountChange)
              '${a[i].since.toIso8601String().substring(0, 10)} ${a[i].shares.toStringAsExponential(3)}',
        ];
        if (large.isNotEmpty) {
          stdout.writeln(
            '  aceita pelo salto: ${c.root}  ${large.join('; ')}',
          );
        }
      }
      return;
    }
    stderr.writeln(
      'companhias: ${companies.length} '
      '($withoutDividend sem o histórico de proventos da B3, '
      '$withoutCount sem contagem por data)',
    );

    final treasury = readTreasury('data/tesouro/precotaxatesourodireto.csv');
    final today = frozenToday;
    final index = await LongIbovespa.build(
      c.ctx.benchmark,
      sourceWindow: DateRange(
        DateTime(today.year - 10, today.month, today.day),
        today,
      ),
    );

    // -------------------------------------------------------------------
    // O prêmio implícito em cada data
    // -------------------------------------------------------------------
    stdout.writeln('-- o prêmio implícito, data a data --');
    stdout.writeln(
      '  data        companhias  valor (R\$ bi)  rendimento  '
      'g nominal   r implícito  prefixado 10a   prêmio    r − Rf   maior     fora',
    );
    final series = <Map<String, Object?>>[];
    final datesOnly = [
      for (final a in args)
        if (a.startsWith('--datas='))
          for (final d in a.substring(8).split(',')) DateTime.parse(d),
    ];
    for (final t in datesOnly.isEmpty ? _dates() : datesOnly) {
      final a = _aggregate(t, companies, dividends);
      if (a.companies == 0 || !(a.marketValueOf > 0)) {
        stdout.writeln('  ${t.toIso8601String().substring(0, 10)}  sem dado');
        continue;
      }
      final anchors = (await ResolveMarketAnchors.call(
        macro: c.ctx.macro,
        benchmark: index,
        asOf: t,
      )).unwrap();
      final g = anchors.nominalEconomyGrowth;
      final curve = TreasuryCurve.at(treasury, t);
      final rf = _fixedRate10(curve);
      final r = a.income * (1 + g) + g;
      final premium = rf == null ? null : (1 + r) / (1 + rf) - 1;
      series.add({
        'data': t.toIso8601String().substring(0, 10),
        'companhias': a.companies,
        'companhiasComProvento': a.withDividend,
        'valorDeMercado': a.marketValueOf,
        'caixaDistribuido': a.cash,
        'rendimento': a.income,
        'crescimentoNominal': g,
        'retornoImplicito': r,
        'prefixado10': rf,
        'premio': premium,
        'foraPelaContagem': a.excludedByCount,
        'maiorCompanhia': a.isGreater?.root,
        'fatiaDaMaior': a.isGreater == null
            ? null
            : a.isGreater!.value / a.marketValueOf,
        'premioComGMenos1': rf == null
            ? null
            : (1 + a.income * (1 + g - 0.01) + g - 0.01) / (1 + rf) - 1,
        'premioComGMais1': rf == null
            ? null
            : (1 + a.income * (1 + g + 0.01) + g + 0.01) / (1 + rf) - 1,
      });
      stdout.writeln(
        '  ${t.toIso8601String().substring(0, 10)}  '
        '${a.companies.toString().padLeft(10)}  '
        '${(a.marketValueOf / 1e9).toStringAsFixed(0).padLeft(13)}  '
        '${_pct(a.income).padLeft(10)}  ${_pct(g).padLeft(9)}   '
        '${_pct(r).padLeft(11)}  ${(rf == null ? '—' : _pct(rf)).padLeft(13)}   '
        '${(premium == null ? '—' : _pct(premium)).padLeft(7)}   '
        '${(rf == null ? '—' : _pct(r - rf)).padLeft(7)}   '
        '${a.isGreater?.root} ${_pct(a.isGreater!.value / a.marketValueOf, 0)}   '
        '${a.excludedByCount.length}',
      );
      if (datesOnly.isNotEmpty) {
        final order = [...a.byCompany]
          ..sort((x, y) => y.value.compareTo(x.value));
        for (final p in order.take(12)) {
          stdout.writeln(
            '      ${p.root}  R\$ ${(p.value / 1e9).toStringAsFixed(1)} bi  '
            '${_pct(p.value / a.marketValueOf, 1)}  rendimento ${_pct(p.income)}',
          );
        }
      }
    }

    // -------------------------------------------------------------------
    // A versão normalizada: médias de cinco e de dez anos
    // -------------------------------------------------------------------
    for (final row in series) {
      final t = DateTime.parse(row['data'] as String);
      for (final years in const [5, 10]) {
        final start = DateTime(t.year - years, t.month, t.day);
        final window = [
          for (final l in series)
            if (DateTime.parse(l['data'] as String).isAfter(start) &&
                !DateTime.parse(l['data'] as String).isAfter(t) &&
                l['premio'] != null &&
                // A data congelada não é trimestre: não entra na média dos
                // trimestres, só a recebe.
                l['data'] != today.toIso8601String().substring(0, 10))
              l['premio'] as double,
        ];
        final expected = years * 4;
        row['normalizado$years'] = window.length >= expected * _minCoverage
            ? window.reduce((x, y) => x + y) / window.length
            : null;
        row['trimestresNaMedia$years'] = window.length;
      }
    }

    // -------------------------------------------------------------------
    // O pacote: a série trimestral que o aplicativo e o backtest leem
    // (decisão 142). A média que o motor usa sai do núcleo, sobre `r − Rf`.
    // -------------------------------------------------------------------
    final entryDay = today.toIso8601String().substring(0, 10);
    final package = ImpliedPremiumPackage(
      generatedAt: DateTime.utc(today.year, today.month, today.day),
      quarters: [
        for (final l in series)
          if (l['data'] != entryDay &&
              l['retornoImplicito'] != null &&
              l['prefixado10'] != null)
            ImpliedPremiumQuarter(
              date: DateTime.parse('${l['data']}T00:00:00Z'),
              impliedReturn: l['retornoImplicito'] as double,
              riskFree: l['prefixado10'] as double,
            ),
      ],
    );
    for (final row in series) {
      final t = DateTime.parse(row['data'] as String);
      final r = row['retornoImplicito'] as double?;
      final rf = row['prefixado10'] as double?;
      row['premioSomado'] = (r == null || rf == null) ? null : r - rf;
      row['premioDoMotor'] = package.normalizedAt(t);
      row['trimestresDoMotor'] = package.window(t).length;
      // A média de cinco anos na mesma forma, só para comparação.
      final five = [
        for (final q in package.quarters)
          if (q.date.isAfter(DateTime.utc(t.year - 5, t.month, t.day)) &&
              !q.date.isAfter(DateTime.utc(t.year, t.month, t.day)))
            q.premium,
      ];
      row['premioSomado5'] = five.length >= 20 * _minCoverage
          ? five.reduce((x, y) => x + y) / five.length
          : null;
    }
    if (datesOnly.isEmpty) {
      // **O passado não muda em silêncio** (item B48). Um trimestre já gravado
      // é fato histórico; se a série medida agora o devolve diferente, a causa
      // é dado que mudou por baixo — em 02/10/2026, as âncoras de 2011 e 2012
      // dependiam de a rede devolver o IBC-Br anterior à entrada congelada, e
      // sem ela o crescimento caía no recuo de 2026. Só regrava com
      // `--aceitar-mudanca-do-passado`, depois de entender a diferença.
      final changed = _changedQuarters(package);
      if (changed.isNotEmpty && !args.contains('--aceitar-mudanca-do-passado')) {
        stderr.writeln(
          'ERRO: ${changed.length} trimestre(s) já gravado(s) em $_package mudaram '
          '(${changed.take(6).join(', ')}${changed.length > 6 ? '…' : ''}); o pacote '
          'não foi regravado. Confira a causa e, se a mudança for intencional, '
          'rode de novo com --aceitar-mudanca-do-passado.',
        );
        exitCode = 1;
        return;
      }
      File(_package).writeAsStringSync(
        jsonEncode(ImpliedPremiumCodec.encode(package)),
      );
      stdout.writeln(
        'escrito $_package: ${package.quarters.length} trimestres; o prêmio do '
        'motor em $entryDay é ${_pct(package.normalizedAt(today) ?? double.nan)}',
      );
    }

    stdout.writeln('');
    // Na forma que o motor soma (`r − Rf`); as médias da forma de Fisher
    // ficam no JSON (`normalizado5`, `normalizado10`).
    stdout.writeln('-- implícito e normalizado nas datas das coortes (r − Rf) --');
    stdout.writeln('  data        implícito   média 5 anos   média 10 anos (o motor)');
    for (final l in series) {
      final d = DateTime.parse(l['data'] as String);
      if (d.year < 2018) continue;
      String f(Object? v) => v == null ? '—' : _pct(v as double);
      stdout.writeln(
        '  ${l['data']}  ${f(l['premioSomado']).padLeft(9)}   '
        '${f(l['premioSomado5']).padLeft(12)}   ${f(l['premioDoMotor']).padLeft(13)}',
      );
    }

    if (args.contains('--so-serie')) return;

    // -------------------------------------------------------------------
    // O que cada um faz ao aplicativo, sobre a entrada congelada
    // -------------------------------------------------------------------
    final ofEntry = series.lastWhere((l) => l['data'] == entryDay);
    final fromEngine = package.normalizedAt(today);
    if (fromEngine == null) {
      stderr.writeln('ERRO: a série não tem trimestres para a média de dez anos');
      exitCode = 1;
      return;
    }
    // A montagem do aplicativo lê o pacote que estava em disco quando a
    // entrada congelada foi montada; se a série medida agora for outra, a
    // conferência contra o gabarito compararia montagens diferentes.
    if ((c.premium.value - fromEngine).abs() > 1e-12) {
      stderr.writeln(
        'ERRO: o pacote em disco dava ${_pct(c.premium.value)} e a série medida '
        'agora dá ${_pct(fromEngine)}. O pacote foi regravado: rode de novo, e '
        'regrave o gabarito antes (tool/gabarito_cascata.dart).',
      );
      exitCode = 1;
      return;
    }
    // A média de cinco anos, na mesma forma `r − Rf`, para comparação.
    final fiveYears = [
      for (final q in package.quarters)
        if (q.date.isAfter(DateTime.utc(today.year - 5, today.month, today.day)))
          q.premium,
    ];
    final candidates = <(String, double?)>[
      // A primeira é a do aplicativo (`premio` nulo: o do pacote), e é a que
      // se confere contra o gabarito.
      ('média de 10 anos — o motor', null),
      ('5,5% (até a decisão 142)', _reference),
      if (ofEntry['premioSomado'] case final double p) ('implícito', p),
      if (fiveYears.length >= 20)
        ('média de 5 anos', fiveYears.reduce((a, b) => a + b) / fiveYears.length),
    ];
    final readings = <_Reading>[];
    for (final (label, premium) in candidates) {
      final l = _Reading(label, premium ?? fromEngine);
      final evaluated = <Ticker, ValuationResult?>{};
      var i = 0;
      for (final t in c.universe) {
        i++;
        if (i % 50 == 0) {
          stderr.write('  $label: $i/${c.universe.length}   \r');
        }
        final prep = await c.prepare(t, premium: premium);
        if (prep.isErr) continue;
        final r = ValuationCascade.evaluate(prep.unwrap());
        if (identical(label, candidates.first.$1)) {
          evaluated[t] = r.valueOrNull;
        }
        if (r.isErr) continue;
        l.fairValue[t.value] = r.unwrap().fairValue.cents;
        l.upside[t.value] = r.unwrap().upside;
      }
      if (identical(label, candidates.first.$1)) {
        final div = await c.checkAgainstAnswerKey(evaluated);
        if (div != null && div.isNotEmpty) {
          stderr.writeln(
            'ERRO: a montagem do aplicativo diverge do gabarito em '
            '${div.length}: ${div.take(8).join(', ')}',
          );
          exitCode = 1;
          return;
        }
      }
      readings.add(l);
    }
    stderr.write('                                        \r');

    final base = readings.first;
    final effects = <Map<String, Object?>>[];
    stdout.writeln('');
    stdout.writeln('-- o universo reavaliado sobre a entrada congelada --');
    stdout.writeln(
      '  prêmio                  avaliados   potencial mediano   '
      'acima de zero   preço justo vs o motor   postos',
    );
    for (final l in readings) {
      final upsideValues = l.upside.values.toList();
      final common = l.fairValue.keys.where(base.fairValue.containsKey).toList()
        ..sort();
      final changeList = <double>[
        for (final k in common)
          if (base.fairValue[k]! != 0) l.fairValue[k]! / base.fairValue[k]! - 1,
      ];
      final rho = common.length < 3
          ? null
          : Regression.spearman(
              [for (final k in common) base.upside[k]!],
              [for (final k in common) l.upside[k]!],
            );
      final above = upsideValues.where((p) => p > 0).length;
      final medianUpside = _median(upsideValues);
      final medVar = _median(changeList);
      stdout.writeln(
        '  ${'${l.label} (${_pct(l.premium)})'.padRight(24)}'
        '${l.fairValue.length.toString().padLeft(9)}   '
        '${(medianUpside == null ? '—' : _pct(medianUpside)).padLeft(17)}   '
        '${'$above de ${upsideValues.length}'.padLeft(13)}   '
        '${(medVar == null ? '—' : _pct(medVar)).padLeft(19)}   '
        '${rho == null ? '—' : rho.toStringAsFixed(3)}',
      );
      effects.add({
        'rotulo': l.label,
        'premio': l.premium,
        'avaliados': l.fairValue.length,
        'potencialMediano': medianUpside,
        'acimaDeZero': above,
        'precoJustoMedianoContraReferencia': medVar,
        'spearmanContraReferencia': rho,
        'casos': {
          for (final t in const ['WEGE3', 'ITUB4', 'VALE3', 'SAPR11', 'RENT3'])
            t: {'justoCentavos': l.fairValue[t], 'potencial': l.upside[t]},
        },
      });
    }

    File(_output).writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert({
        'geradoPor': 'tool/premio_implicito.dart',
        'dataDaEntrada': today.toIso8601String().substring(0, 10),
        'companhias': companies.length,
        'contagensSemSalto': [
          for (final d in discarded)
            {
              'cnpj': d.cnpj,
              'desde': d.since.toIso8601String().substring(0, 10),
              'acoes': d.shares,
              'anterior': d.previous,
              'fonte': d.source,
            },
        ],
        'serie': series,
        'efeitos': effects,
      }),
    );
    stdout.writeln('');
    stdout.writeln('escrito $_output');
  } finally {
    await c.ctx.dispose();
  }
}

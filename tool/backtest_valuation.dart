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
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'package:equisim/data/repositories/b3_registry_repository.dart';

import 'b3/proventos.dart';
import 'coortes/base_da_data.dart';
import 'coortes/deslistadas.dart';
import 'curva_ligar.dart' show lerTesouro;
import 'cvm/codigos_fca.dart';
import 'cvm/documentos.dart';
import 'cvm/outorgas_por_data.dart';
import 'validation/context.dart';

/// CVM mesclada à série de mercado já reescalada, com o que era público na
/// data da coorte.
class _CvmNaData implements FundamentalsRepository {
  _CvmNaData(this.inner, this.hist, this.docs, this.data, {this.ancorada = false});
  final FundamentalsRepository inner;
  final List<FundamentalsSnapshot> hist;
  final List<CvmPeriodDocument>? docs;
  final DateTime data;

  /// Série de doze meses ancorada no trimestre mais recente (A1.8, C1c).
  final bool ancorada;

  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker t) async {
    final meus = docs;
    if (meus == null || meus.isEmpty) return Ok(hist);
    return Ok(CvmSeries.build(
      documentos: meus,
      mercado: hist,
      asOf: data,
      publicado: PointInTimeView(data).isPublished,
      ancorada: ancorada,
    ).series);
  }

  @override
  Future<Result<Asset>> profile(Ticker t) => inner.profile(t);

  @override
  Future<Result<List<Ticker>>> universe() => inner.universe();
}

/// Sorteios da distribuição, iguais ao padrão do aplicativo.
const _sorteios = 10000;

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
    return Ok(PriceSeries(
      ticker: _full!.ticker,
      points: _full!.points.where((p) => range.contains(p.date)).toList(),
    ));
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
  Future<Result<List<Ticker>>> universe() async => _uni ??= await inner.universe();
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
      return Err(InsufficientData('sem preços de ${t.value}', subject: t.value));
    }
    return Ok(PriceSeries(
      ticker: s.ticker,
      points: s.points.where((p) => range.contains(p.date)).toList(),
    ));
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
class _SerieFixa implements PriceRepository {
  _SerieFixa(this.serie);
  final PriceSeries serie;

  PriceSeries _recorte(DateRange range) => PriceSeries(
        ticker: serie.ticker,
        points: serie.points.where((p) => range.contains(p.date)).toList(),
      );

  @override
  Future<Result<PriceSeries>> daily(Ticker t, DateRange range) async =>
      Ok(_recorte(range));

  @override
  Future<Result<Map<Ticker, PriceSeries>>> dailyBatch(
          List<Ticker> tickers, DateRange range) async =>
      Ok({for (final t in tickers) t: _recorte(range)});

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
/// medições de 11/09/2026; a montagem `aplicativo` usa [_reescalaNaData].
List<FundamentalsSnapshot> _reescala(
  List<FundamentalsSnapshot> snaps,
  double precoNaData,
) =>
    _comMercado(
      snaps,
      corrente: (s) => s.sharesOutstandingAsOf,
      valor: (s) => (s.sharesOutstandingAsOf != null &&
              s.sharesOutstandingAsOf! > 0 &&
              precoNaData > 0)
          ? s.sharesOutstandingAsOf! * precoNaData
          : null,
    );

/// O valor de mercado e a contagem corrente **da data** em todo exercício
/// (item C3): a contagem do Formulário de Referência e o valor de mercado da
/// companhia espécie a espécie. Sem contagem da data, recua para a contagem do
/// exercício vezes o preço bruto da data — na base certa, e com a razão de
/// unidade de volta a 1 por construção, o que a linha declara.
List<FundamentalsSnapshot> _reescalaNaData(
  List<FundamentalsSnapshot> snaps, {
  required double? acoesNaData,
  required double? valorDeMercado,
  required double precoBruto,
}) =>
    _comMercado(
      snaps,
      corrente: (s) => acoesNaData ?? s.sharesOutstandingAsOf,
      valor: (s) {
        if (valorDeMercado != null) return valorDeMercado;
        final n = s.sharesOutstandingAsOf;
        return (n != null && n > 0 && precoBruto > 0) ? n * precoBruto : null;
      },
    );

List<FundamentalsSnapshot> _comMercado(
  List<FundamentalsSnapshot> snaps, {
  required double? Function(FundamentalsSnapshot) corrente,
  required double? Function(FundamentalsSnapshot) valor,
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
        sharesOutstanding: corrente(s),
        sharesOutstandingAsOf: s.sharesOutstandingAsOf,
        marketCap: valor(s),
        enterpriseToEbitda: null,
      ),
  ];
}

double? _precoEm(PriceSeries s, DateTime data) {
  double? ultimo;
  for (final p in s.points) {
    if (p.date.isAfter(data)) break;
    ultimo = p.close;
  }
  return ultimo;
}

double? _ajustadoEm(PriceSeries s, DateTime data) {
  double? ultimo;
  for (final p in s.points) {
    if (p.date.isAfter(data)) break;
    ultimo = p.adjustedClose ?? p.close;
  }
  return ultimo;
}

/// Contagem por data e divisão entre espécies de cada listada, gravadas por
/// `tool/b3_deslistadas_contagem.dart` (item C3).
class _ContagemListada {
  _ContagemListada(this.contagem, this.classes);
  final List<({DateTime desde, double acoes})> contagem;
  final ClassesDoCapital classes;

  double? acoesEm(DateTime data) {
    final dia = DateTime.utc(data.year, data.month, data.day);
    double? ultima;
    for (final p in contagem) {
      if (p.desde.isAfter(dia)) break;
      ultima = p.acoes;
    }
    return ultima;
  }

  static Map<String, _ContagemListada>? ler() {
    final f = File('data/b3/listadas_contagem.json');
    if (!f.existsSync()) return null;
    final out = <String, _ContagemListada>{};
    for (final e in (jsonDecode(f.readAsStringSync()) as Map<String, dynamic>)
        .entries) {
      final v = e.value as Map<String, dynamic>;
      out[e.key] = _ContagemListada(
        [
          for (final p in (v['contagem'] as List).cast<Map<String, dynamic>>())
            (
              desde: DateTime.parse('${p['desde']}T00:00:00Z'),
              acoes: (p['acoes'] as num).toDouble(),
            ),
        ]..sort((a, b) => a.desde.compareTo(b.desde)),
        ClassesDoCapital.fromJson(v['classes'] as List?),
      );
    }
    return out;
  }
}

/// A data `meses` depois de [t], no mesmo dia — ou no último dia do mês, quando
/// ele não existe: 31/03 mais três meses é 30/06, e não 01/07.
DateTime _somaMeses(DateTime t, int meses) {
  final total = t.month - 1 + meses;
  final ano = t.year + total ~/ 12;
  final mes = total % 12 + 1;
  final ultimoDia = DateTime(ano, mes + 1, 0).day;
  return DateTime(ano, mes, t.day > ultimoDia ? ultimoDia : t.day);
}

String _dia(DateTime d) => d.toIso8601String().substring(0, 10);

/// Arredonda os `double` a seis algarismos significativos, para que a saída
/// trimestral caiba no repositório; nenhuma medição usa mais que isso.
Object? _compacto(Object? v) {
  if (v is double) {
    // Zero passa pelo mesmo caminho: `toStringAsPrecision` o devolve zero.
    if (!v.isFinite) return v;
    return double.parse(v.toStringAsPrecision(6));
  }
  if (v is List) return [for (final x in v) _compacto(x)];
  if (v is Map) return {for (final e in v.entries) e.key: _compacto(e.value)};
  return v;
}

Future<void> main(List<String> args) async {
  final iMontagem = args.indexOf('--montagem');
  final app = iMontagem >= 0 && args[iMontagem + 1] == 'aplicativo';
  final comDeslistadas = args.contains('--com-deslistadas');
  final trimestral = args.contains('--trimestral');
  final contrafactualBase = args.contains('--contrafactual-base');
  final iAmostra = args.indexOf('--amostra');
  final amostra = iAmostra >= 0 ? int.parse(args[iAmostra + 1]) : null;
  if ((comDeslistadas || trimestral || contrafactualBase) && !app) {
    stderr.writeln('--com-deslistadas, --trimestral e --contrafactual-base '
        'exigem --montagem aplicativo');
    exit(2);
  }
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  final prices = _MemoPrices(ctx.prices);
  final fundamentals = _MemoFundamentals(ctx.fundamentals);
  final benchmark = _MemoBenchmark(ctx.benchmark);

  // Peças da montagem do aplicativo, lidas uma vez.
  final tesouro =
      app ? lerTesouro('data/tesouro/precotaxatesourodireto.csv') : null;
  final docsCvm = app ? carregarDocumentos('data/cvm_exercicios.json') : null;
  final registro = app
      ? B3RegistryCodec.decodePackage(
          jsonDecode(File('assets/b3/emissores.json').readAsStringSync())
              as Map<String, dynamic>)
      : null;
  final pacoteDeProventos = app
      ? CashDividendsCodec.decode(
          jsonDecode(File('assets/b3/proventos.json').readAsStringSync())
              as Map<String, dynamic>)
      : null;
  final outorgas = app ? OutorgasPorData.ler() : null;
  if (app && outorgas == null) {
    stderr.writeln('sem data/cvm/fre: rode python tool/cvm_baixar.py --docs FRE');
    exit(2);
  }
  if (app) {
    // O prazo lido na data de montagem do pacote tem de ser o do pacote.
    final pacote = ConcessionTermsCodec.decode(
        jsonDecode(File('assets/cvm/outorgas.json').readAsStringSync())
            as Map<String, dynamic>);
    var iguais = 0;
    for (final e in pacote.entries) {
      final lido = outorgas!.naData(e.key, DateTime(2026, 9, 14));
      if (lido != null && lido.end == e.value.end) iguais++;
    }
    stderr.writeln('outorgas por data contra o pacote: $iguais de '
        '${pacote.length} iguais em 14/09/2026');
  }
  B3Classification? classe(Ticker t) => registro?[
          t.value.length >= 4 ? t.value.substring(0, 4) : '']
      ?.classification;

  // A base da data das listadas (item C3): a ponte ticker → CNPJ, os códigos
  // que a FCA declara e a contagem por data do Formulário de Referência.
  final ponteListadas = app
      ? ((jsonDecode(File('docs/validacao/ponte_cvm.json').readAsStringSync())
              as Map<String, dynamic>)['ponte'] as Map<String, dynamic>)
          .cast<String, String>()
      : const <String, String>{};
  final fca = app ? CodigosFca.ler() : null;
  final contagemListadas = app ? _ContagemListada.ler() : null;
  if (app && contagemListadas == null) {
    stderr.writeln('sem data/b3/listadas_contagem.json: rode '
        'dart run tool/b3_deslistadas_contagem.dart');
    exit(2);
  }

  // As deslistadas (item C1b), com o setor da B3 ou o representante do setor da
  // CVM, medido nas listadas.
  Deslistadas? deslistadas;
  if (comDeslistadas) {
    final porCnpj = <String, B3Classification>{};
    for (final e in ponteListadas.entries) {
      final c = registro![e.key.length >= 4 ? e.key.substring(0, 4) : '']
          ?.classification;
      if (c != null) porCnpj[e.value] = c;
    }
    deslistadas = Deslistadas.ler(porCnpj);
    if (deslistadas == null) {
      stderr.writeln('sem data/b3/deslistadas_contagem.json: rode '
          'dart run tool/b3_deslistadas_contagem.dart');
      exit(2);
    }
    final origem = <String, int>{};
    for (final p in deslistadas.papeis.values) {
      origem[p.origemDoSetor] = (origem[p.origemDoSetor] ?? 0) + 1;
    }
    final c = deslistadas.setorCvm?.concordancia();
    stderr.writeln(
        'deslistadas: ${deslistadas.papeis.length} papéis; setor $origem');
    if (c != null) {
      stderr.writeln('setor da CVM nas listadas, sem a companhia: '
          '${c.listadas} listadas, ${c.semReferencia} sem referência; '
          'Porta 1 ${c.financeira}, ciclo ${c.ciclica}, '
          'concessão ${c.concessao}, as três ${c.todas}');
    }
  }

  final coortes = trimestral
      ? [
          for (var ano = 2018; ano <= 2025; ano++)
            for (final mes in const [3, 6, 9, 12])
              if (!(ano == 2025 && mes > 9)) DateTime(ano, mes + 1, 0),
        ]
      : [for (var ano = 2018; ano <= 2025; ano++) DateTime(ano, 9, 30)];
  final fimDosDados = DateTime(2026, 9, 4);

  try {
    final universoInteiro = (await fundamentals.universe()).unwrap();
    final universe = amostra == null
        ? universoInteiro
        : universoInteiro.take(amostra).toList();
    stderr.writeln('universo: ${universe.length} ativos, '
        '${coortes.length} coortes');
    // Proventos da B3 e fechamento bruto do COTAHIST: o retorno total (A4) e,
    // na montagem do aplicativo, a base da data de cada papel e de cada espécie
    // da companhia (C3).
    final proventos = lerProventos();
    // Os códigos de cada companhia: os tickers do universo ligados ao CNPJ, os
    // que a FCA declara e as espécies da raiz de cada um.
    final tickersDoCnpj = <String, Set<String>>{};
    for (final e in ponteListadas.entries) {
      (tickersDoCnpj[e.value] ??= <String>{}).add(e.key);
    }
    final codigosDoTicker = <String, Set<String>>{
      for (final t in universe)
        t.value: codigosDaCompanhia({
          t.value,
          ...?tickersDoCnpj[ponteListadas[t.value]],
          ...?fca?.porCnpj[ponteListadas[t.value]],
        }),
    };
    final bruto = lerCotahistBruto({
      for (final c in codigosDoTicker.values) ...c,
    });
    // Pregões de cada código encadeados pelos códigos anteriores da companhia.
    final encadeados = <String, List<Pregao>>{};
    List<Pregao> brutosDe(String codigo, Set<String> daCompanhia) =>
        encadeados[codigo] ??= encadear(codigo, daCompanhia, bruto);

    final linhas = <Map<String, dynamic>>[];
    final tickersListados = <String>{};
    final semBase = <String, int>{};
    for (final t in coortes) {
      final anual = t.month == 9;
      final anchors = (await ResolveMarketAnchors.call(
        macro: ctx.macro,
        benchmark: benchmark,
        asOf: t,
      ))
          .getOrElse(MarketAnchors.fallback2026);
      final curvaDaCoorte = app ? TreasuryCurve.at(tesouro!, t) : null;
      if (app && curvaDaCoorte == null) {
        stderr.writeln('  ${_dia(t)}: sem curva do Tesouro na data');
      }

      var avaliados = 0, avaliadasDeslistadas = 0;
      final valorPorCnpj = <String, ValorDeMercado?>{};

      // **O prior transversal do beta da coorte** (item B11). Sem ele não há
      // beta desalavancado, e a montagem padrão media um motor — beta cru e
      // WACC estático — que não é o que as decisões 40 a 46 descrevem. É
      // resolvido **na data da coorte**, sobre o universo listado dela: um
      // prior de hoje seria conhecimento futuro.
      final priorDaCoorte = app
          ? await ResolveBetaPrior.call(
              tickers: universe,
              prices: prices,
              fundamentals: fundamentals,
              benchmark: benchmark,
              asOf: t,
              dividendsFor: (x) => proventosDo(proventos, x.value),
            )
          : null;
      if (app && priorDaCoorte == null) {
        stderr.writeln('  ${_dia(t)}: sem prior do beta');
      }

      // A medição de uma observação, para listada e deslistada: o que muda
      // entre as duas é de onde vêm o preço, os fundamentos e os proventos.
      Future<void> observar({
        required Ticker ticker,
        required PriceSeries serie,
        required double p0,
        required double precoNaData,
        required FundamentalsRepository fonte,
        required FundamentalsRepository? fonteAncorada,
        required PriceRepository precos,
        required List<Pregao>? brutoDoPapel,
        required List<CashDividend> proventosDoPapel,
        required List<CashDividend>? proventosDoBeta,
        required DateTime? fimDoContrato,
        required OfficialShareCount? contagemOficial,
        required int? acoesNaUnit,
        required void Function() contar,
        bool Function(DateTime de, DateTime ate)? janelaInvalida,
        Map<String, Object?> extras = const {},
        Future<Map<String, Object?>> Function()? contrafactual,
      }) async {
          final prep = await PrepareValuationInputs.call(
            ticker: ticker,
            prices: precos,
            fundamentals: fonte,
            benchmark: benchmark,
            riskFreeRate: anchors.currentRiskFreeRate,
            asOf: t,
            perpetualGrowthCap: anchors.nominalEconomyGrowth,
            inflation: anchors.inflationCagr,
            terminalRiskFreeRate: anchors.riskFreeCagr,
            projectionYears: 10,
            riskFreeCurve: curvaDaCoorte,
            officialShares: contagemOficial,
            concessionEnd: fimDoContrato,
            dividends: proventosDoBeta,
            betaPrior: priorDaCoorte,
            declaredSharesPerUnit: acoesNaUnit,
          );
          if (prep.isErr) return;
          final insumos = prep.unwrap();

          final r = ValuationCascade.evaluate(insumos);
          final upside = r.isOk ? r.unwrap().upside : null;
          if (upside != null) contar();

          // Banda de Monte Carlo com os sorteios do aplicativo — só nas
          // coortes de 30/09, as que o C2 mediu —, e o potencial do recusado
          // sem o corte de liquidez.
          List<double>? quantis;
          if (app && anual && r.isOk) {
            final mc = ValuationCascade.evaluate(
              insumos,
              scenarioBuilder: StochasticScenarios.around,
              monteCarloSamples: _sorteios,
            );
            final dist = mc.isOk ? mc.unwrap().distribution : null;
            if (dist != null && !dist.isEmpty) {
              quantis = [for (var q = 0; q <= 100; q++) dist.percentile(q / 100)];
            }
          }
          final cenarios = r.isOk ? r.unwrap().discreteScenarios : null;
          double? semLiquidez;
          if (app && r.isErr) {
            final contra = ValuationCascade.evaluate(_semSerie(insumos));
            if (contra.isOk) semLiquidez = contra.unwrap().upside;
          }
          final serieDaJanela = insumos.prices;
          final liquidez = serieDaJanela == null
              ? null
              : EligibilityGate.medianTradedValue(serieDaJanela);
          // Fração dos últimos pregões da janela de liquidez sem negócio.
          double? semNegocio;
          if (serieDaJanela != null && serieDaJanela.points.length >= 20) {
            final pts = serieDaJanela.points;
            final ini = pts.length > EligibilityGate.liquidityWindowDays
                ? pts.length - EligibilityGate.liquidityWindowDays
                : 0;
            final janela = pts.sublist(ini);
            semNegocio = janela.where((p) => (p.volume ?? 0) <= 0).length /
                janela.length;
          }

          // Fatores ingênuos, sobre o mesmo exercício que o motor usou — na
          // montagem do aplicativo, a série mesclada com a CVM.
          final view = PointInTimeView(t);
          ({double? bm, double? ey, FundamentalsSnapshot? ultimo}) fatores(
              List<FundamentalsSnapshot> serieFundamentos) {
            final pub = view.published(serieFundamentos);
            final ultimo = pub.isEmpty ? null : pub.last;
            final pl = ultimo?.equityBookValue;
            final vm = ultimo?.marketCap;
            return (
              bm: (pl != null && vm != null && vm > 0) ? pl / vm : null,
              ey: (ultimo?.netIncome != null && vm != null && vm > 0)
                  ? ultimo!.netIncome! / vm
                  : null,
              ultimo: ultimo,
            );
          }

          final ingenuos = fatores(insumos.fundamentals);
          final pub = view.published(insumos.fundamentals);

          // A ponte por papel como o motor a faz, pelas funções públicas dele
          // (item C3): a razão de unidade e a origem do divisor.
          double? razaoDeUnidade;
          QuotedShares? divisor;
          final ultimo = ingenuos.ultimo;
          if (app && ultimo != null) {
            razaoDeUnidade = ValuationCascade.quotedUnitRatio(
              sharesOutstanding: ultimo.sharesOutstanding,
              marketCap: ultimo.marketCap,
              marketPrice: insumos.marketPrice,
            );
            divisor = ValuationCascade.quotedShares(
              latest: ultimo,
              marketPrice: insumos.marketPrice,
              sharesPerQuote: razaoDeUnidade,
              published: pub,
              official: insumos.officialShares,
              asOf: t,
            );
          }

          // A série ancorada no trimestre, sobre os mesmos insumos (item C1c).
          Map<String, Object?> ancorada = const {};
          if (fonteAncorada != null) {
            final h = await fonteAncorada.history(ticker);
            if (h.isOk) {
              final serieAncorada = h.unwrap();
              final ia = _comFundamentos(insumos, serieAncorada);
              final ra = ValuationCascade.evaluate(ia);
              final fa = fatores(serieAncorada);
              final pubA = view.published(serieAncorada);
              ancorada = {
                'upsideAncorada': ra.isOk ? ra.unwrap().upside : null,
                'justoAncorada': ra.isOk ? ra.unwrap().fairValue.reais : null,
                'recusaAncorada': ra.isOk ? null : ra.failureOrNull?.message,
                'fimDoExercicioAncorada':
                    pubA.isEmpty ? null : _dia(pubA.last.fiscalPeriodEnd),
                'bookToMarketAncorada': fa.bm,
                'earningsYieldAncorada': fa.ey,
              };
            }
          }

          double? retorno(int meses, {bool ajustado = false}) {
            final d = _somaMeses(t, meses);
            if (d.isAfter(fimDosDados)) return null;
            if (janelaInvalida != null && janelaInvalida(t, d)) return null;
            final pa = ajustado ? _ajustadoEm(serie, t) : p0;
            final pf = ajustado ? _ajustadoEm(serie, d) : _precoEm(serie, d);
            if (pa == null || pf == null || pa <= 0) return null;
            return pf / pa - 1;
          }

          // Retorno de preço vezes o reinvestimento dos proventos da classe no
          // fechamento bruto da data ex. Sem COTAHIST do papel, não há total.
          double? total(int meses) {
            final preco = retorno(meses);
            if (preco == null || brutoDoPapel == null) return null;
            final r = TotalReturn.factor(
              dividends: proventosDoPapel,
              de: t,
              ate: _somaMeses(t, meses),
              closeOnExDate: (d) =>
                  pregaoApartir(brutoDoPapel, d, folgaDias: 5)?.close,
            );
            return (1 + preco) * r.factor - 1;
          }

          // O mesmo retorno total **começando um mês depois** da coorte (C0). O
          // sinal escalado pelo preço — B/M, potencial — divide pelo mesmo
          // fechamento em que o retorno começa, e em papel ilíquido esse
          // fechamento é ruído: quem saiu barato por acaso volta, e qualquer sinal
          // que dependa do preço "prevê" a volta. Pular o mês separa a reversão do
          // fechamento do que o sinal sabe.
          double? totalPulandoUmMes(int meses) {
            if (brutoDoPapel == null) return null;
            final de = _somaMeses(t, 1);
            final ate = _somaMeses(t, meses);
            if (ate.isAfter(fimDosDados)) return null;
            if (janelaInvalida != null && janelaInvalida(t, ate)) return null;
            final pa = _precoEm(serie, de);
            final pf = _precoEm(serie, ate);
            if (pa == null || pf == null || pa <= 0) return null;
            final r = TotalReturn.factor(
              dividends: proventosDoPapel,
              de: de,
              ate: ate,
              closeOnExDate: (d) =>
                  pregaoApartir(brutoDoPapel, d, folgaDias: 5)?.close,
            );
            return pf / pa * r.factor - 1;
          }

          // Roteamento, para separar quem chegou ao acionista por qual porta.
          // A Porta 1 é setorial; a Porta 3 é o fluxo da firma não sustentado.
          final setor = insumos.sectorKey;
          final porta1 = FinancialSectors.isFinancial(
            sectorKey: setor,
            industry: insumos.industry,
          );
          final sustentado = GrowthGuards.firmFlowIsSustained(pub);

          linhas.add({
            'coorte': app ? _dia(t) : t.year,
            'ticker': ticker.value,
            ...extras,
            'preco': precoNaData,
            'upside': upside,
            'setor': setor,
            'porta1': porta1,
            'fluxoSustentado': sustentado,
            'porta3': !porta1 && !sustentado,
            'ressalvas': r.isOk
                ? [for (final c in r.unwrap().diagnostics!.caveats) c.name]
                : null,
            'pesoTerminal': r.isOk ? r.unwrap().diagnostics!.terminalShare : null,
            'modelo': r.isOk ? r.unwrap().model.name : null,
            'recusa': r.isOk ? null : r.failureOrNull?.message,
            'bookToMarket': ingenuos.bm,
            'earningsYield': ingenuos.ey,
            'ret12': retorno(12),
            'ret36': retorno(36),
            'ret12aj': retorno(12, ajustado: true),
            'ret36aj': retorno(36, ajustado: true),
            'ret12tot': total(12),
            'ret36tot': total(36),
            if (app) ...{
              'justo': r.isOk ? r.unwrap().fairValue.reais : null,
              'pessimista': cenarios == null ? null : cenarios[ScenarioBand.bear]?.reais,
              'otimista': cenarios == null ? null : cenarios[ScenarioBand.bull]?.reais,
              'ke': r.isOk ? r.unwrap().diagnostics!.costOfEquity : null,
              'mcQuantis': quantis,
              // A janela que a série de fato deu ao beta (item B17): a fonte
              // devolve dez anos, e a coorte de 2018 pede cinco que ela não
              // tem. Sem isto, a janela curta entrava sem aparecer.
              'janelaDoBeta': insumos.betaWindowYears,
              'liquidez': liquidez,
              'upsideSemLiquidez': semLiquidez,
              'semNegocio': semNegocio,
              // A escala da forma do C2b, pela mesma função que o aplicativo
              // usa sobre a mesma janela (`cobertura_banda.md` §9).
              'volatilidade': serieDaJanela == null
                  ? null
                  : CalibratedBand.trailingVolatility(serieDaJanela),
              'ret12totPulo': totalPulandoUmMes(12),
              'ret36totPulo': totalPulandoUmMes(36),
              'fimDoContrato':
                  insumos.concessionEnd?.toIso8601String().substring(0, 10),
              'fimDoExercicio':
                  pub.isEmpty ? null : _dia(pub.last.fiscalPeriodEnd),
              'acoesNaData': contagemOficial?.total,
              'valorDeMercado': ultimo?.marketCap,
              'razaoDeUnidade': razaoDeUnidade,
              'origemDoDivisor': divisor?.source.name,
              'divisorDiverge': divisor?.diverge,
              ...ancorada,
              if (contrafactual != null) ...await contrafactual(),
            },
          });
      }

      final cnpjsListadosNaData = <String>{};
      final tickersNaData = <String>{};
      var i = 0;
      for (final ticker in universe) {
        i++;
        if (i % 50 == 0) {
          stderr.write('  ${_dia(t)}: $i/${universe.length}   \r');
        }

        final serieRes = await prices.daily(
          ticker,
          DateRange(DateTime(2010, 1, 1), fimDosDados),
        );
        if (serieRes.isErr) continue;
        final serie = serieRes.unwrap();
        final p0 = _precoEm(serie, t);
        if (p0 == null || p0 <= 0) continue;

        final histRes = await fundamentals.history(ticker);
        if (histRes.isErr) continue;

        if (!app) {
          final hist = _reescala(histRes.unwrap(), p0);
          await observar(
            ticker: ticker,
            serie: serie,
            p0: p0,
            precoNaData: p0,
            fonte: _EscaladoFundamentals(fundamentals, hist),
            fonteAncorada: null,
            precos: prices,
            brutoDoPapel: bruto[ticker.value],
            proventosDoPapel: proventosDo(proventos, ticker.value),
            proventosDoBeta: null,
            fimDoContrato: null,
            contagemOficial: null,
            // A montagem antiga não passa pela FCA, e a razão de unidade dela
            // continua sendo a medida — é o ponto de comparação.
            acoesNaUnit: null,
            contar: () => avaliados++,
          );
          continue;
        }

        // A base da data (item C3). Sem pregão do papel no COTAHIST até dez
        // dias antes, não há preço da data, e a observação sai.
        final daCompanhia = codigosDoTicker[ticker.value] ?? {ticker.value};
        final brutos = brutosDe(ticker.value, daCompanhia);
        final base = fatorDeBase(fonte: serie, brutos: brutos, data: t);
        if (base == null) {
          semBase[_dia(t)] = (semBase[_dia(t)] ?? 0) + 1;
          continue;
        }
        final precoBruto = base.pregao.close;
        final serieNaData = serieNaBaseDaData(serie, brutos, base.fator);
        final cnpj = ponteListadas[ticker.value];
        final contagem = cnpj == null ? null : contagemListadas![cnpj];
        final acoes = contagem?.acoesEm(t);
        final valor = (cnpj == null || acoes == null)
            ? null
            : valorPorCnpj.putIfAbsent(
                cnpj,
                () => ValorDeMercado.naData(
                  acoes: acoes,
                  fracaoOrdinarias: contagem!.classes.at(t),
                  papeis: {
                    for (final c in daCompanhia)
                      if (especieDo(c) == Especie.ordinaria ||
                          especieDo(c) == Especie.preferencial)
                        c: brutosDe(c, daCompanhia),
                  },
                  data: t,
                ));
        final hist = _reescalaNaData(
          histRes.unwrap(),
          acoesNaData: acoes,
          valorDeMercado: valor?.valor,
          precoBruto: precoBruto,
        );
        final docs = docsCvm![ticker.value];
        FundamentalsRepository fonteDe({required bool ancorada}) =>
            OfficialSectorFundamentalsRepository(
              inner: _CvmNaData(fundamentals, hist, docs, t, ancorada: ancorada),
              classificacao: (x) async => classe(x),
            );
        final proventosDoBeta =
            CashDividendsCodec.forTicker(pacoteDeProventos!, ticker.value);
        final fimDoContrato = outorgas!.naData(ticker.value, t)?.end;

        // O contrafactual da base (item C3): a montagem da rodada anterior —
        // preço e volume da fonte, contagem do exercício, sem contagem oficial —
        // sobre o mesmo ativo e a mesma data, só nas coortes de 30/09.
        Future<Map<String, Object?>> contrafactual() async {
          final antiga = _reescala(histRes.unwrap(), p0);
          final prep = await PrepareValuationInputs.call(
            ticker: ticker,
            prices: prices,
            fundamentals: OfficialSectorFundamentalsRepository(
              inner: _CvmNaData(fundamentals, antiga, docs, t),
              classificacao: (x) async => classe(x),
            ),
            benchmark: benchmark,
            riskFreeRate: anchors.currentRiskFreeRate,
            asOf: t,
            perpetualGrowthCap: anchors.nominalEconomyGrowth,
            inflation: anchors.inflationCagr,
            terminalRiskFreeRate: anchors.riskFreeCagr,
            projectionYears: 10,
            riskFreeCurve: curvaDaCoorte,
            concessionEnd: fimDoContrato,
            dividends: proventosDoBeta,
          );
          if (prep.isErr) return const {'recusaBaseAntiga': 'sem insumos'};
          final ins = prep.unwrap();
          final r = ValuationCascade.evaluate(ins);
          final pub = PointInTimeView(t).published(ins.fundamentals);
          final u = pub.isEmpty ? null : pub.last;
          final pl = u?.equityBookValue, vm = u?.marketCap;
          return {
            'upsideBaseAntiga': r.isOk ? r.unwrap().upside : null,
            'recusaBaseAntiga': r.isOk ? null : r.failureOrNull?.message,
            'bookToMarketBaseAntiga':
                (pl != null && vm != null && vm > 0) ? pl / vm : null,
            'liquidezBaseAntiga': ins.prices == null
                ? null
                : EligibilityGate.medianTradedValue(ins.prices!),
          };
        }

        tickersListados.add(ticker.value);
        tickersNaData.add(ticker.value);
        if (cnpj != null) cnpjsListadosNaData.add(cnpj);
        await observar(
          ticker: ticker,
          serie: serie,
          p0: p0,
          precoNaData: precoBruto,
          fonte: fonteDe(ancorada: false),
          fonteAncorada: trimestral ? fonteDe(ancorada: true) : null,
          precos: _SerieFixa(serieNaData),
          brutoDoPapel: brutos,
          proventosDoPapel: proventosDo(proventos, ticker.value),
          proventosDoBeta: proventosDoBeta,
          fimDoContrato: fimDoContrato,
          contagemOficial:
              acoes == null ? null : OfficialShareCount(total: acoes, asOf: t),
          // A composição declarada da unit na FCA vigente na data (item B16).
          acoesNaUnit: cnpj == null
              ? null
              : UnitCompositionCodec.at(
                  fca?.unitsPorCnpj[cnpj] ?? const [], t)?.shares,
          contar: () => avaliados++,
          extras: {
            if (deslistadas != null) 'deslistada': false,
            'fatorDeBase': base.fator,
            // O pregão da data veio de um código anterior da companhia.
            if (!(bruto[ticker.value]?.contains(base.pregao) ?? false))
              'pregaoDeOutroCodigo': true,
            'origemDoValorDeMercado': valor?.origem ??
                (acoes == null ? 'contagemDoExercicio' : 'semPregaoDeEspecie'),
          },
          contrafactual: contrafactualBase && anual ? contrafactual : null,
        );
      }

      // As deslistadas da ponte (item C1b): só o papel que negociava na data,
      // e sem evento declarado e não localizado, nem salto que a série ajustada
      // não explica, na janela do beta — ela não estaria ajustada por eles. No
      // horizonte do retorno, a janela que os atravessa fica sem retorno. O
      // papel que já entrou como listado nesta coorte não entra de novo.
      var excluidasPorEvento = 0, deslistadasNaData = 0, repetidas = 0;
      final papeisDeslistados =
          deslistadas?.papeis.values ?? const <PapelDeslistado>[];
      for (final papel in amostra == null
          ? papeisDeslistados
          : papeisDeslistados.take(amostra)) {
        final pregao = pregaoAte(papel.pregoes, t, folgaDias: folgaDoPregao);
        if (pregao == null || pregao.close <= 0) continue;
        if (tickersNaData.contains(papel.ticker.value) ||
            cnpjsListadosNaData.contains(papel.cnpj)) {
          repetidas++;
          continue;
        }
        deslistadasNaData++;
        if (papel.janelaSuspeita(
            DateTime.utc(t.year - 5, t.month, t.day), t)) {
          excluidasPorEvento++;
          continue;
        }
        final serieFinal = papel.serie(
          DateRange(DateTime(2010, 1, 1), fimDosDados),
          ate: fimDosDados,
        );
        final p0 = _precoEm(serieFinal, t);
        if (p0 == null || p0 <= 0) continue;
        final valor = deslistadas!.valorDeMercado(papel, t);
        final acoes = papel.acoesEm(t);
        final docs = deslistadas.documentos[papel.ticker.value] ?? const [];
        await observar(
          ticker: papel.ticker,
          serie: serieFinal,
          p0: p0,
          precoNaData: pregao.close,
          fonte: FundamentosDeslistada(papel, docs, t, pregao.close,
              valorDeMercado: valor?.valor),
          fonteAncorada: trimestral
              ? FundamentosDeslistada(papel, docs, t, pregao.close,
                  valorDeMercado: valor?.valor, ancorada: true)
              : null,
          precos: PrecosDeslistada(papel, t),
          brutoDoPapel: papel.pregoes,
          proventosDoPapel: papel.proventos,
          proventosDoBeta: papel.proventos,
          fimDoContrato: outorgas!.naDataPorCnpj(papel.cnpj, t)?.end,
          contagemOficial:
              acoes == null ? null : OfficialShareCount(total: acoes, asOf: t),
          acoesNaUnit: UnitCompositionCodec.at(
              fca?.unitsPorCnpj[papel.cnpj] ?? const [], t)?.shares,
          contar: () => avaliadasDeslistadas++,
          janelaInvalida: papel.janelaSuspeita,
          extras: {
            'deslistada': true,
            'cnpj': papel.cnpj,
            'origemDoSetor': papel.origemDoSetor,
            'origemDoValorDeMercado': valor?.origem ?? 'contagemVezesPreco',
          },
        );
      }
      if (deslistadas != null) {
        stderr.writeln('  ${_dia(t)}: deslistadas negociando $deslistadasNaData, '
            '$excluidasPorEvento fora por evento não localizado ou salto, '
            '$repetidas já listadas, $avaliadasDeslistadas avaliadas');
      }
      stderr.writeln('  ${_dia(t)}: $avaliados avaliados de ${universe.length}'
          '${app ? ', ${semBase[_dia(t)] ?? 0} sem pregão na data' : ''}'
          '   (rf=${(anchors.currentRiskFreeRate * 100).toStringAsFixed(2)}%, '
          'rf_inf=${(anchors.riskFreeCagr * 100).toStringAsFixed(2)}%)');
    }

    final destino = amostra != null
        ? 'docs/validacao/backtest_amostra.json'
        : !app
        ? 'docs/validacao/backtest_valuation.json'
        : trimestral
            ? 'docs/validacao/backtest_trimestral.json'
            : comDeslistadas
                ? 'docs/validacao/backtest_aplicativo_deslistadas.json'
                : 'docs/validacao/backtest_aplicativo.json';
    File(destino).writeAsStringSync(app
        ? jsonEncode(_compacto(linhas))
        : const JsonEncoder.withIndent(' ').convert(linhas));
    stderr.writeln('escrito $destino (${linhas.length} observações)');
    if (app && trimestral && comDeslistadas && amostra == null) {
      // O universo que as coortes observam como listado: é o que a ponte das
      // deslistadas (`tool/b3_ponte.py`) exclui, para não dar duas pontas à
      // mesma companhia (item C1d).
      File('docs/validacao/universo_coortes.json').writeAsStringSync(
          const JsonEncoder.withIndent(' ').convert({
        'geradoPor': 'tool/backtest_valuation.dart',
        'tickers': tickersListados.toList()..sort(),
      }));
    }
  } finally {
    await ctx.dispose();
  }
}

/// Os mesmos insumos com outra série de exercícios — a ancorada no trimestre
/// (item C1c). O beta, a curva, a série de preço e a contagem ficam.
ValuationInputs _comFundamentos(
        ValuationInputs b, List<FundamentalsSnapshot> fundamentos) =>
    ValuationInputs(
      ticker: b.ticker,
      asOf: b.asOf,
      fundamentals: fundamentos,
      marketPrice: b.marketPrice,
      capm: b.capm,
      marginOfSafety: b.marginOfSafety,
      projectionYears: b.projectionYears,
      perpetualGrowthCap: b.perpetualGrowthCap,
      sectorKey: b.sectorKey,
      industry: b.industry,
      inflation: b.inflation,
      declaredTerminalRiskFreeRate: b.declaredTerminalRiskFreeRate,
      riskFreeCurve: b.riskFreeCurve,
      officialShares: b.officialShares,
      prices: b.prices,
      isDistressed: b.isDistressed,
      unleveredBeta: b.unleveredBeta,
      concessionEnd: b.concessionEnd,
      dividendsInBeta: b.dividendsInBeta,
    );

/// Os mesmos insumos sem a série de cotações: a Porta 0 omite o corte de
/// liquidez sem ela, e nada mais na cascata lê a série.
ValuationInputs _semSerie(ValuationInputs b) => ValuationInputs(
      ticker: b.ticker,
      asOf: b.asOf,
      fundamentals: b.fundamentals,
      marketPrice: b.marketPrice,
      capm: b.capm,
      marginOfSafety: b.marginOfSafety,
      projectionYears: b.projectionYears,
      perpetualGrowthCap: b.perpetualGrowthCap,
      sectorKey: b.sectorKey,
      industry: b.industry,
      inflation: b.inflation,
      declaredTerminalRiskFreeRate: b.declaredTerminalRiskFreeRate,
      riskFreeCurve: b.riskFreeCurve,
      officialShares: b.officialShares,
      isDistressed: b.isDistressed,
      unleveredBeta: b.unleveredBeta,
      concessionEnd: b.concessionEnd,
      dividendsInBeta: b.dividendsInBeta,
    );

/// Devolve o histórico já reescalado, mantendo o resto do repositório.
class _EscaladoFundamentals implements FundamentalsRepository {
  _EscaladoFundamentals(this.inner, this.hist);
  final FundamentalsRepository inner;
  final List<FundamentalsSnapshot> hist;

  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker t) async => Ok(hist);

  @override
  Future<Result<Asset>> profile(Ticker t) => inner.profile(t);

  @override
  Future<Result<List<Ticker>>> universe() => inner.universe();
}

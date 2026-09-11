import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

/// Repositório macro de teste, que devolve o que lhe entregam.
class _MacroFake implements MacroRepository {
  final RateSeries cdi;
  final RateSeries ipca;
  final RateSeries ibc;

  _MacroFake({required this.cdi, required this.ipca, required this.ibc});

  @override
  Future<Result<RateSeries>> riskFreeDaily(DateRange range) async => Ok(cdi);

  @override
  Future<Result<RateSeries>> inflationMonthly(DateRange range) async =>
      Ok(ipca);

  @override
  Future<Result<RateSeries>> activityIndexMonthly(DateRange range) async =>
      Ok(ibc);
}

class _BenchmarkFake implements BenchmarkRepository {
  final PriceSeries serie;

  _BenchmarkFake(this.serie);

  @override
  Future<Result<PriceSeries>> ibovespa(DateRange range) async => Ok(serie);
}

void main() {
  final hoje = DateTime(2026, 9, 4);

  RateSeries taxas(int n, double v, TimeBasis base) => RateSeries([
        for (var i = 0; i < n; i++)
          RatePoint(date: hoje.subtract(Duration(days: n - i)), rate: v),
      ], basis: base);

  /// Índice que cresce a [aoAno] composto, com ruído multiplicando as pontas.
  ///
  /// Os pontos ficam a **um dia de calendário** um do outro, e por isso a
  /// composição usa 365,25 — a mesma base de `DateRange.years`, que é quem
  /// mede o expoente do outro lado. Compor em 252 aqui faria a série crescer
  /// por pregão e ser medida por calendário, e o `aoAno` do nome seria falso.
  PriceSeries indice({
    required int pregoes,
    required double aoAno,
    double ruidoFinal = 1.0,
    double ruidoInicial = 1.0,
  }) {
    final diario = math.pow(1 + aoAno, 1 / 365.25).toDouble() - 1;
    var nivel = 100.0;
    final pontos = <PricePoint>[];
    for (var i = 0; i < pregoes; i++) {
      var close = nivel;
      if (i == pregoes - 1) close *= ruidoFinal;
      if (i == 0) close *= ruidoInicial;
      pontos.add(PricePoint(
        date: hoje.subtract(Duration(days: pregoes - i)),
        close: close,
      ));
      nivel *= 1 + diario;
    }
    return PriceSeries(ticker: Ticker.parse('IBOV11'), points: pontos);
  }

  Future<double> cagrDe(PriceSeries ibov) async {
    final r = await ResolveMarketAnchors.call(
      macro: _MacroFake(
        cdi: taxas(500, 0.0004, TimeBasis.businessDaily),
        ipca: taxas(60, 0.004, TimeBasis.monthly),
        ibc: taxas(60, 1.0, TimeBasis.monthly),
      ),
      benchmark: _BenchmarkFake(ibov),
      asOf: hoje,
    );
    expect(r.isOk, isTrue, reason: r.failureOrNull?.message);
    return r.unwrap().marketCagr;
  }

  group('CAGR do índice — as pontas são médias, não dois dias', () {
    // O índice de atividade já era medido por média móvel nas pontas: "um CAGR
    // entre dois pontos isolados herdaria inteiramente o ruído deles". O
    // Ibovespa, que oscila muito mais, era o único sem o mesmo tratamento.
    // Medido em 11/09/2026 na janela de dez anos: **12,57% ponta a ponta
    // contra 11,06%** com trimestre nas pontas. Decisão 60.

    test('sobre uma exponencial limpa, recupera a taxa exata', () async {
      // **É esta a razão de medir de centro a centro, e não de ponta a
      // ponta.** Promediar as pontas sem deslocar as datas encurtaria o
      // expoente e enviesaria o CAGR para cima; com os centros, o estimador
      // devolve a taxa verdadeira sem viés nenhum.
      for (final taxa in [0.05, 0.10, 0.18]) {
        expect(
          await cagrDe(indice(pregoes: 1260, aoAno: taxa)),
          closeTo(taxa, 1e-9),
        );
      }
    });

    test('um salto no último pregão quase não move o CAGR', () async {
      final limpo = await cagrDe(indice(pregoes: 1260, aoAno: 0.10));
      final comSalto = await cagrDe(
        indice(pregoes: 1260, aoAno: 0.10, ruidoFinal: 1.20),
      );
      expect((comSalto - limpo).abs(), lessThan(0.005),
          reason: 'um dia 20% acima é diluído por 63 pregões');
    });

    test('e um buraco no primeiro pregão também não', () async {
      final limpo = await cagrDe(indice(pregoes: 1260, aoAno: 0.10));
      final comBuraco = await cagrDe(
        indice(pregoes: 1260, aoAno: 0.10, ruidoInicial: 0.80),
      );
      expect((comBuraco - limpo).abs(), lessThan(0.005));
    });

    test('sem a média, o mesmo salto moveria muito mais', () async {
      // O contrafactual, calculado aqui: ponta a ponta, 20% no último dia
      // sobre cinco anos elevam o CAGR em ~3,7 p.p.
      final p = indice(pregoes: 1260, aoAno: 0.10, ruidoFinal: 1.20).points;
      final anos = DateRange(p.first.date, p.last.date).years;
      final pontaAPonta =
          math.pow(p.last.close / p.first.close, 1 / anos).toDouble() - 1;
      final limpo = await cagrDe(indice(pregoes: 1260, aoAno: 0.10));
      expect((pontaAPonta - limpo).abs(), greaterThan(0.02),
          reason: 'se o contrafactual não se movesse, o teste anterior não '
              'estaria medindo nada');
    });

    test('série curta parte as pontas ao meio, e ainda mede', () async {
      final medido = await cagrDe(indice(pregoes: 40, aoAno: 0.10));
      expect(medido.isFinite, isTrue);
      expect(medido, isNot(MarketAnchors.fallback2026.marketCagr),
          reason: 'quarenta pregões bastam, com pontas de vinte');
    });

    test('série de um ponto cai no recuo declarado', () async {
      final unico = PriceSeries(
        ticker: Ticker.parse('IBOV11'),
        points: [PricePoint(date: hoje, close: 100)],
      );
      expect(await cagrDe(unico), MarketAnchors.fallback2026.marketCagr);
    });
  });
}

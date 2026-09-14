// A1.7 — liga a ingestão da CVM ao motor, e mede o que muda.
//
// Monta o exercício de cada ativo mesclando CVM e fonte de mercado por
// `FundamentalsMerge`, roda a cascata com ele, e confronta com o resultado que
// o motor produz hoje. É a medição que diz se o eixo A se paga.
//
// Uso:
//   dart run tool/cvm_ingerir.dart data/cvm     # produz cvm_exercicios.json
//   dart run tool/cvm_ligar.dart
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'validation/context.dart';

final _hoje = DateTime(2026, 9, 4);

/// Fundamentos da CVM, indexados por ticker.
///
/// A ingestão grava por CNPJ com a lista de tickers; aqui a chave inverte.
class _DaCvm {
  final Map<String, List<FundamentalsSnapshot>> porTicker;
  final int exercicios;
  final int companhias;
  _DaCvm(this.porTicker, this.exercicios, this.companhias);

  static _DaCvm carregar(String caminho) {
    final f = File(caminho);
    if (!f.existsSync()) {
      stderr.writeln('$caminho não existe. Rode antes:');
      stderr.writeln('  dart run tool/cvm_ingerir.dart data/cvm');
      exit(2);
    }
    final linhas = (jsonDecode(f.readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    final out = <String, List<FundamentalsSnapshot>>{};
    final cnpjs = <String>{};
    for (final e in linhas) {
      cnpjs.add(e['cnpj'] as String);
      final tickers = (e['tickers'] as List).cast<String>();
      if (tickers.isEmpty) continue;
      final fim = DateTime.tryParse(e['fimDoExercicio'] as String);
      if (fim == null) continue;
      // Só exercício **anual**: a série do motor é anual, e misturar o
      // trimestral nela duplicaria períodos sem que a cascata saiba.
      if (fim.month != 12) continue;

      double? n(String k) => (e[k] as num?)?.toDouble();
      final integralizadas = n('acoesIntegralizadas');
      final tesouraria = n('acoesEmTesouraria');
      final pl = n('patrimonioLiquido');

      for (final t in tickers) {
        out.putIfAbsent(t, () => []).add(FundamentalsSnapshot(
              ticker: Ticker.parse(t),
              fiscalPeriodEnd: fim,
              receiptDate: e['recebidoEm'] == null
                  ? null
                  : DateTime.tryParse(e['recebidoEm'] as String),
              totalRevenue: n('receita'),
              ebit: n('ebit'),
              netIncome: n('lucroLiquido'),
              incomeBeforeTax: n('resultadoAntesDosTributos'),
              incomeTaxExpense: n('tributos'),
              earningsPerShare: n('lucroPorAcao'),
              cash: n('caixa'),
              shortTermInvestments: n('aplicacoesFinanceiras'),
              shortTermDebt: n('dividaDeCurtoPrazo'),
              longTermDebt: n('dividaDeLongoPrazo'),
              totalStockholderEquity: pl,
              propertyPlantEquipment: n('imobilizado'),
              intangibleAssets: n('intangivel'),
              totalCurrentAssets: n('ativoCirculante'),
              currentLiabilities: n('passivoCirculante'),
              operatingCashFlow: n('caixaOperacional'),
              investmentCashFlow: n('caixaDeInvestimento'),
              minorityInterest: n('naoControladores'),
              totalAssets: n('ativoTotal'),
              // **A contagem absoluta da CVM NÃO entra**, e a fração entra.
              // Medido em 2.081 pares: 60,9% dos `QT_ACAO_TOTAL_CAP_INTEGR`
              // vêm em unidades e 34,5% em milhares, sem campo que declare —
              // a ABEV3 aparece com 15.757.657 contra 15.761.638.000 papéis.
              // Importar o absoluto levou o MILS3 a +14.037% de potencial na
              // primeira execução. A razão `tesouraria ÷ integralizadas` não
              // depende da escala: as duas saem do mesmo registro.
              treasuryFraction: (integralizadas != null &&
                      integralizadas > 0 &&
                      tesouraria != null &&
                      tesouraria >= 0 &&
                      tesouraria < integralizadas)
                  ? tesouraria / integralizadas
                  : null,
            ));
      }
    }
    for (final v in out.values) {
      v.sort((a, b) => a.fiscalPeriodEnd.compareTo(b.fiscalPeriodEnd));
    }
    return _DaCvm(out, linhas.length, cnpjs.length);
  }
}

/// Repositório que devolve a série mesclada em vez da bruta.
class _Mesclado implements FundamentalsRepository {
  final FundamentalsRepository interno;
  final _DaCvm cvm;
  final Map<String, FundamentalsProvenance> procedencia = {};
  int comCvm = 0, semCvm = 0;

  _Mesclado(this.interno, this.cvm);

  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker t) async {
    final base = await interno.history(t);
    if (base.isErr) return base;
    final doMercado = base.unwrap();
    final daCvm = cvm.porTicker[t.value];
    if (daCvm == null || daCvm.isEmpty) {
      semCvm++;
      return base;
    }
    comCvm++;

    // Índice por ano: a CVM e o mercado nomeiam o mesmo exercício com datas
    // que podem diferir em dias.
    final porAno = <int, FundamentalsSnapshot>{
      for (final s in doMercado) s.fiscalPeriodEnd.year: s,
    };
    final anos = {
      ...porAno.keys,
      ...daCvm.map((s) => s.fiscalPeriodEnd.year),
    }.toList()
      ..sort();

    final out = <FundamentalsSnapshot>[];
    for (final ano in anos) {
      final c = daCvm.where((s) => s.fiscalPeriodEnd.year == ano).firstOrNull;
      final m = porAno[ano];
      final merged = FundamentalsMerge.merge(cvm: c, mercado: m);
      if (merged == null) continue;
      out.add(merged.snapshot);
      if (c != null && m != null) {
        procedencia['${t.value}:$ano'] = merged.provenance;
      }
    }
    return Ok(out);
  }

  @override
  Future<Result<Asset>> profile(Ticker t) => interno.profile(t);

  @override
  Future<Result<List<Ticker>>> universe() => interno.universe();
}

String _pc(double? v) =>
    v == null ? '—' : '${(v * 100).toStringAsFixed(1)}%';

double? _mediana(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

Future<void> main(List<String> args) async {
  final cvm = _DaCvm.carregar('data/cvm_exercicios.json');
  stdout.writeln('== A1.7 — a ingestão ligada ao motor ==\n');
  stdout.writeln('  exercícios ingeridos: ${cvm.exercicios} '
      '(${cvm.companhias} companhias)');
  stdout.writeln('  tickers com exercício ANUAL da CVM: '
      '${cvm.porTicker.length}\n');

  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro,
      benchmark: ctx.benchmark,
      asOf: _hoje,
    ))
        .getOrElse(MarketAnchors.fallback2026);
    final universe = (await ctx.fundamentals.universe()).unwrap();
    final mesclado = _Mesclado(ctx.fundamentals, cvm);

    Future<ValuationResult?> avaliar(
      Ticker t,
      FundamentalsRepository fonte,
    ) async {
      final prep = await PrepareValuationInputs.call(
        ticker: t,
        prices: ctx.prices,
        fundamentals: fonte,
        benchmark: ctx.benchmark,
        riskFreeRate: anchors.currentRiskFreeRate,
        asOf: _hoje,
        perpetualGrowthCap: anchors.nominalEconomyGrowth,
        inflation: anchors.inflationCagr,
        terminalRiskFreeRate: anchors.riskFreeCagr,
        projectionYears: 10,
      );
      if (prep.isErr) return null;
      final r = ValuationCascade.evaluate(prep.unwrap());
      return r.isOk ? r.unwrap() : null;
    }

    final linhas = <Map<String, Object?>>[];
    var i = 0;
    for (final t in universe) {
      i++;
      if (i % 25 == 0) stderr.write('  $i/${universe.length}   \r');
      final antes = await avaliar(t, ctx.fundamentals);
      final depois = await avaliar(t, mesclado);
      if (antes == null && depois == null) continue;
      linhas.add({
        'ticker': t.value,
        'temCvm': cvm.porTicker.containsKey(t.value),
        'potencialAntes': antes?.upside,
        'potencialDepois': depois?.upside,
        'justoAntes': antes?.fairValue.reais,
        'justoDepois': depois?.fairValue.reais,
        'modeloAntes': antes?.model.name,
        'modeloDepois': depois?.model.name,
      });
    }
    stderr.writeln('');

    final comAmbos = linhas
        .where((l) => l['potencialAntes'] != null && l['potencialDepois'] != null)
        .toList();
    final novos = linhas
        .where((l) => l['potencialAntes'] == null && l['potencialDepois'] != null)
        .toList();
    final perdidos = linhas
        .where((l) => l['potencialAntes'] != null && l['potencialDepois'] == null)
        .toList();

    stdout.writeln('  tickers com série da CVM : ${mesclado.comCvm}');
    stdout.writeln('  tickers só de mercado    : ${mesclado.semCvm}');
    stdout.writeln('');
    stdout.writeln('  avaliados antes  : '
        '${linhas.where((l) => l['potencialAntes'] != null).length}');
    stdout.writeln('  avaliados depois : '
        '${linhas.where((l) => l['potencialDepois'] != null).length}');
    stdout.writeln('  GANHOS  (só depois): ${novos.length}  '
        '${novos.map((l) => l['ticker']).take(12).join(" ")}');
    stdout.writeln('  PERDIDOS (só antes): ${perdidos.length}  '
        '${perdidos.map((l) => l['ticker']).take(12).join(" ")}');

    if (comAmbos.isNotEmpty) {
      final dif = [
        for (final l in comAmbos)
          (l['potencialDepois']! as double) - (l['potencialAntes']! as double)
      ];
      final absDif = [for (final d in dif) d.abs()];
      stdout.writeln('');
      stdout.writeln('  dos ${comAmbos.length} avaliados nas duas montagens:');
      stdout.writeln('    mediana do |Δ potencial| : ${_pc(_mediana(absDif))}');
      stdout.writeln('    moveram mais de 1 p.p.   : '
          '${absDif.where((d) => d > 0.01).length}');
      stdout.writeln('    moveram mais de 10 p.p.  : '
          '${absDif.where((d) => d > 0.10).length}');
      comAmbos.sort((a, b) => (((b['potencialDepois']! as double) -
              (b['potencialAntes']! as double))
          .abs())
          .compareTo(((a['potencialDepois']! as double) -
                  (a['potencialAntes']! as double))
              .abs()));
      stdout.writeln('\n    os dez que mais se moveram:');
      stdout.writeln('    ticker      antes     depois      Δ');
      for (final l in comAmbos.take(10)) {
        final a = l['potencialAntes']! as double;
        final d = l['potencialDepois']! as double;
        stdout.writeln('    ${(l['ticker']! as String).padRight(8)} '
            '${_pc(a).padLeft(9)} ${_pc(d).padLeft(10)} '
            '${_pc(d - a).padLeft(9)}');
      }
    }

    // Procedência: quantos campos vieram de cada fonte, no agregado.
    final total = <FieldSource, int>{};
    for (final p in mesclado.procedencia.values) {
      p.contagem.forEach((k, v) => total[k] = (total[k] ?? 0) + v);
    }
    stdout.writeln('\n  procedência dos campos, sobre '
        '${mesclado.procedencia.length} exercícios mesclados:');
    for (final e in total.entries) {
      stdout.writeln('    ${e.key.label.padRight(18)} ${e.value}');
    }
    final exemplo = mesclado.procedencia.entries.firstOrNull;
    if (exemplo != null) {
      stdout.writeln('    exemplo (${exemplo.key}): da CVM vieram '
          '${exemplo.value.daCvm.length} campos');
    }

    File('docs/validacao/cvm_ligacao.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(linhas),
    );
    stdout.writeln('\n  gravado docs/validacao/cvm_ligacao.json');
  } finally {
    await ctx.dispose();
  }
}

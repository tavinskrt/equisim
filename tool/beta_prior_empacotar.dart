// B11 — resolve o prior transversal do beta e o empacota para o aplicativo.
//
// **Por que empacotar.** `ResolveBetaPrior` varre o universo inteiro — cinco
// anos de cotação, o histórico de fundamentos e o perfil de cada papel — para
// produzir uma mediana. O aplicativo não paga isso a cada abertura de tela, e
// sem o prior não há beta desalavancado: o motor cai no beta cru e no WACC
// estático, que são o recuo das decisões 40 e 41, e o caminho de taxas
// resolvido das decisões 41 a 46 nunca age em produção.
//
// **Sobre a entrada congelada do gabarito, por padrão.** O prior tem de ser
// reproduzível junto com o resto dos pacotes versionados, que são todos de
// 14/09/2026: gerá-lo contra o dado do dia faria o pacote depender do que a
// fonte devolvesse naquele instante. `--agora` usa o cache vivo e a data de
// hoje, para quando o conjunto de pacotes for atualizado.
//
// **O programa também mede o que justifica o pacote**: resolve o prior em
// várias datas e mostra o quanto ele anda. Prior que se move depressa não pode
// ser empacotado; este anda pouco, e o número fica no registro em vez de ser
// suposto.
//
// Uso:
//   dart run tool/gabarito_cascata.dart          # congela a entrada
//   dart run tool/beta_prior_empacotar.dart
//   dart run tool/beta_prior_empacotar.dart --deriva   # mede a defasagem
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'package:equisim/data/repositories/b3_registry_repository.dart';
import 'package:equisim/data/repositories/cvm_fundamentals_repository.dart';

import 'validation/context.dart';

const _saida = 'assets/mercado/beta_prior.json';
const _cacheCongelado = 'data/gabarito/cache.sqlite';
const _universoCongelado = 'data/gabarito/universo.json';

/// A data de referência dos pacotes versionados.
final _hoje = DateTime(2026, 9, 14);

/// Datas em que o prior é remedido para a conferência de deriva, em dias antes
/// da data de referência. Um trimestre, um semestre e um ano.
const _defasagens = [90, 180, 365];

Future<void> main(List<String> args) async {
  final medirDeriva = args.contains('--deriva');
  final agora = args.contains('--agora');
  final data = agora ? DateTime.now() : _hoje;

  if (!agora && !File(_cacheCongelado).existsSync()) {
    stderr.writeln('sem entrada congelada em $_cacheCongelado. Rode antes:');
    stderr.writeln('  dart run tool/gabarito_cascata.dart');
    exitCode = 2;
    return;
  }

  final ctx = ValidationContext.create(
    outputDir: 'docs/validacao',
    cacheFile: agora ? null : _cacheCongelado,
    frozenCache: !agora,
  );
  try {
    final List<Ticker> tickers;
    if (!agora && File(_universoCongelado).existsSync()) {
      tickers = [
        for (final s
            in (jsonDecode(File(_universoCongelado).readAsStringSync()) as List)
                .cast<String>())
          Ticker.parse(s),
      ];
    } else {
      final universo = await ctx.fundamentals.universe();
      if (universo.isErr) {
        stderr.writeln('sem universo: ${universo.failureOrNull!.message}');
        exitCode = 2;
        return;
      }
      tickers = universo.unwrap();
    }

    // **A mesma camada de dados do aplicativo**, e não a de mercado crua: o
    // prior encolhe o beta contra a alavancagem e a mediana setorial, e as duas
    // saem dos fundamentos. A CVM mesclada e o setor da B3 por emissor são o
    // que o `fundamentalsRepositoryProvider` monta (decisões 80 e 87);
    // resolver o prior sobre outra camada daria um prior de outro motor.
    final registro = B3RegistryCodec.decodePackage(
        jsonDecode(File('assets/b3/emissores.json').readAsStringSync())
            as Map<String, dynamic>);
    final fundamentos = OfficialSectorFundamentalsRepository(
      inner: CvmFundamentalsRepository(
        mercado: ctx.fundamentals,
        carregarPacote: () async =>
            File('assets/cvm/documentos.json').readAsStringSync(),
        hoje: () => data,
      ),
      classificacao: (t) async => t.value.length >= 4
          ? registro[t.value.substring(0, 4)]?.classification
          : null,
    );
    final proventos = CashDividendsCodec.decode(
        jsonDecode(File('assets/b3/proventos.json').readAsStringSync())
            as Map<String, dynamic>);
    List<CashDividend> proventosDe(Ticker t) =>
        CashDividendsCodec.forTicker(proventos, t.value);

    Future<BetaPrior?> resolver(DateTime quando) => ResolveBetaPrior.call(
          tickers: tickers,
          prices: ctx.prices,
          fundamentals: fundamentos,
          benchmark: ctx.benchmark,
          asOf: quando,
          dividendsFor: proventosDe,
        );

    final prior = await resolver(data);
    if (prior == null) {
      stderr.writeln('prior não resolvido: nenhuma observação utilizável');
      exitCode = 2;
      return;
    }

    File(_saida)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(BetaPriorCodec.encode(
        prior,
        geradoEm: data,
        observations: tickers.length,
      )));

    stdout.writeln('== prior do beta, em ${_dia(data)} ==');
    stdout.writeln('  universo: ${prior.unleveredUniverse.toStringAsFixed(4)}');
    stdout.writeln('  dispersão: ${prior.dispersion.toStringAsFixed(4)}');
    stdout.writeln('  papéis varridos: ${tickers.length}');
    stdout.writeln('  setores com mediana própria: '
        '${prior.unleveredBySector.length}');
    for (final e in prior.unleveredBySector.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key))) {
      stdout.writeln('    ${e.key.padRight(28)} ${e.value.toStringAsFixed(4)}');
    }
    stdout.writeln('  gravado $_saida');

    if (!medirDeriva) return;
    stdout.writeln('\n== quanto o prior anda ==');
    stdout.writeln('  defasagem   universo            dispersão   setores');
    stdout.writeln('  na data     '
        '${prior.unleveredUniverse.toStringAsFixed(4)}              '
        '${prior.dispersion.toStringAsFixed(4)}      '
        '${prior.unleveredBySector.length}');
    for (final dias in _defasagens) {
      // **Dia civil, e não instante.** `subtract(Duration(days: n))` soma horas
      // absolutas, e no salto do horário de verão o corte *point-in-time* cai
      // um dia antes ou depois. O componente fora da faixa é normalizado pelo
      // próprio `DateTime`.
      final antes = await resolver(
          DateTime(data.year, data.month, data.day - dias));
      if (antes == null) {
        stdout.writeln('  −$dias dias: não resolvido');
        continue;
      }
      // O prior é mediana de betas desalavancados e não deveria ser zero; se
      // for, a razão não tem leitura, e imprimir `NaN%` seria pior que nada.
      // Comparação por tolerância, e não igualdade: `double` derivado de
      // mediana não chega a zero exato, e `== 0` deixaria o divisor passar.
      final du = prior.unleveredUniverse.abs() < 1e-12
          ? double.nan
          : (antes.unleveredUniverse / prior.unleveredUniverse - 1) * 100;
      stdout.writeln('  −${'$dias'.padRight(4)} dias  '
          '${antes.unleveredUniverse.toStringAsFixed(4)} '
          '(${du.isNaN ? '—' : '${du >= 0 ? '+' : ''}${du.toStringAsFixed(1)}%'})'
          '      ${antes.dispersion.toStringAsFixed(4)}      '
          '${antes.unleveredBySector.length}');
    }
  } finally {
    await ctx.dispose();
  }
}

String _dia(DateTime d) => d.toIso8601String().substring(0, 10);

// Conferência do cálculo do usuário sobre o universo inteiro (decisão 147).
//
// **A promessa.** O botão "Editar valuation" abre a conta do motor congelada, e
// o usuário a refaz com os números dele. Duas coisas precisam ser verdade em
// cada ativo avaliado, e não só nos casos que os testes do núcleo montam:
//
// 1. **Sem nenhuma troca, o preço é o do motor** — igualdade exata, e o mesmo
//    centavo que a tela mostra.
// 2. **A conta responde como a teoria manda**: taxa mais alta dá preço mais
//    baixo; a decomposição de "onde você discorda" soma a diferença inteira; e
//    a taxa que "o preço de hoje supõe", quando existe, devolve o preço de
//    mercado.
//
// Roda sobre a entrada congelada de 14/09/2026, na montagem do aplicativo — a
// mesma do gabarito.
//
// Uso:
//   dart run tool/conferir_calculo_manual.dart
//   dart run tool/conferir_calculo_manual.dart --exemplo WEGE3
//
// Sai com código 1 quando alguma propriedade falha, e lista os ativos. Com
// `--exemplo`, imprime também o caso de um ativo — o preço do motor, o efeito
// de trocar cada campo e o que o preço de hoje supõe —, que é de onde saem os
// números do guia de estudo (capítulo 4, seção 4.16).

import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'validation/congelado.dart';

Future<void> main(List<String> args) async {
  final i = args.indexOf('--exemplo');
  final example = i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  final c = await Frozen.build();
  var evaluated = 0;
  var firm = 0;
  var shareholder = 0;
  var withSolution = 0;
  var withoutSolution = 0;
  var largestReverseDeviation = 0.0;
  final failures = <String>[];

  for (final t in c.universe) {
    final prep = await c.prepare(t);
    if (prep.isErr) continue;
    final r = ValuationCascade.evaluate(prep.unwrap());
    if (r.isErr) continue;
    final res = r.unwrap();
    evaluated++;
    final m = res.manual;
    if (m == null) {
      failures.add('${t.value}: avaliado sem a conta congelada');
      continue;
    }
    if (m.lane == ValuationLane.firm) {
      firm++;
    } else {
      shareholder++;
    }
    final p = m.enginePremises;
    if (example == t.value) _printExample(t, m);

    // 1. Sem troca, o preço do motor.
    final without = m.evaluate(p);
    if (without.isErr) {
      failures.add('${t.value}: sem troca, a conta recusou — '
          '${without.failureOrNull!.message}');
      continue;
    }
    final yours = without.unwrap().fairValuePerShare;
    if (yours != m.engineFairValue) {
      failures.add('${t.value}: sem troca, $yours contra ${m.engineFairValue} '
          'do motor');
    }
    if (Money.fromReais(yours) != res.fairValue) {
      failures.add('${t.value}: sem troca, ${Money.fromReais(yours)} contra '
          '${res.fairValue} na tela');
    }

    // 2a. Taxa mais alta, preço mais baixo.
    final high = m.evaluate(p.copyWith(discountRate: p.discountRate + 0.01));
    if (high.isOk && high.unwrap().fairValuePerShare >= yours) {
      failures.add('${t.value}: +1 p.p. de taxa não baixou o preço');
    }

    // 2b. A decomposição soma a diferença inteira.
    final swapped = p.copyWith(
      baseProfit: p.baseProfit * 1.1,
      growth: p.growth + 0.01,
      discountRate: p.discountRate - 0.005,
    );
    final swappedResult = m.evaluate(swapped);
    if (swappedResult.isOk) {
      final steps = m.attribution(swapped);
      final sum = steps.fold(0.0, (s, d) => s + (d.delta ?? double.nan));
      final target = swappedResult.unwrap().fairValuePerShare - m.engineFairValue;
      if (!((sum - target).abs() <= 1e-6 * (1 + target.abs()))) {
        failures.add('${t.value}: degraus somam $sum, a diferença é $target');
      }
    }

    // 2c. A taxa que o preço de hoje supõe devolve o preço de mercado.
    final s = m.solve(ManualField.discountRate, p);
    final v = s.value;
    if (v == null) {
      withoutSolution++;
    } else {
      withSolution++;
      final price = m.evaluate(p.copyWith(discountRate: v));
      final d = price.isOk
          ? (price.unwrap().fairValuePerShare - m.marketPrice).abs()
          : double.infinity;
      if (d > largestReverseDeviation) largestReverseDeviation = d;
      if (d > 0.005) {
        failures.add('${t.value}: a taxa de ${(v * 100).toStringAsFixed(2)}% '
            'dá preço a $d do de mercado');
      }
    }
  }

  stdout.writeln('ativos avaliados: $evaluated '
      '($firm pela via da firma, $shareholder pela do acionista)');
  stdout.writeln('a taxa que o preço de hoje supõe: $withSolution com solução, '
      '$withoutSolution sem; maior desvio do preço de mercado: '
      'R\$ ${largestReverseDeviation.toStringAsExponential(2)}');
  if (failures.isEmpty) {
    stdout.writeln('CONTA DO USUÁRIO CONFERIDA: sem troca, o preço do motor '
        'em todos os ativos, ao centavo e bit a bit.');
    exit(0);
  }
  stdout.writeln('FALHAS (${failures.length}):');
  for (final f in failures) {
    stdout.writeln('  $f');
  }
  exit(1);
}

String _pct(double v) => '${(v * 100).toStringAsFixed(2)}%';
String _rs(double v) => 'R\$ ${v.toStringAsFixed(2)}';
String _inMillions(double v) => 'R\$ ${(v / 1e6).toStringAsFixed(1)} mi';

/// O caso de um ativo, para o guia de estudo.
void _printExample(Ticker t, ManualValuation m) {
  final p = m.enginePremises;
  double price(ManualPremises x) =>
      m.evaluate(x).valueOrNull?.fairValuePerShare ?? double.nan;
  final o = m.evaluate(p).unwrap();
  stdout.writeln('--- exemplo ${t.value} (${m.lane.name}) ---');
  stdout.writeln('preço de mercado ${_rs(m.marketPrice)}; motor '
      '${_rs(m.engineFairValue)}');
  stdout.writeln('lucro de partida ${_inMillions(p.baseProfit)}'
      '${m.publishedBase == null ? '' : ' (último exercício ${_inMillions(m.publishedBase!)})'}; '
      'crescimento ${_pct(p.growth)}; taxa ${_pct(p.discountRate)} no ano 1 e '
      '${_pct(m.engineTerminalRate)} na perpetuidade; perpetuidade '
      '${_pct(p.perpetualGrowth)}; retorno ${_pct(p.returnOnCapital)}; '
      'capital novo ${p.terminalReturn == null ? 'igual à taxa' : _pct(p.terminalReturn!)}');
  stdout.writeln('VP dos 10 anos ${_inMillions(o.explicitPresentValue)}; VP da '
      'perpetuidade ${_inMillions(o.terminalPresentValue)}; patrimônio '
      '${_inMillions(o.equityValue)}; ações ${(m.shares / 1e6).toStringAsFixed(1)} mi');
  stdout.writeln('taxa −1 p.p.: ${_rs(price(p.copyWith(discountRate: p.discountRate - 0.01)))}; '
      '+1 p.p.: ${_rs(price(p.copyWith(discountRate: p.discountRate + 0.01)))}');
  stdout.writeln('taxa constante de ${_pct(p.discountRate)}: '
      '${_rs(price(p.copyWith(ratePath: ManualRatePath.constant)))}');
  stdout.writeln('crescimento +2 p.p.: ${_rs(price(p.copyWith(growth: p.growth + 0.02)))}; '
      'lucro do último exercício: '
      '${m.publishedBase == null ? '—' : _rs(price(p.copyWith(baseProfit: m.publishedBase)))}');
  stdout.writeln('capital novo rendendo a taxa + 5 p.p.: '
      '${_rs(price(p.copyWith(terminalReturn: m.engineTerminalRate + 0.05)))}');
  for (final f in [
    ManualField.discountRate,
    ManualField.growth,
    ManualField.baseProfit,
  ]) {
    final s = m.solve(f, p);
    final v = s.value;
    stdout.writeln('o preço de hoje supõe ${f.name} = '
        '${v == null ? 'sem solução' : f == ManualField.baseProfit ? _inMillions(v) : _pct(v)}');
  }
}

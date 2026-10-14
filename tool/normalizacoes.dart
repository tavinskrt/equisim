// Por que o lucro de partida de cada ativo foi normalizado, e em que direção.
//
// **O pedido.** O orientador refez os valuations por Gordon e chegou aos preços
// do motor por centavos; pediu, em 14/10/2026, que se detalhasse o motivo das
// normalizações — por que acontecem, e por que para cima ou para baixo —, sem
// retirá-las. Esta ferramenta lista a decisão de cada ativo avaliado, com os
// números que a tomaram: o retorno do último exercício, o típico (a mediana dos
// oito anteriores), o teste de destoar, as travas e o fator.
//
// Roda sobre a entrada congelada de 14/09/2026, na montagem do aplicativo — a
// mesma do gabarito —, e lê o registro `BaseNormalization` que a cascata deixa
// nos diagnósticos: nada aqui recalcula a guarda.
//
// Uso:
//   dart run tool/normalizacoes.dart
//
// Grava docs/validacao/normalizacoes.md.

import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'validation/congelado.dart';

const _saida = 'docs/validacao/normalizacoes.md';

String _pct(double? v) =>
    v == null ? '—' : '${(v * 100).toStringAsFixed(1).replaceAll('.', ',')}%';

String _num(double? v, [int casas = 2]) =>
    v == null ? '—' : v.toStringAsFixed(casas).replaceAll('.', ',');

String _resultado(BaseNormalizationOutcome o) => switch (o) {
      BaseNormalizationOutcome.paraCima => 'para cima',
      BaseNormalizationOutcome.paraBaixo => 'para baixo',
      BaseNormalizationOutcome.dentroDoNormal => 'dentro do normal',
      BaseNormalizationOutcome.tendencia => 'novo patamar (tendência)',
      BaseNormalizationOutcome.travadaPelaSaude => 'travada pela queda',
      BaseNormalizationOutcome.reconstruida => 'reconstruída do ciclo',
      BaseNormalizationOutcome.semCiclo => 'sem ciclo medível',
      BaseNormalizationOutcome.imposta => 'imposta',
    };

/// Por que destoou: pela razão, pela distância ou pelos dois.
String _criterio(BaseNormalization n) {
  final r = n.ratio;
  final z = n.robustZ;
  if (r == null || z == null) return '—';
  final pelaRazao =
      r < ValuationParameters.bandLow || r > ValuationParameters.bandHigh;
  final pelaDistancia = z > ValuationParameters.robustZ;
  if (!n.deviates) return 'não destoou';
  if (pelaRazao && pelaDistancia) return 'razão e distância';
  return pelaRazao ? 'razão' : 'distância';
}

String _observacao(BaseNormalization n) => [
      if (n.saturated)
        'fator limitado (pedia ${_num(n.rawFactor)}×)',
      if (n.cyclicalPrecedence &&
          n.trendDominates &&
          (n.outcome == BaseNormalizationOutcome.paraCima ||
              n.outcome == BaseNormalizationOutcome.paraBaixo))
        'commodity: ciclo antes da tendência',
      if (n.healthCapped)
        'queda de ${_pct(n.operationalDecline)} em 3 anos (pedia ${_num(n.rawFactor)}×)',
      if (n.healthExempt && n.factor > 1)
        'queda de ${_pct(n.operationalDecline)}, isenta por ser commodity',
      if (n.rebuilt)
        '${_pct(n.rebuiltPositiveShare)} da janela no lucro',
    ].join('; ');

Future<void> main(List<String> args) async {
  final c = await Congelado.montar();
  final linhas = <({Ticker t, BaseNormalization n})>[];
  for (final t in c.universo) {
    final prep = await c.preparar(t);
    if (prep.isErr) continue;
    final r = ValuationCascade.evaluate(prep.unwrap());
    if (r.isErr) continue;
    final n = r.unwrap().diagnostics?.baseNormalization;
    if (n != null) linhas.add((t: t, n: n));
  }

  final ordem = BaseNormalizationOutcome.values;
  linhas.sort((a, b) {
    final o = ordem.indexOf(a.n.outcome).compareTo(ordem.indexOf(b.n.outcome));
    if (o != 0) return o;
    return b.n.factor.compareTo(a.n.factor);
  });
  final contagem = <BaseNormalizationOutcome, int>{
    for (final o in ordem) o: linhas.where((l) => l.n.outcome == o).length,
  };

  final md = StringBuffer()
    ..writeln('# Por que o lucro de partida foi normalizado')
    ..writeln()
    ..writeln('Gerado por `dart run tool/normalizacoes.dart` sobre a entrada '
        'congelada de 14/09/2026, na montagem do aplicativo. Pedido do '
        'orientador em 14/10/2026: o porquê de cada normalização e a direção '
        'dela. **Não edite à mão.**')
    ..writeln()
    ..writeln('## A regra, em uma frase')
    ..writeln()
    ..writeln('Um ano só pode ter sido um pico ou um vale, e o preço justo é '
        'proporcional ao lucro de partida. O motor compara o retorno sobre o '
        'capital do último exercício com o **retorno típico** da empresa — a '
        'mediana dos 8 exercícios anteriores — e, quando os dois destoam, '
        'parte do lucro que a empresa de hoje teria rendendo o típico:')
    ..writeln()
    ..writeln('```')
    ..writeln('fator = típico ÷ último   (limitado entre '
        '${_num(ValuationParameters.baseFactorFloor)} e '
        '${_num(ValuationParameters.baseFactorCeiling)})')
    ..writeln('lucro de partida = lucro publicado × fator')
    ..writeln('```')
    ..writeln()
    ..writeln('- **Para cima** quando o último ano rendeu abaixo do típico (um '
        'vale); **para baixo** quando rendeu acima (um pico).')
    ..writeln('- **Destoa** quando o último ano dividido pelo típico sai de '
        '${_num(ValuationParameters.bandLow)} a '
        '${_num(ValuationParameters.bandHigh)} (*razão*), ou quando a '
        'distância entre os dois passa de '
        '${_num(ValuationParameters.robustZ, 1)} desvios típicos da janela '
        '(*distância*).')
    ..writeln('- **Não normaliza** quando o retorno tem tendência que domina a '
        'volta ao típico (o último ano é o novo patamar) — exceto em '
        'commodity, onde a alta do ciclo tem cara de tendência —, nem para '
        'cima quando o lucro ou o EBITDA caiu mais de '
        '${_pct(ValuationParameters.maxOperationalDecline)} em 3 anos.')
    ..writeln('- **Reconstrói** quando o último ano deu prejuízo: o típico sobre '
        'o capital de hoje, se ele é positivo e ao menos '
        '${_pct(ValuationParameters.minPositiveFlow)} da janela deu lucro.')
    ..writeln()
    ..writeln('O porquê de cada ativo também está no painel de logs, no passo '
        '"Base do fluxo", e na tela Editar valuation, no cartão do lucro de '
        'partida.')
    ..writeln()
    ..writeln('## Quantos, de ${linhas.length} avaliados')
    ..writeln()
    ..writeln('| Resultado | Ativos |')
    ..writeln('|---|---|');
  for (final o in ordem) {
    if (contagem[o]! > 0) md.writeln('| ${_resultado(o)} | ${contagem[o]} |');
  }
  md
    ..writeln()
    ..writeln('## Ativo a ativo')
    ..writeln()
    ..writeln('"Último" é o retorno sobre o capital (via da firma) ou sobre o '
        'patrimônio (via do acionista) do exercício mais recente; "típico" é '
        'a mediana dos anteriores. "Destoou por" diz qual critério decidiu.')
    ..writeln()
    ..writeln('| Ativo | Via | Resultado | Último | Típico (anos) | Razão | '
        'Desvios | Destoou por | Fator | Observação |')
    ..writeln('|---|---|---|---|---|---|---|---|---|---|');
  for (final l in linhas) {
    final n = l.n;
    final anos = n.windowYears;
    md.writeln(
      '| ${l.t.value} '
      '| ${n.lane == ValuationLane.firm ? 'firma' : 'acionista'} '
      '| ${_resultado(n.outcome)} '
      '| ${_pct(n.latestReturn)} (${n.latestYear ?? '—'}) '
      '| ${_pct(n.cycleReturn)} '
      '(${anos == null ? '—' : '${anos.first}–${anos.last}'}) '
      '| ${_num(n.ratio)} '
      '| ${_num(n.robustZ, 1)} '
      '| ${_criterio(n)} '
      '| ${_num(n.factor)}× '
      '| ${_observacao(n)} |',
    );
  }
  File(_saida).writeAsStringSync(md.toString());

  stdout.writeln('avaliados: ${linhas.length}');
  for (final o in ordem) {
    if (contagem[o]! > 0) stdout.writeln('  ${_resultado(o)}: ${contagem[o]}');
  }
  stdout.writeln('gravado $_saida');
}

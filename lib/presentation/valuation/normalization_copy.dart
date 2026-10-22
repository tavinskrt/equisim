import 'package:equisim_core/equisim_core.dart';

import '../shared/ui_kit.dart';

/// O texto que explica a normalização do lucro de partida, na tela.
///
/// **O núcleo diz o que decidiu, e com que números** — em [BaseNormalization];
/// a frase é montada aqui, com a formatação brasileira, como as decisões 122 e
/// 125 pedem. O rastro de auditoria tem a explicação dele, escrita pelo núcleo
/// na mesma ordem e com os mesmos números: o painel de logs é rastro, e a tela é
/// tela.
///
/// Pedido do orientador em 14/10/2026: entender o porquê das normalizações e a
/// direção de cada uma, e não retirá-las.
abstract final class NormalizationCopy {
  /// O nome do retorno da via, como se diz.
  static String returnRate(ValuationLane lane) => lane == ValuationLane.firm
      ? 'retorno sobre o capital investido'
      : 'retorno sobre o patrimônio';

  static String _pct(double? v) => v == null ? '—' : Fmt.percent(v, decimals: 1);

  static String _inMillions(double v) =>
      'R\$ ${Fmt.ratio(v / 1e6, decimals: 1)} mi';

  static String _x(double v) => '×${Fmt.ratio(v, decimals: 2)}';

  /// A pergunta que abre a explicação.
  static String question(BaseNormalization n) => switch (n.outcome) {
        BaseNormalizationOutcome.upward =>
          'Por que o motor subiu o lucro de partida?',
        BaseNormalizationOutcome.downward =>
          'Por que o motor baixou o lucro de partida?',
        BaseNormalizationOutcome.rebuilt =>
          'Por que o motor reconstruiu o lucro de partida?',
        BaseNormalizationOutcome.imposed => 'Por que este fator?',
        BaseNormalizationOutcome.withinNormal ||
        BaseNormalizationOutcome.trend ||
        BaseNormalizationOutcome.healthLocked ||
        BaseNormalizationOutcome.noCycle =>
          'Por que o motor usou o lucro publicado?',
      };

  /// O resumo em duas ou três palavras, para o selo.
  static String badge(BaseNormalization n) => switch (n.outcome) {
        BaseNormalizationOutcome.upward => 'Para cima, ${_x(n.factor)}',
        BaseNormalizationOutcome.downward => 'Para baixo, ${_x(n.factor)}',
        BaseNormalizationOutcome.withinNormal => 'Dentro do normal',
        BaseNormalizationOutcome.trend => 'Novo patamar',
        BaseNormalizationOutcome.healthLocked => 'Travada pela queda',
        BaseNormalizationOutcome.rebuilt => 'Reconstruído do ciclo',
        BaseNormalizationOutcome.noCycle => 'Sem ciclo medível',
        BaseNormalizationOutcome.imposed => 'Imposto, ${_x(n.factor)}',
      };

  /// A regra, que vale para todo ativo.
  static String rule(BaseNormalization n) {
    final years = n.windowYears;
    final window = years == null ? '' : ', de ${years.first} a ${years.last}';
    return 'Um ano só pode ter sido um pico ou um vale, e o preço justo é '
        'proporcional ao lucro de partida. Por isso o motor compara o '
        '${returnRate(n.lane)} do último exercício com o retorno típico da '
        'empresa — a mediana dos ${n.cycleWindow.length} exercícios '
        'anteriores$window — e só parte de outro lucro quando os dois '
        'destoam.';
  }

  /// A resposta para este ativo, com os números dele.
  static String answer(BaseNormalization n) {
    final year = n.latestYear;
    final current = _pct(n.latestReturn);
    final typical = _pct(n.cycleReturn);
    return switch (n.outcome) {
      BaseNormalizationOutcome.upward =>
        'Em $year a empresa rendeu $current, abaixo do seu típico de $typical. O '
            'motor lê o último ano como um vale e parte do lucro que a empresa '
            'de hoje teria rendendo o típico: ${_x(n.factor)} sobre o lucro '
            'publicado.',
      BaseNormalizationOutcome.downward =>
        'Em $year a empresa rendeu $current, acima do seu típico de $typical. O '
            'motor lê o último ano como um pico e parte do lucro que a empresa '
            'de hoje teria rendendo o típico: ${_x(n.factor)} sobre o lucro '
            'publicado.',
      BaseNormalizationOutcome.withinNormal =>
        'Em $year a empresa rendeu $current, contra o seu típico de $typical — '
            'dentro do normal dela. Não há o que corrigir, e a base é o lucro '
            'publicado.',
      BaseNormalizationOutcome.trend =>
        '$current em $year destoa do típico de $typical, mas o retorno vem mudando '
            'de patamar ano a ano, e em '
            '${ValuationParameters.trendDriftWindow} anos essa tendência anda '
            'mais do que a volta ao típico. O motor lê o último ano como o novo '
            'normal, e a base é o lucro publicado.',
      BaseNormalizationOutcome.healthLocked =>
        '$current em $year está abaixo do típico de $typical, e o motor subiria a '
            'base ${_x(n.rawFactor)}. Não subiu porque o lucro ou o EBITDA caiu '
            '${_pct(n.operationalDecline)} em '
            '${ValuationParameters.operationalHealthWindow} anos, mais que o '
            'limite de '
            '${Fmt.percent(ValuationParameters.maxOperationalDecline, decimals: 0)}: '
            'quem perdeu mais da metade do resultado mudou de patamar, e '
            'trazê-lo de volta ao típico lhe daria um retorno que não vai se '
            'repetir. A base é o lucro publicado.',
      BaseNormalizationOutcome.rebuilt =>
        'Em $year a empresa deu prejuízo ($current), e não há fator que corrija um '
            'lucro negativo. Com o típico positivo ($typical) e '
            '${_pct(n.rebuiltPositiveShare)} da janela no lucro, o motor parte '
            'do típico sobre o capital de hoje: a afirmação de que a empresa '
            'volta ao que já foi.',
      BaseNormalizationOutcome.noCycle =>
        'A série não tem um retorno típico positivo com que comparar o último '
            'ano, e a base é o lucro publicado.',
      BaseNormalizationOutcome.imposed =>
        'O fator foi imposto de fora, por varredura de diagnóstico.',
    };
  }

  /// O teste de destoar, com os dois critérios, ou `null` quando ele não foi
  /// o que decidiu.
  static String? test(BaseNormalization n) {
    final ratio = n.ratio;
    final z = n.robustZ;
    if (ratio == null || z == null) return null;
    if (n.outcome == BaseNormalizationOutcome.rebuilt ||
        n.outcome == BaseNormalizationOutcome.noCycle ||
        n.outcome == BaseNormalizationOutcome.imposed) {
      return null;
    }
    final byRatio = ratio < ValuationParameters.bandLow ||
        ratio > ValuationParameters.bandHigh;
    final byDistance = z > ValuationParameters.robustZ;
    final verdict = !n.deviates
        ? 'Os dois dentro do normal: não destoou.'
        : byRatio && byDistance
            ? 'Destoou pelos dois critérios.'
            : byRatio
                ? 'Destoou pela razão.'
                : 'Destoou pela distância.';
    return 'O teste: o último ano dividido pelo típico dá '
        '${Fmt.ratio(ratio, decimals: 2)} — o normal vai de '
        '${Fmt.ratio(ValuationParameters.bandLow, decimals: 2)} a '
        '${Fmt.ratio(ValuationParameters.bandHigh, decimals: 2)} —, e a '
        'distância entre os dois é de ${Fmt.ratio(z, decimals: 1)} desvios '
        'típicos da janela — o normal vai até '
        '${Fmt.ratio(ValuationParameters.robustZ, decimals: 1)}. $verdict';
  }

  /// A conta da base, ou `null` quando a base é o lucro publicado.
  static String? account(BaseNormalization n) {
    final published = n.publishedProfit;
    final base = n.baseProfit;
    if (published == null || base == null) return null;
    return switch (n.outcome) {
      BaseNormalizationOutcome.upward ||
      BaseNormalizationOutcome.downward ||
      BaseNormalizationOutcome.imposed =>
        'A conta: ${_inMillions(published)} × ${Fmt.ratio(n.factor, decimals: 2)} = '
            '${_inMillions(base)}'
            '${n.saturated ? '' : ' — o mesmo que o capital com que a empresa começou ${n.latestYear} rendendo o típico de ${_pct(n.cycleReturn)}'}.',
      BaseNormalizationOutcome.rebuilt =>
        'A conta: o típico de ${_pct(n.cycleReturn)} sobre o capital de hoje '
            'dá ${_inMillions(base)}, no lugar do prejuízo de ${_inMillions(published)}.',
      _ => null,
    };
  }

  /// O que mais pesou na decisão, além do teste.
  static List<String> warnings(BaseNormalization n) {
    final out = <String>[];
    if (n.saturated) {
      out.add(
        'Limite: a razão pedia ${_x(n.rawFactor)}, e o fator foi limitado a '
        '${_x(n.factor)}. Ele fica entre '
        '${Fmt.ratio(ValuationParameters.baseFactorFloor, decimals: 2)} e '
        '${Fmt.ratio(ValuationParameters.baseFactorCeiling, decimals: 2)} '
        'porque a normalização corrige um ano, e não inventa uma empresa.',
      );
    }
    if (n.cyclicalPrecedence &&
        n.trendDominates &&
        (n.outcome == BaseNormalizationOutcome.upward ||
            n.outcome == BaseNormalizationOutcome.downward)) {
      out.add(
        'O retorno tem tendência, mas a empresa é de commodity ou de setor '
        'cíclico pesado: ali a alta do ciclo tem cara de tendência, e o ciclo '
        'tem precedência (decisão 28).',
      );
    }
    if (n.healthExempt && n.factor > 1) {
      out.add(
        'O lucro ou o EBITDA caiu ${_pct(n.operationalDecline)} em '
        '${ValuationParameters.operationalHealthWindow} anos, mas em commodity '
        'a queda entre pico e vale é do preço do insumo, e não mudança de '
        'patamar: a trava que impede subir não se aplica (decisão 30).',
      );
    }
    return out;
  }
}

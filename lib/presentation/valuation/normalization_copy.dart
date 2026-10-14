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
  static String retorno(ValuationLane via) => via == ValuationLane.firm
      ? 'retorno sobre o capital investido'
      : 'retorno sobre o patrimônio';

  static String _pct(double? v) => v == null ? '—' : Fmt.percent(v, decimals: 1);

  static String _mi(double v) =>
      'R\$ ${Fmt.ratio(v / 1e6, decimals: 1)} mi';

  static String _x(double v) => '×${Fmt.ratio(v, decimals: 2)}';

  /// A pergunta que abre a explicação.
  static String pergunta(BaseNormalization n) => switch (n.outcome) {
        BaseNormalizationOutcome.paraCima =>
          'Por que o motor subiu o lucro de partida?',
        BaseNormalizationOutcome.paraBaixo =>
          'Por que o motor baixou o lucro de partida?',
        BaseNormalizationOutcome.reconstruida =>
          'Por que o motor reconstruiu o lucro de partida?',
        BaseNormalizationOutcome.imposta => 'Por que este fator?',
        BaseNormalizationOutcome.dentroDoNormal ||
        BaseNormalizationOutcome.tendencia ||
        BaseNormalizationOutcome.travadaPelaSaude ||
        BaseNormalizationOutcome.semCiclo =>
          'Por que o motor usou o lucro publicado?',
      };

  /// O resumo em duas ou três palavras, para o selo.
  static String selo(BaseNormalization n) => switch (n.outcome) {
        BaseNormalizationOutcome.paraCima => 'Para cima, ${_x(n.factor)}',
        BaseNormalizationOutcome.paraBaixo => 'Para baixo, ${_x(n.factor)}',
        BaseNormalizationOutcome.dentroDoNormal => 'Dentro do normal',
        BaseNormalizationOutcome.tendencia => 'Novo patamar',
        BaseNormalizationOutcome.travadaPelaSaude => 'Travada pela queda',
        BaseNormalizationOutcome.reconstruida => 'Reconstruído do ciclo',
        BaseNormalizationOutcome.semCiclo => 'Sem ciclo medível',
        BaseNormalizationOutcome.imposta => 'Imposto, ${_x(n.factor)}',
      };

  /// A regra, que vale para todo ativo.
  static String regra(BaseNormalization n) {
    final anos = n.windowYears;
    final janela = anos == null ? '' : ', de ${anos.first} a ${anos.last}';
    return 'Um ano só pode ter sido um pico ou um vale, e o preço justo é '
        'proporcional ao lucro de partida. Por isso o motor compara o '
        '${retorno(n.lane)} do último exercício com o retorno típico da '
        'empresa — a mediana dos ${n.cycleWindow.length} exercícios '
        'anteriores$janela — e só parte de outro lucro quando os dois '
        'destoam.';
  }

  /// A resposta para este ativo, com os números dele.
  static String resposta(BaseNormalization n) {
    final ano = n.latestYear;
    final atual = _pct(n.latestReturn);
    final tipico = _pct(n.cycleReturn);
    return switch (n.outcome) {
      BaseNormalizationOutcome.paraCima =>
        'Em $ano a empresa rendeu $atual, abaixo do seu típico de $tipico. O '
            'motor lê o último ano como um vale e parte do lucro que a empresa '
            'de hoje teria rendendo o típico: ${_x(n.factor)} sobre o lucro '
            'publicado.',
      BaseNormalizationOutcome.paraBaixo =>
        'Em $ano a empresa rendeu $atual, acima do seu típico de $tipico. O '
            'motor lê o último ano como um pico e parte do lucro que a empresa '
            'de hoje teria rendendo o típico: ${_x(n.factor)} sobre o lucro '
            'publicado.',
      BaseNormalizationOutcome.dentroDoNormal =>
        'Em $ano a empresa rendeu $atual, contra o seu típico de $tipico — '
            'dentro do normal dela. Não há o que corrigir, e a base é o lucro '
            'publicado.',
      BaseNormalizationOutcome.tendencia =>
        '$atual em $ano destoa do típico de $tipico, mas o retorno vem mudando '
            'de patamar ano a ano, e em '
            '${ValuationParameters.trendDriftWindow} anos essa tendência anda '
            'mais do que a volta ao típico. O motor lê o último ano como o novo '
            'normal, e a base é o lucro publicado.',
      BaseNormalizationOutcome.travadaPelaSaude =>
        '$atual em $ano está abaixo do típico de $tipico, e o motor subiria a '
            'base ${_x(n.rawFactor)}. Não subiu porque o lucro ou o EBITDA caiu '
            '${_pct(n.operationalDecline)} em '
            '${ValuationParameters.operationalHealthWindow} anos, mais que o '
            'limite de '
            '${Fmt.percent(ValuationParameters.maxOperationalDecline, decimals: 0)}: '
            'quem perdeu mais da metade do resultado mudou de patamar, e '
            'trazê-lo de volta ao típico lhe daria um retorno que não vai se '
            'repetir. A base é o lucro publicado.',
      BaseNormalizationOutcome.reconstruida =>
        'Em $ano a empresa deu prejuízo ($atual), e não há fator que corrija um '
            'lucro negativo. Com o típico positivo ($tipico) e '
            '${_pct(n.rebuiltPositiveShare)} da janela no lucro, o motor parte '
            'do típico sobre o capital de hoje: a afirmação de que a empresa '
            'volta ao que já foi.',
      BaseNormalizationOutcome.semCiclo =>
        'A série não tem um retorno típico positivo com que comparar o último '
            'ano, e a base é o lucro publicado.',
      BaseNormalizationOutcome.imposta =>
        'O fator foi imposto de fora, por varredura de diagnóstico.',
    };
  }

  /// O teste de destoar, com os dois critérios, ou `null` quando ele não foi
  /// o que decidiu.
  static String? teste(BaseNormalization n) {
    final razao = n.ratio;
    final z = n.robustZ;
    if (razao == null || z == null) return null;
    if (n.outcome == BaseNormalizationOutcome.reconstruida ||
        n.outcome == BaseNormalizationOutcome.semCiclo ||
        n.outcome == BaseNormalizationOutcome.imposta) {
      return null;
    }
    final pelaRazao = razao < ValuationParameters.bandLow ||
        razao > ValuationParameters.bandHigh;
    final pelaDistancia = z > ValuationParameters.robustZ;
    final veredito = !n.deviates
        ? 'Os dois dentro do normal: não destoou.'
        : pelaRazao && pelaDistancia
            ? 'Destoou pelos dois critérios.'
            : pelaRazao
                ? 'Destoou pela razão.'
                : 'Destoou pela distância.';
    return 'O teste: o último ano dividido pelo típico dá '
        '${Fmt.ratio(razao, decimals: 2)} — o normal vai de '
        '${Fmt.ratio(ValuationParameters.bandLow, decimals: 2)} a '
        '${Fmt.ratio(ValuationParameters.bandHigh, decimals: 2)} —, e a '
        'distância entre os dois é de ${Fmt.ratio(z, decimals: 1)} desvios '
        'típicos da janela — o normal vai até '
        '${Fmt.ratio(ValuationParameters.robustZ, decimals: 1)}. $veredito';
  }

  /// A conta da base, ou `null` quando a base é o lucro publicado.
  static String? conta(BaseNormalization n) {
    final publicado = n.publishedProfit;
    final base = n.baseProfit;
    if (publicado == null || base == null) return null;
    return switch (n.outcome) {
      BaseNormalizationOutcome.paraCima ||
      BaseNormalizationOutcome.paraBaixo ||
      BaseNormalizationOutcome.imposta =>
        'A conta: ${_mi(publicado)} × ${Fmt.ratio(n.factor, decimals: 2)} = '
            '${_mi(base)}'
            '${n.saturated ? '' : ' — o mesmo que o capital com que a empresa começou ${n.latestYear} rendendo o típico de ${_pct(n.cycleReturn)}'}.',
      BaseNormalizationOutcome.reconstruida =>
        'A conta: o típico de ${_pct(n.cycleReturn)} sobre o capital de hoje '
            'dá ${_mi(base)}, no lugar do prejuízo de ${_mi(publicado)}.',
      _ => null,
    };
  }

  /// O que mais pesou na decisão, além do teste.
  static List<String> avisos(BaseNormalization n) {
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
        (n.outcome == BaseNormalizationOutcome.paraCima ||
            n.outcome == BaseNormalizationOutcome.paraBaixo)) {
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

/// Porta 0 — elegibilidade e integridade contábil.
library;

import '../../entities/fundamentals.dart';
import '../../entities/price_series.dart';
import 'inference.dart';

/// Por que um ativo não é avaliável.
enum IneligibilityReason {
  /// Volume financeiro médio abaixo do corte.
  illiquid('liquidez insuficiente para formar preço confiável'),

  /// Exercícios publicados de menos para qualquer inferência.
  shortHistory('histórico curto demais para os testes das guardas'),

  /// Patrimônio líquido não positivo de forma persistente.
  insolvent('patrimônio líquido não positivo em exercícios consecutivos'),

  /// Continuidade formalmente suspensa.
  distressed('em recuperação judicial ou extrajudicial');

  final String label;
  const IneligibilityReason(this.label);
}

/// Veredito da Porta 0.
class EligibilityVerdict {
  /// `true` quando o ativo pode ser avaliado.
  final bool isEligible;

  /// Motivos de recusa, em ordem de verificação. Vazio quando elegível.
  final List<IneligibilityReason> reasons;

  /// Volume financeiro diário mediano medido, em reais. `null` sem série.
  final double? averageDailyTradedValue;

  /// Exercícios publicados considerados.
  final int publishedPeriods;

  const EligibilityVerdict({
    required this.isEligible,
    required this.reasons,
    required this.publishedPeriods,
    this.averageDailyTradedValue,
  });

  /// Frase única para a interface, ou `null` quando elegível.
  String? get message {
    if (isEligible) return null;
    return 'Ativo fora do universo analisável: '
        '${reasons.map((r) => r.label).join('; ')}.';
  }
}

/// Filtra o universo antes de qualquer decisão de modelo.
///
/// **Por que existe.** Os parâmetros das guardas foram calibrados sobre dezoito
/// ativos cujo volume financeiro diário mediano vai de R$ 36,6 mi a
/// R$ 1.541,9 mi. A mediana do universo negociável da B3 é de R$ 9,2 mi e o
/// primeiro quartil, R$ 1,9 mi — a amostra está inteira no decil superior de
/// liquidez. A Porta 0 torna essa fronteira explícita em vez de extrapolá-la em
/// silêncio (decisão 25).
abstract final class EligibilityGate {
  /// P1 — volume financeiro diário mediano mínimo, em reais.
  ///
  /// Com este corte, 161 dos 382 papéis-base da B3 permanecem analisáveis.
  ///
  /// **O que ele protege.** Pregão sem formação de preço gera retorno zero
  /// espúrio, que enviesa o beta para baixo por negociação não sincronizada —
  /// `β̂ → β(1 − θ)` com fração `θ` de pregões vazios. Beta menor reduz Ke e
  /// WACC e **infla** o preço justo: é o pior sentido possível de erro.
  static const double minAverageDailyTradedValue = 2000000.0;

  /// Pregões da janela de liquidez.
  static const int liquidityWindowDays = 90;

  /// P2 — exercícios publicados mínimos.
  ///
  /// Oito dá seis graus de liberdade, e é o menor `n` em que a janela de ciclo
  /// de oito anos ainda existe. Abaixo disso o teste de tendência não tem poder:
  /// com `n = 6`, só uma tendência que explique 53% da variância é detectável.
  static const int minPublishedPeriods = 8;

  /// Avalia a elegibilidade de um ativo.
  ///
  /// - [snapshots]: exercícios **já filtrados por publicação**.
  /// - [prices]: série de cotações; sem volume, o teste de liquidez é omitido
  ///   em vez de reprovar — cache antigo não tem a coluna, e recusar por dado
  ///   ausente confundiria falta de informação com falta de liquidez.
  /// - [isDistressed]: veio de lista externa. A fonte não publica situação de
  ///   recuperação judicial, e `isActive` marca negociabilidade, não
  ///   continuidade — os 786 tickers vêm todos com `isActive = true`.
  static EligibilityVerdict assess({
    required List<FundamentalsSnapshot> snapshots,
    PriceSeries? prices,
    bool isDistressed = false,
    double minTradedValue = minAverageDailyTradedValue,
    int minPeriods = minPublishedPeriods,
  }) {
    final motivos = <IneligibilityReason>[];

    final adtv = prices == null ? null : medianTradedValue(prices);
    if (adtv != null && adtv < minTradedValue) {
      motivos.add(IneligibilityReason.illiquid);
    }

    if (snapshots.length < minPeriods) {
      motivos.add(IneligibilityReason.shortHistory);
    }

    if (_insolvent(snapshots)) {
      motivos.add(IneligibilityReason.insolvent);
    }

    if (isDistressed) {
      motivos.add(IneligibilityReason.distressed);
    }

    return EligibilityVerdict(
      isEligible: motivos.isEmpty,
      reasons: motivos,
      publishedPeriods: snapshots.length,
      averageDailyTradedValue: adtv,
    );
  }

  /// Volume financeiro diário **mediano** dos últimos pregões.
  ///
  /// Mediana e não média: um leilão de bloco isolado distorce a média, e é
  /// exatamente o caso que o corte quer excluir.
  ///
  /// Devolve `null` quando a série não traz volume ou é curta demais para a
  /// janela — ausência de dado, que o chamador trata como omissão do teste, não
  /// como reprovação.
  static double? medianTradedValue(
    PriceSeries series, {
    int window = liquidityWindowDays,
  }) {
    final pontos = series.points;
    if (pontos.length < 20) return null;

    final ini = pontos.length > window ? pontos.length - window : 0;
    final financeiro = <double>[];
    for (var i = ini; i < pontos.length; i++) {
      final v = pontos[i].volume;
      if (v == null || v < 0) continue;
      financeiro.add(pontos[i].close * v);
    }
    if (financeiro.length < 20) return null;
    return Inference.median(financeiro);
  }

  /// Patrimônio não positivo no exercício mais recente **e** no anterior.
  ///
  /// Dois consecutivos, e não um: um exercício isolado de patrimônio negativo é
  /// evento a normalizar, e a Porta 2 tem mecanismo para isso. Persistente é
  /// outra coisa — sem base de capital não há ROE, ROIC, retenção nem
  /// crescimento fundamental, e as duas vias perdem o denominador.
  static bool _insolvent(List<FundamentalsSnapshot> s) {
    if (s.length < 2) return false;
    final ultimo = s.last.equityBookValue;
    final penultimo = s[s.length - 2].equityBookValue;
    bool ruim(double? v) => v == null || v <= 0;
    return ruim(ultimo) && ruim(penultimo);
  }
}

/// As guardas e saídas da Porta 2, conforme a decisão 25.
library;

import 'dart:math' as math;

import '../../entities/fundamentals.dart';
import 'capital_base.dart';
import 'inference.dart';

/// Parâmetros homologados das portas e guardas.
///
/// Todos foram calibrados sobre os dezoito ativos das carteiras de teste e a
/// sensibilidade de cada um está medida na seção 10.2 de
/// `docs/refinamento-do-valuation.md`. **Continuam sendo escolhas** — o ganho é
/// que passaram a ter interpretação (nível de significância, ponto de ruptura,
/// materialidade, precisão), não que dispensem calibragem.
///
/// A validação fora da amostra sobre os elegíveis da B3 é o que a completa.
abstract final class ValuationParameters {
  /// P3 — nível de significância dos testes de tendência e de dispersão.
  ///
  /// 10% e não 5%: com séries de 8 a 16 exercícios o poder é baixo, e um nível
  /// mais estrito faria os testes nunca rejeitarem. Medido: passar para 5% não
  /// muda nenhuma classificação da amostra.
  static const double alpha = 0.10;

  /// P4 — desvios robustos a partir dos quais o exercício é atípico.
  static const double robustZ = 1.5;

  /// P5 — banda de materialidade do nível do retorno, em razão contra o ciclo.
  ///
  /// Vale em **união** com [robustZ], não em substituição: o `z` mede raridade e
  /// a razão mede materialidade, e como o valor da perpetuidade é proporcional à
  /// base, é a razão que traduz impacto. Sob `z` puro a VALE3 deixaria de ser
  /// normalizada num vale de ciclo, o que inverteria o propósito da guarda.
  static const double bandLow = 0.75;
  static const double bandHigh = 1.33;

  /// P6 — capital externo tolerado, em múltiplos da base inicial da janela.
  static const double maxExternalCapital = 1.0;

  /// P7 — piso absoluto de materialidade da discordância entre estimadores.
  static const double dispersionFloor = 0.02;

  /// P8 — piso relativo da mesma discordância, em fração do próprio
  /// crescimento.
  static const double dispersionRelative = 0.25;

  /// P9 — fração de exercícios com fluxo de manutenção positivo exigida pela
  /// Porta 3.
  static const double minPositiveFlow = 0.60;

  /// P10 — participação mínima do equity no valor da firma, como
  /// **pós-condição** da via A.
  ///
  /// Não é pré-filtro: depende do valor da firma, que só existe depois do
  /// desconto. Ver `ValuationCascade`.
  static const double minEquityShare = 0.20;

  /// P11 — janela do ciclo, em exercícios.
  ///
  /// **O parâmetro mais sensível de todos.** Com 5 anos a PETR4 aparece a 0,65
  /// do ciclo; com 8, a 1,13; com a série toda, a 1,77. Cinco dos dezoito mudam
  /// de classificação conforme a janela.
  static const int cycleWindow = 8;

  /// P13 — erro-padrão máximo do estimador de crescimento.
  ///
  /// Existe porque a discordância `D` é uma razão e **encolhe quando o
  /// denominador explode**: dois estimadores ruins concordam por construção. A
  /// PRIO3 passa no teste `D` com 0,91 tendo `se(ĝ) = 9,9 p.p.` e intervalo de
  /// confiança de [16,9%; 51,9%] — sem este piso, o ativo mais imprecisamente
  /// medido da amostra receberia o maior crescimento.
  static const double maxGrowthStdError = 0.03;

  /// Inclinação mínima relativa: a deriva da tendência no horizonte precisa
  /// superar a correção que a reversão à média faria.
  static const double minTrendDominance = 1.0;

  // ------------------------------------- Vantagem competitiva residual --
  //
  // Colapsar toda empresa em `ROIC_∞ = WACC` trata franquia duradoura e
  // negócio comoditizado da mesma forma. A exceção existe, mas o preço dela é
  // alto: o valor terminal volta a depender de `g_∞`, que o retorno neutro
  // havia eliminado. Por isso as três condições são **cumulativas** e
  // deliberadamente restritivas — a exceção precisa ser rara para não desfazer
  // a robustez que a decisão 25 comprou.

  /// Fração do excedente de retorno preservada na perpetuidade.
  ///
  /// `ROIC_∞ = WACC_∞ + 0,30 · (ROIC_ciclo − WACC_∞)`: sete décimos da vantagem
  /// se dissolvem, três sobrevivem.
  static const double moatRetainedSpread = 0.30;

  /// Teto de capital externo para o crescimento ser considerado orgânico.
  ///
  /// Mais restritivo que [maxExternalCapital], que vale para a normalização da
  /// base: uma vantagem competitiva que precisa de emissão para se sustentar não
  /// é vantagem, é aporte.
  static const double moatMaxExternalCapital = 0.35;

  /// Múltiplo do custo de capital que o retorno do ciclo precisa alcançar.
  static const double moatReturnMultiple = 2.0;

  /// Exercícios mínimos de histórico para a vantagem ser considerada comprovada.
  ///
  /// Doze contra os oito da Porta 0: sustentar retorno excedente por mais de uma
  /// década é o que distingue franquia de fase boa do ciclo.
  static const int moatMinPeriods = 12;

}

/// Como o crescimento foi obtido.
enum GrowthOrigin {
  /// Mediana das variações anuais da base de capital.
  fundamental('crescimento fundamental da base de capital'),

  /// Âncora *top-down* pela inflação, autorizada pela retenção observada.
  inflationAnchor('âncora de inflação, financiável pela retenção observada'),

  /// Sem crescimento: valor da capacidade de gerar lucro.
  earningsPower('valor da capacidade de gerar lucro, sem crescimento');

  final String label;
  const GrowthOrigin(this.label);
}

/// Resultado do teste de tendência da Guarda 1.
class TrendVerdict {
  /// Inclinação anual do retorno, em fração por ano.
  final double slope;

  /// Estatística `t` com erro-padrão de Newey-West.
  final double tStatistic;

  /// Valor crítico de `t` ao nível adotado.
  final double criticalT;

  /// Razão entre a deriva da tendência e a correção por reversão.
  final double dominance;

  /// `true` quando há tendência significante **e** ela domina a reversão.
  final bool dominates;

  const TrendVerdict({
    required this.slope,
    required this.tStatistic,
    required this.criticalT,
    required this.dominance,
    required this.dominates,
  });

  bool get isSignificant => tStatistic.abs() >= criticalT;
}

/// Resultado do teste de dispersão da Saída 2.
class DispersionVerdict {
  /// Crescimento pela mediana das variações.
  final double medianGrowth;

  /// Crescimento pela regressão log-linear.
  final double regressionGrowth;

  /// Erro-padrão do estimador por regressão, pelo método delta.
  final double stdError;

  /// Discordância padronizada.
  final double d;

  /// Valor crítico de `D`.
  final double criticalD;

  /// `true` quando o estimador é preciso e os dois métodos concordam.
  final bool isIdentified;

  /// Por que não foi identificado, quando não foi.
  final String? failure;

  const DispersionVerdict({
    required this.medianGrowth,
    required this.regressionGrowth,
    required this.stdError,
    required this.d,
    required this.criticalD,
    required this.isIdentified,
    this.failure,
  });
}

/// As guardas da Porta 2 e a decisão da taxa.
abstract final class GrowthGuards {
  /// Guarda 1 — a tendência do retorno domina a reversão à média?
  ///
  /// Roda sobre a **série completa**, não sobre a janela do ciclo: com `n = 8` o
  /// estimador HAC monta a variância a partir de somas de 6 e 7 termos e chega a
  /// inflar `|t|` em 2,2 vezes. Com a série inteira o quadro estabiliza.
  ///
  /// Exige as duas condições. Significância sozinha não basta — a RENT3 tem
  /// tendência com `t = −2,84` e ainda assim a correção por reversão é 2,5 vezes
  /// maior que a deriva no horizonte.
  ///
  /// - [series]: série de capital da via escolhida.
  /// - [horizonYears]: horizonte explícito de projeção.
  static TrendVerdict? trend(CapitalSeries series, {required int horizonYears}) {
    final r = series.returns;
    if (r.length < 6) return null;

    final xs = [for (final p in r) p.year.toDouble()];
    final ys = [for (final p in r) p.value];
    final fit = Inference.ols(xs, ys);
    if (fit == null) return null;

    final se = Inference.hacSlopeStdError(xs, fit) ?? fit.slopeStdError;
    final t = fit.slope / se;
    final tc = Inference.studentT(
      1 - ValuationParameters.alpha / 2,
      fit.degreesOfFreedom,
    );

    final atual = series.latestReturn;
    final ciclo = series.cycleReturn(window: ValuationParameters.cycleWindow);
    if (atual == null || ciclo == null) return null;

    final correcao = (atual - ciclo).abs();
    final deriva = fit.slope.abs() * horizonYears;
    final rho = correcao > 1e-12 ? deriva / correcao : double.infinity;

    final significante = t.abs() >= tc;
    return TrendVerdict(
      slope: fit.slope,
      tStatistic: t,
      criticalT: tc,
      dominance: rho,
      dominates: significante && rho >= ValuationParameters.minTrendDominance,
    );
  }

  /// Guarda 2 — quanto da expansão da base veio de capital externo.
  ///
  /// Da relação de excedente limpo, `externo = max(0, ΔBase − lucro)`: se a base
  /// cresceu mais do que a empresa lucrou, o excesso não veio de lucro retido.
  ///
  /// **Não usa a variação do capital social.** Ele sobe também por incorporação
  /// de reservas, que não traz dinheiro novo — a WEGE3 acusaria R$ 9,0 bi de
  /// emissão sobre base de R$ 6,3 bi, sendo que as duas maiores altas vieram com
  /// reservas de lucro caindo junto. Medir pelo patrimônio é imune, porque
  /// bonificação não o altera.
  ///
  /// Devolve `null` sem janela suficiente.
  static double? externalCapitalRatio(CapitalSeries series) {
    final p = series.points;
    const w = ValuationParameters.cycleWindow;
    if (p.length < w + 1) return null;

    final janela = p.sublist(p.length - w - 1);
    final inicial = janela.first.base;
    if (inicial <= 0) return null;

    var externo = 0.0;
    for (var i = 1; i < janela.length; i++) {
      final a = janela[i - 1], b = janela[i];
      if (b.year - a.year != 1) continue;
      final delta = b.base - a.base;
      final lucro = b.profit ?? 0.0;
      final excesso = delta - lucro;
      if (excesso > 0) externo += excesso;
    }
    final phi = externo / inicial;
    return phi.isFinite ? phi : null;
  }

  /// Guarda 3 — o exercício corrente destoa do ciclo o bastante para normalizar?
  ///
  /// **União de dois critérios**, deliberadamente. O desvio robusto pega o que a
  /// banda não vê em setor estável — a VIVT3 tem razão de 1,27, dentro da banda,
  /// mas 2,27 desvios, porque o ROIC dela oscila 0,7 ponto percentual. A banda
  /// pega o que o `z` não vê em setor volátil — a PRIO3 tem razão de 0,18, muito
  /// fora, e apenas 1,05 desvio, porque oscila 36,6 pontos.
  ///
  /// Devolve `null` quando não há ciclo medível.
  static bool? deviatesFromCycle(CapitalSeries series) {
    final atual = series.latestReturn;
    final ciclo = series.cycleReturn(window: ValuationParameters.cycleWindow);
    if (atual == null || ciclo == null || ciclo <= 0) return null;

    final r = series.returns;
    final ini = r.length - 1 - ValuationParameters.cycleWindow;
    final janela = r.sublist(ini < 0 ? 0 : ini, r.length - 1);
    final escala = Inference.scaledMad([for (final x in janela) x.value]);

    final z = escala == null ? 0.0 : (atual - ciclo).abs() / escala;
    final razao = atual / ciclo;

    return z > ValuationParameters.robustZ ||
        razao < ValuationParameters.bandLow ||
        razao > ValuationParameters.bandHigh;
  }

  /// Saída 2, primeira perna — o crescimento é identificável?
  ///
  /// Combina três exigências, e as três existem por um caso medido:
  ///
  /// 1. **Precisão** — `se(ĝ) ≤ σ_max`. Sem ela, a PRIO3 recebe 25,4% com
  ///    intervalo de confiança de 35 pontos percentuais de largura.
  /// 2. **Concordância** — `D ≤ D_crit`, dois estimadores do mesmo parâmetro.
  /// 3. **Materialidade** — a discordância precisa importar. Sem ela, o BBAS3
  ///    seria reprovado por uma diferença de 1,9 p.p. cujo erro-padrão é de
  ///    0,3 p.p.
  ///
  /// Devolve `null` quando a série não sustenta nenhum dos dois estimadores.
  static DispersionVerdict? dispersion(CapitalSeries series) {
    final variacoes = series.annualVariations;
    if (variacoes.length < 4) return null;
    final gMediana = Inference.median(variacoes);
    if (gMediana == null) return null;

    final xs = [for (final p in series.points) p.year.toDouble()];
    final ys = [for (final p in series.points) math.log(p.base)];
    final fit = Inference.ols(xs, ys);
    if (fit == null) return null;

    final gRegressao = math.exp(fit.slope) - 1;
    // Método delta sobre g = e^b − 1: se(ĝ) = e^b · se(b̂).
    final se = (1 + gRegressao) * fit.slopeStdError;
    if (!se.isFinite || se <= 0) return null;

    final diferenca = (gMediana - gRegressao).abs();
    final d = diferenca / se;
    final dc = Inference.studentT(
      1 - ValuationParameters.alpha / 2,
      fit.degreesOfFreedom,
    );
    final delta = math.max(
      ValuationParameters.dispersionFloor,
      ValuationParameters.dispersionRelative * gMediana.abs(),
    );

    String? falha;
    if (se > ValuationParameters.maxGrowthStdError) {
      falha = 'estimador impreciso: erro-padrão de '
          '${(se * 100).toStringAsFixed(1)} pontos percentuais, acima do '
          'máximo de ${(ValuationParameters.maxGrowthStdError * 100).toStringAsFixed(0)}';
    } else if (d > dc && diferenca > delta) {
      falha = 'os dois estimadores discordam em '
          '${(diferenca * 100).toStringAsFixed(1)} pontos percentuais '
          '(${d.toStringAsFixed(1)} erros-padrão), acima do que a série sustenta';
    }

    return DispersionVerdict(
      medianGrowth: gMediana,
      regressionGrowth: gRegressao,
      stdError: se,
      d: d,
      criticalD: dc,
      isIdentified: falha == null,
      failure: falha,
    );
  }

  /// Saída 2, segunda perna — a âncora de inflação é financiável?
  ///
  /// Crescer à inflação exige reter `inflação / retorno`. Só faz sentido se a
  /// empresa retiver ao menos isso: é a **mesma identidade** que sustenta a via
  /// B, de modo que o modelo se confere em vez de precisar de lista de exceções.
  ///
  /// Discrimina de verdade: a AZZA3 precisa reter 24,3% e retém 69,3%, passa; a
  /// VIVT3 precisaria reter 73,3% e retém 7,9%, reprova.
  static bool anchorIsFundable({
    required double inflation,
    required double? cycleReturn,
    required double? observedRetention,
  }) {
    if (cycleReturn == null || cycleReturn <= 0) return false;
    if (observedRetention == null) return false;
    final exigida = inflation / cycleReturn;
    return exigida < 1.0 && exigida <= observedRetention;
  }

  /// Porta 3 — o fluxo da firma sustenta uma perpetuidade?
  ///
  /// Mede sobre o **fluxo de manutenção**, não sobre o fluxo livre publicado.
  /// Como o capex de manutenção de uma empresa madura repõe a depreciação,
  /// `FCF_manutenção = NOPAT + D&A − CapEx_manutenção ≈ NOPAT` — o que dispensa
  /// o CapEx que a fonte não publica.
  ///
  /// Isso desfaz a migração errônea de quem está em ciclo de investimento: a
  /// EGIE3 caía para a via do acionista por um exercício de fluxo negativo
  /// depois de onze positivos em dezesseis.
  static bool firmFlowIsSustained(List<FundamentalsSnapshot> snapshots) {
    final v = <double>[];
    for (final s in snapshots) {
      final n = s.nopatOrDerived;
      if (n != null) v.add(n);
    }
    if (v.length < 4) return false;
    final positivos = v.where((x) => x > 0).length;
    return positivos / v.length >= ValuationParameters.minPositiveFlow;
  }

  /// Retorno terminal quando a vantagem competitiva é comprovada.
  ///
  /// Devolve `null` — estado estacionário, `ROIC_∞ = WACC_∞` — quando qualquer
  /// das três condições falha, quando falta insumo, ou quando o resultado não
  /// supera o próprio custo de capital.
  ///
  /// - [cycleReturn]: ROIC ou ROE mediano do ciclo.
  /// - [terminalDiscountRate]: custo de capital de equilíbrio.
  /// - [externalCapitalRatio]: Φ, ou `null` quando não medido.
  /// - [periods]: exercícios utilizáveis na série de capital.
  static double? residualMoatReturn({
    required double? cycleReturn,
    required double terminalDiscountRate,
    required double? externalCapitalRatio,
    required int periods,
  }) {
    if (cycleReturn == null || !cycleReturn.isFinite) return null;
    if (terminalDiscountRate <= 0) return null;
    if (periods < ValuationParameters.moatMinPeriods) return null;
    if (externalCapitalRatio == null) return null;
    if (externalCapitalRatio > ValuationParameters.moatMaxExternalCapital) return null;
    if (cycleReturn < ValuationParameters.moatReturnMultiple * terminalDiscountRate) return null;

    final terminal = terminalDiscountRate +
        ValuationParameters.moatRetainedSpread * (cycleReturn - terminalDiscountRate);
    if (!terminal.isFinite || terminal <= terminalDiscountRate) return null;
    return terminal;
  }
}

/// Encolhimento do beta por precisão, e a relação de Hamada que o desalavanca.
library;

/// Prior transversal do beta, resolvido fora do núcleo.
///
/// **Por que vem de fora.** A cascata avalia **um** ativo por vez e é pura: ela
/// não enxerga a seção transversal. A mediana setorial e a dispersão do
/// universo só existem depois de varrer o universo, e por isso chegam como
/// insumo — o mesmo arranjo que `MarketAnchors` já usa para as âncoras macro.
class BetaPrior {
  /// Beta **desalavancado** mediano por chave de setor.
  ///
  /// Só entram setores com pares suficientes para a mediana significar algo.
  final Map<String, double> unleveredBySector;

  /// Beta desalavancado mediano do universo, para ativo sem setor utilizável.
  final double unleveredUniverse;

  /// Dispersão robusta dos betas **alavancados** do universo.
  ///
  /// É a variância do prior no encolhimento. Medida em 0,53 sobre os 363
  /// papéis em 10/09/2026.
  final double dispersion;

  const BetaPrior({
    required this.unleveredBySector,
    required this.unleveredUniverse,
    required this.dispersion,
  });

  /// Beta desalavancado do setor, com recuo para o do universo.
  double unleveredFor(String? sectorKey) {
    final k = sectorKey?.trim();
    if (k == null || k.isEmpty) return unleveredUniverse;
    return unleveredBySector[k] ?? unleveredUniverse;
  }
}

/// Beta resultante do encolhimento, com o peso que o produziu.
class ShrunkBeta {
  /// Beta a usar no CAPM.
  final double beta;

  /// Peso do estimador individual em `[0, 1]`. `1` significa que a regressão
  /// decidiu sozinha.
  final double weight;

  /// Beta desalavancado do próprio ativo, por Hamada. É o que liga `Ke` a
  /// `WACC`, e por isso sai junto.
  final double? unlevered;

  /// Prior alavancado para a estrutura de capital do ativo.
  final double prior;

  const ShrunkBeta({
    required this.beta,
    required this.weight,
    required this.unlevered,
    required this.prior,
  });
}

/// Desalavancagem e encolhimento do beta.
///
/// **O que a medição de 10/09/2026 estabeleceu, e o que ela descartou.**
/// A proposta original era substituir a regressão individual pela mediana
/// setorial realavancada — beta *bottom-up* clássico. Medida sobre os 363
/// papéis do universo, ela **não se justifica**:
///
/// - o erro-padrão da regressão individual fica em **0,07** na mediana, com
///   cinco anos de pregão diário; ela não é o estimador ruidoso que a proposta
///   supunha;
/// - agrupar por setor reduz a dispersão robusta em apenas **13,1%**
///   (0,40 para 0,35), e a dispersão **dentro** dos setores grandes fica em
///   0,41 a 0,48 — o setor é prior fraco;
/// - **95 dos 363** não têm setor com pares suficientes;
/// - e a troca moveria o `Ke` do ativo mediano em **2,13 p.p.**, sem ganho
///   medido.
///
/// O que sobra, e é o que esta classe faz, é **encolher por precisão**. O peso
/// do estimador individual é a razão entre a precisão dele e a soma das duas:
///
/// ```
/// w = (1/SE²) / (1/SE² + 1/σ_prior²)
/// β = w · β_regressão + (1 − w) · β_prior
/// ```
///
/// Nenhum limiar decide — a precisão decide, e é contínua. Medido: peso
/// mediano de **0,98**, com apenas 23 dos 363 abaixo de 0,90, e `|ΔKe|`
/// mediano de **0,03 p.p.** O ativo típico não se move.
///
/// Onde ele age é onde precisa: a AZUL3 tem `β = 109.108` com `ρ = 0,11` sobre
/// 142 pregões e erro-padrão de 83.228, e o encolhimento a leva ao prior por
/// inteiro. Antes disso, aquele número entrava no CAPM.
abstract final class BetaShrinkage {
  /// Teto da relação `D/E` usada em Hamada.
  ///
  /// **Existe porque a relação é linear e a realidade não.** Hamada supõe
  /// dívida sem risco; acima de alguma alavancagem o capital próprio vira uma
  /// opção sobre os ativos e a relação deixa de descrever. Medido em
  /// 10/09/2026, `D/E` tem mediana de 0,28 e p75 de 1,96 — mas chega a **94,5**
  /// na AZUL3, onde o valor de mercado do capital próprio praticamente sumiu.
  /// Sem teto, realavancar um prior por 94,5 inventa um beta de dezenas.
  ///
  /// Em 3,0 a dívida responde por 75% do capital. É alto e é real em concessão
  /// e saneamento; acima disso o ativo já cai na Porta 0 ou na pós-condição da
  /// ponte, e o confinamento é guarda de canto, não de regime.
  static const double maxDebtToEquity = 3.0;

  /// `β_U = β_L / (1 + (1 − t)·D/E)` — Hamada.
  ///
  /// - [leveredBeta]: o beta observado, que carrega risco de negócio **e** de
  ///   estrutura de capital.
  /// - [debtToEquity]: dívida bruta sobre valor de mercado do capital próprio,
  ///   confinada em [maxDebtToEquity].
  /// - [taxRate]: alíquota que dá o escudo fiscal da dívida.
  ///
  /// Devolve `null` com entrada não finita.
  static double? unlever({
    required double leveredBeta,
    required double debtToEquity,
    required double taxRate,
  }) {
    if (!leveredBeta.isFinite || !debtToEquity.isFinite) return null;
    final f = leverageFactor(debtToEquity: debtToEquity, taxRate: taxRate);
    if (f == null || f <= 0) return null;
    final v = leveredBeta / f;
    return v.isFinite ? v : null;
  }

  /// `1 + (1 − t)·D/E`, com `D/E` confinado. `null` com entrada não finita.
  static double? leverageFactor({
    required double debtToEquity,
    required double taxRate,
  }) {
    if (!debtToEquity.isFinite || !taxRate.isFinite) return null;
    final de = debtToEquity.clamp(0.0, maxDebtToEquity).toDouble();
    final f = 1 + (1 - taxRate) * de;
    return f.isFinite ? f : null;
  }

  /// Encolhe [leveredBeta] em direção ao prior, pela precisão de cada um.
  ///
  /// - [standardError]: erro-padrão da regressão. Nulo ou não positivo entrega
  ///   o prior inteiro — sem medida de precisão não há como defender o
  ///   individual.
  ///
  /// Sem prior utilizável devolve o próprio [leveredBeta] com peso 1.
  static ShrunkBeta shrink({
    required double leveredBeta,
    required double? standardError,
    required BetaPrior prior,
    required String? sectorKey,
    required double debtToEquity,
    required double taxRate,
  }) {
    final fator = leverageFactor(debtToEquity: debtToEquity, taxRate: taxRate);
    final priorAlavancado = (fator == null)
        ? leveredBeta
        : prior.unleveredFor(sectorKey) * fator;

    // **O desalavancado sai do beta que sai daqui, e não do cru** (decisão
    // 54). Encolher em espaço alavancado e desalavancar o resultado é
    // idêntico a encolher em espaço desalavancado, porque o fator é o mesmo
    // nos dois lados:
    //
    // ```
    // encolhido / f = w·(β_L/f) + (1 − w)·β_U,prior = w·β_U + (1 − w)·β_U,prior
    // ```
    //
    // Derivá-lo do cru descartava o encolhimento inteiro para quem usa o
    // caminho resolvido — que é a maioria do universo —, porque o ponto fixo
    // realavanca `unlevered` e nunca toca em `beta`. A decisão 40 existe para
    // trocar precisão por viés, e essa troca não estava chegando ao preço.
    double? desalavancar(double b) =>
        (fator != null && fator > 0 && b.isFinite) ? b / fator : null;

    ShrunkBeta resultado(double beta, double peso) => ShrunkBeta(
          beta: beta,
          weight: peso,
          unlevered: desalavancar(beta),
          prior: priorAlavancado,
        );

    if (!priorAlavancado.isFinite || prior.dispersion <= 0) {
      return resultado(leveredBeta, 1.0);
    }

    if (standardError == null ||
        !standardError.isFinite ||
        standardError <= 0) {
      return resultado(priorAlavancado, 0.0);
    }

    final precisaoIndividual = 1 / (standardError * standardError);
    final precisaoPrior = 1 / (prior.dispersion * prior.dispersion);
    final soma = precisaoIndividual + precisaoPrior;
    if (!soma.isFinite || soma <= 0) return resultado(leveredBeta, 1.0);

    final w = (precisaoIndividual / soma).clamp(0.0, 1.0).toDouble();
    final encolhido = w * leveredBeta + (1 - w) * priorAlavancado;

    return encolhido.isFinite
        ? resultado(encolhido, w)
        : resultado(priorAlavancado, w);
  }
}

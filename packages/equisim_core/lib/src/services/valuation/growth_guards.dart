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
  ///
  /// **Limiar de declaração, não de bloqueio**, desde 07/09/2026. Até então ele
  /// travava a normalização da base: Φ acima de 1,0 e o exercício corrente
  /// permanecia como observado, por mais que destoasse do ciclo. A precedência
  /// era errada de unidade — Φ mede *tamanho*, e o que a Guarda 3 corrige é o
  /// *retorno percentual*, que é grandeza intensiva. Um pico de margem de
  /// commodity não vira patamar perene porque a empresa fez uma aquisição.
  ///
  /// O que Φ acima deste limiar continua significando, e o que o resultado
  /// declara, é que **níveis absolutos** de lucro não são comparáveis entre as
  /// pontas da janela. Para a vantagem competitiva residual, onde a pergunta é
  /// justamente se o crescimento foi financiado por dentro, o corte que barra é
  /// o [moatMaxExternalCapital], mais estrito.
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

  /// Teto e piso do fator de normalização da base.
  ///
  /// **O fator é `f = retorno_ciclo / retorno_atual`, e ele explode.** Quando o
  /// exercício corrente tem retorno próximo de zero o denominador some, e como o
  /// DCF é **homogêneo de grau 1 no fluxo-base**, o fator multiplica o preço
  /// justo inteiro: a MBRF3 recebeu 21,4x e saiu a +406,1% de potencial na
  /// terceira rodada, e FESA4 e DXCO3 já vinham recebendo dez vezes.
  ///
  /// A saturação é **simétrica em razão**, `1/3` contra `3`, e não em diferença:
  /// normalizar para cima e para baixo precisa custar o mesmo, senão o teto vira
  /// um viés de direção. Ela responde à pergunta que a
  /// `docs/validacao/normalizacao_fluxo_base.md` fazia sobre `τ` — quanto se
  /// autoriza um único exercício a mover a avaliação inteira da empresa — com um
  /// limite explícito em vez de nenhum.
  ///
  /// **Não é detecção de atípico**, é política: acima de 3x a normalização
  /// deixa de corrigir um exercício e passa a inventar uma empresa.
  ///
  /// **O teto cai para 1,00 quando a saúde operacional reprova**, exceto em setor
  /// cíclico. Empresa não cíclica que perdeu mais da metade do resultado no
  /// triênio não recebe base normalizada para cima, qualquer que seja a mediana
  /// do ciclo — ver [maxOperationalDecline]. O piso continua valendo em todos os
  /// casos: quem deteriorou e ainda assim teve um exercício acima do ciclo é
  /// normalizado para baixo normalmente.
  static const double baseFactorFloor = 0.33;
  static const double baseFactorCeiling = 3.00;

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

  /// Inclinação mínima relativa: a deriva da tendência na janela precisa
  /// superar a correção que a reversão à média faria.
  static const double minTrendDominance = 1.0;

  /// Janela, em anos, sobre a qual a deriva da tendência é medida.
  ///
  /// **É [cycleWindow], e não o horizonte de projeção.** A Guarda 1 responde a
  /// uma pergunta sobre a série — o nível corrente é patamar novo ou desvio a
  /// corrigir? —, e a resposta não pode depender de quantos anos o usuário pediu
  /// para ver projetados. Com `deriva = |inclinação| · N`, dependia: medido em
  /// 07/09/2026 sobre o universo elegível, **13 dos 120 avaliados trocavam de
  /// veredito entre `N = 5` e `N = 10`**, e o preço justo ia junto — a AZZA3 de
  /// R$ 16,11 para R$ 57,48 (3,57x), a CYRE3 de R$ 8,53 para R$ 3,40 (0,40x).
  /// O horizonte sozinho, com a guarda estável, move o valor em cerca de 2%.
  ///
  /// A janela do ciclo é a escolha coerente porque é **a mesma** sobre a qual a
  /// correção por reversão é medida: os dois lados da razão passam a falar do
  /// mesmo intervalo, e a dominância vira uma comparação entre grandezas
  /// homogêneas em vez de uma comparação entre a série e a tela.
  static const int trendDriftWindow = cycleWindow;

  // ------------------------------------- Vantagem competitiva residual --
  //
  // Colapsar toda empresa em `ROIC_∞ = WACC` trata franquia duradoura e
  // negócio comoditizado da mesma forma. A exceção existe, mas o preço dela é
  // alto: o valor terminal volta a depender de `g_∞`, que o retorno neutro
  // havia eliminado. Por isso as três condições — crescimento orgânico,
  // rentabilidade estrutural e histórico longo — são **cumulativas**: a exceção
  // precisa ser rara para não desfazer a robustez que a decisão 25 comprou.
  //
  // A recalibragem de 07/09/2026 mexeu no **nível** de duas delas, não na
  // estrutura: a rentabilidade ganhou uma segunda perna em união e o histórico
  // desceu ao piso da Porta 0. O critério de crescimento orgânico continua
  // intacto, porque é o que separa franquia de aporte.

  /// Fração do excedente de retorno preservada na perpetuidade.
  ///
  /// `ROIC_∞ = WACC_∞ + 0,30 · (ROIC_ciclo − WACC_∞)`: sete décimos da vantagem
  /// se dissolvem, três sobrevivem.
  static const double moatRetainedSpread = 0.30;

  /// Teto de capital externo para o crescimento ser considerado orgânico.
  ///
  /// Mais restritivo que [maxExternalCapital]: uma vantagem competitiva que
  /// precisa de emissão para se sustentar não é vantagem, é aporte.
  ///
  /// **0,60 e não mais 0,35**, por determinação de 07/09/2026. A instrumentação
  /// da terceira rodada mostrou que era este — e não o critério de rentabilidade
  /// recalibrado — o parâmetro que prendia as franquias: EGIE3 caía com
  /// `Φ = 0,58` e ITUB4 com `Φ = 0,50`. O corte de 0,35 confundia duas coisas
  /// diferentes. Concessionária que financia outorga com dívida e banco que
  /// capta por definição do negócio acusam Φ alto **sem** que isso signifique
  /// que a rentabilidade depende de aporte de sócio.
  ///
  /// O que o corte continua barrando, agora com folga calibrada, é a empresa
  /// cuja base cresceu por emissão em múltiplos da própria base — a SUZB3, com
  /// `Φ = 0,77`, segue reprovada.
  static const double moatMaxExternalCapital = 0.60;

  /// Queda máxima tolerada de lucro ou de EBITDA no triênio recente.
  ///
  /// **Filtro de saúde operacional, e vale em dois lugares.**
  ///
  /// No *moat*, sem ele `Φ` premiava quem está encolhendo: a QUAL3 passou na
  /// terceira rodada com `Φ = 0,01` — não porque financia o crescimento por
  /// dentro, mas porque **não há crescimento nenhum a financiar**. O lucro dela
  /// caiu de R$ 0,10 bi em 2022 para R$ 0,02 bi em 2025, e a mediana do ciclo de
  /// oito anos ainda carregava os exercícios bons de antes. Vantagem competitiva
  /// é afirmação sobre o **futuro** do retorno excedente, e quem caiu pela
  /// metade no triênio não a sustenta.
  ///
  /// Na **Porta 2a** ele proíbe normalizar a base *para cima* — ver
  /// [baseFactorCeiling]. Barrar só o *moat* resolvia metade do problema: a
  /// QUAL3 perdeu a vantagem residual na quarta rodada e continuou a +477,3% de
  /// potencial, porque o número não vinha da perpetuidade, vinha da mediana de
  /// ROIC de oito anos aplicada à base corrente. Puxar a base de uma empresa
  /// que mudou de patamar de volta à mediana histórica produz um retorno que ela
  /// não vai repetir.
  ///
  /// **Setor cíclico é isento na Porta 2a, e só nela.** Em commodity, uma queda
  /// de mais de 50% entre o pico de 2022 e o vale de 2025 é oscilação do preço
  /// internacional do insumo, não quebra de modelo de negócio: a VALE3 acusava
  /// 87,7% e a GGBR4 87,6%, e a trava as empurrava para −70,3% e −92,7% de
  /// potencial. A precedência da Guarda 3 estabelecida pela decisão 28 existe
  /// justamente para deixar a reversão operar nos dois sentidos ali, e uma trava
  /// que morde só na subida a desfazia no vale — que é onde ela importa. O
  /// limite que continua valendo em commodity é a saturação.
  ///
  /// **No *moat* não há isenção.** Nem commodity em vale, nem empresa em
  /// contração recebe retorno excedente na perpetuidade: ali a pergunta é sobre
  /// o futuro do excedente, e um vale de ciclo não o sustenta melhor que uma
  /// deterioração estrutural. Ver [CyclicalSectors].
  static const double maxOperationalDecline = 0.50;

  /// Exercícios do triênio de saúde operacional.
  static const int operationalHealthWindow = 3;

  /// Múltiplo do custo de capital que o retorno do ciclo precisa alcançar.
  ///
  /// **1,5 e não mais 2,0**, por recalibragem homologada em 07/09/2026. Com o
  /// custo de capital de equilíbrio brasileiro na casa de 11% a 14%, o dobro
  /// exigia de 22% a 28% de retorno sobre um capital investido **contábil
  /// reconstituído** — base que a reavaliação de ativos e o ágio de aquisição
  /// incham sem que a empresa tenha ficado menos rentável. O critério punia
  /// justamente a franquia eficiente de base expandida: dos 120 avaliados na
  /// primeira validação fora da amostra, dois passaram.
  static const double moatReturnMultiple = 1.5;

  /// Excedente absoluto que, em alternativa ao múltiplo, comprova rentabilidade
  /// estrutural: `ROIC_ciclo − WACC_∞ ≥ 5 p.p.`
  ///
  /// **Vale em união com [moatReturnMultiple]**, e a união não é redundância: o
  /// múltiplo e o excedente se cruzam em `WACC_∞ = 10%`. Acima disso o
  /// excedente é o critério que decide — a 14% de custo de capital ele pede
  /// 19% de retorno contra os 21% do múltiplo —, e abaixo dele o múltiplo é que
  /// decide, impedindo que custo de capital baixo transforme 5 p.p. de spread
  /// em vantagem competitiva declarada. Cada perna é registrada em separado no
  /// log de avaliação, para que a calibragem seja auditável depois.
  static const double moatMinSpread = 0.05;

  /// Exercícios mínimos de histórico para a vantagem ser considerada comprovada.
  ///
  /// **Oito, alinhado ao piso da Porta 0 e à janela do ciclo** ([cycleWindow]),
  /// por recalibragem homologada em 07/09/2026. Os doze anteriores expressavam
  /// a ideia certa — franquia se distingue de fase boa do ciclo pela duração —,
  /// mas cobravam histórico que a fonte raramente publica: exigir mais anos do
  /// que a própria janela sobre a qual o retorno do ciclo é medido reprovava por
  /// falta de dado, não por falta de vantagem.
  static const int moatMinPeriods = 8;

  // ---------------------------------------------- Alíquota do escudo fiscal --

  /// Alíquota marginal estatutária brasileira: IRPJ 15% + adicional 10% +
  /// CSLL 9% = **34%**.
  ///
  /// **É a alíquota do escudo fiscal do WACC, e não a efetiva do exercício.**
  /// O benefício fiscal do endividamento é o valor presente dos escudos das
  /// despesas financeiras **futuras**, que se realizam à alíquota marginal da
  /// jurisdição — a razão contábil `imposto ÷ lucro antes do imposto` de um
  /// exercício mede outra coisa: incentivos, JCP, prejuízo fiscal compensado,
  /// equivalência patrimonial e diferimento. É a orientação de Damodaran e da
  /// McKinsey, e a que este projeto passou a adotar.
  ///
  /// **A troca também elimina uma incoerência interna medida.** A fonte publica
  /// `nopat` e ele é, em 4.572 de 4.572 exercícios do cache de produção,
  /// exatamente `EBIT × 0,66` — ou seja, o fluxo da firma **já vinha** apurado
  /// à alíquota estatutária. O escudo do WACC, não: a efetiva tinha mediana de
  /// 19,2% entre os avaliados, ficava nula em 9 deles (escudo desligado) e
  /// batia no teto de 50% em outros 9. O numerador e o denominador do mesmo
  /// desconto usavam convenções tributárias diferentes.
  ///
  /// **Limite declarado:** instituição financeira paga 45% (CSLL de 20%), e
  /// esta constante não a distingue. Não há efeito prático porque a Porta 1
  /// roteia o setor para a via do acionista, que desconta ao Ke e não monta
  /// WACC — mas quem levar o WACC para lá precisa tratar o caso.
  static const double statutoryTaxRate = 0.34;

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

/// Qual condição barrou a vantagem competitiva residual.
///
/// Existe para **auditoria metodológica**, não para a conta: sem nomear a
/// condição que reprovou, um universo em que quase ninguém passa é
/// indistinguível de um universo em que quase ninguém merece passar. É a
/// diferença entre calibrar um parâmetro e adivinhar qual deles está apertado.
enum MoatBlock {
  /// Sem retorno do ciclo medível — série curta ou lucro não publicado.
  semRetornoDoCiclo('retorno do ciclo não medido'),

  /// Custo de capital de equilíbrio não positivo: nada a comparar.
  semCustoDeCapital('custo de capital de equilíbrio não positivo'),

  /// Histórico mais curto que [ValuationParameters.moatMinPeriods].
  historicoCurto('histórico curto'),

  /// Φ não medido. Ausência não é aprovação: sem saber quanto da expansão veio
  /// de fora, não há como afirmar que o crescimento foi orgânico.
  capitalExternoNaoMedido('capital externo não medido'),

  /// Φ acima de [ValuationParameters.moatMaxExternalCapital].
  crescimentoInorganico('crescimento inorgânico'),

  /// Reprovou nas **duas** pernas da rentabilidade: nem o múltiplo do custo de
  /// capital, nem o excedente absoluto.
  rentabilidadeInsuficiente('rentabilidade insuficiente'),

  /// Lucro ou EBITDA recuou mais de [ValuationParameters.maxOperationalDecline]
  /// no triênio recente. Vantagem competitiva é afirmação sobre o futuro do
  /// retorno excedente, e quem encolheu pela metade não a sustenta.
  saudeOperacional('resultado em queda no triênio'),

  /// Passou nas três condições, mas o retorno terminal resultante não supera o
  /// próprio custo de capital — excedente que não sobrevive à preservação
  /// parcial. Sem conteúdo econômico, e por isso tratado como reprovação.
  excedenteDegenerado('excedente não sobrevive à preservação parcial');

  final String label;
  const MoatBlock(this.label);
}

/// Veredito da vantagem competitiva residual, com o porquê da recusa.
class MoatVerdict {
  /// Retorno terminal preservado, ou `null` no estado estacionário.
  final double? terminalReturn;

  /// Condições que reprovaram, na ordem em que são avaliadas. Vazia quando a
  /// vantagem é comprovada.
  ///
  /// **É lista e não um único motivo**: um ativo que reprova por histórico
  /// curto *e* por rentabilidade continuaria reprovado se só o primeiro fosse
  /// afrouxado, e uma calibragem guiada apenas pelo primeiro motivo prometeria
  /// um destravamento que não aconteceria.
  final List<MoatBlock> blocks;

  /// ROIC ou ROE mediano do ciclo, como entrou na conta.
  final double? cycleReturn;

  /// Custo de capital de equilíbrio contra o qual o retorno foi medido.
  final double terminalDiscountRate;

  /// Φ — capital externo em múltiplos da base inicial da janela.
  final double? externalCapitalRatio;

  /// Exercícios utilizáveis na série de capital.
  final int periods;

  /// Retorno exigido pela perna do múltiplo: `k · WACC_∞`.
  final double requiredByMultiple;

  /// Retorno exigido pela perna do excedente: `WACC_∞ + 5 p.p.`
  final double requiredBySpread;

  /// `true` quando a perna do múltiplo aprova, isoladamente.
  final bool passesByMultiple;

  /// `true` quando a perna do excedente aprova, isoladamente.
  final bool passesBySpread;

  /// Queda de lucro ou EBITDA no triênio recente, em fração. `null` quando não
  /// há referência positiva a comparar.
  final double? operationalDecline;

  const MoatVerdict({
    required this.terminalReturn,
    required this.blocks,
    required this.cycleReturn,
    required this.terminalDiscountRate,
    required this.externalCapitalRatio,
    required this.periods,
    required this.requiredByMultiple,
    required this.requiredBySpread,
    required this.passesByMultiple,
    required this.passesBySpread,
    required this.operationalDecline,
  });

  /// `true` quando a vantagem foi comprovada.
  bool get isProven => terminalReturn != null;

  /// Primeira condição que barrou, ou `null` quando comprovada. É por ela que o
  /// relatório agrupa.
  MoatBlock? get primaryBlock => blocks.isEmpty ? null : blocks.first;

  /// `true` quando **só** a rentabilidade reprovou — a fronteira que a
  /// recalibragem de 07/09/2026 moveu, e a que se quer medir de novo.
  bool get blockedOnlyByReturn =>
      blocks.length == 1 && blocks.first == MoatBlock.rentabilidadeInsuficiente;

  /// Excedente do ciclo sobre o custo de capital de equilíbrio, em fração.
  double? get spread =>
      cycleReturn == null ? null : cycleReturn! - terminalDiscountRate;
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
  /// **A deriva é medida na janela do ciclo, não no horizonte de projeção.**
  /// Ver [ValuationParameters.trendDriftWindow]: um veredito estatístico sobre a
  /// série não pode mudar porque o usuário trocou a projeção de 5 para 10 anos.
  ///
  /// - [series]: série de capital da via escolhida.
  /// - [driftWindow]: janela sobre a qual a deriva é acumulada. O padrão é a
  ///   janela do ciclo, e o parâmetro existe para a análise de sensibilidade.
  static TrendVerdict? trend(
    CapitalSeries series, {
    int driftWindow = ValuationParameters.trendDriftWindow,
  }) {
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
    final deriva = fit.slope.abs() * driftWindow;
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
  /// **O que ela decide mudou.** Φ não barra mais a normalização do retorno —
  /// ver [ValuationParameters.maxExternalCapital] —; ele declara a base
  /// inorgânica e barra a vantagem competitiva residual, por um corte próprio e
  /// mais estrito.
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

  /// Queda de lucro ou de EBITDA no triênio recente, em fração.
  ///
  /// Compara o exercício mais recente com o de três antes, e devolve a **pior**
  /// das duas quedas — a que primeiro denuncia deterioração. Lucro cai antes de
  /// EBITDA quando o problema é financeiro; EBITDA cai antes quando o problema é
  /// operacional, e o filtro precisa pegar os dois casos.
  ///
  /// Devolve `null` quando não há referência positiva a comparar: a série é curta
  /// demais, tem buraco no triênio, ou o exercício de referência já era prejuízo.
  /// **Ausência aqui não reprova** — quem não tem lucro publicado já não tem
  /// retorno de ciclo medível, e é por ali que a vantagem residual cai.
  ///
  /// - [snapshots]: exercícios publicados, em ordem cronológica.
  static double? recentOperationalDecline(
    List<FundamentalsSnapshot> snapshots,
  ) {
    const w = ValuationParameters.operationalHealthWindow;
    if (snapshots.length < w + 1) return null;

    final atual = snapshots.last;
    final referencia = snapshots[snapshots.length - 1 - w];
    // O triênio precisa ser mesmo de três anos: buraco na série compararia
    // pontas de distâncias diferentes e o limiar deixaria de significar o mesmo.
    if (atual.fiscalPeriodEnd.year - referencia.fiscalPeriodEnd.year != w) {
      return null;
    }

    double? queda(double? recente, double? base) {
      if (recente == null || base == null || base <= 0) return null;
      final q = 1 - recente / base;
      return q.isFinite ? q : null;
    }

    final porLucro = queda(atual.netIncome, referencia.netIncome);
    final porEbitda = queda(atual.ebitda, referencia.ebitda);
    if (porLucro == null) return porEbitda;
    if (porEbitda == null) return porLucro;
    return porLucro > porEbitda ? porLucro : porEbitda;
  }

  /// Retorno terminal quando a vantagem competitiva é comprovada, com o
  /// registro de qual condição barrou quando não é.
  ///
  /// Devolve um veredito de [MoatVerdict.terminalReturn] nulo — estado
  /// estacionário, `ROIC_∞ = WACC_∞` — quando qualquer das três condições falha,
  /// quando falta insumo, ou quando o resultado não supera o próprio custo de
  /// capital. As condições são **todas avaliadas**, e não em curto-circuito, de
  /// modo que [MoatVerdict.blocks] traga o quadro inteiro: interromper na
  /// primeira faria toda calibragem posterior enxergar só a condição mais à
  /// esquerda.
  ///
  /// A rentabilidade aprova por **união** de duas pernas: `ROIC_ciclo ≥ k·WACC_∞`
  /// ou `ROIC_ciclo − WACC_∞ ≥ 5 p.p.` — ver [ValuationParameters.moatMinSpread].
  ///
  /// - [operationalDecline]: queda de lucro ou EBITDA no triênio, de
  ///   [recentOperationalDecline]. `null` não reprova.
  ///
  /// - [cycleReturn]: ROIC ou ROE mediano do ciclo.
  /// - [terminalDiscountRate]: custo de capital de equilíbrio.
  /// - [externalCapitalRatio]: Φ, ou `null` quando não medido.
  /// - [periods]: exercícios utilizáveis na série de capital.
  static MoatVerdict residualMoat({
    required double? cycleReturn,
    required double terminalDiscountRate,
    required double? externalCapitalRatio,
    required int periods,
    double? operationalDecline,
  }) {
    final exigidoPorMultiplo =
        ValuationParameters.moatReturnMultiple * terminalDiscountRate;
    final exigidoPorExcedente =
        terminalDiscountRate + ValuationParameters.moatMinSpread;

    final retorno =
        (cycleReturn != null && cycleReturn.isFinite) ? cycleReturn : null;
    final porMultiplo = retorno != null && retorno >= exigidoPorMultiplo;
    final porExcedente = retorno != null && retorno >= exigidoPorExcedente;

    final blocks = <MoatBlock>[];
    if (retorno == null) blocks.add(MoatBlock.semRetornoDoCiclo);
    if (terminalDiscountRate <= 0) blocks.add(MoatBlock.semCustoDeCapital);
    if (periods < ValuationParameters.moatMinPeriods) {
      blocks.add(MoatBlock.historicoCurto);
    }
    if (externalCapitalRatio == null) {
      blocks.add(MoatBlock.capitalExternoNaoMedido);
    } else if (externalCapitalRatio >
        ValuationParameters.moatMaxExternalCapital) {
      blocks.add(MoatBlock.crescimentoInorganico);
    }
    if (retorno != null && !porMultiplo && !porExcedente) {
      blocks.add(MoatBlock.rentabilidadeInsuficiente);
    }
    if (operationalDecline != null &&
        operationalDecline > ValuationParameters.maxOperationalDecline) {
      blocks.add(MoatBlock.saudeOperacional);
    }

    double? terminal;
    if (blocks.isEmpty) {
      final t = terminalDiscountRate +
          ValuationParameters.moatRetainedSpread *
              (retorno! - terminalDiscountRate);
      if (t.isFinite && t > terminalDiscountRate) {
        terminal = t;
      } else {
        blocks.add(MoatBlock.excedenteDegenerado);
      }
    }

    return MoatVerdict(
      terminalReturn: terminal,
      blocks: List.unmodifiable(blocks),
      cycleReturn: retorno,
      terminalDiscountRate: terminalDiscountRate,
      externalCapitalRatio: externalCapitalRatio,
      periods: periods,
      requiredByMultiple: exigidoPorMultiplo,
      requiredBySpread: exigidoPorExcedente,
      passesByMultiple: porMultiplo,
      passesBySpread: porExcedente,
      operationalDecline: operationalDecline,
    );
  }

  /// O retorno terminal do veredito, para quem só precisa do número.
  static double? residualMoatReturn({
    required double? cycleReturn,
    required double terminalDiscountRate,
    required double? externalCapitalRatio,
    required int periods,
    double? operationalDecline,
  }) =>
      residualMoat(
        cycleReturn: cycleReturn,
        terminalDiscountRate: terminalDiscountRate,
        externalCapitalRatio: externalCapitalRatio,
        periods: periods,
        operationalDecline: operationalDecline,
      ).terminalReturn;
}

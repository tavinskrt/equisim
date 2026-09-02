import 'package:equisim_core/equisim_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../shared/failure_copy.dart';
import '../study/study_notifier.dart';

/// Parâmetros da simulação histórica.
class BacktestSettings {
  /// Piso da janela, em anos.
  static const int minWindowYears = 1;

  /// Teto da janela, em anos — o que a fonte de cotações entrega.
  ///
  /// Nomeado porque o número é citado em três lugares: o mutador que trava a
  /// faixa, o controle deslizante que a desenha e o aviso que explica ao
  /// usuário por que uma meta de vinte anos não cabe na simulação. Escrito
  /// como literal nos três, bastaria a fonte passar a entregar quinze para
  /// que a interface passasse a mentir em dois deles.
  static const int maxWindowYears = 10;

  /// Quantos anos de histórico a simulação percorre, contados **para trás a
  /// partir de hoje**. Dez anos é o teto porque é o que a fonte de cotações
  /// entrega.
  final int windowYears;

  /// Dia do mês em que o aporte mensal entra.
  ///
  /// Limitado a 28 pelo domínio, para existir em todos os meses. Fixo no
  /// padrão: não há controle na interface.
  final int contributionDay;

  /// Declara os parâmetros.
  const BacktestSettings({
    this.windowYears = 5,
    this.contributionDay = 5,
  });

  /// Cópia com os campos informados substituídos.
  BacktestSettings copyWith({
    int? windowYears,
    int? contributionDay,
  }) => BacktestSettings(
    windowYears: windowYears ?? this.windowYears,
    contributionDay: contributionDay ?? this.contributionDay,
  );
}

class BacktestSettingsNotifier extends Notifier<BacktestSettings> {
  @override
  BacktestSettings build() => const BacktestSettings();

  /// Ajusta a janela do backtest, travada na faixa declarada por
  /// [BacktestSettings.minWindowYears] e [BacktestSettings.maxWindowYears].
  void setWindowYears(int years) => state = state.copyWith(
    windowYears: years.clamp(
      BacktestSettings.minWindowYears,
      BacktestSettings.maxWindowYears,
    ),
  );

  // O dia do aporte não tem mutador: é parâmetro declarado, fixo no padrão de
  // [BacktestSettings]. O `setContributionDay` que existia aqui nunca teve
  // chamador e foi removido na auditoria de código morto.
}

final backtestSettingsProvider =
    NotifierProvider<BacktestSettingsNotifier, BacktestSettings>(
      BacktestSettingsNotifier.new,
    );

/// Papel de um ponto na dispersão risco × retorno.
///
/// Ativo e carteira são papéis distintos, e a carteira de origem também: o
/// ponto de um candidato da Reserva precisa se distinguir de um ativo já
/// detido, porque é justamente essa comparação que sustenta a troca.
enum RiskReturnKind {
  /// Ativo que já compõe a carteira Principal.
  principalAsset,

  /// Candidato da Reserva. Distinguir os dois é o que permite ler a troca.
  reservaAsset,

  /// A carteira Principal consolidada.
  principal,

  /// A carteira Reserva consolidada.
  reserva,
}

/// Um ponto da dispersão: volatilidade e retorno anualizados, em **pontos
/// percentuais** — a unidade em que os eixos são rotulados.
class RiskReturnPoint {
  /// Rótulo do ponto: o ticker, ou o nome da carteira.
  final String label;

  /// Volatilidade anualizada em pontos percentuais — eixo horizontal.
  final double risk;

  /// Retorno anualizado em pontos percentuais — eixo vertical.
  final double ret;

  /// Papel do ponto, que decide cor e forma.
  final RiskReturnKind kind;

  /// Declara o ponto.
  const RiskReturnPoint({
    required this.label,
    required this.risk,
    required this.ret,
    required this.kind,
  });

  /// `true` para os pontos de carteira, `false` para os de ativo.
  bool get isPortfolio =>
      kind == RiskReturnKind.principal || kind == RiskReturnKind.reserva;
}

/// Resultado comparativo das duas carteiras sob o mesmo plano de aportes.
class PortfolioComparison {
  /// Resultado da Principal, ou `null` quando ela não pôde ser simulada —
  /// nesse caso o motivo está em [principalFailure].
  final BacktestOutcome? principal;

  /// Resultado da Reserva, com a mesma convenção de [principal].
  final BacktestOutcome? reserva;

  /// Janela **efetivamente simulada**, idêntica nas duas carteiras.
  final DateRange window;

  /// Janela pedida no parâmetro "Janela", antes de qualquer encurtamento.
  final DateRange requestedWindow;

  /// Ativo cujo histórico obrigou a encurtar a janela, quando houve.
  final Ticker? limitingTicker;

  /// Por que a Principal não pôde ser simulada, quando não pôde.
  final String? principalFailure;

  /// Por que a Reserva não pôde ser simulada, quando não pôde.
  final String? reservaFailure;

  /// Dispersão risco × retorno: um ponto por ativo das duas carteiras, mais
  /// as próprias carteiras.
  final List<RiskReturnPoint> riskReturn;

  /// Agrupa o resultado comparativo já apurado.
  const PortfolioComparison({
    required this.window,
    required this.requestedWindow,
    this.principal,
    this.reserva,
    this.limitingTicker,
    this.principalFailure,
    this.reservaFailure,
    this.riskReturn = const [],
  });

  /// `true` quando as duas carteiras foram simuladas — condição para que
  /// [twrGap] exista.
  bool get hasBoth => principal != null && reserva != null;

  /// `true` quando a janela simulada ficou menor que a pedida.
  bool get windowWasShortened => window.start.isAfter(requestedWindow.start);

  /// Diferença de retorno ponderado pelo tempo, em pontos percentuais.
  ///
  /// TWR é a métrica correta para esta comparação: neutraliza o cronograma de
  /// aportes, que é idêntico nas duas carteiras, e isola o que de fato difere
  /// — a composição.
  double? get twrGap => hasBoth
      ? (principal!.metrics.timeWeightedReturn -
                reserva!.metrics.timeWeightedReturn) *
            100
      : null;
}

/// Executa o backtest das duas carteiras com o mesmo plano de aportes.
///
/// **As duas carteiras são simuladas na mesma janela**, e é isso que sustenta
/// a comparação. O início comum é o primeiro pregão em que *todos* os ativos
/// das duas carteiras já negociavam — SAPR11, por exemplo, só tem cotação
/// desde 22/11/2017, de modo que uma janela de nove anos não pode começar
/// antes disso sem deixar a Principal sem preço para alocar o aporte.
///
/// Sem esse alinhamento cada carteira começava no seu próprio primeiro pregão:
/// os patrimônios aportados divergiam, o TWR comparava períodos diferentes e
/// as duas curvas apareciam deslocadas no gráfico, dando a impressão de que
/// uma delas parara de aportar antes do fim.
final comparisonProvider = FutureProvider<PortfolioComparison?>((ref) async {
  final study = ref.watch(studyProvider).study;
  final settings = ref.watch(backtestSettingsProvider);
  final goal = study.goal;

  if (study.principal.isEmpty && study.reserva.isEmpty) return null;
  if (goal == null) return null;

  final today = DateTime.now();
  final requested = DateRange(
    DateTime(today.year - settings.windowYears, today.month, today.day),
    today,
  );

  final prices = ref.watch(priceRepositoryProvider);
  final riskFree = await ref.watch(riskFreeRateProvider.future);

  final tickers = <Ticker>{
    ...study.principal.tickers,
    ...study.reserva.tickers,
  }.toList();
  if (tickers.isEmpty) return null;

  // Um único lote para todos os ativos das duas carteiras.
  final priceResult = await prices.dailyBatch(tickers, requested);
  if (priceResult.isErr) {
    final message = FailureCopy.of(priceResult.failureOrNull!);
    return PortfolioComparison(
      window: requested,
      requestedWindow: requested,
      principalFailure: message,
      reservaFailure: message,
    );
  }
  final priceMap = priceResult.unwrap();

  // Início comum às duas carteiras: o mais tardio dos primeiros pregões.
  var start = requested.start;
  Ticker? limiting;
  for (final ticker in tickers) {
    final series = priceMap[ticker];
    if (series == null || series.isEmpty) continue;
    if (series.firstDate.isAfter(start)) {
      start = series.firstDate;
      limiting = ticker;
    }
  }
  final window = DateRange(start, requested.end);

  final plan = ContributionPlan(
    initial: goal.initialContribution,
    monthly: goal.monthlyContribution,
    contributionDay: settings.contributionDay,
  );

  Result<BacktestOutcome>? runFor(Portfolio portfolio) {
    if (portfolio.isEmpty) return null;
    return PortfolioBacktest.run(
      portfolio: portfolio,
      prices: priceMap,
      plan: plan,
      range: window,
      riskFreeRate: riskFree,
    );
  }

  final principalRun = runFor(study.principal);
  final reservaRun = runFor(study.reserva);
  final principal = principalRun?.valueOrNull;
  final reserva = reservaRun?.valueOrNull;

  return PortfolioComparison(
    window: window,
    requestedWindow: requested,
    limitingTicker: limiting,
    principal: principal,
    reserva: reserva,
    principalFailure: _copyOf(principalRun),
    reservaFailure: _copyOf(reservaRun),
    riskReturn: _riskReturnPoints(
      principalPortfolio: study.principal,
      reservaPortfolio: study.reserva,
      prices: priceMap,
      window: window,
      principal: principal,
      reserva: reserva,
    ),
  );
});

/// Monta a dispersão risco × retorno.
///
/// Cada ativo entra com a volatilidade e o CAGR da **sua própria** série de
/// fechamentos no período; as carteiras entram com as métricas já apuradas
/// pelo backtest. É o contraste entre os dois grupos que torna o efeito da
/// diversificação visível — a carteira costuma cair à esquerda da nuvem, com
/// menos volatilidade que a maioria dos seus componentes.
///
/// **As duas carteiras contribuem com seus ativos**, marcados por carteira de
/// origem. A Reserva existe para abastecer a Principal, e a troca se decide
/// olhando onde o candidato cai em relação ao que já está em casa: um ativo
/// que rende mais assumindo menos risco fica acima e à esquerda.
List<RiskReturnPoint> _riskReturnPoints({
  required Portfolio principalPortfolio,
  required Portfolio reservaPortfolio,
  required Map<Ticker, PriceSeries> prices,
  required DateRange window,
  required BacktestOutcome? principal,
  required BacktestOutcome? reserva,
}) {
  final points = <RiskReturnPoint>[];
  // Um ticker desenhado duas vezes empilharia rótulos no mesmo pixel; a
  // carteira em que ele aparece primeiro é a que responde por ele.
  final drawn = <Ticker>{};

  void addAssets(Portfolio portfolio, RiskReturnKind kind) {
    for (final ticker in portfolio.tickers) {
      if (!drawn.add(ticker)) continue;

      final series = prices[ticker];
      if (series == null || series.isEmpty) continue;

      final path = _closesIn(series, window);
      // Menos de um mês de pregões não sustenta desvio-padrão anualizado.
      if (path.dates.length < 21) continue;

      final years = DateRange(path.dates.first, path.dates.last).years;
      if (years <= 0) continue;

      final first = path.closes.first;
      if (first <= 0) continue;
      final totalReturn = path.closes.last / first - 1;

      points.add(
        RiskReturnPoint(
          label: ticker.value,
          risk: RiskMetrics.annualizedVolatility(_dailyReturns(path.closes)) *
              100,
          ret: Returns.annualize(totalReturn, years) * 100,
          kind: kind,
        ),
      );
    }
  }

  addAssets(principalPortfolio, RiskReturnKind.principalAsset);
  addAssets(reservaPortfolio, RiskReturnKind.reservaAsset);

  void addPortfolio(
    BacktestOutcome? outcome,
    String label,
    RiskReturnKind kind,
  ) {
    if (outcome == null) return;
    points.add(
      RiskReturnPoint(
        label: label,
        risk: outcome.metrics.volatility * 100,
        ret: outcome.metrics.cagr * 100,
        kind: kind,
      ),
    );
  }

  addPortfolio(principal, 'Principal', RiskReturnKind.principal);
  addPortfolio(reserva, 'Reserva', RiskReturnKind.reserva);

  return points;
}

/// Matriz de correlação entre os ativos da carteira Principal.
///
/// Construída sobre o `close` de cada ativo, nunca sobre o `adjustedClose` da
/// fonte — que embute provento com ajuste que a auditoria reprovou (§0.4).
final correlationProvider =
    FutureProvider<({List<Ticker> tickers, List<List<double>> matrix})?>((
      ref,
    ) async {
      final study = ref.watch(studyProvider).study;
      final tickers = study.principal.tickers;
      if (tickers.length < 2) return null;

      final settings = ref.watch(backtestSettingsProvider);
      final today = DateTime.now();
      final window = DateRange(
        DateTime(today.year - settings.windowYears, today.month, today.day),
        today,
      );

      final priceResult = await ref
          .watch(priceRepositoryProvider)
          .dailyBatch(tickers, window);
      if (priceResult.isErr) return null;
      final priceMap = priceResult.unwrap();

      final available = tickers.where(priceMap.containsKey).toList();
      if (available.length < 2) return null;

      // Todas as séries pareadas pelo calendário comum: correlação sobre datas
      // desencontradas mediria ruído de calendário, não co-movimento.
      final common = <DateTime>{...priceMap[available.first]!.dates};
      for (final ticker in available.skip(1)) {
        common.retainAll(priceMap[ticker]!.dates);
      }
      final calendar = common.toList()..sort();
      if (calendar.length < 30) return null;

      final returns = <List<double>>[];
      for (final ticker in available) {
        final path = _closesIn(priceMap[ticker]!, window);
        final byDate = <DateTime, double>{
          for (var i = 0; i < path.dates.length; i++)
            path.dates[i]: path.closes[i],
        };

        final series = <double>[];
        double? previous;
        for (final date in calendar) {
          final value = byDate[date];
          if (value == null || value <= 0) continue;
          if (previous != null && previous > 0) {
            series.add(value / previous - 1);
          }
          previous = value;
        }
        returns.add(series);
      }

      return (
        tickers: available,
        matrix: BetaCalculator.correlationMatrix(returns),
      );
    });

/// Fechamentos de uma série dentro da janela, com as datas alinhadas.
///
/// É o substituto do antigo motor de retorno total: sem provento no modelo, a
/// trajetória de um ativo **é** a série de `close`, e não há mais o que somar
/// a ela.
({List<DateTime> dates, List<double> closes}) _closesIn(
  PriceSeries series,
  DateRange window,
) {
  final dates = <DateTime>[];
  final closes = <double>[];
  for (final point in series.points) {
    if (!window.contains(point.date)) continue;
    dates.add(point.date);
    closes.add(point.close);
  }
  return (dates: dates, closes: closes);
}

/// Retornos simples entre fechamentos consecutivos.
///
/// Pares cujo fechamento anterior não é positivo são **descartados** em vez de
/// virarem divisão por zero, então o resultado pode ter menos de `n − 1`
/// elementos e deixa de estar alinhado às datas.
List<double> _dailyReturns(List<double> closes) {
  final out = <double>[];
  for (var i = 1; i < closes.length; i++) {
    if (closes[i - 1] > 0) out.add(closes[i] / closes[i - 1] - 1.0);
  }
  return out;
}

/// Diagnóstico de uma simulação que não produziu resultado, já em texto de
/// tela. `null` quando a carteira nem chegou a ser simulada — carteira vazia
/// não é falha, é ausência.
String? _copyOf(Result<BacktestOutcome>? run) {
  final failure = run?.failureOrNull;
  return failure == null ? null : FailureCopy.of(failure);
}

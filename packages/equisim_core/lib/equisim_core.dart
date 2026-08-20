/// Núcleo de domínio do Equisim.
///
/// Pacote **Dart puro**: sem Flutter, sem rede, sem I/O. A ausência dessas
/// dependências não é convenção — é verificada automaticamente por
/// `test/purity_test.dart`, que falha o build se alguém importar
/// `package:flutter` ou um cliente HTTP aqui dentro.
///
/// Consequência prática: todo o motor financeiro é testável de forma
/// determinística e pode ser executado fora do aplicativo, o que garante que
/// os números da monografia venham do mesmo código que roda em produção.
library;

// --- Objetos de valor ---
export 'src/value_objects/date_range.dart';
export 'src/value_objects/money.dart';
export 'src/value_objects/ticker.dart';
export 'src/value_objects/weight.dart';

// --- Falhas ---
export 'src/failures/failure.dart';
export 'src/failures/result.dart';

// --- Entidades ---
export 'src/entities/asset.dart';
export 'src/entities/dividend_event.dart';
export 'src/entities/financial_goal.dart';
export 'src/entities/fundamentals.dart';
export 'src/entities/portfolio.dart';
export 'src/entities/price_series.dart';
export 'src/entities/valuation.dart';

// --- Recorte temporal ---
export 'src/time/point_in_time_view.dart';

// --- Tributação ---
export 'src/tax/tax_policy.dart';

// --- Serviços de domínio ---
export 'src/services/backtest/portfolio_backtest.dart';
export 'src/services/goal/feasibility.dart';
export 'src/services/goal/required_return.dart';
export 'src/services/metrics/beta.dart';
export 'src/services/metrics/returns.dart';
export 'src/services/metrics/risk_metrics.dart';
export 'src/services/portfolio/expected_return.dart';
export 'src/services/portfolio/sector_concentration.dart';
export 'src/services/total_return_engine.dart';
export 'src/services/valuation/cost_of_capital.dart';
export 'src/services/valuation/dcf.dart';
export 'src/services/valuation/scenario_engine.dart';

// --- Contratos de repositório ---
export 'src/repositories/repositories.dart';

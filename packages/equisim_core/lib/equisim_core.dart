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

// --- Auditoria de cálculo ---
export 'src/audit/audit_recorder.dart';
export 'src/audit/calculation_trace.dart';

// --- Objetos de valor ---
export 'src/value_objects/date_range.dart';
export 'src/value_objects/money.dart';
export 'src/value_objects/paired_series.dart';
export 'src/value_objects/ticker.dart';
export 'src/value_objects/weight.dart';

// --- Falhas ---
export 'src/failures/failure.dart';
export 'src/failures/result.dart';

// --- Entidades ---
export 'src/entities/asset.dart';
export 'src/entities/financial_goal.dart';
export 'src/entities/fundamentals.dart';
export 'src/entities/portfolio.dart';
export 'src/entities/price_series.dart';
export 'src/entities/valuation.dart';

// --- Recorte temporal ---
export 'src/time/brazilian_calendar.dart';
export 'src/time/point_in_time_view.dart';

// --- Serviços de domínio ---
export 'src/services/backtest/portfolio_backtest.dart';
export 'src/services/goal/feasibility.dart';
export 'src/services/goal/required_return.dart';
export 'src/services/metrics/beta.dart';
export 'src/services/metrics/beta_shrinkage.dart';
export 'src/services/metrics/market_leverage.dart';
export 'src/services/metrics/returns.dart';
export 'src/services/metrics/risk_metrics.dart';
export 'src/services/portfolio/expected_return.dart';
export 'src/services/portfolio/sector_concentration.dart';
export 'src/services/portfolio/transversal_ordering.dart';
export 'src/services/valuation/calibrated_band.dart';
export 'src/services/valuation/skill_reading.dart';
export 'src/services/valuation/capital_base.dart';
export 'src/services/cvm/cvm_bridge.dart';
export 'src/services/cvm/fundamentals_merge.dart';
export 'src/services/cvm/cvm_document_codec.dart';
export 'src/services/cvm/cvm_series.dart';
export 'src/services/cvm/trailing_twelve_months.dart';
export 'src/services/b3/b3_registry.dart';
export 'src/services/b3/corporate_events.dart';
export 'src/services/b3/cash_dividends.dart';
export 'src/services/cvm/cvm_chart.dart';
export 'src/services/cvm/fre_concessions.dart';
export 'src/services/cvm/share_count_history.dart';
export 'src/services/cvm/unit_composition.dart';
export 'src/services/valuation/concession_sectors.dart';
export 'src/services/valuation/financial_sectors.dart';
export 'src/services/valuation/cyclical_sectors.dart';
export 'src/services/valuation/eligibility.dart';
export 'src/services/valuation/growth_guards.dart';
export 'src/services/valuation/levered_rates.dart';
export 'src/services/valuation/inference.dart';
export 'src/services/valuation/cost_of_capital.dart';
export 'src/services/valuation/dcf.dart';
export 'src/services/valuation/growth_estimator.dart';
export 'src/services/valuation/scenario_engine.dart';
export 'src/services/valuation/yield_curve.dart';

// --- Casos de uso ---
export 'src/usecases/resolve_beta_prior.dart';
export 'src/usecases/compute_valuation.dart';
export 'src/usecases/portfolio_usecases.dart';
export 'src/usecases/prepare_valuation_inputs.dart';

// --- Contratos de repositório ---
export 'src/repositories/repositories.dart';

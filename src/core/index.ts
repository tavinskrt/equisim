/**
 * Núcleo de domínio do Equisim.
 *
 * **TypeScript puro**: sem React, sem rede, sem I/O, sem relógio no caminho
 * de cálculo. A ausência dessas dependências não é convenção — é verificada
 * por `test/core/purity.test.ts`, que falha a suíte se alguém importar o
 * navegador, a camada de dados ou um cliente HTTP aqui dentro.
 *
 * Consequência prática: todo o motor financeiro é testável de forma
 * determinística e pode ser executado fora do aplicativo — num *worker*, num
 * script de `tool/` ou no oráculo de paridade —, o que garante que os números
 * da monografia venham do mesmo código que roda em produção.
 */

// --- Semântica de linguagem herdada do motor original ---
export * from './lang/num';
export * from './lang/date-time';
export * from './lang/random';
export * from './lang/iter';
export * from './lang/json';
export * from './lang/dart-enum';

// --- Auditoria de cálculo ---
export * from './audit/wire-keyed';
export * from './audit/audit-recorder';
export * from './audit/calculation-trace';

// --- Objetos de valor ---
export * from './value-objects/date-range';
export * from './value-objects/money';
export * from './value-objects/paired-series';
export * from './value-objects/ticker';
export * from './value-objects/weight';

// --- Falhas ---
export * from './failures/failure';
export * from './failures/result';

// --- Entidades ---
export * from './entities/asset';
export * from './entities/financial-goal';
export * from './entities/fundamentals';
export * from './entities/portfolio';
export * from './entities/price-series';
export * from './entities/share-issue';
export * from './entities/valuation';

// --- Recorte temporal ---
export * from './time/brazilian-calendar';
export * from './time/point-in-time-view';

// --- Serviços de domínio ---
export * from './services/backtest/portfolio-backtest';
export * from './services/goal/feasibility';
export * from './services/goal/required-return';
export * from './services/metrics/beta';
export * from './services/metrics/beta-shrinkage';
export * from './services/metrics/market-leverage';
export * from './services/metrics/returns';
export * from './services/metrics/risk-metrics';
export * from './services/portfolio/expected-return';
export * from './services/portfolio/sector-concentration';
export * from './services/portfolio/transversal-ordering';
export * from './services/valuation/base-normalization';
export * from './services/valuation/calibrated-band';
export * from './services/valuation/skill-reading';
export * from './services/valuation/capital-base';
export * from './services/cvm/cvm-bridge';
export * from './services/cvm/fundamentals-merge';
export * from './services/cvm/cvm-document-codec';
export * from './services/cvm/cvm-series';
export * from './services/cvm/trailing-twelve-months';
export * from './services/cvm/year-to-date';
export * from './services/b3/b3-registry';
export * from './services/b3/corporate-events';
export * from './services/b3/cash-dividends';
export * from './services/cvm/cvm-chart';
export * from './services/cvm/fre-concessions';
export * from './services/cvm/capital-events';
export * from './services/cvm/share-count-history';
export * from './services/cvm/unit-composition';
export * from './services/cvm/shareholder-control';
export * from './services/valuation/concession-sectors';
export * from './services/valuation/financial-sectors';
export * from './services/valuation/peer-multiples';
export * from './services/valuation/cyclical-sectors';
export * from './services/valuation/eligibility';
export * from './services/valuation/growth-guards';
export * from './services/valuation/moat-fixed-point';
export * from './services/valuation/levered-rates';
export * from './services/valuation/inference';
export * from './services/valuation/cost-of-capital';
export * from './services/valuation/dcf';
export * from './services/valuation/manual-valuation';
export * from './services/valuation/manual-valuation-record';
export * from './services/valuation/growth-estimator';
export * from './services/valuation/implied-premium';
export * from './services/valuation/scenario-engine';
export * from './services/valuation/yield-curve';

// --- Casos de uso ---
export * from './usecases/resolve-beta-prior';
export * from './usecases/compute-valuation';
export * from './usecases/portfolio-usecases';
export * from './usecases/prepare-valuation-inputs';

// --- Contratos de repositório ---
export * from './repositories/repositories';

// B11 — resolve o prior transversal do beta e o empacota para o aplicativo.
//
// **Por que empacotar.** `ResolveBetaPrior` varre o universo inteiro — cinco
// anos de cotação, o histórico de fundamentos e o perfil de cada papel — para
// produzir uma mediana. O aplicativo não paga isso a cada abertura de tela, e
// sem o prior não há beta desalavancado: o motor cai no beta cru e no WACC
// estático, que são o recuo das decisões 40 e 41, e o caminho de taxas
// resolvido das decisões 41 a 46 nunca age em produção.
//
// **Sobre a entrada congelada do gabarito, por padrão.** O prior tem de ser
// reproduzível junto com o resto dos pacotes versionados, que são todos de
// 14/09/2026: gerá-lo contra o dado do dia faria o pacote depender do que a
// fonte devolvesse naquele instante. `--agora` usa o cache vivo e a data de
// hoje, para quando o conjunto de pacotes for atualizado.
//
// **O programa também mede o que justifica o pacote**: resolve o prior em
// várias datas e mostra o quanto ele anda. Prior que se move depressa não pode
// ser empacotado; este anda pouco, e o número fica no registro em vez de ser
// suposto.
//
// Uso:
//   npm run tool -- cascade-golden                 # congela a entrada
//   npm run tool -- beta-prior-package
//   npm run tool -- beta-prior-package --deriva    # mede a defasagem
import { existsSync, readFileSync } from 'node:fs';

import {
  B3RegistryCodec,
  type BetaPrior,
  BetaPriorCodec,
  type CashDividend,
  CashDividendsCodec,
  compareStr,
  DateTime,
  type JsonObject,
  ResolveBetaPrior,
  Ticker,
} from '../src/core';
import { OfficialSectorFundamentalsRepository } from '../src/data/repositories/b3-registry-repository';
import { CvmFundamentalsRepository } from '../src/data/repositories/cvm-fundamentals-repository';
import { errln, outln, readJson, writeText } from './lib/files';
import { ValidationContext } from './validation/context';

const output = 'public/assets/mercado/beta_prior.json';
const frozenCache = 'data/gabarito/cache.sqlite';
const frozenUniverse = 'data/gabarito/universo.json';

/** A data de referência dos pacotes versionados. */
const referenceDay = DateTime.local(2026, 9, 14);

/**
 * Datas em que o prior é remedido para a conferência de deriva, em dias antes
 * da data de referência. Um trimestre, um semestre e um ano.
 */
const lags = [90, 180, 365];

export async function main(args: string[]): Promise<void> {
  const measureDrift = args.includes('--deriva');
  const now = args.includes('--agora');
  const date = now ? DateTime.now() : referenceDay;

  if (!now && !existsSync(frozenCache)) {
    errln(`sem entrada congelada em ${frozenCache}. Rode antes:`);
    errln('  npm run tool -- cascade-golden');
    process.exitCode = 2;
    return;
  }

  const ctx = ValidationContext.create({
    outputDir: 'docs/validacao',
    ...(now ? {} : { cacheFile: frozenCache }),
    frozenCache: !now,
  });
  try {
    let tickers: Ticker[];
    if (!now && existsSync(frozenUniverse)) {
      tickers = readJson<string[]>(frozenUniverse).map((s) => Ticker.parse(s));
    } else {
      const universe = await ctx.fundamentals.universe();
      if (universe.isErr) {
        errln(`sem universo: ${universe.failureOrNull!.message}`);
        process.exitCode = 2;
        return;
      }
      tickers = universe.unwrap();
    }

    // **A mesma camada de dados do aplicativo**, e não a de mercado crua: o
    // prior encolhe o beta contra a alavancagem e a mediana setorial, e as duas
    // saem dos fundamentos. A CVM mesclada e o setor da B3 por emissor são o
    // que o aplicativo monta (decisões 80 e 87); resolver o prior sobre outra
    // camada daria um prior de outro motor.
    const registry = B3RegistryCodec.decodePackage(readJson<JsonObject>('public/assets/b3/emissores.json'));
    const fundamentals = new OfficialSectorFundamentalsRepository({
      inner: new CvmFundamentalsRepository({
        market: ctx.fundamentals,
        loadPackage: async () => readFileSync('public/assets/cvm/documentos.json', 'utf8'),
        today: () => date,
      }),
      classification: async (t) => (t.value.length >= 4 ? (registry.get(t.value.slice(0, 4))?.classification ?? null) : null),
    });
    const dividends = CashDividendsCodec.decode(readJson<JsonObject>('public/assets/b3/proventos.json'));
    const dividendsOf = (t: Ticker): CashDividend[] => CashDividendsCodec.forTicker(dividends, t.value);

    const resolver = (asOfDate: DateTime): Promise<BetaPrior | null> =>
      ResolveBetaPrior.call({
        tickers,
        prices: ctx.prices,
        fundamentals,
        benchmark: ctx.benchmark,
        asOf: asOfDate,
        dividendsFor: dividendsOf,
      });

    const prior = await resolver(date);
    if (prior === null) {
      errln('prior não resolvido: nenhuma observação utilizável');
      process.exitCode = 2;
      return;
    }

    writeText(output, JSON.stringify(BetaPriorCodec.encode(prior, { generatedAt: date, observations: tickers.length })));

    outln(`== prior do beta, em ${day(date)} ==`);
    outln(`  universo: ${prior.unleveredUniverse.toFixed(4)}`);
    outln(`  dispersão: ${prior.dispersion.toFixed(4)}`);
    outln(`  papéis varridos: ${tickers.length}`);
    outln(`  setores com mediana própria: ${prior.unleveredBySector.size}`);
    for (const [sector, beta] of [...prior.unleveredBySector].sort((a, b) => compareStr(a[0], b[0]))) {
      outln(`    ${sector.padEnd(28)} ${beta.toFixed(4)}`);
    }
    outln(`  gravado ${output}`);

    if (!measureDrift) return;
    outln('\n== quanto o prior anda ==');
    outln('  defasagem   universo            dispersão   setores');
    outln(
      `  na data     ${prior.unleveredUniverse.toFixed(4)}              ${prior.dispersion.toFixed(4)}      ` +
        `${prior.unleveredBySector.size}`,
    );
    for (const days of lags) {
      // **Dia civil, e não instante.** Subtrair uma duração soma horas
      // absolutas, e no salto do horário de verão o corte *point-in-time* cai
      // um dia antes ou depois. O componente fora da faixa é normalizado pelo
      // próprio `DateTime`.
      const before = await resolver(DateTime.local(date.year, date.month, date.day - days));
      if (before === null) {
        outln(`  −${days} dias: não resolvido`);
        continue;
      }
      // O prior é mediana de betas desalavancados e não deveria ser zero; se
      // for, a razão não tem leitura, e imprimir `NaN%` seria pior que nada.
      // Comparação por tolerância, e não igualdade: `double` derivado de
      // mediana não chega a zero exato, e `=== 0` deixaria o divisor passar.
      const du =
        Math.abs(prior.unleveredUniverse) < 1e-12 ? Number.NaN : (before.unleveredUniverse / prior.unleveredUniverse - 1) * 100;
      outln(
        `  −${String(days).padEnd(4)} dias  ${before.unleveredUniverse.toFixed(4)} ` +
          `(${Number.isNaN(du) ? '—' : `${du >= 0 ? '+' : ''}${du.toFixed(1)}%`})` +
          `      ${before.dispersion.toFixed(4)}      ${before.unleveredBySector.size}`,
      );
    }
  } finally {
    await ctx.dispose();
  }
}

const day = (d: DateTime): string => d.toIso8601String().slice(0, 10);

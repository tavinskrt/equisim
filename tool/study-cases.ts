// Os casos da documentação de estudo (`docs/estudo/casos/`), com tudo o que o
// aplicativo calcula para cada ativo, sobre a entrada congelada do gabarito
// (14/09/2026): insumos, CAPM, curva, exercícios publicados, resultado,
// cenários, Monte Carlo, faixa calibrada, múltiplos, ressalvas, avisos e o
// rastro de auditoria inteiro — o mesmo do painel de logs.
//
// A entrada é congelada, então a saída só muda quando o motor muda. Os casos
// escritos citam estes números: depois de mudar o motor, rode de novo e
// confira os documentos.
//
// Uso:
//   npm run tool -- study-cases                     # os cinco casos
//   npm run tool -- study-cases <pasta> PETR4 ...   # outros ativos
import {
  type AuditEvent,
  AuditJson,
  AuditRecorder,
  CalibratedBand,
  CalibratedBandCodec,
  type JsonObject,
  PeerMultipleCodec,
  PointInTimeView,
  round,
  StochasticScenarios,
  Ticker,
  ValuationCascade,
  VolatilityBandTable,
} from '../src/core';
import { jsonPretty, outln, readJson, writeText } from './lib/files';
import { Frozen } from './validation/frozen';

export async function main(args: string[]): Promise<void> {
  const output = args.length === 0 ? 'docs/estudo/casos/dados' : args[0]!;
  const targets = (args.length > 1 ? args.slice(1) : ['WEGE3', 'ITUB4', 'VALE3', 'SAPR11', 'RENT3']).map((s) => Ticker.parse(s));
  const c = await Frozen.build();
  const pairs = PeerMultipleCodec.decode(readJson<JsonObject>('public/assets/mercado/multiplos_setoriais.json'));
  const bands = CalibratedBandCodec.decode(readJson<JsonObject>('public/assets/validacao/banda_calibrada.json'));

  for (const t of targets) {
    const prep = await c.prepare(t);
    if (prep.isErr) {
      outln(`${t.value}: preparo falhou ${prep.failureOrNull?.message}`);
      continue;
    }
    const inputs = prep.unwrap().withPeerMultiples(pairs.get(t.value) ?? null);
    let ev: AuditEvent | null = null;
    AuditRecorder.attach((e) => {
      ev = e;
    });
    const r = ValuationCascade.evaluate(inputs);
    AuditRecorder.detach();
    let mc: Record<string, number> | null = null;
    if (r.isOk) {
      const m = ValuationCascade.evaluate(inputs, { scenarioBuilder: (base) => StochasticScenarios.around(base) });
      const d = m.valueOrNull?.distribution ?? null;
      if (d !== null && !d.isEmpty) {
        mc = {};
        for (const p of [0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 0.95]) mc[`p${round(p * 100)}`] = d.percentile(p);
        mc['n'] = d.sortedValues.length;
      }
    }
    const curve = inputs.riskFreeCurve;
    const view = new PointInTimeView(inputs.asOf);
    const lastOnes = inputs.fundamentals.filter((f) => view.isPublished(f));
    const res = r.valueOrNull;
    const event = ev as AuditEvent | null;

    const ranges: JsonObject[] = [];
    if (res !== null) {
      for (const months of [12, 36]) {
        for (const nominal of [0.5, 0.8, 0.9]) {
          const tab = CalibratedBand.select(bands, { months, nominal });
          if (tab === null) continue;
          const band = CalibratedBand.of(res.fairValue, tab, { marketPrice: res.marketPrice, volatility: res.priceVolatility });
          ranges.push({
            meses: months,
            nominal,
            coberturaForaDaAmostra: tab.outOfSampleCoverage,
            ...(tab instanceof VolatilityBandTable ? { a: tab.a, b: tab.b, zInf: tab.zLower, zSup: tab.zUpper } : {}),
            faixa: band === null ? null : [band.low.reais, band.high.reais],
          });
        }
      }
    }

    const json: JsonObject = {
      ticker: t.value,
      asOf: inputs.asOf.toIso8601String().slice(0, 10),
      preco: inputs.marketPrice,
      setor: inputs.sectorKey,
      subsetor: inputs.industry,
      capm: {
        rf: inputs.capm.riskFreeRate,
        beta: inputs.capm.beta,
        origemBeta: inputs.capm.betaSource.name,
        premio: inputs.capm.marketPremium,
        ke: inputs.capm.costOfEquity,
        betaDesalavancado: inputs.unleveredBeta,
      },
      ancoras: {
        inflacao: inputs.inflation,
        tetoCrescimentoNominal: inputs.perpetualGrowthCap,
        rfEstruturalDeclarada: inputs.declaredTerminalRiskFreeRate,
        rfTerminal: inputs.terminalRiskFreeRate,
      },
      curva:
        curve === null
          ? null
          : {
              data: curve.referenceDate.toIso8601String().slice(0, 10),
              forwards: curve.annualForwards(inputs.projectionYears),
              terminal: curve.terminalRate(inputs.projectionYears),
              vertices: curve.vertices.map((v) => [v.years, v.rate]),
            },
      exercicios: lastOnes.map((f) => ({
        ano: f.fiscalPeriodEnd.year,
        receita: f.totalRevenue,
        ebit: f.ebit,
        ebitda: f.ebitda,
        lucroLiquido: f.netIncome,
        lucroAntesIR: f.incomeBeforeTax,
        imposto: f.incomeTaxExpense,
        despesaFinanceira: f.interestExpense,
        equivalencia: f.equityIncomeResult,
        vpa: f.bookValuePerShare,
        acoesExercicio: f.sharesOutstandingAsOf,
        acoesCorrentes: f.sharesOutstanding,
        pl: f.equityBookValue,
        dividaBruta: f.totalDebt,
        caixa: f.totalCash,
        dividaLiquida: f.netDebt,
        capitalInvestido: f.investedCapital,
        minoritarios: f.minorityInterest,
        valorDeMercado: f.marketCap,
        aliquotaEfetiva: f.effectiveTaxRate,
        cobertura: f.interestCoverage,
        alavancagem: f.netDebtToEbitda,
        kdObservado: f.costOfDebt,
        nopatPublicado: f.nopat,
      })),
      recusa: r.isErr ? (r.failureOrNull?.message ?? null) : null,
      resultado:
        res === null
          ? null
          : {
              modelo: res.model.name,
              justo: res.fairValue.reais,
              preco: res.marketPrice.reais,
              potencial: res.upside,
              descontoAno1: res.discountRate,
              cenarios:
                res.discreteScenarios === null
                  ? null
                  : Object.fromEntries([...res.discreteScenarios].map(([k, v]) => [k.name, v.reais])),
              monteCarlo: mc,
              volatilidade: res.priceVolatility,
              faixas: ranges,
              ressalvas: res.caveats.map((x) => x.key),
              avisos: res.warnings,
              triangulacao:
                res.triangulation === null
                  ? null
                  : {
                      consolidado: res.triangulation.consolidated,
                      divergencia: res.triangulation.divergence,
                      leituras: res.triangulation.readings.map((l) => ({
                        tipo: l.kind.key,
                        justo: l.fairValuePerShare,
                        recusa: l.refusal?.key ?? null,
                        mediana: l.peer?.median ?? null,
                        pares: l.peer?.peers ?? null,
                        grupo: l.peer?.group ?? null,
                      })),
                    },
            },
      rastro: event === null ? null : AuditJson.safe(event.toJson()),
    };
    writeText(`${output}/${t.value}.json`, jsonPretty(json));
    outln(`${t.value}: ${res === null ? 'recusa' : `justo ${res.fairValue} potencial ${res.upside.toFixed(3)}`}`);
  }
}

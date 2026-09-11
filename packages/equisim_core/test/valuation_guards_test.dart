import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

/// Testes das portas e guardas introduzidas pela decisão 25.
///
/// Cada caso reproduz a **forma** de um ativo real da calibragem, com os
/// números que motivaram a regra. É o que impede que um limiar volte a ser
/// ajustado sem que o motivo original seja reencontrado.
void main() {
  final ticker = Ticker.parse('TEST3');

  FundamentalsSnapshot exercicio(
    int ano, {
    double? vpa,
    double? acoes,
    double? lucro,
    double? nopat,
    double dividaCurta = 0,
    double dividaLonga = 0,
    double caixa = 0,
  }) =>
      FundamentalsSnapshot(
        ticker: ticker,
        fiscalPeriodEnd: DateTime(ano, 12, 31),
        bookValuePerShare: vpa,
        sharesOutstandingAsOf: acoes,
        sharesOutstanding: acoes,
        netIncome: lucro,
        nopat: nopat,
        shortTermDebt: dividaCurta,
        longTermDebt: dividaLonga,
        cash: caixa,
      );

  group('Inference — primitivas conferidas contra tabela', () {
    test('quantil da t de Student bate com a tabela publicada', () {
      expect(Inference.studentT(0.975, 14), closeTo(2.1448, 5e-4));
      expect(Inference.studentT(0.975, 6), closeTo(2.4469, 5e-4));
      expect(Inference.studentT(0.95, 10), closeTo(1.8125, 5e-4));
      expect(Inference.studentT(0.995, 30), closeTo(2.7500, 5e-4));
    });

    test('R² crítico depende de n, e é isso que condena o limiar fixo', () {
      // Com n = 8 o corte correto é 0,50; com n = 16, 0,25. Um limiar único é
      // simultaneamente laxo numa ponta e estrito na outra.
      expect(Inference.criticalR2(8, 0.05), closeTo(0.499, 1e-3));
      expect(Inference.criticalR2(16, 0.05), closeTo(0.247, 1e-3));
      expect(Inference.criticalR2(8, 0.05),
          greaterThan(Inference.criticalR2(16, 0.05)));
    });

    test('MAD escalado resiste a contaminação que derruba o desvio-padrão', () {
      // Mediana 3, MAD 1 → 1,4826. O ponto em 100 não move a escala robusta.
      expect(Inference.scaledMad([1, 2, 3, 4, 100]), closeTo(1.4826, 1e-4));
    });
  });

  group('Base de capital', () {
    test('patrimônio usa a contagem de ações do exercício, não a corrente', () {
      // Forma do BBAS3: bonificação dobra as ações em 2024. Com a contagem
      // corrente aplicada a todos os anos, a série cairia pela metade num
      // degrau que é troca de denominador, não de lucro.
      final antes = exercicio(2023, vpa: 56.9, acoes: 2865417000, lucro: 33.1e9);
      final depois = exercicio(2024, vpa: 32.1, acoes: 5730834000, lucro: 29.2e9);
      expect(antes.equityBookValue! / 1e9, closeTo(163.1, 0.5));
      expect(depois.equityBookValue! / 1e9, closeTo(184.0, 0.5));
      expect(depois.equityBookValue, greaterThan(antes.equityBookValue!),
          reason: 'o patrimônio cresceu; foi o valor por ação que se dividiu');
    });

    test('capital investido soma dívida e subtrai caixa', () {
      final e = exercicio(2025,
          vpa: 10,
          acoes: 1000,
          nopat: 900,
          dividaCurta: 2000,
          dividaLonga: 3000,
          caixa: 1500);
      expect(e.investedCapital, closeTo(10 * 1000 + 5000 - 1500, 1e-9));
    });

    test('limpeza é por vizinhança: crescimento real de ordens de magnitude '
        'sobrevive', () {
      // Forma da PRIO3, que multiplicou a base por trinta em oito anos — 1,53x
      // ao ano. Um corte contra a mediana global apagaria os exercícios
      // recentes, os únicos que descrevem a empresa de hoje.
      var vpa = 1.0;
      final pontos = <FundamentalsSnapshot>[];
      for (var ano = 2018; ano <= 2025; ano++) {
        pontos.add(exercicio(ano, vpa: vpa, acoes: 1000, lucro: vpa * 100));
        vpa *= 1.526;
      }
      final serie = CapitalSeries.build(pontos, ValuationLane.shareholder);
      expect(serie.length, 8, reason: 'nenhum exercício legítimo foi cortado');
    });

    test('limpeza remove falha pontual da fonte', () {
      // Forma da ABEV3 em 2012: bookValue de 0,062 contra 2,81 no ano seguinte.
      final serie = CapitalSeries.build([
        exercicio(2020, vpa: 10, acoes: 1000, lucro: 100),
        exercicio(2021, vpa: 0.05, acoes: 1000, lucro: 100),
        exercicio(2022, vpa: 11, acoes: 1000, lucro: 100),
        exercicio(2023, vpa: 12, acoes: 1000, lucro: 100),
      ], ValuationLane.shareholder);
      expect(serie.length, 3);
      expect(serie.points.any((p) => p.year == 2021), isFalse);
    });
  });

  group('Conciliação da contagem de ações', () {
    // Os números são os do MILS3 no exercício de 2025, medidos no cache de
    // produção em 07/09/2026. A contagem corrente vinha 4.868x menor que a do
    // exercício, e a ponte de equity devolvia R$ 37.708,72 contra R$ 15,79 de
    // mercado na validação fora da amostra.
    FundamentalsSnapshot mils({double? lpa}) => FundamentalsSnapshot(
          ticker: ticker,
          fiscalPeriodEnd: DateTime(2025, 12, 31),
          netIncome: 301263000,
          earningsPerShare: lpa,
          sharesOutstanding: 48172,
          sharesOutstandingAsOf: 234178210,
          bookValuePerShare: 6.7376337,
        );

    test('o lucro por ação publicado arbitra a favor da contagem do exercício',
        () {
      // N implícito = 301.263.000 / 1,2865 = 234,2 mi, que é a do exercício.
      final f = mils(lpa: 1.2865);
      expect(f.reconciledShares, 234178210);
    });

    test('sem árbitro, prevalece a contagem que reconstrói o patrimônio', () {
      expect(mils().reconciledShares, 234178210);
    });

    test('o árbitro pode confirmar a contagem corrente, e então ela vence', () {
      // Mesmo par de candidatas, mas agora o LPA aponta para a corrente:
      // 301.263.000 / 6254,0 = 48.172.
      final f = mils(lpa: 6254.0);
      expect(f.reconciledShares, 48172);
    });

    test('divergência das duas contagens é sinalizada', () {
      expect(mils().sharesDisagree, isTrue);
    });

    test('contagens concordantes não geram sinal nem escolha', () {
      final f = FundamentalsSnapshot(
        ticker: ticker,
        fiscalPeriodEnd: DateTime(2025, 12, 31),
        sharesOutstanding: 100000000,
        sharesOutstandingAsOf: 98000000,
      );
      expect(f.sharesDisagree, isFalse);
      expect(f.reconciledShares, 98000000);
    });

    test('uma contagem só é usada como está', () {
      final f = FundamentalsSnapshot(
        ticker: ticker,
        fiscalPeriodEnd: DateTime(2025, 12, 31),
        sharesOutstanding: 48172,
      );
      expect(f.reconciledShares, 48172);
      expect(f.sharesDisagree, isFalse);
    });

    test('LPA nulo ou zerado não é árbitro', () {
      expect(mils(lpa: 0).reconciledShares, 234178210);
    });
  });

  group('Guarda 2 — capital externo', () {
    test('expansão por lucro retido é orgânica', () {
      // Patrimônio cresce exatamente pelo lucro: nada veio de fora.
      var pl = 1000.0;
      final pontos = <FundamentalsSnapshot>[];
      for (var ano = 2016; ano <= 2025; ano++) {
        pontos.add(exercicio(ano, vpa: pl / 1000, acoes: 1000, lucro: 100));
        pl += 100;
      }
      final serie = CapitalSeries.build(pontos, ValuationLane.shareholder);
      final phi = GrowthGuards.externalCapitalRatio(serie);
      expect(phi, isNotNull);
      expect(phi!, lessThan(0.05));
    });

    test('salto de patrimônio acima do lucro acusa capital externo', () {
      // Forma da RENT3 na incorporação: o patrimônio salta muito além do que a
      // empresa lucrou no ano.
      final pontos = <FundamentalsSnapshot>[];
      var pl = 1000.0;
      for (var ano = 2016; ano <= 2025; ano++) {
        if (ano == 2022) pl += 8000;
        pontos.add(exercicio(ano, vpa: pl / 1000, acoes: 1000, lucro: 100));
        pl += 100;
      }
      final serie = CapitalSeries.build(pontos, ValuationLane.shareholder);
      final phi = GrowthGuards.externalCapitalRatio(serie);
      expect(phi, isNotNull);
      expect(phi!, greaterThan(ValuationParameters.maxExternalCapital));
    });
  });

  group('Precedência da Guarda 2 — Φ declara, não barra', () {
    // Forma da SUZB3 e da QUAL3: base de capital que salta por incorporação —
    // Φ muito acima de 1,0 — e um exercício corrente de rentabilidade em pico.
    // Sob a precedência anterior, Φ travava a normalização e o pico virava
    // patamar perene: a SUZB3 saía a +259,1% e a QUAL3 a +477,3% de potencial.
    List<FundamentalsSnapshot> incorporacaoComPico({
      required double roeDoCiclo,
      required double roeCorrente,
    }) {
      final pontos = <FundamentalsSnapshot>[];
      var pl = 1000.0;
      for (var ano = 2012; ano <= 2025; ano++) {
        // O retorno do ano é medido sobre a base de **abertura**, que é a
        // convenção de `CapitalSeries.returns`.
        final lucro = ano == 2025 ? roeCorrente * pl : roeDoCiclo * pl;
        pl += lucro;
        // A incorporação: em 2020 a base salta seis vezes o lucro do ano.
        if (ano == 2020) pl += 6000;
        pontos.add(FundamentalsSnapshot(
          ticker: ticker,
          fiscalPeriodEnd: DateTime(ano, 12, 31),
          bookValuePerShare: pl / 1000,
          sharesOutstanding: 1000,
          sharesOutstandingAsOf: 1000,
          netIncome: ano == 2012 ? null : lucro,
          marketCap: 20000,
        ));
      }
      return pontos;
    }

    ValuationInputs entradas(
      List<FundamentalsSnapshot> historico, {
      String? setor,
      String? subsetor,
    }) =>
        ValuationInputs(
          ticker: ticker,
          asOf: DateTime(2026, 6, 30),
          fundamentals: historico,
          marketPrice: 20.0,
          capm: const CapmInputs(
            riskFreeRate: 0.105,
            beta: 1.0,
            marketPremium: 0.055,
          ),
          sectorKey: setor,
          industry: subsetor,
        );

    /// Fator de normalização registrado no log de avaliação.
    double fatorRegistrado(ValuationInputs inputs) {
      final capturados = <AuditEvent>[];
      AuditRecorder.attach(capturados.add);
      ValuationCascade.evaluate(inputs);
      AuditRecorder.detach();
      final base = capturados.single.calculations.firstWhere(
        (c) => c.formulaName == 'Base do fluxo: normalização pelo ciclo',
      );
      return base.finalValue!;
    }

    tearDown(AuditRecorder.detach);

    test('Φ acima do limiar não impede a normalização do retorno', () {
      final historico =
          incorporacaoComPico(roeDoCiclo: 0.10, roeCorrente: 0.30);
      final serie =
          CapitalSeries.build(historico, ValuationLane.shareholder);

      // A base é mesmo inorgânica, e por larga margem.
      final phi = GrowthGuards.externalCapitalRatio(serie);
      expect(phi, isNotNull);
      expect(phi!, greaterThan(ValuationParameters.maxExternalCapital));

      // E o exercício corrente destoa do ciclo.
      expect(GrowthGuards.deviatesFromCycle(serie), isTrue);

      // Logo o retorno é normalizado, sobre a base de capital corrente: o
      // fator é a razão entre o ciclo e o exercício de pico.
      expect(fatorRegistrado(entradas(historico)), closeTo(0.10 / 0.30, 1e-3),
          reason: 'ROIC e ROE são grandezas intensivas: mudança de tamanho '
              'por evento societário não torna o pico um patamar perene');
    });

    test('sem desvio do ciclo, Φ alto sozinho não normaliza nada', () {
      // A Guarda 3 continua sendo quem decide **se** normaliza. Φ nunca
      // normalizou nada, e continua não normalizando.
      final historico =
          incorporacaoComPico(roeDoCiclo: 0.10, roeCorrente: 0.10);
      expect(fatorRegistrado(entradas(historico)), closeTo(1.0, 1e-9));
    });

    test('em commodity, a tendência não segura a base', () {
      // Forma da SUZB3: retorno corrente muito acima do ciclo, subindo ano a
      // ano, de modo que a Guarda 1 lê a perna de alta como tendência
      // estrutural. Fora de setor cíclico a base fica; em papel e celulose,
      // não.
      final pontos = <FundamentalsSnapshot>[];
      var pl = 1000.0;
      for (var ano = 2012; ano <= 2025; ano++) {
        // Retorno subindo de 8% a 34%: tendência significante e dominante.
        final roe = 0.08 + (ano - 2012) * 0.02;
        final lucro = roe * pl;
        pl += lucro;
        pontos.add(FundamentalsSnapshot(
          ticker: ticker,
          fiscalPeriodEnd: DateTime(ano, 12, 31),
          bookValuePerShare: pl / 1000,
          sharesOutstanding: 1000,
          sharesOutstandingAsOf: 1000,
          netIncome: ano == 2012 ? null : lucro,
          marketCap: 20000,
        ));
      }
      final serie = CapitalSeries.build(pontos, ValuationLane.shareholder);
      final t = GrowthGuards.trend(serie);
      expect(t?.dominates, isTrue,
          reason: 'a fixture precisa mesmo acionar a Guarda 1');
      expect(GrowthGuards.deviatesFromCycle(serie), isTrue);

      expect(fatorRegistrado(entradas(pontos, setor: 'tecnologia')),
          closeTo(1.0, 1e-9),
          reason: 'fora de commodity a tendência continua segurando a base');
      expect(
        fatorRegistrado(entradas(pontos,
            setor: 'materiais-basicos', subsetor: 'Papel e Celulose')),
        lessThan(1.0),
        reason: 'em commodity a reversão ao ciclo tem precedência',
      );
    });

    /// Base que salta por emissão no penúltimo exercício, com o lucro
    /// **preservado**: o retorno corrente desaba sem que a empresa tenha
    /// encolhido, que é a única forma de estourar o fator sem cair no filtro de
    /// saúde. O salto é de 7x porque acima de 8x a limpeza por vizinhança
    /// descartaria o próprio exercício.
    List<FundamentalsSnapshot> emissaoComLucroPreservado() {
      final pontos = <FundamentalsSnapshot>[];
      var pl = 1000.0;
      var lucroCongelado = 0.0;
      for (var ano = 2012; ano <= 2025; ano++) {
        final lucro = ano >= 2024 ? lucroCongelado : 0.10 * pl;
        if (ano == 2023) lucroCongelado = 0.10 * pl;
        pl += lucro;
        if (ano == 2024) pl *= 7;
        pontos.add(FundamentalsSnapshot(
          ticker: ticker,
          fiscalPeriodEnd: DateTime(ano, 12, 31),
          bookValuePerShare: pl / 1000,
          sharesOutstanding: 1000,
          sharesOutstandingAsOf: 1000,
          netIncome: ano == 2012 ? null : lucro,
          marketCap: 20000,
        ));
      }
      return pontos;
    }

    /// Forma da QUAL3: lucro desabando no triênio e retorno corrente **abaixo**
    /// do ciclo, de modo que a normalização puxaria a base para cima.
    List<FundamentalsSnapshot> deterioracaoEstrutural() {
      final pontos = <FundamentalsSnapshot>[];
      var pl = 1000.0;
      for (var ano = 2012; ano <= 2025; ano++) {
        // 15% de retorno até 2022, 1,5% depois: queda de 90% no triênio.
        final roe = ano >= 2023 ? 0.015 : 0.15;
        final lucro = roe * pl;
        pl += lucro;
        pontos.add(FundamentalsSnapshot(
          ticker: ticker,
          fiscalPeriodEnd: DateTime(ano, 12, 31),
          bookValuePerShare: pl / 1000,
          sharesOutstanding: 1000,
          sharesOutstandingAsOf: 1000,
          netIncome: ano == 2012 ? null : lucro,
          marketCap: 20000,
        ));
      }
      return pontos;
    }

    test('o fator de normalização é saturado em [0,33; 3,00]', () {
      final pontos = emissaoComLucroPreservado();
      final serie = CapitalSeries.build(pontos, ValuationLane.shareholder);
      final bruto = serie.cycleReturn(window: ValuationParameters.cycleWindow)! /
          serie.latestReturn!;
      expect(bruto, greaterThan(ValuationParameters.baseFactorCeiling),
          reason: 'a fixture precisa mesmo estourar a banda');
      expect(GrowthGuards.recentOperationalDecline(pontos),
          lessThan(ValuationParameters.maxOperationalDecline),
          reason: 'e precisa passar na saúde, senão quem trava é a outra regra');

      expect(fatorRegistrado(entradas(pontos)),
          closeTo(ValuationParameters.baseFactorCeiling, 1e-9));
    });

    test('a saturação é declarada nos avisos', () {
      final r = ValuationCascade.evaluate(entradas(emissaoComLucroPreservado()));
      expect(r.isOk, isTrue);
      expect(r.unwrap().warnings.any((w) => w.contains('saturado em')), isTrue,
          reason: 'um preço justo confinado por política precisa dizer que foi');
    });

    test('deterioração estrutural proíbe normalizar a base para cima', () {
      final pontos = deterioracaoEstrutural();
      final serie = CapitalSeries.build(pontos, ValuationLane.shareholder);

      // A fixture é mesmo o caso: destoa do ciclo, e para cima.
      expect(GrowthGuards.deviatesFromCycle(serie), isTrue);
      final bruto = serie.cycleReturn(window: ValuationParameters.cycleWindow)! /
          serie.latestReturn!;
      expect(bruto, greaterThan(1.0));
      expect(GrowthGuards.recentOperationalDecline(pontos),
          greaterThan(ValuationParameters.maxOperationalDecline));

      expect(fatorRegistrado(entradas(pontos)), closeTo(1.0, 1e-9),
          reason: 'trazer a base de uma empresa que mudou de patamar de volta à '
              'mediana de oito anos lhe atribui um retorno que não repetirá');

      final r = ValuationCascade.evaluate(entradas(pontos));
      expect(r.isOk, isTrue);
      expect(
        r.unwrap().warnings.any((w) => w.contains('não foi normalizada para cima')),
        isTrue,
      );
    });

    test('commodity em vale de ciclo é isenta da trava de saúde', () {
      // VALE3 e GGBR4: queda de ~87% entre o pico de 2022 e o vale de 2025, com
      // o retorno corrente abaixo do ciclo. Fora de commodity a base fica
      // travada em 1,00; em materiais básicos a convergência opera.
      final pontos = deterioracaoEstrutural();
      expect(GrowthGuards.recentOperationalDecline(pontos),
          greaterThan(ValuationParameters.maxOperationalDecline));

      expect(fatorRegistrado(entradas(pontos, setor: 'saude')),
          closeTo(1.0, 1e-9),
          reason: 'fora de commodity a trava continua valendo integralmente');
      expect(
        fatorRegistrado(entradas(pontos,
            setor: 'materiais-basicos', subsetor: 'Siderurgia')),
        greaterThan(1.0),
        reason: 'em commodity a queda entre pico e vale é preço do insumo, e a '
            'reversão ao ciclo precisa operar nos dois sentidos',
      );
    });

    test('a trava de saúde vale só na Porta 2a, e o moat não a consulta', () {
      // Desde a decisão 36 a pergunta do moat não é mais "esta empresa merece
      // uma exceção", e sim "quanto do excedente dela persiste". Deterioração
      // entra pela série que estima a persistência, e não por um limiar em
      // cima dela. A trava de saúde continua inteira na Porta 2a, que é onde a
      // QUAL3 era de fato resolvida.
      final v = GrowthGuards.residualMoat(
        cycleReturn: 0.30,
        terminalDiscountRate: 0.12,
        externalCapitalRatio: 0.10,
        periods: 14,
        excessReturns: [
          for (var i = 0; i < 5; i++)
            (year: 2021 + i, excess: 0.18 / _pot(2, i)),
        ],
        projectionYears: 10,
      );
      expect(v.isProven, isTrue);
      expect(
        v.blocks,
        isEmpty,
        reason: 'nenhum bloco de saúde operacional sobrou no moat',
      );
    });

    test('a isenção em commodity continua limitada pela saturação', () {
      // O que limita a normalização em setor cíclico é a banda, e ela vale
      // igual: isentar da trava de saúde não abre o teto de 3,00x.
      final pontos = emissaoComLucroPreservado();
      expect(
        fatorRegistrado(entradas(pontos,
            setor: 'materiais-basicos', subsetor: 'Papel e Celulose')),
        closeTo(ValuationParameters.baseFactorCeiling, 1e-9),
      );
    });

    test('a isenção é declarada nos avisos', () {
      final r = ValuationCascade.evaluate(entradas(deterioracaoEstrutural(),
          setor: 'materiais-basicos', subsetor: 'Siderurgia'));
      expect(r.isOk, isTrue);
      expect(
        r.unwrap().warnings.any((w) => w.contains('setor de commodity')),
        isTrue,
        reason: 'uma isenção silenciosa é pior que a trava que ela remove',
      );
    });

    test('o piso continua valendo para quem reprovou na saúde', () {
      // Deterioração no lucro **com** o exercício corrente acima do ciclo: a
      // trava é só de teto, e normalizar para baixo é a direção conservadora.
      final pontos = <FundamentalsSnapshot>[];
      var pl = 1000.0;
      for (var ano = 2012; ano <= 2025; ano++) {
        // Retorno cai de 20% para 2% e o exercício corrente volta a 30%: o
        // lucro do triênio despencou, mas o ano é de pico contra o ciclo.
        final roe = ano == 2025 ? 0.30 : (ano >= 2023 ? 0.02 : 0.20);
        final lucro = roe * pl;
        pl += lucro;
        pontos.add(FundamentalsSnapshot(
          ticker: ticker,
          fiscalPeriodEnd: DateTime(ano, 12, 31),
          bookValuePerShare: pl / 1000,
          sharesOutstanding: 1000,
          sharesOutstandingAsOf: 1000,
          netIncome: ano == 2012 ? null : lucro,
          marketCap: 20000,
        ));
      }
      final serie = CapitalSeries.build(pontos, ValuationLane.shareholder);
      final bruto = serie.cycleReturn(window: ValuationParameters.cycleWindow)! /
          serie.latestReturn!;
      expect(bruto, lessThan(1.0), reason: 'a fixture precisa normalizar para baixo');

      expect(fatorRegistrado(entradas(pontos)), lessThan(1.0));
    });

    test('a base inorgânica é declarada nos avisos, não silenciada', () {
      final historico =
          incorporacaoComPico(roeDoCiclo: 0.10, roeCorrente: 0.30);
      final resultado = ValuationCascade.evaluate(entradas(historico));
      expect(resultado.isOk, isTrue);
      expect(
        resultado.unwrap().warnings.any((w) => w.contains('grandeza intensiva')),
        isTrue,
        reason: 'trocar bloqueio por permissão silenciosa seria pior que o '
            'defeito que se está corrigindo',
      );
    });
  });

  group('Porta 1 — instituição financeira, pelo setor', () {
    /// Empresa com NOPAT positivo em todos os exercícios: pela Porta 3, ela
    /// **iria** para a via da firma. É o que torna o teste capaz de isolar a
    /// decisão da Porta 1 — sem isso, a via do acionista seria escolhida pela
    /// porta seguinte e o teste não provaria nada.
    List<FundamentalsSnapshot> comFluxoDeFirma({required double divida}) {
      final pontos = <FundamentalsSnapshot>[];
      var pl = 1000.0;
      for (var ano = 2012; ano <= 2025; ano++) {
        final lucro = 0.12 * pl;
        pl += lucro;
        pontos.add(FundamentalsSnapshot(
          ticker: ticker,
          fiscalPeriodEnd: DateTime(ano, 12, 31),
          bookValuePerShare: pl / 1000,
          sharesOutstanding: 1000,
          sharesOutstandingAsOf: 1000,
          netIncome: ano == 2012 ? null : lucro,
          nopat: lucro,
          ebit: lucro * 1.4,
          longTermDebt: divida,
          marketCap: 20000,
        ));
      }
      return pontos;
    }

    ValuationResult? avaliar({required String? setor, required double divida}) {
      final r = ValuationCascade.evaluate(ValuationInputs(
        ticker: ticker,
        asOf: DateTime(2026, 6, 30),
        fundamentals: comFluxoDeFirma(divida: divida),
        marketPrice: 20.0,
        capm: const CapmInputs(
          riskFreeRate: 0.105,
          beta: 1.0,
          marketPremium: 0.055,
        ),
        sectorKey: setor,
      ));
      return r.isOk ? r.unwrap() : null;
    }

    test('setor financeiro manda para a via do acionista', () {
      final v = avaliar(setor: 'servicos-financeiros', divida: 0);
      expect(v, isNotNull);
      expect(v!.model, ValuationModel.dcfEarnings);
      expect(
        v.warnings.any((w) => w.contains('Instituição financeira')),
        isTrue,
        reason: 'a porta que decidiu precisa aparecer no resultado',
      );
    });

    test('passivo oneroso NÃO tira a financeira da Porta 1', () {
      // Captação é a matéria-prima do negócio bancário: exigir dívida nula
      // barrava justamente quem a porta existe para pegar. Cinco dos 28 ativos
      // do setor caíam por ela para a via da firma, e na B3SA3 as debêntures
      // viravam dívida líquida subtraída do valor da firma.
      //
      // A justificativa original da exigência — a RENT3 chegando como
      // `Finance` — é de outra taxonomia: a porta compara contra a do perfil,
      // onde a RENT3 vem como `consumo-ciclico`.
      final v = avaliar(setor: 'servicos-financeiros', divida: 500);
      expect(v, isNotNull);
      expect(v!.model, ValuationModel.dcfEarnings);
      expect(v.warnings.any((w) => w.contains('Instituição financeira')), isTrue);
    });

    test('fora do setor financeiro, dívida nula não aciona a Porta 1', () {
      final v = avaliar(setor: 'bens-industriais', divida: 0);
      expect(v, isNotNull);
      expect(v!.model, ValuationModel.dcfFcff);
      expect(v.warnings.any((w) => w.contains('Instituição financeira')), isFalse);
    });

    test('sem setor informado, o roteamento cai na Porta 3', () {
      // Degradação segura declarada na decisão 25: perfil que não carrega não
      // pode ligar uma exceção de via.
      final v = avaliar(setor: null, divida: 0);
      expect(v, isNotNull);
      expect(v!.model, ValuationModel.dcfFcff);
    });
  });

  group('Precedência do ciclo em commodity — Guarda 3 sobre Guarda 1', () {
    test('a taxonomia separa petróleo de energia elétrica', () {
      // A chave `energia` reúne exploração de petróleo, que é commodity pura, e
      // 28 elétricas, que são concessão regulada. Tratar a chave inteira como
      // cíclica inverteria a natureza das segundas.
      bool ciclico(String? setor, String? sub) =>
          CyclicalSectors.hasCyclePrecedence(sectorKey: setor, industry: sub);

      expect(ciclico('energia', 'Exploração e Produção de Petróleo'), isTrue);
      expect(ciclico('energia', 'Exploração, Refino e Distribuição'), isTrue);
      expect(ciclico('energia', 'Petróleo e Gás Integrado'), isTrue);
      expect(ciclico('energia', 'Energia Elétrica'), isFalse);
      expect(ciclico('energia', 'Gás'), isFalse,
          reason: 'distribuição de gás é concessão, não exploração');
      expect(ciclico('saneamento', 'Água e Saneamento'), isFalse);
      expect(ciclico('servicos-financeiros', 'Bancos'), isFalse);
    });

    test('materiais básicos é cíclico por inteiro', () {
      for (final sub in [
        'Papel e Celulose',
        'Siderurgia',
        'Minerais Metálicos',
        'Petroquímicos',
        'Fertilizantes e Defensivos',
      ]) {
        expect(
          CyclicalSectors.hasCyclePrecedence(
              sectorKey: 'materiais-basicos', industry: sub),
          isTrue,
          reason: sub,
        );
      }
    });

    test('a variante de pontuação da fonte não muda a classificação', () {
      // A fonte publica os dois: com vírgula e com ponto.
      expect(
        CyclicalSectors.hasCyclePrecedence(
            sectorKey: 'energia', industry: 'Exploração, Refino e Distribuição'),
        CyclicalSectors.hasCyclePrecedence(
            sectorKey: 'energia', industry: 'Exploração. Refino e Distribuição'),
      );
    });

    test('sem setor nem subsetor, não há precedência', () {
      expect(CyclicalSectors.hasCyclePrecedence(), isFalse,
          reason: 'ausência de classificação não pode ligar uma exceção');
    });
  });

  group('Saída 2 — identificação do crescimento', () {
    List<FundamentalsSnapshot> comCrescimento(double g, {double ruido = 0}) {
      var pl = 1000.0;
      final pontos = <FundamentalsSnapshot>[];
      for (var ano = 2014; ano <= 2025; ano++) {
        final desvio = ruido == 0 ? 1.0 : (ano.isEven ? 1 + ruido : 1 - ruido);
        pontos.add(exercicio(ano,
            vpa: pl * desvio / 1000, acoes: 1000, lucro: pl * 0.15));
        pl *= 1 + g;
      }
      return pontos;
    }

    test('série limpa devolve o crescimento pela mediana das variações', () {
      final serie =
          CapitalSeries.build(comCrescimento(0.08), ValuationLane.shareholder);
      final d = GrowthGuards.dispersion(serie);
      expect(d, isNotNull);
      expect(d!.isIdentified, isTrue);
      expect(d.medianGrowth, closeTo(0.08, 1e-6));
    });

    test('estimador impreciso é barrado antes do teste de discordância', () {
      // Forma da PRIO3: os dois estimadores concordam (D pequeno) porque ambos
      // são ruins. Sem o piso de precisão, o ativo mais imprecisamente medido
      // da amostra receberia o maior crescimento.
      final serie = CapitalSeries.build(
          comCrescimento(0.25, ruido: 0.45), ValuationLane.shareholder);
      final d = GrowthGuards.dispersion(serie);
      expect(d, isNotNull);
      expect(d!.stdError, greaterThan(ValuationParameters.maxGrowthStdError));
      expect(d.isIdentified, isFalse);
      expect(d.failure, contains('impreciso'));
    });

    test('financiabilidade discrimina por retorno, não por setor', () {
      // Retorno alto torna a inflação barata de financiar; retorno baixo, não.
      // É a forma de BBSE3 contra VIVT3.
      expect(
        GrowthGuards.anchorIsFundable(
            inflation: 0.05, cycleReturn: 0.675, observedRetention: 0.113),
        isTrue,
        reason: 'com retorno de 67,5%, crescer à inflação custa 7,4% de '
            'retenção contra 11,3% observados',
      );
      expect(
        GrowthGuards.anchorIsFundable(
            inflation: 0.05, cycleReturn: 0.078, observedRetention: 0.06),
        isFalse,
        reason: 'com retorno de 7,8%, exigiria reter 64% contra 6% observados',
      );
    });
  });

  group('Porta 0 — elegibilidade', () {
    test('histórico curto reprova', () {
      final v = EligibilityGate.assess(snapshots: [
        for (var ano = 2021; ano <= 2025; ano++)
          exercicio(ano, vpa: 10, acoes: 1000, lucro: 100),
      ]);
      expect(v.isEligible, isFalse);
      expect(v.reasons, contains(IneligibilityReason.shortHistory));
    });

    test('patrimônio negativo em dois exercícios consecutivos reprova', () {
      final v = EligibilityGate.assess(snapshots: [
        for (var ano = 2016; ano <= 2023; ano++)
          exercicio(ano, vpa: 10, acoes: 1000, lucro: 100),
        exercicio(2024, vpa: -1, acoes: 1000, lucro: -50),
        exercicio(2025, vpa: -2, acoes: 1000, lucro: -50),
      ]);
      expect(v.isEligible, isFalse);
      expect(v.reasons, contains(IneligibilityReason.insolvent));
    });

    test('um exercício isolado de patrimônio negativo não reprova', () {
      final v = EligibilityGate.assess(snapshots: [
        for (var ano = 2016; ano <= 2023; ano++)
          exercicio(ano, vpa: 10, acoes: 1000, lucro: 100),
        exercicio(2024, vpa: -1, acoes: 1000, lucro: -50),
        exercicio(2025, vpa: 9, acoes: 1000, lucro: 80),
      ]);
      expect(v.reasons, isNot(contains(IneligibilityReason.insolvent)));
    });

    test('recuperação judicial reprova, e vem de fora', () {
      final v = EligibilityGate.assess(
        snapshots: [
          for (var ano = 2016; ano <= 2025; ano++)
            exercicio(ano, vpa: 10, acoes: 1000, lucro: 100),
        ],
        isDistressed: true,
      );
      expect(v.isEligible, isFalse);
      expect(v.reasons, contains(IneligibilityReason.distressed));
    });

    test('série sem volume omite o teste de liquidez em vez de reprovar', () {
      final v = EligibilityGate.assess(
        snapshots: [
          for (var ano = 2016; ano <= 2025; ano++)
            exercicio(ano, vpa: 10, acoes: 1000, lucro: 100),
        ],
        prices: PriceSeries(
          ticker: ticker,
          points: [
            for (var i = 0; i < 100; i++)
              PricePoint(date: DateTime(2026, 1, 1).add(Duration(days: i)),
                  close: 10),
          ],
        ),
      );
      expect(v.averageDailyTradedValue, isNull);
      expect(v.reasons, isNot(contains(IneligibilityReason.illiquid)));
    });

    test('volume financeiro abaixo do corte reprova', () {
      final v = EligibilityGate.assess(
        snapshots: [
          for (var ano = 2016; ano <= 2025; ano++)
            exercicio(ano, vpa: 10, acoes: 1000, lucro: 100),
        ],
        prices: PriceSeries(
          ticker: ticker,
          points: [
            for (var i = 0; i < 100; i++)
              PricePoint(
                  date: DateTime(2026, 1, 1).add(Duration(days: i)),
                  close: 10,
                  volume: 1000),
          ],
        ),
      );
      expect(v.averageDailyTradedValue, closeTo(10000, 1e-6));
      expect(v.reasons, contains(IneligibilityReason.illiquid));
    });
  });

  group('Estrutura a termo do desconto', () {
    const a = DcfAssumptions(
      projectionYears: 10,
      growthRate: 0.10,
      perpetualGrowth: 0.05,
      discountRate: 0.16,
      terminalDiscountRate: 0.12,
      returnOnCapital: 0.20,
    );

    test('a taxa parte da corrente e chega à de equilíbrio', () {
      expect(a.discountRateAt(1), closeTo(0.16, 1e-12));
      expect(a.discountRateAt(10), closeTo(0.12, 1e-12));
    });

    test('o decaimento é linear no passo da janela', () {
      // No ano 6 percorreram-se 5/9 da janela.
      expect(a.discountRateAt(6), closeTo(0.16 - 0.04 * 5 / 9, 1e-12));
    });

    test('o retorno converge para o custo de capital do próprio ano', () {
      expect(a.returnOnCapitalAt(1), closeTo(0.20, 1e-12));
      expect(a.returnOnCapitalAt(10), closeTo(a.discountRateAt(10), 1e-12));
    });

    test('o último ano explícito encontra a retenção do estado estacionário',
        () {
      // b_N = g_inf / r_inf é exatamente a retenção que o terminal supõe:
      // a projeção deixa de saltar para a perpetuidade.
      expect(a.retentionAt(10), closeTo(0.05 / 0.12, 1e-12));
    });

    test('o fator de desconto acumula as taxas, não eleva uma só a t', () {
      final r = DcfCalculator.shareholder(
        baseProfit: 100,
        assumptions: const DcfAssumptions(
          projectionYears: 2,
          growthRate: 0.0,
          perpetualGrowth: 0.0,
          discountRate: 0.20,
          terminalDiscountRate: 0.10,
        ),
      );
      final o = r.unwrap();
      // Ano 1 a 20%, ano 2 a 10%: fatores 1,20 e 1,20 x 1,10 = 1,32. O
      // levantamento de meio de ano usa a taxa **do próprio ano**, e é o que
      // separa "o caixa chega no meio do ano" de "a curva mudou".
      expect(o.discountedFlows[0],
          closeTo(100 * math.sqrt(1.20) / 1.20, 1e-9));
      expect(o.discountedFlows[1],
          closeTo(100 * math.sqrt(1.10) / 1.32, 1e-9));
    });

    test('a convenção de meio de ano levanta o valor por raiz de (1+r)', () {
      // O levantamento incide sobre a avaliação **inteira** — período
      // explícito e perpetuidade —, e por isso é razão exata quando a taxa é
      // plana. Com taxa única de 13%, vale 6,30%.
      DcfOutcome comTiming(CashTiming timing) => DcfCalculator
          .shareholder(
            baseProfit: 100,
            assumptions: DcfAssumptions(
              projectionYears: 10,
              growthRate: 0.04,
              perpetualGrowth: 0.04,
              discountRate: 0.13,
              terminalDiscountRate: 0.13,
              cashTiming: timing,
            ),
          )
          .unwrap();

      final fim = comTiming(CashTiming.fimDeAno);
      final meio = comTiming(CashTiming.meioDeAno);
      expect(meio.fairValuePerShare / fim.fairValuePerShare,
          closeTo(math.sqrt(1.13), 1e-12));
      expect(math.sqrt(1.13) - 1, closeTo(0.0630, 1e-4));

      // A composição do valor **não** muda: o levantamento é o mesmo fator nos
      // dois pedaços, e o peso do terminal fica onde estava.
      expect(meio.terminalShare, closeTo(fim.terminalShare, 1e-12));
    });

    test('sob taxa que varia, o levantamento não é fator único', () {
      // Cada ano é levantado pela taxa daquele ano, de modo que a razão entre
      // as duas convenções fica **entre** as raízes dos extremos. Se fosse
      // fator único, o meio de ano seria mera reescala e não precisaria
      // atravessar a projeção.
      DcfOutcome comTiming(CashTiming timing) => DcfCalculator
          .shareholder(
            baseProfit: 100,
            assumptions: DcfAssumptions(
              projectionYears: 10,
              growthRate: 0.04,
              perpetualGrowth: 0.04,
              discountRate: 0.18,
              terminalDiscountRate: 0.09,
              cashTiming: timing,
            ),
          )
          .unwrap();

      final razao = comTiming(CashTiming.meioDeAno).fairValuePerShare /
          comTiming(CashTiming.fimDeAno).fairValuePerShare;
      expect(razao, greaterThan(math.sqrt(1.09)));
      expect(razao, lessThan(math.sqrt(1.18)));
    });

    test('sem taxa terminal declarada, o desconto é plano', () {
      const plana = DcfAssumptions(
        projectionYears: 10,
        growthRate: 0.10,
        perpetualGrowth: 0.05,
        discountRate: 0.16,
      );
      expect(plana.terminalDiscountRate, 0.16);
      expect(plana.discountRateAt(7), closeTo(0.16, 1e-12));
    });
  });

  group('Alíquota estrutural no fluxo da firma', () {
    // [imposto] é o **ônus**, em módulo. A fonte grava a despesa com sinal
    // negativo — `lucro líquido = lucro antes + incomeTaxExpense` —, e o
    // fixture reproduz essa convenção para que o teste exercite a conta real.
    FundamentalsSnapshot comImposto(
      int ano,
      double lucroAntes,
      double imposto, {
      double? ebitDoAno,
    }) =>
        FundamentalsSnapshot(
          ticker: ticker,
          fiscalPeriodEnd: DateTime(ano, 12, 31),
          ebit: ebitDoAno ?? 1000,
          ebitda: (ebitDoAno ?? 1000) + 300,
          netIncome: lucroAntes - imposto,
          incomeBeforeTax: lucroAntes,
          incomeTaxExpense: -imposto,
          nopat: (ebitDoAno ?? 1000) * 0.66,
          totalStockholderEquity: 5000,
          bookValuePerShare: 5.0,
          propertyPlantEquipment: 6000,
          totalCurrentAssets: 2000,
          currentLiabilities: 1000,
          sharesOutstanding: 1000,
          sharesOutstandingAsOf: 1000,
        );

    List<FundamentalsSnapshot> comAliquota(double taxa, {int anos = 10}) => [
          for (var i = anos - 1; i >= 0; i--)
            comImposto(2025 - i, 1000, 1000 * taxa),
        ];

    test('a estrutural é a mediana dos exercícios, não a do último', () {
      // Nove exercícios a 20% e um a 45%: a mediana ignora o atípico, que é o
      // ponto de usar mediana e não o último exercício.
      final serie = [
        for (var i = 9; i >= 1; i--) comImposto(2025 - i, 1000, 200),
        comImposto(2025, 1000, 450),
      ];
      expect(
        CapitalSeries.structuralTaxRate(serie, statutoryRate: 0.34),
        closeTo(0.20, 1e-12),
      );
    });

    test('é confinada no teto da estatutária', () {
      // Pagar mais que a marginal em perpetuidade é transitório, e a fonte já
      // aplicou a estatutária: ir além penalizaria duas vezes.
      expect(
        CapitalSeries.structuralTaxRate(comAliquota(0.45), statutoryRate: 0.34),
        closeTo(0.34, 1e-12),
      );
    });

    test('série curta demais devolve nulo, e o chamador recua', () {
      expect(
        CapitalSeries.structuralTaxRate(comAliquota(0.15, anos: 4),
            statutoryRate: 0.34),
        isNull,
      );
      expect(
        CapitalSeries.structuralTaxRate(comAliquota(0.15, anos: 5),
            statutoryRate: 0.34),
        closeTo(0.15, 1e-12),
      );
    });

    test('crédito tributário vira alíquota nula, não imposto a pagar', () {
      // A versão anterior aplicava `.abs()` antes da divisão, e o exercício em
      // que a empresa **recuperou** imposto saía com alíquota positiva — o
      // `clamp`, que existe para conter a distorção, nunca chegava a agir.
      // Ônus negativo é crédito: a fonte o grava com `incomeTaxExpense`
      // positivo, e o fixture inverte, então isto produz +200 no campo.
      final credito = comImposto(2025, 1000, -200);
      expect(credito.incomeTaxExpense, 200);
      expect(credito.effectiveTaxRate, 0.0);
      // E o NOPAT desse exercício é o EBIT cheio, não EBIT x 0,80.
      expect(credito.nopatAtRate(credito.effectiveTaxRate),
          closeTo(1000.0, 1e-9));
    });

    test('nopatAtRate recalcula sobre o EBIT, e recua sem alíquota', () {
      final s = comImposto(2025, 1000, 150);
      expect(s.nopatAtRate(0.15), closeTo(1000 * 0.85, 1e-9));
      // Sem alíquota informada vale o publicado pela fonte, que é EBIT x 0,66.
      expect(s.nopatAtRate(null), closeTo(660.0, 1e-9));
    });

    test('a série de capital carrega a alíquota, e o ROIC sobe com ela', () {
      final serie = comAliquota(0.15);
      final estatutaria = CapitalSeries.build(serie, ValuationLane.firm);
      final estrutural = CapitalSeries.build(
        serie,
        ValuationLane.firm,
        firmTaxRate: 0.15,
      );
      final rEstatutaria = estatutaria.latestReturn!;
      final rEstrutural = estrutural.latestReturn!;
      expect(rEstrutural, greaterThan(rEstatutaria));
      // NOPAT passa de EBIT x 0,66 para EBIT x 0,85 sobre a mesma base.
      expect(rEstrutural / rEstatutaria, closeTo(0.85 / 0.66, 1e-9));
    });

    test('o ROIC e o fluxo-base mudam juntos, e o freio fica coerente', () {
      // É o ponto que a decisão 31 já havia medido em 17% na AZZA3: casar o
      // `g` de uma série com o `ROIC` de outra cobra reinvestimento de um
      // retorno que não é o do fluxo descontado. Mudar só o fluxo repetiria o
      // defeito, agora pela via do imposto.
      final serie = comAliquota(0.15);
      final s = CapitalSeries.build(
        serie,
        ValuationLane.firm,
        firmTaxRate: 0.15,
      );
      final ultimo = serie.last;
      final base = ultimo.nopatAtRate(0.15)!;
      final capital = ultimo.investedCapital!;
      expect(s.latestReturn!, closeTo(base / capital, 1e-9),
          reason: 'o retorno da série tem de ser o do fluxo-base sobre a '
              'mesma base de capital');
    });

    test('a via do acionista não é tocada', () {
      final serie = comAliquota(0.15);
      final semTaxa = CapitalSeries.build(serie, ValuationLane.shareholder);
      final comTaxa = CapitalSeries.build(
        serie,
        ValuationLane.shareholder,
        firmTaxRate: 0.15,
      );
      expect(comTaxa.latestReturn, semTaxa.latestReturn,
          reason: 'o lucro líquido já vem tributado; aplicar alíquota de novo '
              'tributaria duas vezes');
    });
  });

  group('Vantagem competitiva residual — decaimento medido', () {
    // Excedente exatamente geométrico: `e_t = e_0 · phi^t`. Sobre ele o AR(1)
    // devolve a inclinação exata, o que torna o teste uma verificação da conta
    // e não uma comparação com número decorado.
    List<({int year, double excess})> geometrica(
      double e0,
      double phi,
      int pontos,
    ) =>
        [
          for (var i = 0; i < pontos; i++)
            (year: 2010 + i, excess: e0 * _pot(phi, i)),
        ];

    /// Série com os anos informados, para exercitar buraco de calendário.
    List<({int year, double excess})> nosAnos(
      List<int> anos,
      double e0,
      double phi,
    ) =>
        [
          for (var i = 0; i < anos.length; i++)
            (year: anos[i], excess: e0 * _pot(phi, i)),
        ];

    double? moat({
      double? retorno = 0.30,
      double desconto = 0.12,
      double? phi = 0.10,
      int exercicios = 14,
      List<({int year, double excess})>? excedentes,
      int anos = 10,
    }) =>
        GrowthGuards.residualMoatReturn(
          cycleReturn: retorno,
          terminalDiscountRate: desconto,
          externalCapitalRatio: phi,
          periods: exercicios,
          excessReturns: excedentes ?? geometrica(0.18, 0.5, 9),
          projectionYears: anos,
        );

    test('o AR(1) recupera a persistência crua de uma série geométrica', () {
      final p = GrowthGuards.excessPersistence(geometrica(0.18, 0.5, 9))!;
      expect(p.rawPhi, closeTo(0.5, 1e-12));
      expect(p.pairs, 8);
      // Sem correção de viés: o que a série mostra é o que entra. A tentativa
      // de corrigir Kendall pôs dez de vinte e quatro ativos no teto, e o
      // teto passou a decidir no lugar do dado — ver `excessPersistence`.
      expect(p.phi, closeTo(0.5, 1e-12));
    });

    test('a persistência é confinada no teto', () {
      // Série quase perene: a correção levaria phi acima de 1, que seria
      // excedente que nunca decai — exatamente o que o terminal neutro nega.
      final p = GrowthGuards.excessPersistence(geometrica(0.18, 0.98, 12))!;
      expect(p.rawPhi, closeTo(0.98, 1e-12));
      expect(p.phi, ValuationParameters.moatMaxPersistence);
      expect(p.phi, lessThan(p.rawPhi),
          reason: 'o teto só morde no extremo, e quando morde tem de aparecer '
              'na diferença entre o cru e o aplicado');
    });

    test('excedente que oscila não é vantagem que decai', () {
      // Sinais alternados: o AR(1) devolve inclinação negativa, e o
      // confinamento a leva a zero. Sem persistência não há o que preservar.
      final alternado = [
        for (var i = 0; i < 7; i++)
          (year: 2010 + i, excess: i.isEven ? 0.10 : -0.10),
      ];
      final p = GrowthGuards.excessPersistence(alternado)!;
      expect(p.rawPhi, lessThan(0));
      expect(p.phi, 0.0);
      expect(moat(excedentes: alternado), isNull);
    });

    test('série curta demais não estima persistência, e isso barra', () {
      expect(GrowthGuards.excessPersistence(geometrica(0.1, 0.5, 3)), isNull);
      final v = GrowthGuards.residualMoat(
        cycleReturn: 0.30,
        terminalDiscountRate: 0.12,
        externalCapitalRatio: 0.10,
        periods: 14,
        excessReturns: geometrica(0.1, 0.5, 3),
        projectionYears: 10,
      );
      expect(v.isProven, isFalse);
      expect(v.blocks, contains(MoatBlock.persistenciaNaoEstimavel));
    });

    test('buraco de calendário não vira par: 2023 não regride sobre 2019', () {
      // `CapitalSeries.returns` pula exercício sem base ou sem lucro, então a
      // lista pode ter salto de ano. Parear anos não adjacentes leria quatro
      // anos de decaimento como um, e enviesaria φ para baixo.
      final contigua = geometrica(0.18, 0.5, 9);
      final comBuraco = nosAnos(
        [2010, 2011, 2012, 2013, 2018, 2019, 2020, 2021, 2022],
        0.18,
        0.5,
      );
      final a = GrowthGuards.excessPersistence(contigua)!;
      final b = GrowthGuards.excessPersistence(comBuraco)!;
      expect(a.pairs, 8);
      expect(b.pairs, 7, reason: 'o par 2013→2018 não pode existir');
      expect(b.rawPhi, closeTo(0.5, 1e-12),
          reason: 'descartado o par do buraco, o decaimento é o mesmo');
    });

    test('pares adjacentes de menos devolvem nulo', () {
      // Quatro pontos alternados dão zero pares adjacentes.
      expect(
        GrowthGuards.excessPersistence(
          nosAnos([2010, 2012, 2014, 2016, 2018, 2020], 0.18, 0.5),
        ),
        isNull,
      );
    });

    test('o retorno terminal é a taxa mais phi elevado a N vezes o excedente',
        () {
      final lambda = _pot(0.5, 10);
      expect(moat(), closeTo(0.12 + lambda * (0.30 - 0.12), 1e-12));
    });

    test('o retorno terminal nunca ultrapassa o que a empresa entregou', () {
      // Invariante da forma: `lambda` vive em [0, 1], logo o terminal vive em
      // (r_inf, ROIC do ciclo]. Preservar mais do que o próprio ciclo seria
      // inventar vantagem que a série não mostrou.
      for (final phi in [0.1, 0.3, 0.5, 0.7, 0.9]) {
        final t = moat(excedentes: geometrica(0.18, phi, 12));
        if (t == null) continue;
        expect(t, greaterThan(0.12));
        expect(t, lessThanOrEqualTo(0.30 + 1e-12));
      }
    });

    test('NÃO há degrau: o terminal é contínuo no retorno do ciclo', () {
      // É o defeito que a decisão 36 corrige. Antes dela, o retorno do ciclo
      // atravessando `1,5 · WACC` ou `WACC + 5 p.p.` fazia o preço justo
      // saltar; medido em 09/09/2026, o salto valia de 10% a 32% em onze
      // ativos, e estava ordenado ao contrário do tamanho do efeito.
      double? anterior;
      var avaliados = 0;
      for (var passo = 0; passo <= 60; passo++) {
        final ciclo = 0.1201 + passo * 0.0030;
        final t = moat(retorno: ciclo);
        if (t == null) continue;
        avaliados++;
        if (anterior != null) {
          expect(t, greaterThan(anterior - 1e-12),
              reason: 'monotonia no retorno do ciclo');
          // O passo do terminal é `lambda` vezes o passo do ciclo. Com lambda
          // em [0, 1], nenhum incremento pode superar o do próprio ciclo — que
          // é justamente o que um degrau faria.
          expect(t - anterior, lessThanOrEqualTo(0.0030 + 1e-12),
              reason: 'salto maior que o passo do ciclo é degrau');
        }
        anterior = t;
      }
      expect(avaliados, greaterThan(50));
    });

    test('excedente pequeno recebe preservação pequena, e não recusa', () {
      // Sob o degrau, 2,4 p.p. de excedente reprovavam por inteiro: era o caso
      // de SAPR4, SAPR11, TAEE4 e TAEE11, que perdiam de 12% a 16% de preço
      // justo por um limiar. Agora recebem o que a persistência sustenta.
      final t = moat(retorno: 0.144);
      expect(t, isNotNull);
      expect(t!, greaterThan(0.12));
      expect(t, lessThan(0.144));
    });

    test('horizonte nulo não vira excedente perene', () {
      // `φ⁰ = 1` preservaria o excedente inteiro para sempre — o oposto do que
      // o decaimento existe para fazer, e um erro silencioso porque produziria
      // um número plausível. `DcfCalculator` recusa projeção com menos de um
      // ano antes disso; o piso aqui existe para a função não depender dessa
      // recusa para estar certa.
      final comZero = moat(anos: 0);
      final comUm = moat(anos: 1);
      expect(comZero, isNotNull);
      expect(comZero, comUm);
      expect(comZero!, lessThan(0.30),
          reason: 'preservar o excedente inteiro seria φ⁰ = 1');
    });

    test('crescimento inorgânico reprova, no limiar de 0,60', () {
      expect(moat(phi: 0.61), isNull);
      expect(moat(phi: 0.60), isNotNull);
      // Sob o corte anterior de 0,35, a EGIE3 (0,58) e o ITUB4 (0,50) caíam
      // aqui — concessão e banco acusam Φ alto por definição do negócio.
      expect(moat(phi: 0.58), isNotNull);
    });

    test('Phi não medido reprova — ausência não é aprovação', () {
      expect(moat(phi: null), isNull);
    });

    test('histórico curto reprova, no piso da Porta 0', () {
      expect(moat(exercicios: 7), isNull);
      expect(moat(exercicios: 8), isNotNull);
    });

    test('sem retorno do ciclo não há vantagem a preservar', () {
      expect(moat(retorno: null), isNull);
    });

    test('retorno abaixo do custo de capital não é excedente', () {
      expect(moat(retorno: 0.11), isNull);
      final v = GrowthGuards.residualMoat(
        cycleReturn: 0.11,
        terminalDiscountRate: 0.12,
        externalCapitalRatio: 0.10,
        periods: 14,
        excessReturns: geometrica(0.18, 0.5, 9),
        projectionYears: 10,
      );
      expect(v.blocks, contains(MoatBlock.semExcedente));
      expect(v.blockedOnlyByNoSpread, isTrue);
    });

    test('o veredito nomeia todas as condições que barraram', () {
      final v = GrowthGuards.residualMoat(
        cycleReturn: 0.10,
        terminalDiscountRate: 0.12,
        externalCapitalRatio: 0.90,
        periods: 5,
        excessReturns: geometrica(0.01, 0.5, 2),
        projectionYears: 10,
      );
      expect(v.isProven, isFalse);
      expect(
        v.blocks,
        containsAll(<MoatBlock>[
          MoatBlock.historicoCurto,
          MoatBlock.crescimentoInorganico,
          MoatBlock.persistenciaNaoEstimavel,
          MoatBlock.semExcedente,
        ]),
        reason: 'avaliar em curto-circuito esconderia as demais recusas',
      );
      expect(v.blockedOnlyByNoSpread, isFalse);
    });

    test('o veredito carrega phi cru e phi aplicado lado a lado', () {
      // Os dois números viajam juntos para que o confinamento seja auditável:
      // quem recalibrar o teto precisa saber onde ele mordeu.
      final v = GrowthGuards.residualMoat(
        cycleReturn: 0.30,
        terminalDiscountRate: 0.12,
        externalCapitalRatio: 0.10,
        periods: 14,
        excessReturns: geometrica(0.18, 0.5, 9),
        projectionYears: 10,
      );
      expect(v.rawPersistence, closeTo(0.5, 1e-12));
      expect(v.persistence, closeTo(0.5, 1e-12));
      expect(v.retainedFraction, closeTo(_pot(0.5, 10), 1e-12));
      expect(v.persistencePoints, 8);
    });

    test('o terminal com moat supera o do estado estacionário', () {
      const base = DcfAssumptions(
        projectionYears: 10,
        growthRate: 0.08,
        perpetualGrowth: 0.05,
        discountRate: 0.14,
        terminalDiscountRate: 0.12,
        returnOnCapital: 0.30,
      );
      final neutro =
          DcfCalculator.terminalValue(finalProfit: 100, assumptions: base)
              .unwrap();
      final comMoat = DcfCalculator.terminalValue(
        finalProfit: 100,
        assumptions: base.copyWith(terminalReturnOnCapital: 0.174),
      ).unwrap();
      // Neutro: 105 / 0,12 = 875.
      expect(neutro, closeTo(875.0, 1e-9));
      // Moat: 105 x (1 - 0,05/0,174) / (0,12 - 0,05) = 1039,3...
      expect(comMoat, closeTo(105 * (1 - 0.05 / 0.174) / 0.07, 1e-9));
      expect(comMoat, greaterThan(neutro));
    });

    test('o terminal com moat exige folga entre desconto e crescimento', () {
      const apertado = DcfAssumptions(
        projectionYears: 10,
        growthRate: 0.08,
        perpetualGrowth: 0.119,
        discountRate: 0.14,
        terminalDiscountRate: 0.12,
        returnOnCapital: 0.30,
        terminalReturnOnCapital: 0.174,
      );
      final r =
          DcfCalculator.terminalValue(finalProfit: 100, assumptions: apertado);
      expect(r.isErr, isTrue);
    });
  });

  group('Constantes que carregam decisão', () {
    test('horizonte de convergência é de 36 meses', () {
      // Com 12 a anualização vira a identidade e o upside bruto passa a ser
      // lido como retorno anual — o defeito D1 da decisão 25.
      expect(ExpectedReturn.defaultHorizonMonths, 36);
      final r = ExpectedReturn.annualizedFromUpside(1.0);
      expect(r, closeTo(0.2599, 1e-4),
          reason: '(1 + 1,00)^(1/3) − 1, e não os 100% da identidade');
    });

    test('teto nominal compõe crescimento real medido com inflação', () {
      const a = MarketAnchors(
        riskFreeCagr: 0.10,
        marketCagr: 0.12,
        inflationCagr: 0.05,
        realEconomyGrowth: 0.0145,
        observedYears: 10,
      );
      expect(a.nominalEconomyGrowth, closeTo(0.0652, 1e-4));
    });

    test('projeção explícita é de dez anos', () {
      const a = DcfAssumptions(
        growthRate: 0.10,
        perpetualGrowth: 0.04,
        discountRate: 0.12,
      );
      expect(a.projectionYears, 10);
    });
  });

  // ------------------------------------------------------- Decisão 31 --

  group('Série de retorno — exercício de prejuízo entra', () {
    test('a mediana do ciclo não é a mediana só dos anos bons', () {
      // Forma da CVCB3: quatro exercícios de prejuízo numa janela de oito.
      // Descartá-los levava a mediana de ROIC de 0,55% para 33,8%, e o fator
      // de normalização — `ciclo ÷ atual` — carregava o viés inteiro para o
      // preço justo, porque o DCF é homogêneo de grau 1 no fluxo-base.
      const resultados = {
        2016: 100.0,
        2017: 110.0,
        2018: -400.0,
        2019: -350.0,
        2020: -300.0,
        2021: -250.0,
        2022: 120.0,
        2023: 130.0,
        2024: 140.0,
        2025: 150.0,
      };
      final pontos = [
        for (final e in resultados.entries)
          exercicio(e.key, vpa: 1.0, acoes: 1000, lucro: e.value, nopat: e.value),
      ];
      final serie = CapitalSeries.build(pontos, ValuationLane.firm);

      final comPrejuizo = serie.returns.where((r) => r.value < 0).length;
      expect(comPrejuizo, 4, reason: 'os quatro anos de prejuízo entram');

      final ciclo = serie.cycleReturn(window: ValuationParameters.cycleWindow)!;
      expect(ciclo, lessThan(0.10),
          reason: 'a mediana de um ciclo com quatro anos de prejuízo não pode '
              'descrever só os anos bons');
    });

    test('exercício sem lucro publicado continua fora', () {
      // Ausência de dado não é retorno nulo: incluí-la como zero inventaria
      // observação onde não há nenhuma.
      final pontos = [
        for (var ano = 2016; ano <= 2025; ano++)
          exercicio(ano,
              vpa: 1.0,
              acoes: 1000,
              lucro: ano == 2020 ? null : 100.0,
              nopat: ano == 2020 ? null : 100.0),
      ];
      final serie = CapitalSeries.build(pontos, ValuationLane.firm);
      expect(serie.returns.any((r) => r.year == 2020), isFalse);
    });
  });

  group('Guarda 1 — a deriva não depende do horizonte da tela', () {
    test('o veredito é o mesmo qualquer que seja a projeção pedida', () {
      // Forma da AZZA3: tendência de queda significante, com a deriva na
      // fronteira da correção por reversão. Medindo a deriva no horizonte,
      // `N = 10` dava dominância 1,49 e `N = 5` dava 0,74 — o veredito
      // virava, a base era normalizada por 2,50x e o preço justo saía de
      // R$ 16,11 para R$ 57,48 na mesma empresa, no mesmo dia.
      var pl = 1000.0;
      final pontos = <FundamentalsSnapshot>[];
      for (var ano = 2010; ano <= 2025; ano++) {
        final roic = 0.26 - 0.0175 * (ano - 2010);
        final lucro = roic * pl;
        pontos.add(exercicio(ano,
            vpa: pl / 1000, acoes: 1000, lucro: lucro, nopat: lucro));
        pl += lucro * 0.7;
      }
      final serie = CapitalSeries.build(pontos, ValuationLane.firm);

      final v = GrowthGuards.trend(serie);
      expect(v, isNotNull);
      expect(v!.dominance,
          closeTo(GrowthGuards.trend(serie)!.dominance, 1e-12),
          reason: 'a guarda não tem mais por onde receber o horizonte');

      // A janela é a do ciclo, e é a mesma sobre a qual a correção é medida.
      expect(ValuationParameters.trendDriftWindow,
          ValuationParameters.cycleWindow);
      final metade = GrowthGuards.trend(serie, driftWindow: 4)!;
      expect(metade.dominance, closeTo(v.dominance / 2, 1e-9),
          reason: 'a deriva é linear na janela, e o parâmetro só existe para '
              'a análise de sensibilidade');
    });
  });

  group('Contagem de papéis da ponte', () {
    FundamentalsSnapshot comMercado({
      required double corrente,
      required double doExercicio,
      required double valorDeMercado,
      double? lucro,
      double? lpa,
    }) =>
        FundamentalsSnapshot(
          ticker: ticker,
          fiscalPeriodEnd: DateTime(2025, 12, 31),
          bookValuePerShare: 10,
          sharesOutstanding: corrente,
          sharesOutstandingAsOf: doExercicio,
          marketCap: valorDeMercado,
          netIncome: lucro,
          earningsPerShare: lpa,
        );

    test('contagens que concordam: vale a implícita no valor de mercado', () {
      // É a que forma o preço comparado, e adotá-la faz o potencial virar
      // `E ÷ VM − 1`, sem contagem de ação nenhuma no caminho.
      final s = comMercado(
        corrente: 206489810,
        doExercicio: 206489810,
        valorDeMercado: 206489810 * 17.69,
        lucro: 911249000,
        lpa: 4.413046,
      );
      final d = ValuationCascade.quotedShares(
        latest: s,
        marketPrice: 17.69,
        sharesPerQuote: 1.0,
      );
      expect(d!.source, QuotedSharesSource.market);
      expect(d.diverge, isFalse);
      expect(d.count, closeTo(206489810, 1));
    });

    test('na divergência vale a maior, e o mercado pode ser a maior', () {
      // Forma da MOVI3: LPA publicado como zero, o árbitro `lucro ÷ LPA` fica
      // indisponível, e a contagem do exercício — 152.068.530 — era adotada
      // contra as 402.158.940 que formam o preço. Erro de 2,65x, direto no
      // preço justo, e no sentido de inflá-lo.
      final s = comMercado(
        corrente: 402158940,
        doExercicio: 152068530,
        valorDeMercado: 402158940 * 8.11,
        lucro: 318364000,
        lpa: 0.0,
      );
      final d = ValuationCascade.quotedShares(
        latest: s,
        marketPrice: 8.11,
        sharesPerQuote: 1.0,
      );
      expect(d!.diverge, isTrue);
      expect(d.source, QuotedSharesSource.market);
      expect(d.count, closeTo(402158940, 1));
      expect(s.reconciledShares, 152068530,
          reason: 'a contagem contábil não muda: é ela que reconstrói o '
              'patrimônio publicado');
    });

    test('na divergência vale a maior, e a contábil pode ser a maior', () {
      // Forma do MILS3: valor de mercado de R$ 760 mil, herdado de uma
      // contagem corrente corrompida de 48.172 papéis. Adotá-la daria preço
      // justo de R$ 37.708,72 contra R$ 15,79 de mercado — o sinal falso de
      // desconto levado ao absurdo.
      final s = comMercado(
        corrente: 48172,
        doExercicio: 234178210,
        valorDeMercado: 48172 * 15.79,
        lucro: 1000000000,
        lpa: 4.2646,
      );
      final d = ValuationCascade.quotedShares(
        latest: s,
        marketPrice: 15.79,
        sharesPerQuote: 1.0,
      );
      expect(d!.diverge, isTrue);
      expect(d.source, QuotedSharesSource.reconciled);
      expect(d.count, closeTo(234178210, 1));
      expect(d.divergence, greaterThan(1000));
    });

    test('a contábil entra na ponte já na unidade negociada', () {
      // As demonstrações contam **ações**; a cotação e o valor de mercado vêm
      // por *unit*. Comparar as duas candidatas em unidades diferentes
      // escolheria a maior por erro de escala, não por conservadorismo.
      final s = comMercado(
        corrente: 503735170,
        doExercicio: 1511205500,
        valorDeMercado: 100747034 * 34.95,
        lucro: 1000000000,
        lpa: 0.6617,
      );
      final d = ValuationCascade.quotedShares(
        latest: s,
        marketPrice: 34.95,
        sharesPerQuote: 5.0,
      );
      expect(d!.fromMarketCap, closeTo(100747034, 1));
      expect(d.fromStatements, closeTo(1511205500 / 5, 1));
      expect(d.source, QuotedSharesSource.reconciled);
      expect(d.count, closeTo(302241100, 1));
    });

    test('sem valor de mercado, a contábil é a única disponível', () {
      final s = comMercado(
        corrente: 48172,
        doExercicio: 234178210,
        valorDeMercado: 0,
      );
      final d = ValuationCascade.quotedShares(
        latest: s,
        marketPrice: 15.79,
        sharesPerQuote: 1.0,
      );
      expect(d!.source, QuotedSharesSource.onlyAvailable);
      expect(d.count, closeTo(234178210, 1));
      expect(d.diverge, isFalse, reason: 'não há duas candidatas a divergir');
    });
  });

  group('Ponte de equity — recusa nomeada quando não há o que repartir', () {
    /// Empresa com fluxo de firma positivo e dívida líquida maior que o valor
    /// da firma, e **sem** lucro líquido: a via da firma produz participação
    /// não positiva, e a via do acionista não tem base para migrar.
    List<FundamentalsSnapshot> afogada() {
      final pontos = <FundamentalsSnapshot>[];
      var pl = 1000.0;
      for (var ano = 2012; ano <= 2025; ano++) {
        pl += 20.0;
        pontos.add(FundamentalsSnapshot(
          ticker: ticker,
          fiscalPeriodEnd: DateTime(ano, 12, 31),
          bookValuePerShare: pl / 1000,
          sharesOutstanding: 1000,
          sharesOutstandingAsOf: 1000,
          marketCap: 20000,
          netIncome: -50.0,
          nopat: 30.0,
          ebit: 45.0,
          ebitda: 60.0,
          interestExpense: 400.0,
          longTermDebt: 900000.0,
        ));
      }
      return pontos;
    }

    test('a recusa nomeia o motivo, e não devolve resíduo de subtração', () {
      final r = ValuationCascade.evaluate(ValuationInputs(
        ticker: ticker,
        asOf: DateTime(2026, 6, 30),
        fundamentals: afogada(),
        marketPrice: 20.0,
        capm: const CapmInputs(
          riskFreeRate: 0.105,
          beta: 1.0,
          marketPremium: 0.055,
        ),
      ));
      expect(r.isErr, isTrue);
      final msg = r.failureOrNull!.message;
      expect(msg, contains('capital próprio responde por apenas'));
      expect(msg, contains('não é avaliável por fluxo descontado'));
      expect(msg, isNot(contains('Infinity')),
          reason: 'participação não positiva não pode virar 1/0 na mensagem');
    });
  });

  group('Diagnósticos — o resultado diz o que a conta fez', () {
    test('não há nota ordinal de confiança, e a ausência é medida', () {
      // A primeira versão trazia `ValuationConfidence` derivada da contagem de
      // ressalvas. A validação preditiva da decisão 32 mediu o contrário do
      // prometido: em 36 meses, o grupo sem ressalva alguma teve IC de −0,007
      // (positivo em 2 de 5 coortes) e o grupo com uma ou duas teve 0,206
      // (5 de 5). Uma nota que ordena ao contrário é pior que nenhuma.
      const d = ValuationDiagnostics(
        terminalShare: 0.5,
        equityShare: 0.8,
        baseFactor: 1.0,
        growthIdentified: true,
        moatApplied: false,
        costOfEquity: 0.16,
        terminalDiscountRate: 0.12,
        terminalRetainedSpread: 0.0,
        growthRate: 0.06,
        returnOnCapital: 0.15,
        terminalReturnOnCapital: null,
      );
      expect(d.hasCaveats, isFalse);
      expect(d.caveats, isEmpty);
    });

    test('a ressalva de custo da dívida não está no conjunto', () {
      // Ela disparava em 469 das 821 avaliações do backtest. Ressalva que vale
      // para a maioria não distingue nada, e a classificação sintética virou
      // método pela decisão 31 — não é mais um recuo a declarar aqui.
      expect(
        ValuationCaveat.values.map((c) => c.name),
        isNot(contains('custoDaDividaEstimado')),
      );
    });

    test('os cortes carregam a decisão que os originou', () {
      // 80% é o topo da faixa que a decisão 25 citou para justificar dez anos
      // de projeção em vez de cinco; 2,0x é metade da autoridade que a
      // saturação da decisão 28 concede a um único exercício; 35% é a faixa
      // acima do corte de migração em que a ponte já é resíduo e ninguém
      // avisava.
      expect(ValuationDiagnostics.terminalShareLimit, 0.80);
      expect(ValuationDiagnostics.baseFactorLimit, 2.0);
      expect(ValuationDiagnostics.fragileEquityShare, 0.35);
      expect(ValuationDiagnostics.fragileEquityShare,
          greaterThan(ValuationParameters.minEquityShare),
          reason: 'a ressalva precisa cobrir a faixa que a migração deixa '
              'passar, não repeti-la');
    });

    test('resultado montado à mão não inventa diagnóstico', () {
      final r = ValuationResult(
        ticker: ticker,
        asOf: DateTime(2026, 9, 4),
        model: ValuationModel.dcfFcff,
        fairValue: Money.fromReais(10),
        marketPrice: Money.fromReais(8),
        discountRate: 0.15,
      );
      expect(r.diagnostics, isNull);
      expect(r.caveats, isEmpty);
    });

    test('a cascata preenche o diagnóstico com o que ela mesma apurou', () {
      final pontos = <FundamentalsSnapshot>[];
      var pl = 1000.0;
      for (var ano = 2012; ano <= 2025; ano++) {
        final lucro = 0.15 * pl;
        pl += lucro * 0.5;
        pontos.add(FundamentalsSnapshot(
          ticker: ticker,
          fiscalPeriodEnd: DateTime(ano, 12, 31),
          bookValuePerShare: pl / 1000,
          sharesOutstanding: 1000,
          sharesOutstandingAsOf: 1000,
          marketCap: 20000,
          netIncome: lucro,
          nopat: lucro,
          ebit: lucro * 1.4,
          ebitda: lucro * 1.8,
          interestExpense: 50,
          longTermDebt: 500,
        ));
      }
      final r = ValuationCascade.evaluate(ValuationInputs(
        ticker: ticker,
        asOf: DateTime(2026, 6, 30),
        fundamentals: pontos,
        marketPrice: 20.0,
        capm: const CapmInputs(
          riskFreeRate: 0.105,
          beta: 1.0,
          marketPremium: 0.055,
        ),
      ));
      expect(r.isOk, isTrue);
      final d = r.unwrap().diagnostics;
      expect(d, isNotNull);
      expect(d!.terminalShare, greaterThan(0.0));
      expect(d.terminalShare, lessThan(1.0));
      expect(d.baseFactor, greaterThan(0.0));
      expect(d.equityShare, greaterThan(0.0));
    });
  });

  group('Consistência da base acionária entre exercícios', () {
    FundamentalsSnapshot ex(int ano, double acoes, double vpa) =>
        FundamentalsSnapshot(
          ticker: ticker,
          fiscalPeriodEnd: DateTime(ano, 12, 31),
          sharesOutstandingAsOf: acoes,
          sharesOutstanding: 1259387000,
          bookValuePerShare: vpa,
          marketCap: 49317593000,
        );

    test('falha de escala da fonte é descartada do divisor', () {
      // Forma da EQTL3: o exercício de 2024 vem com 246.152 ações contra 1,50
      // bilhão em 2023 e 1,26 bilhão em 2025, e o VPA acompanha em
      // R$ 121.419,23. O patrimônio sai certo porque o erro se cancela em
      // `VPA × N`; o divisor da ponte, que usa `N` sozinho, sairia cinco mil
      // vezes errado.
      final serie = [
        ex(2021, 1128934500, 12.94),
        ex(2022, 1129315500, 16.44),
        ex(2023, 1500000000, 16.86),
        ex(2024, 246152, 121419.23),
      ];
      expect(
        ValuationCascade.shareBaseIsConsistent(serie, serie.last),
        isFalse,
      );

      final d = ValuationCascade.quotedShares(
        latest: serie.last,
        marketPrice: 39.36,
        sharesPerQuote: 1.0,
        published: serie,
      );
      expect(d, isNotNull);
      expect(d!.fromStatements, isNull,
          reason: 'a contagem quebrada não pode entrar como candidata');
      expect(d.source, QuotedSharesSource.onlyAvailable);
      expect(d.count, closeTo(49317593000 / 39.36, 1));
    });

    test('ação societária real passa, e é o ponto do fator ser largo', () {
      // Forma da VIVT3: a base dobra em 2024 — 1,65 para 3,26 bilhões — com o
      // VPA caindo de R$ 42,13 para R$ 21,40. `VPA × N` fica estável em
      // R$ 69 bilhões o tempo todo: foi desdobramento, não erro.
      final serie = [
        ex(2021, 1690985000, 41.40),
        ex(2022, 1676938200, 40.82),
        ex(2023, 1652588400, 42.13),
        ex(2024, 3261287400, 21.40),
      ];
      expect(
        ValuationCascade.shareBaseIsConsistent(serie, serie.last),
        isTrue,
        reason: 'dobrar a base é ação societária; o corte é de ordem de '
            'grandeza, não de fator dois',
      );
    });

    test('série curta demais aprova em vez de reprovar', () {
      // Mesmo critério da Porta 0 com a liquidez: sem vizinhança contra a qual
      // julgar, ausência de informação não é evidência de defeito.
      final serie = [ex(2024, 246152, 121419.23)];
      expect(
        ValuationCascade.shareBaseIsConsistent(serie, serie.last),
        isTrue,
      );
      expect(
        ValuationCascade.shareBaseIsConsistent(const [], serie.last),
        isTrue,
      );
    });

    test('o corte é o mesmo que a série de capital já usa', () {
      // Duas cópias do mesmo limiar divergiriam na primeira recalibragem, e o
      // raciocínio é idêntico: falha de fonte é de ordem de grandeza, salto
      // societário fica entre duas e nove vezes.
      expect(CapitalSeries.neighbourFactor, 8.0);
    });
  });

  group('Escudo fiscal e custo da dívida', () {
    test('o escudo do WACC é a alíquota estatutária', () {
      // A fonte publica `nopat` como `EBIT × 0,66` em 4.572 de 4.572
      // exercícios do cache: o fluxo da firma já vinha apurado à alíquota
      // legal, e só o escudo do desconto não vinha. O parâmetro fica travado
      // aqui para que a incoerência não volte por descuido.
      expect(ValuationParameters.statutoryTaxRate, 0.34);
    });

    test('a alavancagem ordena o prêmio, e é monótona', () {
      double spread(double? l) => CostOfCapital.leverageSpread(l);
      expect(spread(-0.5), lessThan(spread(1.5)));
      expect(spread(1.5), lessThan(spread(2.8)));
      expect(spread(2.8), lessThan(spread(4.5)));
      expect(spread(6.0), CostOfCapital.maxCreditSpread);
      expect(spread(null), CostOfCapital.maxCreditSpread,
          reason: 'sem EBITDA positivo vale o pior caso');
      var anterior = 0.0;
      for (var l = -2.0; l <= 8.0; l += 0.1) {
        final atual = spread(l);
        expect(atual, greaterThanOrEqualTo(anterior),
            reason: 'prêmio caiu ao subir a alavancagem em $l');
        anterior = atual;
      }
    });

    test('a despesa financeira arbitra se a cobertura pode falar', () {
      const rf = 0.1409;
      double s({required double obs, double? cob, double? alav}) =>
          CostOfCapital.syntheticSpread(
            leverage: alav,
            coverage: cob,
            observedCostOfDebt: obs,
            riskFreeRate: rf,
          );

      // Forma da SAPR11: despesa observada de 41,7% ao ano é contaminada por
      // arrendamento e variação cambial. A cobertura de 0,76x que sai dela não
      // pode decidir o crédito de quem tem 0,60x de alavancagem.
      expect(s(obs: 0.417, cob: 0.76, alav: 0.60),
          CostOfCapital.leverageSpread(0.60));

      // Forma da MOVI3: despesa de 16,4% ao ano é juro de dívida de verdade.
      // A cobertura de 0,91x é informação, e ela é mais exigente que a
      // alavancagem de 3,13x — vale a pior das duas.
      final movi = s(obs: 0.164, cob: 0.91, alav: 3.13);
      expect(movi, CostOfCapital.coverageSpread(0.91));
      expect(movi, greaterThan(CostOfCapital.leverageSpread(3.13)));

      // Dentro da banda, mas com cobertura folgada: quem manda é a alavancagem.
      expect(s(obs: 0.16, cob: 9.0, alav: 4.5),
          CostOfCapital.leverageSpread(4.5));

      // Abaixo do piso a despesa também não serve: dívida subsidiada não
      // descreve o custo marginal de captar.
      expect(s(obs: 0.02, cob: 44.0, alav: 1.45),
          CostOfCapital.leverageSpread(1.45));
    });
  });

  group('Fronteira das vias e monotonia na taxa', () {
    // A pós-condição da ponte de equity é um degrau entre dois estimadores
    // diferentes. Medi-la na taxa do dia fazia o degrau andar com o ciclo
    // monetário: na KLBN11, baixar a taxa livre de risco de 9,00% para 8,75%
    // levava o preço justo de R$ 7,98 para R$ 5,36 — capital mais barato
    // produzindo empresa menos valiosa, que contradiz a definição de fluxo
    // descontado. Passou a ser medida na taxa estrutural, que não acompanha a
    // Selic.
    FundamentalsSnapshot alavancado(int ano, double escala) =>
        FundamentalsSnapshot(
          ticker: ticker,
          fiscalPeriodEnd: DateTime(ano, 12, 31),
          totalRevenue: 10000 * escala,
          ebit: 1400 * escala,
          ebitda: 1900 * escala,
          netIncome: 500 * escala,
          incomeBeforeTax: 800 * escala,
          // Negativo, na convenção da fonte: 800 − 300 = 500 de líquido.
          incomeTaxExpense: -300 * escala,
          interestExpense: 600,
          earningsPerShare: 0.5 * escala,
          cash: 500,
          shortTermInvestments: 200,
          shortTermDebt: 3200,
          longTermDebt: 12800,
          totalStockholderEquity: 4000 * escala,
          bookValuePerShare: 4.0 * escala,
          operatingCashFlow: 1500 * escala,
          freeCashFlow: 900 * escala,
          nopat: 924 * escala,
          sharesOutstanding: 1000,
          sharesOutstandingAsOf: 1000,
          marketCap: 9000,
          enterpriseToEbitda: 8.0,
        );

    List<FundamentalsSnapshot> serie() {
      final out = <FundamentalsSnapshot>[];
      var escala = 1.0;
      for (var i = 15; i >= 0; i--) {
        out.add(alavancado(2025 - i, escala));
        escala *= 1.06;
      }
      return out;
    }

    ValuationResult? com(double rf) {
      final r = ValuationCascade.evaluate(ValuationInputs(
        ticker: ticker,
        asOf: DateTime(2026, 9, 9),
        fundamentals: serie(),
        marketPrice: 9.0,
        capm: CapmInputs(riskFreeRate: rf, beta: 1.0, marketPremium: 0.055),
        declaredTerminalRiskFreeRate: 0.094,
      ));
      return r.isOk ? r.unwrap() : null;
    }

    test('baratear o capital nunca derruba o preço justo', () {
      double? anterior;
      var avaliados = 0;
      for (var passo = 0; passo <= 32; passo++) {
        final rf = 0.1600 - passo * 0.0025;
        final v = com(rf);
        if (v == null) continue;
        final justo = v.fairValue.reais;
        avaliados++;
        if (anterior != null) {
          // A tolerância de um centavo é ruído de arredondamento em `Money`,
          // não folga de regra: a quebra medida era de 33%.
          expect(justo, greaterThanOrEqualTo(anterior - 0.01),
              reason: 'em Rf de ${(rf * 100).toStringAsFixed(2)}% o preço justo '
                  'caiu de $anterior para $justo ao baratear o capital');
        }
        anterior = justo;
      }
      expect(avaliados, greaterThan(20),
          reason: 'a varredura precisa cobrir a faixa para ter conteúdo');
    });

    test('NÃO há degrau: o preço justo é contínuo na taxa', () {
      // É o defeito que a decisão 38 corrige. A pós-condição escolhia uma via
      // inteira em s = 20%, e as duas discordam além de 1,5x em 55 de 92
      // ativos — a VBBR3 saía a R$ 2,65 pela firma ou R$ 33,71 pelo acionista.
      // Cruzar o corte fazia o preço justo saltar por múltiplos.
      double? anterior;
      var maiorSalto = 0.0;
      var avaliados = 0;
      for (var passo = 0; passo <= 60; passo++) {
        final justo = com(0.1600 - passo * 0.0010)?.fairValue.reais;
        if (justo == null || justo <= 0) continue;
        avaliados++;
        if (anterior != null) {
          final salto = (justo / anterior - 1).abs();
          if (salto > maiorSalto) maiorSalto = salto;
        }
        anterior = justo;
      }
      expect(avaliados, greaterThan(40),
          reason: 'a varredura precisa cobrir a faixa para ter conteúdo');
      // Dez pontos-base de taxa não movem um fluxo descontado em mais de uns
      // poucos por cento. Um degrau de via move por múltiplos.
      expect(maiorSalto, lessThan(0.15),
          reason: 'salto de ${(maiorSalto * 100).toStringAsFixed(1)}% entre '
              'dois passos de 10 pontos-base é degrau de via, não desconto');
    });

    test('na faixa de transição o justo fica entre as duas vias', () {
      ValuationResult? porVia(double rf, ValuationLane? via) {
        final r = ValuationCascade.evaluate(ValuationInputs(
          ticker: ticker,
          asOf: DateTime(2026, 9, 9),
          fundamentals: serie(),
          marketPrice: 9.0,
          capm: CapmInputs(riskFreeRate: rf, beta: 1.0, marketPremium: 0.055),
          declaredTerminalRiskFreeRate: 0.094,
          laneOverride: via,
        ));
        return r.isOk ? r.unwrap() : null;
      }

      var mesclados = 0;
      for (var passo = 0; passo <= 60; passo++) {
        final rf = 0.1600 - passo * 0.0010;
        final producao = porVia(rf, null);
        if (producao == null) continue;
        final temMescla = producao.diagnostics!.caveats
            .contains(ValuationCaveat.viasMescladas);
        if (!temMescla) continue;
        mesclados++;

        final firma = porVia(rf, ValuationLane.firm);
        final acionista = porVia(rf, ValuationLane.shareholder);
        expect(firma, isNotNull);
        expect(acionista, isNotNull);

        final a = firma!.fairValue.reais;
        final b = acionista!.fairValue.reais;
        final menor = a < b ? a : b;
        final maior = a < b ? b : a;
        final justo = producao.fairValue.reais;
        expect(justo, greaterThanOrEqualTo(menor - 0.01));
        expect(justo, lessThanOrEqualTo(maior + 0.01));
      }
      expect(mesclados, greaterThan(0),
          reason: 'a varredura precisa atravessar a faixa de transição');
    });

    test('crescimento e fator impostos são nulos em produção', () {
      // As duas costuras do teste A1 não podem mover nada quando não são
      // usadas: elas existem para medir o motor, não para ser o motor.
      final producao = com(0.14);
      final comNulos = ValuationCascade.evaluate(ValuationInputs(
        ticker: ticker,
        asOf: DateTime(2026, 9, 9),
        fundamentals: serie(),
        marketPrice: 9.0,
        capm: const CapmInputs(
          riskFreeRate: 0.14,
          beta: 1.0,
          marketPremium: 0.055,
        ),
        declaredTerminalRiskFreeRate: 0.094,
        growthOverride: null,
        baseFactorOverride: null,
      ));
      expect(producao, isNotNull);
      expect(comNulos.isOk, isTrue);
      expect(comNulos.unwrap().fairValue.cents, producao!.fairValue.cents);
    });

    test('crescimento imposto entra no cálculo e é declarado', () {
      ValuationResult? comG(double? g) {
        final r = ValuationCascade.evaluate(ValuationInputs(
          ticker: ticker,
          asOf: DateTime(2026, 9, 9),
          fundamentals: serie(),
          marketPrice: 9.0,
          capm: const CapmInputs(
            riskFreeRate: 0.14,
            beta: 1.0,
            marketPremium: 0.055,
          ),
          declaredTerminalRiskFreeRate: 0.094,
          laneOverride: ValuationLane.firm,
          growthOverride: g,
        ));
        return r.isOk ? r.unwrap() : null;
      }

      final baixo = comG(0.02);
      final alto = comG(0.09);
      expect(baixo, isNotNull);
      expect(alto, isNotNull);
      expect(alto!.diagnostics!.growthRate, closeTo(0.09, 1e-12));
      expect(baixo!.diagnostics!.growthRate, closeTo(0.02, 1e-12));
      // **Crescer mais não vale mais por princípio**, e o fixture mostra por
      // quê: com o retorno da base abaixo do custo de capital, o freio
      // `b = g/ROIC` cobra mais reinvestimento do que o crescimento devolve, e
      // o valor cai. É a economia do modelo, não defeito — e é o sinal certo
      // para travar, porque um motor que premiasse crescimento indiscriminado
      // estaria errado.
      expect(alto.diagnostics!.returnOnCapital,
          lessThan(alto.diagnostics!.terminalDiscountRate),
          reason: 'o fixture precisa estar no regime de retorno abaixo do '
              'custo de capital para o teste significar isto');
      expect(alto.fairValue.cents, lessThan(baixo.fairValue.cents),
          reason: 'crescimento sem retorno excedente destrói valor');
      expect((alto.fairValue.cents - baixo.fairValue.cents).abs(),
          greaterThan(0),
          reason: 'sem efeito algum, a varredura de A1 não mediria nada');
      expect(
        alto.warnings.any((w) => w.contains('Crescimento imposto')),
        isTrue,
      );
    });

    test('fator de base imposto multiplica o preço justo, e é declarado', () {
      ValuationResult? comF(double f) {
        final r = ValuationCascade.evaluate(ValuationInputs(
          ticker: ticker,
          asOf: DateTime(2026, 9, 9),
          fundamentals: serie(),
          marketPrice: 9.0,
          capm: const CapmInputs(
            riskFreeRate: 0.14,
            beta: 1.0,
            marketPremium: 0.055,
          ),
          declaredTerminalRiskFreeRate: 0.094,
          laneOverride: ValuationLane.firm,
          baseFactorOverride: f,
        ));
        return r.isOk ? r.unwrap() : null;
      }

      final um = comF(1.0);
      final dois = comF(2.0);
      expect(um, isNotNull);
      expect(dois, isNotNull);
      expect(dois!.diagnostics!.baseFactor, closeTo(2.0, 1e-12));
      // O DCF é homogêneo de grau 1 no fluxo-base, e a ponte de dívida
      // líquida é o que impede a razão de ser exatamente 2.
      expect(dois.fairValue.cents, greaterThan(um!.fairValue.cents));
      expect(
        dois.warnings.any((w) => w.contains('Fator de normalização imposto')),
        isTrue,
      );
    });

    test('com o caminho resolvido, o capital próprio não passa pela ponte', () {
      // O fixture é alavancado de propósito: sob a interpolação ele atravessa
      // a pós-condição dos 20% e recebe a mescla da decisão 38. Sob a rota
      // derivada não há ponte, não há degrau e não há mescla.
      ValuationResult? avaliar({double? betaU, required double rf}) {
        final r = ValuationCascade.evaluate(ValuationInputs(
          ticker: ticker,
          asOf: DateTime(2026, 9, 9),
          fundamentals: serie(),
          marketPrice: 9.0,
          capm: CapmInputs(riskFreeRate: rf, beta: 1.0, marketPremium: 0.055),
          declaredTerminalRiskFreeRate: 0.094,
          unleveredBeta: betaU,
        ));
        return r.isOk ? r.unwrap() : null;
      }

      var mescladosSem = 0;
      var mescladosCom = 0;
      var avaliadosCom = 0;
      for (var passo = 0; passo <= 40; passo++) {
        final rf = 0.1600 - passo * 0.0015;
        final sem = avaliar(rf: rf);
        final comU = avaliar(betaU: 0.60, rf: rf);
        if (sem != null &&
            sem.diagnostics!.caveats.contains(ValuationCaveat.viasMescladas)) {
          mescladosSem++;
        }
        if (comU != null) {
          avaliadosCom++;
          if (comU.diagnostics!.caveats
              .contains(ValuationCaveat.viasMescladas)) {
            mescladosCom++;
          }
        }
      }

      expect(avaliadosCom, greaterThan(20),
          reason: 'a varredura precisa cobrir a faixa para ter conteúdo');
      expect(mescladosSem, greaterThan(0),
          reason: 'sem o caminho resolvido, este fixture atravessa a mescla — '
              'se não atravessar, o teste não está medindo o que promete');
      expect(mescladosCom, 0,
          reason: 'sob a rota derivada não há dois estimadores a mesclar');
    });

    test('a rota derivada é contínua na taxa, sem degrau de ponte', () {
      double? justo(double rf) {
        final r = ValuationCascade.evaluate(ValuationInputs(
          ticker: ticker,
          asOf: DateTime(2026, 9, 9),
          fundamentals: serie(),
          marketPrice: 9.0,
          capm: CapmInputs(riskFreeRate: rf, beta: 1.0, marketPremium: 0.055),
          declaredTerminalRiskFreeRate: 0.094,
          unleveredBeta: 0.60,
        ));
        return r.isOk ? r.unwrap().fairValue.reais : null;
      }

      double? anterior;
      var maiorSalto = 0.0;
      var avaliados = 0;
      for (var passo = 0; passo <= 50; passo++) {
        final v = justo(0.1600 - passo * 0.0010);
        if (v == null || v <= 0) continue;
        avaliados++;
        if (anterior != null) {
          final salto = (v / anterior - 1).abs();
          if (salto > maiorSalto) maiorSalto = salto;
        }
        anterior = v;
      }
      expect(avaliados, greaterThan(30));
      expect(maiorSalto, lessThan(0.15),
          reason: 'salto de ${(maiorSalto * 100).toStringAsFixed(1)}% entre '
              'dois passos de 10 pontos-base seria degrau, não desconto');
    });

    test('a narrativa do moat cita a taxa resolvida, não a interpolada', () {
      // D1d: o veredito de vantagem competitiva é fechado contra a taxa que o
      // ponto fixo devolve. Publicá-lo contra a interpolada afirmaria um
      // veredito que a conta final descartou.
      final r = ValuationCascade.evaluate(ValuationInputs(
        ticker: ticker,
        asOf: DateTime(2026, 9, 9),
        fundamentals: serie(),
        marketPrice: 9.0,
        capm: const CapmInputs(
          riskFreeRate: 0.14,
          beta: 1.0,
          marketPremium: 0.055,
        ),
        declaredTerminalRiskFreeRate: 0.094,
        laneOverride: ValuationLane.firm,
        unleveredBeta: 0.60,
      ));
      expect(r.isOk, isTrue);
      final v = r.unwrap();
      final narrativa = v.warnings
          .where((w) => w.startsWith('Vantagem competitiva residual:'))
          .toList();
      if (narrativa.isEmpty) return; // este fixture pode não ter excedente
      final pct = (v.diagnostics!.terminalDiscountRate * 100)
          .toStringAsFixed(1);
      expect(narrativa.single, contains('equilíbrio de $pct%'),
          reason: 'a taxa citada tem de ser a que o diagnóstico carrega');
    });

    test('sem beta desalavancado, o desconto é a interpolação de antes', () {
      // O caminho novo é opcional por construção: quem não tem `β_U` continua
      // exatamente onde estava. É o que permite ligá-lo sem quebrar o que a
      // fonte não sustenta.
      final producao = com(0.14);
      expect(producao, isNotNull);
      expect(
        producao!.warnings.any((w) => w.contains('resolvido ano a ano')),
        isFalse,
      );
    });

    test('com beta desalavancado, o custo de capital é resolvido e declarado',
        () {
      ValuationResult? comBetaU(double? betaU) {
        final r = ValuationCascade.evaluate(ValuationInputs(
          ticker: ticker,
          asOf: DateTime(2026, 9, 9),
          fundamentals: serie(),
          marketPrice: 9.0,
          capm: const CapmInputs(
            riskFreeRate: 0.14,
            beta: 1.0,
            marketPremium: 0.055,
          ),
          declaredTerminalRiskFreeRate: 0.094,
          laneOverride: ValuationLane.firm,
          unleveredBeta: betaU,
        ));
        return r.isOk ? r.unwrap() : null;
      }

      final sem = comBetaU(null);
      final comU = comBetaU(0.60);
      expect(sem, isNotNull);
      expect(comU, isNotNull);

      expect(
        comU!.warnings.any((w) => w.contains('resolvido ano a ano')),
        isTrue,
        reason: 'o resultado precisa declarar que a taxa virou caminho',
      );
      expect(
        comU.warnings.any((w) => w.contains('participação do capital próprio '
            'sai de')),
        isTrue,
        reason: 'e precisa dizer quanto a alavancagem se moveu',
      );

      // O fixture é alavancado: resolver a taxa contra a alavancagem tem de
      // mover o número. Sem efeito, a decisão 41 não estaria ligada.
      expect(comU.fairValue.cents, isNot(sem!.fairValue.cents));
    });

    test('o terminal do diagnóstico é o resolvido, não o interpolado', () {
      final r = ValuationCascade.evaluate(ValuationInputs(
        ticker: ticker,
        asOf: DateTime(2026, 9, 9),
        fundamentals: serie(),
        marketPrice: 9.0,
        capm: const CapmInputs(
          riskFreeRate: 0.14,
          beta: 1.0,
          marketPremium: 0.055,
        ),
        declaredTerminalRiskFreeRate: 0.094,
        laneOverride: ValuationLane.firm,
        unleveredBeta: 0.60,
      ));
      expect(r.isOk, isTrue);
      final d = r.unwrap().diagnostics!;
      // O texto do aviso traz a mesma taxa que o diagnóstico carrega: se os
      // dois divergissem, um relatório contaria uma história e a máquina
      // outra.
      final aviso = r.unwrap().warnings.firstWhere(
            (w) => w.contains('perpetuidade é descontada a'),
          );
      final pct = (d.terminalDiscountRate * 100).toStringAsFixed(1);
      expect(aviso, contains('$pct%'));
    });

    test('a via imposta ignora roteamento e pós-condição, e declara', () {
      final r = ValuationCascade.evaluate(ValuationInputs(
        ticker: ticker,
        asOf: DateTime(2026, 9, 9),
        fundamentals: serie(),
        marketPrice: 9.0,
        capm: const CapmInputs(
          riskFreeRate: 0.14,
          beta: 1.0,
          marketPremium: 0.055,
        ),
        declaredTerminalRiskFreeRate: 0.094,
        laneOverride: ValuationLane.firm,
      ));
      expect(r.isOk, isTrue);
      final v = r.unwrap();
      expect(v.model, ValuationModel.dcfFcff);
      expect(
        v.warnings.any((w) => w.contains('Via imposta')),
        isTrue,
        reason: 'o resultado precisa declarar que é instrumento, não avaliação',
      );
      expect(
        v.diagnostics!.caveats.contains(ValuationCaveat.viasMescladas),
        isFalse,
        reason: 'via imposta não mescla: o ponto de impô-la é medir aquela via',
      );
    });

    test('a via não muda com a taxa livre de risco corrente', () {
      final vias = <ValuationModel>{};
      for (var passo = 0; passo <= 16; passo++) {
        final v = com(0.1600 - passo * 0.0050);
        if (v != null) vias.add(v.model);
      }
      expect(vias.length, 1,
          reason: 'a estrutura de capital é fato de longo prazo; qual via a '
              'descreve não pode depender de onde a Selic está hoje');
    });
  });

  group('Retorno terminal imposto — a costura do DCF reverso', () {
    // `terminalReturnOverride` existe para a varredura da decisão 35. Ele é a
    // única entrada capaz de mudar o valor terminal de fora, e por isso precisa
    // de três garantias travadas: não fazer nada quando nulo, mandar quando
    // preenchido, e não se passar por vantagem competitiva reconhecida.
    FundamentalsSnapshot exercicio(int ano, double escala) =>
        FundamentalsSnapshot(
          ticker: ticker,
          fiscalPeriodEnd: DateTime(ano, 12, 31),
          totalRevenue: 10000 * escala,
          ebit: 1400 * escala,
          ebitda: 1900 * escala,
          netIncome: 700 * escala,
          incomeBeforeTax: 1060 * escala,
          // Negativo, na convenção da fonte: 1060 − 360 = 700 de líquido.
          incomeTaxExpense: -360 * escala,
          interestExpense: 120,
          earningsPerShare: 0.7 * escala,
          cash: 800,
          shortTermInvestments: 200,
          shortTermDebt: 400,
          longTermDebt: 1600,
          totalStockholderEquity: 5000 * escala,
          bookValuePerShare: 5.0 * escala,
          operatingCashFlow: 1500 * escala,
          freeCashFlow: 900 * escala,
          nopat: 924 * escala,
          sharesOutstanding: 1000,
          sharesOutstandingAsOf: 1000,
          marketCap: 12000,
          enterpriseToEbitda: 8.0,
        );

    List<FundamentalsSnapshot> serie() {
      final out = <FundamentalsSnapshot>[];
      var escala = 1.0;
      for (var i = 15; i >= 0; i--) {
        out.add(exercicio(2025 - i, escala));
        escala *= 1.05;
      }
      return out;
    }

    ValuationResult? com(double? imposto) {
      final r = ValuationCascade.evaluate(ValuationInputs(
        ticker: ticker,
        asOf: DateTime(2026, 9, 9),
        fundamentals: serie(),
        marketPrice: 12.0,
        capm: const CapmInputs(
          riskFreeRate: 0.14,
          beta: 1.0,
          marketPremium: 0.055,
        ),
        declaredTerminalRiskFreeRate: 0.094,
        terminalReturnOverride: imposto,
      ));
      return r.isOk ? r.unwrap() : null;
    }

    test('nulo é exatamente o comportamento de produção', () {
      final semCampo = ValuationCascade.evaluate(ValuationInputs(
        ticker: ticker,
        asOf: DateTime(2026, 9, 9),
        fundamentals: serie(),
        marketPrice: 12.0,
        capm: const CapmInputs(
          riskFreeRate: 0.14,
          beta: 1.0,
          marketPremium: 0.055,
        ),
        declaredTerminalRiskFreeRate: 0.094,
      ));
      final comNulo = com(null);
      expect(semCampo.isOk, isTrue);
      expect(comNulo, isNotNull);
      expect(comNulo!.fairValue.reais,
          closeTo(semCampo.unwrap().fairValue.reais, 1e-9));
    });

    test('retorno terminal maior não reduz o preço justo', () {
      // Monotonia é o que a varredura por bissecção pressupõe dentro do
      // intervalo que ela isola. Se ela quebrasse aqui, a raiz não teria
      // significado.
      final baixo = com(0.10);
      final alto = com(0.40);
      expect(baixo, isNotNull);
      expect(alto, isNotNull);
      expect(alto!.fairValue.reais,
          greaterThanOrEqualTo(baixo!.fairValue.reais - 0.01));
      expect(alto.fairValue.reais, greaterThan(baixo.fairValue.reais),
          reason: 'sem efeito algum, a varredura da decisão 35 não mede nada');
    });

    test('imposição não se passa por vantagem competitiva reconhecida', () {
      final v = com(0.40);
      final producao = com(null);
      expect(v, isNotNull);
      expect(producao, isNotNull);
      // A bandeira e o retorno imposto são grandezas distintas: `moatApplied`
      // alimenta relatório de cobertura, e varredura de diagnóstico não é
      // veredito. O que se trava é que a imposição **não move a bandeira** —
      // e não que ela seja falsa, que depende do ativo do fixture.
      expect(v!.diagnostics!.moatApplied, producao!.diagnostics!.moatApplied,
          reason: 'a imposição não pode criar nem apagar veredito');
      expect(v.diagnostics!.terminalRetainedSpread,
          producao.diagnostics!.terminalRetainedSpread,
          reason: 'lambda é do veredito, não do valor imposto');
      expect(
        v.warnings.any((w) => w.contains('imposto')),
        isTrue,
        reason: 'o resultado precisa declarar que é instrumento, não avaliação',
      );
      expect(
        v.warnings.any((w) => w.contains('Vantagem competitiva residual:')),
        isFalse,
        reason: 'a narrativa do veredito não sai junto com a imposição',
      );
    });
  });

  group('Caixa rende taxa livre de risco, e não o WACC', () {
    // Sem dívida bruta não há custo de dívida a medir, e o recuo era a própria
    // taxa de desconto. Com dívida líquida **negativa** ela multiplica um peso
    // negativo: o motor creditava ao caixa o rendimento do negócio. Medido em
    // 11/09/2026, a ALOS3 — R$ 2,43 bi de caixa líquido — caiu 10,5% ao trocar
    // o recuo pela taxa livre de risco. Decisão 58.
    const premissas = DcfAssumptions(
      projectionYears: 5,
      growthRate: 0.04,
      perpetualGrowth: 0.04,
      discountRate: 0.12,
      terminalDiscountRate: 0.12,
      returnOnCapital: 0.0,
    );

    double justoCom(double kd, {required double dividaLiquida}) =>
        DcfCalculator.equityFromFirm(
          baseProfit: 100,
          assumptions: premissas,
          netDebt: dividaLiquida,
          sharesOutstanding: 10,
          costOfDebt: kd,
          taxRate: 0.34,
          equityDiscountRate: 0.14,
          terminalEquityDiscountRate: 0.14,
        ).unwrap().fairValuePerShare;

    test('com caixa líquido, o rendimento atribuído a ele decide o preço', () {
      const rf = 0.09;
      const wacc = 0.12;
      final comRf = justoCom(rf, dividaLiquida: -400);
      final comWacc = justoCom(wacc, dividaLiquida: -400);
      expect(comWacc, greaterThan(comRf),
          reason: 'creditar o WACC ao caixa infla o fluxo do acionista — é '
              'exatamente o que o recuo antigo fazia');
      expect((comWacc / comRf - 1).abs(), greaterThan(0.01),
          reason: 'se a diferença fosse desprezível o teste não mediria nada');
    });

    test('sem dívida líquida, o rendimento do caixa não decide nada', () {
      // O termo da ponte é `D·(kd(1−τ) − g)`: com `D = 0` ele some, e a
      // escolha do recuo deixa de importar.
      expect(justoCom(0.09, dividaLiquida: 0),
          closeTo(justoCom(0.30, dividaLiquida: 0), 1e-9));
    });

    test('sem dívida bruta não há custo de dívida a medir', () {
      final semDivida = FundamentalsSnapshot(
        ticker: ticker,
        fiscalPeriodEnd: DateTime(2025, 12, 31),
        interestExpense: 50,
        cash: 900,
        netIncome: 100,
        ebit: 150,
      );
      expect(semDivida.totalDebt, 0);
      expect(semDivida.costOfDebt, isNull);
      expect(semDivida.netDebt, lessThan(0),
          reason: 'é o caso que torna o recuo alcançável');
    });
  });

  group('O vale do ciclo não descarta a empresa', () {
    // A normalização funcionava no pico e desligava no vale: o fator é
    // `ciclo ÷ atual` e exige denominador positivo. Medido em 11/09/2026:
    // sete ativos elegíveis eram recusados por fluxo-base não positivo, entre
    // eles USIM3, USIM5, CSAN3 e CSNA3 — cíclicos num ano ruim.
    FundamentalsSnapshot ano(
      int y,
      double lucro, {
      double patrimonio = 10000,
      double? ebitda,
    }) =>
        FundamentalsSnapshot(
          ticker: ticker,
          fiscalPeriodEnd: DateTime(y, 12, 31),
          totalRevenue: 20000,
          ebit: lucro / 0.66,
          ebitda: ebitda ?? (lucro / 0.66 + 800),
          netIncome: lucro,
          incomeBeforeTax: lucro * 1.4,
          incomeTaxExpense: -lucro * 0.4,
          interestExpense: 120,
          earningsPerShare: lucro / 1000,
          cash: 500,
          shortTermInvestments: 100,
          shortTermDebt: 300,
          longTermDebt: 1200,
          totalStockholderEquity: patrimonio,
          bookValuePerShare: patrimonio / 1000,
          operatingCashFlow: lucro * 1.5,
          freeCashFlow: lucro,
          nopat: lucro,
          sharesOutstanding: 1000,
          sharesOutstandingAsOf: 1000,
          marketCap: 12000,
        );

    /// Série com [negativos] exercícios de prejuízo no fim.
    List<FundamentalsSnapshot> serie({
      required int negativos,
      double lucroBom = 1200,
      double? ebitdaFinal,
    }) {
      final out = <FundamentalsSnapshot>[];
      for (var i = 15; i >= 0; i--) {
        final y = 2025 - i;
        final ruim = i < negativos;
        out.add(ano(
          y,
          ruim ? -400 : lucroBom,
          ebitda: i == 0 ? ebitdaFinal : null,
        ));
      }
      return out;
    }

    ValuationResult? avaliar(
      List<FundamentalsSnapshot> f, {
      String? setor,
      String? subsetor,
    }) {
      final r = ValuationCascade.evaluate(ValuationInputs(
        ticker: ticker,
        asOf: DateTime(2026, 9, 9),
        fundamentals: f,
        marketPrice: 12.0,
        capm: const CapmInputs(
          riskFreeRate: 0.13,
          beta: 1.0,
          marketPremium: 0.055,
        ),
        declaredTerminalRiskFreeRate: 0.094,
        sectorKey: setor,
        industry: subsetor,
      ));
      return r.isOk ? r.unwrap() : null;
    }

    test('um ano de prejuízo deixa de descartar a empresa', () {
      // Cíclico de propósito: em não cíclico, prejuízo depois de lucro sempre
      // reprova na trava de saúde — ver o teste dela abaixo.
      final v = avaliar(serie(negativos: 1), setor: 'materiais-basicos');
      expect(v, isNotNull,
          reason: 'com o fluxo-base do exercício, este fixture seria recusado '
              'por lucro não positivo');
      expect(v!.fairValue.reais, greaterThan(0));
      expect(v.diagnostics!.caveats,
          contains(ValuationCaveat.baseReconstruida));
      expect(
        v.warnings.any((w) => w.contains('reconstruído do ciclo')),
        isTrue,
      );
    });

    test('o fluxo-base é o retorno do ciclo sobre o capital de hoje', () {
      final f = serie(negativos: 1);
      final v = avaliar(f, setor: 'materiais-basicos')!;
      final pub = PointInTimeView(DateTime(2026, 9, 9)).published(f);
      // A mesma alíquota que a cascata aplica: sem ela o NOPAT da série é
      // outro, e o ciclo também.
      final s = CapitalSeries.build(
        pub,
        ValuationLane.firm,
        firmTaxRate: CapitalSeries.structuralTaxRate(
          pub,
          statutoryRate: ValuationParameters.statutoryTaxRate,
        ),
      );
      final ciclo = s.cycleReturn(window: ValuationParameters.cycleWindow)!;
      // O retorno que governa o freio é o do ciclo, e não o do exercício de
      // prejuízo: sem isso o fluxo viria do ciclo e o reinvestimento do vale.
      expect(v.diagnostics!.returnOnCapital, closeTo(ciclo, 1e-12));
      expect(ciclo, greaterThan(0));
    });

    test('ciclo não positivo continua recusando', () {
      // Empresa que perde dinheiro na maior parte da janela: não há a que
      // voltar, e a mediana não é resgate.
      expect(avaliar(serie(negativos: 7), setor: 'materiais-basicos'), isNull);
    });

    test('prejuízo que virou regra continua recusando', () {
      // Metade da janela negativa passa no teste do sinal da mediana e falha
      // no da frequência — é o caso que separa vale de declínio.
      final f = serie(negativos: 5);
      final pub = PointInTimeView(DateTime(2026, 9, 9)).published(f);
      final s = CapitalSeries.build(pub, ValuationLane.firm);
      final fracao = s.positiveShare(window: ValuationParameters.cycleWindow)!;
      expect(fracao, lessThan(ValuationParameters.minPositiveFlow),
          reason: 'o fixture precisa cair abaixo do corte para medir o que '
              'promete');
      expect(avaliar(f, setor: 'materiais-basicos'), isNull);
    });

    test('a trava de saúde bloqueia, e cíclico é isento dela', () {
      // Ela foi retirada e reposta por medição: sem ela a RAPT4 entra a
      // +311,7% de potencial, com o resultado caído 109% no triênio e o
      // fluxo-base reconstruído sobre um retorno de ciclo que a empresa
      // acabou de deixar de ter. Reconstruir a base erra para cima, e é esse
      // risco que a trava controla.
      final f = serie(negativos: 1);
      final queda = GrowthGuards.recentOperationalDecline(
        PointInTimeView(DateTime(2026, 9, 9)).published(f),
      );
      expect(queda, isNotNull);
      expect(queda!, greaterThan(ValuationParameters.maxOperationalDecline));

      expect(avaliar(f, setor: 'bens-industriais'), isNull);
      // A isenção cíclica da decisão 30 vale aqui pela mesma razão que vale na
      // normalização: em commodity, queda entre pico e vale é o ciclo.
      expect(avaliar(f, setor: 'materiais-basicos'), isNotNull);
    });

    test('a trava tem um buraco, e a frequência o cobre', () {
      // Quando a referência de três anos atrás também era prejuízo, a trava
      // **aprova** — não há queda a medir. É a frequência do prejuízo na
      // janela que recusa nesse caso, e não a trava.
      final f = serie(negativos: 5);
      final queda = GrowthGuards.recentOperationalDecline(
        PointInTimeView(DateTime(2026, 9, 9)).published(f),
      );
      expect(queda, isNotNull);
      expect(queda!, lessThan(ValuationParameters.maxOperationalDecline),
          reason: 'a trava aprova este caso — é o buraco que a frequência '
              'cobre');
      expect(avaliar(f, setor: 'materiais-basicos'), isNull);
    });
  });

  group('Ausência não é zero: o exercício sem resultado', () {
    // Medido em 10/09/2026: a fonte publica o exercício com o balanço
    // preenchido e o resultado inteiro zerado em 4 dos 376 ativos. A TIMS3
    // aparecia com receita, EBIT, lucro e LPA zerados e patrimônio de R$ 24
    // bilhões, tendo tido EBIT de R$ 4,7 bi dois exercícios antes — e era
    // recusada por "os dados não sustentam nenhuma das duas vias", que é a
    // mensagem errada para um dado que a fonte não entregou.
    FundamentalsSnapshot exercicio(
      int ano, {
      double? receita,
      double? ebit,
      double? lucro,
      double? lpa,
      double patrimonio = 24000,
    }) =>
        FundamentalsSnapshot(
          ticker: ticker,
          fiscalPeriodEnd: DateTime(ano, 12, 31),
          totalRevenue: receita,
          ebit: ebit,
          ebitda: ebit == null ? null : ebit * 1.3,
          netIncome: lucro,
          incomeBeforeTax: lucro == null ? null : lucro * 1.4,
          incomeTaxExpense: lucro == null ? null : -lucro * 0.4,
          earningsPerShare: lpa,
          cash: 500,
          shortTermDebt: 400,
          longTermDebt: 1600,
          totalStockholderEquity: patrimonio,
          bookValuePerShare: patrimonio / 1000,
          nopat: ebit == null ? null : ebit * 0.66,
          sharesOutstanding: 1000,
          sharesOutstandingAsOf: 1000,
          marketCap: 30000,
        );

    test('os quatro zerados juntos é ausência; um só não é', () {
      // Zerar um deles é possível — holding sem receita, empresa no zero a
      // zero, exercício sem LPA publicado.
      expect(exercicio(2025).hasIncomeStatement, isFalse);
      expect(
        exercicio(2025, receita: 0, ebit: 0, lucro: 0, lpa: 0)
            .hasIncomeStatement,
        isFalse,
      );
      expect(exercicio(2025, receita: 8000).hasIncomeStatement, isTrue);
      expect(exercicio(2025, ebit: 1000).hasIncomeStatement, isTrue);
      expect(exercicio(2025, lucro: 700).hasIncomeStatement, isTrue);
      expect(exercicio(2025, lpa: 0.7).hasIncomeStatement, isTrue);
      // Prejuízo é resultado publicado, e não pode ser confundido com ausência.
      expect(exercicio(2025, ebit: -1000).hasIncomeStatement, isTrue);

      // **Resíduo de ponto flutuante não é resultado.** A fonte devolve o zero
      // às vezes sujo, e `== 0` leria `1e-16` como lucro publicado.
      expect(
        exercicio(2025, receita: 1e-16, ebit: -1e-14, lucro: 0, lpa: 0)
            .hasIncomeStatement,
        isFalse,
      );
      // E o corte por papel é o centavo, não o real: LPA de R$ 0,50 é
      // legítimo, e o corte dos agregados o descartaria.
      expect(exercicio(2025, lpa: 0.50).hasIncomeStatement, isTrue);
      expect(exercicio(2025, lpa: 0.001).hasIncomeStatement, isFalse);
    });

    List<FundamentalsSnapshot> serie({required int vazios}) {
      final out = <FundamentalsSnapshot>[];
      var escala = 1.0;
      for (var i = 15; i >= 0; i--) {
        final ano = 2025 - i;
        final vazio = i < vazios;
        out.add(vazio
            ? exercicio(ano)
            : exercicio(
                ano,
                receita: 10000 * escala,
                ebit: 1400 * escala,
                lucro: 700 * escala,
                lpa: 0.7 * escala,
                patrimonio: 6000 * escala,
              ));
        escala *= 1.05;
      }
      return out;
    }

    ValuationResult? avaliar(int vazios) {
      final r = ValuationCascade.evaluate(ValuationInputs(
        ticker: ticker,
        asOf: DateTime(2026, 9, 9),
        fundamentals: serie(vazios: vazios),
        marketPrice: 10.0,
        capm: const CapmInputs(
          riskFreeRate: 0.13,
          beta: 1.0,
          marketPremium: 0.055,
        ),
        declaredTerminalRiskFreeRate: 0.094,
      ));
      return r.isOk ? r.unwrap() : null;
    }

    test('o exercício vazio sai da série, e a base vem do anterior', () {
      final limpo = avaliar(0);
      final comVazio = avaliar(1);
      expect(limpo, isNotNull);
      expect(comVazio, isNotNull,
          reason: 'lido como zero, o último exercício produziria base nula e '
              'a avaliação seria recusada');
      // A base passa a ser o exercício anterior, que é menor pela escala — o
      // preço justo cai, e não vai a zero nem some.
      expect(comVazio!.fairValue.reais, greaterThan(0));
      expect(comVazio.fairValue.reais, lessThan(limpo!.fairValue.reais));
    });

    test('a exclusão é declarada, com a contagem', () {
      final v = avaliar(2)!;
      expect(
        v.warnings.any((w) => w.contains('sem demonstração de resultado')),
        isTrue,
      );
      expect(v.warnings.any((w) => w.startsWith('2 exercícios')), isTrue);
    });

    test('série inteira vazia vira recusa que nomeia a causa', () {
      final r = ValuationCascade.evaluate(ValuationInputs(
        ticker: ticker,
        asOf: DateTime(2026, 9, 9),
        fundamentals: serie(vazios: 16),
        marketPrice: 10.0,
        capm: const CapmInputs(
          riskFreeRate: 0.13,
          beta: 1.0,
          marketPremium: 0.055,
        ),
      ));
      expect(r.isErr, isTrue);
      final m = r.failureOrNull!.message;
      expect(m, contains('sem demonstração de resultado'));
      expect(m, isNot(contains('nenhuma das duas vias')),
          reason: 'a causa é o dado que a fonte não entregou, e não o modelo '
              'não se aplicar');
    });
  });

  group('O peso do terminal mede a mesma coisa nas três rotas', () {
    // Antes da decisão 51 a ponte media contra o valor da **firma** e as
    // outras duas contra o do **acionista**: o mesmo campo carregava duas
    // grandezas conforme um caminho que o leitor não vê, e o corte de 80% da
    // ressalva valia para as duas.
    const premissas = DcfAssumptions(
      projectionYears: 5,
      growthRate: 0.04,
      perpetualGrowth: 0.04,
      discountRate: 0.12,
      terminalDiscountRate: 0.12,
      returnOnCapital: 0.0,
    );

    test('a ponte mede contra o capital próprio, não contra a firma', () {
      final o = DcfCalculator.firm(
        baseProfit: 100,
        assumptions: premissas,
        netDebt: 300,
        sharesOutstanding: 10,
      ).unwrap();

      expect(o.terminalShare,
          closeTo(o.discountedTerminalValue / o.equityValue, 1e-12));
      expect(o.terminalShare,
          greaterThan(o.discountedTerminalValue / o.enterpriseValue),
          reason: 'com dívida, a referência do acionista é maior — e é a que '
              'diz quanto do preço repousa na perpetuidade');
    });

    test('sem dívida as duas referências coincidem', () {
      final o = DcfCalculator.firm(
        baseProfit: 100,
        assumptions: premissas,
        netDebt: 0,
        sharesOutstanding: 10,
      ).unwrap();
      expect(o.terminalShare,
          closeTo(o.discountedTerminalValue / o.enterpriseValue, 1e-12));
    });

    test('capital próprio fino leva a razão acima de 100%, e não trunca', () {
      // Truncar em 1 esconderia exatamente o caso mais frágil.
      final o = DcfCalculator.firm(
        baseProfit: 100,
        assumptions: premissas,
        netDebt: 900,
        sharesOutstanding: 10,
      ).unwrap();
      expect(o.equityValue, greaterThan(0),
          reason: 'o fixture precisa sobreviver à ponte para medir o que '
              'promete');
      expect(o.terminalShare, greaterThan(1.0));
    });

    test('a rota derivada desconta o minoritário da referência também', () {
      DcfOutcome derivada(double m) => DcfCalculator
          .equityFromFirm(
            baseProfit: 100,
            assumptions: premissas,
            netDebt: 300,
            sharesOutstanding: 10,
            costOfDebt: 0.10,
            taxRate: 0.34,
            equityDiscountRate: 0.14,
            terminalEquityDiscountRate: 0.14,
            minorityInterest: m,
          )
          .unwrap();
      expect(derivada(200).terminalShare,
          greaterThan(derivada(0).terminalShare),
          reason: 'o que sobra ao controlador é menor, e o terminal pesa mais '
              'nele');
    });
  });

  group('Concessão não preserva excedente na perpetuidade', () {
    // Medido em 10/09/2026: 15 dos 120 avaliados operam sob contrato de prazo
    // determinado, e cinco recebiam excedente de retorno preservado para
    // sempre — a CPFE3 com λ = 0,261. Uma concessão é relicitada, e a tarifa
    // remunera o capital ao custo dele.
    test('a classificação pega concessão e não pega o resto', () {
      bool prazo(String? setor, String? sub) =>
          ConcessionSectors.hasFiniteTerm(sectorKey: setor, industry: sub);

      expect(prazo('energia', 'Energia Elétrica'), isTrue);
      expect(prazo('saneamento', null), isTrue);
      expect(prazo('infraestrutura', null), isTrue);
      expect(prazo('bens-industriais', 'Exploração de Rodovias'), isTrue);
      expect(prazo('bens-industriais', 'Transporte Ferroviário'), isTrue);
      // Acentuação e pontuação não decidem nada: a fonte publica variantes.
      expect(prazo('energia', 'ENERGIA ELETRICA'), isTrue);

      expect(prazo('energia', 'Exploração. Refino e Distribuição'), isFalse);
      expect(prazo('materiais-basicos', 'Siderurgia'), isFalse);
      expect(prazo('consumo-ciclico', 'Tecidos, Vestuário e Calçados'), isFalse);
      expect(prazo(null, null), isFalse);
    });

    test('o excedente perpétuo é recusado, com o motivo nomeado', () {
      MoatVerdict veredito({required bool prazo}) => GrowthGuards.residualMoat(
            cycleReturn: 0.28,
            terminalDiscountRate: 0.12,
            externalCapitalRatio: 0.10,
            periods: 12,
            excessReturns: [
              for (var ano = 2014; ano <= 2025; ano++)
                (year: ano, excess: 0.16 * _pot(0.9, ano - 2014)),
            ],
            projectionYears: 10,
            finiteTerm: prazo,
          );

      final livre = veredito(prazo: false);
      expect(livre.terminalReturn, isNotNull,
          reason: 'sem prazo este fixture precisa conceder o excedente — se '
              'não conceder, o teste não mede o que promete');

      final preso = veredito(prazo: true);
      expect(preso.terminalReturn, isNull);
      expect(preso.blocks, contains(MoatBlock.prazoDeterminado));
    });
  });

  group('O rastro descreve a conta que foi feita', () {
    // A lente `metodo` apontou, e é o tipo de divergência que a auditoria
    // existe justamente para impedir: a fórmula publicada omitia o
    // levantamento de meio de ano e descrevia um desconto 6% maior que o
    // aplicado.
    FundamentalsSnapshot exercicio(int ano, double escala) =>
        FundamentalsSnapshot(
          ticker: ticker,
          fiscalPeriodEnd: DateTime(ano, 12, 31),
          totalRevenue: 10000 * escala,
          ebit: 1400 * escala,
          ebitda: 1900 * escala,
          netIncome: 700 * escala,
          incomeBeforeTax: 1000 * escala,
          incomeTaxExpense: -300 * escala,
          interestExpense: 120,
          earningsPerShare: 0.7 * escala,
          cash: 500,
          shortTermInvestments: 200,
          shortTermDebt: 400,
          longTermDebt: 1600,
          totalStockholderEquity: 6000 * escala,
          bookValuePerShare: 6.0 * escala,
          operatingCashFlow: 1500 * escala,
          freeCashFlow: 900 * escala,
          nopat: 924 * escala,
          sharesOutstanding: 1000,
          sharesOutstandingAsOf: 1000,
          marketCap: 10000,
        );

    List<String> formulas(CashTiming timing) {
      final capturadas = <String>[];
      AuditRecorder.attach((evento) {
        for (final c in evento.calculations) {
          capturadas.add(c.latexRepresentation);
        }
      });
      try {
        ValuationCascade.evaluate(ValuationInputs(
          ticker: ticker,
          asOf: DateTime(2026, 9, 9),
          fundamentals: [
            for (var i = 15; i >= 0; i--) exercicio(2025 - i, _pot(1.05, 15 - i))
          ],
          marketPrice: 10.0,
          capm: const CapmInputs(
            riskFreeRate: 0.13,
            beta: 1.0,
            marketPremium: 0.055,
          ),
          declaredTerminalRiskFreeRate: 0.094,
          cashTimingOverride: timing,
        ));
      } finally {
        AuditRecorder.detach();
      }
      return capturadas;
    }

    test('a fórmula do explícito declara o levantamento, e só quando há', () {
      final meio = formulas(CashTiming.meioDeAno).join(' ');
      final fim = formulas(CashTiming.fimDeAno).join(' ');
      expect(meio, isNotEmpty, reason: 'o rastro precisa ter sido capturado');
      expect(meio, contains(r'\sqrt{1 + r_t}'));
      expect(fim, isNot(contains(r'\sqrt{1 + r_t}')));
    });

    test('a fórmula do terminal declara o levantamento de equilíbrio', () {
      final meio = formulas(CashTiming.meioDeAno).join(' ');
      final fim = formulas(CashTiming.fimDeAno).join(' ');
      expect(meio, contains(r'\sqrt{1 + r_\infty}'));
      expect(fim, isNot(contains(r'\sqrt{1 + r_\infty}')));
    });
  });

  group('A ponte devolve o que não é do controlador', () {
    // Medido em 10/09/2026 na fonte: a conta-mãe `loansAndFinancing` **já
    // contém** debêntures e arrendamento — somá-los estouraria o passivo não
    // circulante em PETR4, VALE3 e RENT3. O que de fato falta na ponte é a
    // participação dos não controladores, e ela é grande: 24,1% do valor de
    // mercado na CSNA3.
    const premissas = DcfAssumptions(
      projectionYears: 5,
      growthRate: 0.04,
      perpetualGrowth: 0.04,
      discountRate: 0.12,
      terminalDiscountRate: 0.12,
      returnOnCapital: 0.0,
    );

    DcfOutcome comMinoritarios(double m) => DcfCalculator
        .firm(
          baseProfit: 100,
          assumptions: premissas,
          netDebt: 300,
          sharesOutstanding: 10,
          minorityInterest: m,
        )
        .unwrap();

    test('o preço por papel cai exatamente a parte dos minoritários', () {
      final sem = comMinoritarios(0);
      final com = comMinoritarios(200);
      expect(sem.fairValuePerShare - com.fairValuePerShare,
          closeTo(200 / 10, 1e-9));
      expect(com.equityValue, closeTo(sem.equityValue - 200, 1e-9));
    });

    test('a alavancagem NÃO muda: minoritário é capital próprio', () {
      // Tirá-los de `equityShare` os trataria como dívida, e a pós-condição da
      // ponte e o ponto fixo leriam uma estrutura de capital que não existe.
      final sem = comMinoritarios(0);
      final com = comMinoritarios(200);
      expect(com.equityShare, closeTo(sem.equityShare, 1e-12));
      expect(com.enterpriseValue, closeTo(sem.enterpriseValue, 1e-12));
    });

    test('participação negativa é tratada como zero', () {
      // Controlada com patrimônio negativo produz minoritário negativo, e
      // subtraí-lo **aumentaria** o valor do controlador.
      expect(comMinoritarios(-500).fairValuePerShare,
          closeTo(comMinoritarios(0).fairValuePerShare, 1e-12));
    });

    test('a rota derivada desconta a mesma parte', () {
      DcfOutcome derivada(double m) => DcfCalculator
          .equityFromFirm(
            baseProfit: 100,
            assumptions: premissas,
            netDebt: 300,
            sharesOutstanding: 10,
            costOfDebt: 0.10,
            taxRate: 0.34,
            equityDiscountRate: 0.14,
            terminalEquityDiscountRate: 0.14,
            minorityInterest: m,
          )
          .unwrap();
      expect(derivada(0).fairValuePerShare - derivada(200).fairValuePerShare,
          closeTo(200 / 10, 1e-9));
    });
  });

  group('Equivalência patrimonial não é tributada duas vezes', () {
    // Na DRE brasileira a equivalência entra acima do EBIT, e chega líquida do
    // imposto pago pela investida. Medido no ITSA4 em 10/09/2026: EBIT de
    // R$ 18,1 bi contra equivalência de R$ 17,5 bi — 97% do resultado
    // operacional era lucro já tributado, e recebia 34% de novo.
    FundamentalsSnapshot comEquivalencia(double? equiv) => FundamentalsSnapshot(
          ticker: ticker,
          fiscalPeriodEnd: DateTime(2025, 12, 31),
          ebit: 1000,
          ebitda: 1200,
          netIncome: 800,
          incomeBeforeTax: 900,
          incomeTaxExpense: -100,
          equityIncomeResult: equiv,
          sharesOutstanding: 100,
          sharesOutstandingAsOf: 100,
        );

    test('sem equivalência, nada muda', () {
      expect(comEquivalencia(null).nopatAtRate(0.25), closeTo(750, 1e-9));
      expect(comEquivalencia(0).nopatAtRate(0.25), closeTo(750, 1e-9));
    });

    test('a parte da equivalência passa sem imposto', () {
      // `NOPAT = (1000 − 400)·0,75 + 400 = 850`, contra os 750 de antes.
      expect(comEquivalencia(400).nopatAtRate(0.25), closeTo(850, 1e-9));
    });

    test('equivalência negativa não devolve imposto', () {
      // Prejuízo da investida reduz o EBIT sem ter gerado crédito na
      // controladora; devolver imposto ali inventaria caixa.
      expect(comEquivalencia(-400).nopatAtRate(0.25), closeTo(750, 1e-9));
    });

    test('não passa do próprio EBIT', () {
      // Operação no prejuízo com equivalência maior que o EBIT: o NOPAT não
      // pode superar o resultado que o gerou.
      final s = comEquivalencia(1500);
      expect(s.taxableEquityIncome, closeTo(1000, 1e-9));
      expect(s.nopatAtRate(0.25), closeTo(1000, 1e-9));
    });
  });

  group('Estrutura de capital recusada pela realavancagem', () {
    // Medido em 10/09/2026: seis dos noventa e seis ativos com as duas vias
    // avaliáveis caem aqui, e são **exatamente** os seis que ainda eram
    // mesclados e migrados. O solucionador recusa — capital próprio não
    // positivo no ano zero, ou taxa de equilíbrio abaixo do crescimento
    // perpétuo — e o motor recuava para a interpolação, que não enxerga o
    // problema porque desconta pela taxa que a realavancagem rejeitou.
    FundamentalsSnapshot afogado(int ano, double escala, double divida) =>
        FundamentalsSnapshot(
          ticker: ticker,
          fiscalPeriodEnd: DateTime(ano, 12, 31),
          totalRevenue: 10000 * escala,
          ebit: 1400 * escala,
          ebitda: 1900 * escala,
          netIncome: 500 * escala,
          incomeBeforeTax: 800 * escala,
          incomeTaxExpense: -300 * escala,
          interestExpense: 600,
          earningsPerShare: 0.5 * escala,
          cash: 500,
          shortTermInvestments: 200,
          shortTermDebt: divida * 0.2,
          longTermDebt: divida * 0.8,
          totalStockholderEquity: 4000 * escala,
          bookValuePerShare: 4.0 * escala,
          operatingCashFlow: 1500 * escala,
          freeCashFlow: 900 * escala,
          nopat: 924 * escala,
          sharesOutstanding: 1000,
          sharesOutstandingAsOf: 1000,
          marketCap: 9000,
          enterpriseToEbitda: 8.0,
        );

    List<FundamentalsSnapshot> serie(double divida) {
      final out = <FundamentalsSnapshot>[];
      var escala = 1.0;
      for (var i = 15; i >= 0; i--) {
        out.add(afogado(2025 - i, escala, divida));
        escala *= 1.06;
      }
      return out;
    }

    ValuationResult? avaliar({required double divida, double? betaU}) {
      final r = ValuationCascade.evaluate(ValuationInputs(
        ticker: ticker,
        asOf: DateTime(2026, 9, 9),
        fundamentals: serie(divida),
        marketPrice: 9.0,
        capm: CapmInputs(
          riskFreeRate: 0.14,
          beta: 1.0,
          marketPremium: 0.055,
        ),
        declaredTerminalRiskFreeRate: 0.094,
        unleveredBeta: betaU,
      ));
      return r.isOk ? r.unwrap() : null;
    }

    test('a recusa da realavancagem não vira preço pela interpolação', () {
      var mescladosSem = 0;
      var mescladosCom = 0;
      var recusados = 0;
      var avaliados = 0;
      for (var passo = 0; passo <= 30; passo++) {
        final divida = 16000 + passo * 2000.0;
        final sem = avaliar(divida: divida);
        final comU = avaliar(divida: divida, betaU: 0.60);
        if (sem != null &&
            sem.diagnostics!.caveats.contains(ValuationCaveat.viasMescladas)) {
          mescladosSem++;
        }
        if (comU == null) {
          recusados++;
          continue;
        }
        avaliados++;
        if (comU.diagnostics!.caveats
            .contains(ValuationCaveat.viasMescladas)) {
          mescladosCom++;
        }
      }

      expect(mescladosSem, greaterThan(0),
          reason: 'sem beta desalavancado esta varredura precisa atravessar a '
              'mescla — se não atravessar, o teste não mede o que promete');
      expect(avaliados + recusados, 31);
      expect(mescladosCom, 0,
          reason: 'a via da firma recusada não pode voltar pela interpolação '
              'para ser mesclada com a do acionista');
    });

    test('a via do acionista carrega o ativo, e a migração é declarada', () {
      // Dívida escolhida para a recusa disparar: com ela o capital próprio
      // some quando o custo dele é reprecificado pela alavancagem que tem.
      final comU = avaliar(divida: 60000, betaU: 0.60)!;
      expect(comU.model, ValuationModel.dcfEarnings,
          reason: 'sem via da firma, quem avalia é o fluxo do acionista');
      expect(comU.diagnostics!.caveats, contains(ValuationCaveat.viaMigrada));
      expect(
        comU.warnings.any((w) => w.contains('não sustenta a via da firma')),
        isTrue,
        reason: 'a migração por estrutura recusada precisa ser nomeada',
      );
      // A via do acionista resolve o próprio `Ke` desde a decisão 46, de modo
      // que a nota do caminho resolvido **existe** aqui — o que não pode
      // acontecer é ela descrever um custo médio, que esta via não tem.
      final nota = comU.warnings
          .where((w) => w.contains('resolvido ano a ano'))
          .toList();
      expect(nota, hasLength(1));
      expect(nota.single, contains('o Ke vai de'));
      expect(nota.single, isNot(contains('WACC')));
    });
  });

  group('A via do acionista resolve o próprio custo de capital', () {
    // Decisão 46. A via do acionista avalia sozinha 33 dos 120 em produção, e
    // em nenhum deles a via da firma produz caminho de taxas para emprestar:
    // ou o `Ke` sai dos fluxos dela mesma, ou ela segue supondo a alavancagem
    // de hoje perene — a hipótese que a decisão 41 mediu e descartou.
    FundamentalsSnapshot exercicio(int ano, double escala) =>
        FundamentalsSnapshot(
          ticker: ticker,
          fiscalPeriodEnd: DateTime(ano, 12, 31),
          totalRevenue: 10000 * escala,
          ebit: 1400 * escala,
          ebitda: 1900 * escala,
          netIncome: 500 * escala,
          incomeBeforeTax: 800 * escala,
          incomeTaxExpense: -300 * escala,
          interestExpense: 600,
          earningsPerShare: 0.5 * escala,
          cash: 500,
          shortTermInvestments: 200,
          shortTermDebt: 2000,
          longTermDebt: 8000,
          totalStockholderEquity: 4000 * escala,
          bookValuePerShare: 4.0 * escala,
          operatingCashFlow: 1500 * escala,
          freeCashFlow: 900 * escala,
          nopat: 924 * escala,
          sharesOutstanding: 1000,
          sharesOutstandingAsOf: 1000,
          marketCap: 9000,
          enterpriseToEbitda: 8.0,
        );

    List<FundamentalsSnapshot> serie() {
      final out = <FundamentalsSnapshot>[];
      var escala = 1.0;
      for (var i = 15; i >= 0; i--) {
        out.add(exercicio(2025 - i, escala));
        escala *= 1.06;
      }
      return out;
    }

    ValuationResult? acionista({double? betaU, String? setor}) {
      final r = ValuationCascade.evaluate(ValuationInputs(
        ticker: ticker,
        asOf: DateTime(2026, 9, 9),
        fundamentals: serie(),
        marketPrice: 9.0,
        capm: CapmInputs(riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055),
        declaredTerminalRiskFreeRate: 0.094,
        sectorKey: setor,
        unleveredBeta: betaU,
        laneOverride: ValuationLane.shareholder,
      ));
      return r.isOk ? r.unwrap() : null;
    }

    test('com beta desalavancado, o Ke é resolvido e declarado', () {
      final sem = acionista()!;
      final com = acionista(betaU: 0.60)!;

      expect(sem.warnings.any((w) => w.contains('resolvido ano a ano')),
          isFalse,
          reason: 'sem β_U não há realavancagem, e o comportamento é o antigo');
      final nota = com.warnings
          .where((w) => w.contains('resolvido ano a ano'))
          .toList();
      expect(nota, hasLength(1));
      expect(nota.single, contains('o Ke vai de'));
      expect(nota.single, isNot(contains('WACC')),
          reason: 'esta via não tem custo médio a declarar');
      expect(com.fairValue.reais, isNot(closeTo(sem.fairValue.reais, 1e-9)),
          reason: 'resolver a taxa tem de mover o preço, ou não resolveu nada');
    });

    test('instituição financeira fica de fora, e o preço não muda', () {
      // Depósito e captação são insumo do negócio, não financiamento:
      // realavancar por `D/E` trataria a matéria-prima como estrutura de
      // capital, que é o que a Porta 1 existe para não fazer.
      final sem = acionista(setor: 'servicos-financeiros')!;
      final com = acionista(setor: 'servicos-financeiros', betaU: 0.60)!;

      expect(com.warnings.any((w) => w.contains('resolvido ano a ano')),
          isFalse);
      expect(com.fairValue.cents, sem.fairValue.cents,
          reason: 'para banco, oferecer β_U não pode mudar coisa alguma');
    });

    test('o Ke resolvido acompanha a alavancagem, e não a taxa do dia', () {
      // O mesmo ativo com mais dívida tem de sair com preço justo menor: o
      // capital próprio de uma empresa mais alavancada é mais caro.
      ValuationResult? comDivida(double divida) {
        final base = serie();
        final ajustada = [
          for (final f in base)
            FundamentalsSnapshot(
              ticker: f.ticker,
              fiscalPeriodEnd: f.fiscalPeriodEnd,
              totalRevenue: f.totalRevenue,
              ebit: f.ebit,
              ebitda: f.ebitda,
              netIncome: f.netIncome,
              incomeBeforeTax: f.incomeBeforeTax,
              incomeTaxExpense: f.incomeTaxExpense,
              interestExpense: f.interestExpense,
              earningsPerShare: f.earningsPerShare,
              cash: f.cash,
              shortTermInvestments: f.shortTermInvestments,
              shortTermDebt: divida * 0.2,
              longTermDebt: divida * 0.8,
              totalStockholderEquity: f.totalStockholderEquity,
              bookValuePerShare: f.bookValuePerShare,
              operatingCashFlow: f.operatingCashFlow,
              freeCashFlow: f.freeCashFlow,
              nopat: f.nopat,
              sharesOutstanding: f.sharesOutstanding,
              sharesOutstandingAsOf: f.sharesOutstandingAsOf,
              marketCap: f.marketCap,
              enterpriseToEbitda: f.enterpriseToEbitda,
            )
        ];
        final r = ValuationCascade.evaluate(ValuationInputs(
          ticker: ticker,
          asOf: DateTime(2026, 9, 9),
          fundamentals: ajustada,
          marketPrice: 9.0,
          capm: CapmInputs(riskFreeRate: 0.14, beta: 1.0, marketPremium: 0.055),
          declaredTerminalRiskFreeRate: 0.094,
          unleveredBeta: 0.60,
          laneOverride: ValuationLane.shareholder,
        ));
        return r.isOk ? r.unwrap() : null;
      }

      final leve = comDivida(4000);
      final pesada = comDivida(20000);
      expect(leve, isNotNull);
      expect(pesada, isNotNull);
      expect(pesada!.fairValue.reais, lessThan(leve!.fairValue.reais),
          reason: 'mais alavancagem, capital próprio mais caro, preço menor — '
              'e o lucro por papel é o mesmo nos dois');
    });
  });
}

/// Potencia de expoente inteiro, usada pelos testes de persistencia.
double _pot(double base, int expoente) {
  var r = 1.0;
  for (var i = 0; i < expoente; i++) {
    r *= base;
  }
  return r;
}

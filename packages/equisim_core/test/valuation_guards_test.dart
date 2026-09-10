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
        (c) => c.formulaName == 'Base do fluxo: convergência ao ciclo',
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

    test('a isenção não alcança o moat: commodity em vale não ganha vantagem',
        () {
      // A decisão 28 fica intacta aqui. A pergunta do moat é sobre o futuro do
      // excedente, e um vale de ciclo não o sustenta melhor que uma quebra.
      final v = GrowthGuards.residualMoat(
        cycleReturn: 0.30,
        terminalDiscountRate: 0.12,
        externalCapitalRatio: 0.10,
        periods: 14,
        operationalDecline: 0.87,
      );
      expect(v.isProven, isFalse);
      expect(v.blocks, contains(MoatBlock.saudeOperacional));
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
      // Ano 1 a 20%, ano 2 a 10%: fatores 1,20 e 1,20 x 1,10 = 1,32.
      expect(o.discountedFlows[0], closeTo(100 / 1.20, 1e-9));
      expect(o.discountedFlows[1], closeTo(100 / 1.32, 1e-9));
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

  group('Vantagem competitiva residual', () {
    double? moat({
      double? retorno = 0.30,
      double desconto = 0.12,
      double? phi = 0.10,
      int exercicios = 14,
      double? queda,
    }) =>
        GrowthGuards.residualMoatReturn(
          cycleReturn: retorno,
          terminalDiscountRate: desconto,
          externalCapitalRatio: phi,
          periods: exercicios,
          operationalDecline: queda,
        );

    test('as três condições cumpridas preservam 30% do excedente', () {
      // 0,12 + 0,30 x (0,30 - 0,12) = 0,174
      expect(moat(), closeTo(0.174, 1e-12));
    });

    test('crescimento inorgânico reprova, no limiar de 0,60', () {
      expect(moat(phi: 0.61), isNull);
      expect(moat(phi: 0.60), isNotNull);
      // Sob o corte anterior de 0,35, a EGIE3 (0,58) e o ITUB4 (0,50) caíam
      // aqui — concessão e banco acusam Φ alto por definição do negócio, não
      // por dependerem de aporte de sócio.
      expect(moat(phi: 0.58), isNotNull);
    });

    test('resultado em queda no triênio reprova, por mais rentável que seja',
        () {
      // Forma da QUAL3: Φ de 0,01 não por financiar crescimento por dentro, mas
      // por não haver crescimento nenhum a financiar. A mediana de oito anos
      // ainda carrega os exercícios bons de antes da queda.
      expect(moat(queda: 0.49), isNotNull);
      expect(moat(queda: 0.51), isNull);
      expect(moat(queda: null), isNotNull,
          reason: 'queda não medida não reprova: quem não publica lucro já cai '
              'pelo retorno do ciclo, e reprovar duas vezes esconderia a causa');
    });

    test('a queda no triênio é a pior entre lucro e EBITDA', () {
      FundamentalsSnapshot exercicioCom(int ano, double lucro, double ebitda) =>
          FundamentalsSnapshot(
            ticker: ticker,
            fiscalPeriodEnd: DateTime(ano, 12, 31),
            netIncome: lucro,
            ebitda: ebitda,
          );

      // Lucro despenca, EBITDA cresce — a forma da QUAL3 entre 2022 e 2025.
      final lucroCai = [
        exercicioCom(2022, 100, 360),
        exercicioCom(2023, 80, 120),
        exercicioCom(2024, 20, 190),
        exercicioCom(2025, 20, 580),
      ];
      expect(GrowthGuards.recentOperationalDecline(lucroCai),
          closeTo(0.80, 1e-12));

      // E o caminho inverso: lucro sustentado por resultado financeiro
      // enquanto a operação encolhe.
      final ebitdaCai = [
        exercicioCom(2022, 100, 400),
        exercicioCom(2023, 100, 300),
        exercicioCom(2024, 100, 220),
        exercicioCom(2025, 110, 120),
      ];
      expect(GrowthGuards.recentOperationalDecline(ebitdaCai),
          closeTo(0.70, 1e-12));
    });

    test('buraco no triênio não é queda: a medida devolve nulo', () {
      // Comparar 2020 com 2025 como se fossem três anos mediria cinco, e o
      // limiar deixaria de significar o mesmo em ativos diferentes.
      final comBuraco = [
        exercicio(2019, vpa: 10, acoes: 1000, lucro: 100),
        exercicio(2020, vpa: 11, acoes: 1000, lucro: 100),
        exercicio(2024, vpa: 12, acoes: 1000, lucro: 100),
        exercicio(2025, vpa: 13, acoes: 1000, lucro: 10),
      ];
      expect(GrowthGuards.recentOperationalDecline(comBuraco), isNull);
    });

    test('Phi não medido reprova — ausência não é aprovação', () {
      expect(moat(phi: null), isNull);
    });

    test('a rentabilidade aprova pela união das duas pernas', () {
      // Com WACC_inf de 12%, o múltiplo pede 18% e o excedente pede 17%. Quem
      // decide é o menos exigente dos dois, que aqui é o excedente.
      expect(moat(retorno: 0.169), isNull);
      expect(moat(retorno: 0.17), isNotNull);
      // A recalibragem moveu a fronteira: sob o critério anterior — dobro do
      // custo de capital — 17% reprovava e só 24% passava.
      expect(0.17, lessThan(2.0 * 0.12));
    });

    test('abaixo de 10% de custo de capital quem decide é o múltiplo', () {
      // O múltiplo e o excedente se cruzam em WACC_inf = 10%: com 8%, o
      // múltiplo pede 12% e o excedente pediria só 13% — a perna mais frouxa
      // passa a ser a do múltiplo, e é ela que impede que custo de capital
      // baixo transforme 5 p.p. de spread em vantagem declarada.
      expect(moat(retorno: 0.119, desconto: 0.08), isNull);
      expect(moat(retorno: 0.12, desconto: 0.08), isNotNull);
    });

    test('histórico curto reprova, no piso da Porta 0', () {
      expect(moat(exercicios: 7), isNull);
      expect(moat(exercicios: 8), isNotNull);
    });

    test('sem retorno do ciclo não há vantagem a preservar', () {
      expect(moat(retorno: null), isNull);
    });

    test('o veredito nomeia todas as condições que barraram', () {
      final v = GrowthGuards.residualMoat(
        cycleReturn: 0.10,
        terminalDiscountRate: 0.12,
        externalCapitalRatio: 0.90,
        periods: 5,
      );
      expect(v.isProven, isFalse);
      expect(
        v.blocks,
        containsAll(<MoatBlock>[
          MoatBlock.historicoCurto,
          MoatBlock.crescimentoInorganico,
          MoatBlock.rentabilidadeInsuficiente,
        ]),
        reason: 'avaliar em curto-circuito esconderia duas das três recusas',
      );
      expect(v.primaryBlock, MoatBlock.historicoCurto);
      expect(v.blockedOnlyByReturn, isFalse);
    });

    test('barrado só pela rentabilidade é a fronteira que a calibragem move',
        () {
      final v = GrowthGuards.residualMoat(
        cycleReturn: 0.15,
        terminalDiscountRate: 0.12,
        externalCapitalRatio: 0.10,
        periods: 14,
      );
      expect(v.blockedOnlyByReturn, isTrue);
      expect(v.passesByMultiple, isFalse);
      expect(v.passesBySpread, isFalse);
      expect(v.spread, closeTo(0.03, 1e-12));
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
        terminalDiscountRate: 0.12,
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
          incomeTaxExpense: 300 * escala,
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
          incomeTaxExpense: 360 * escala,
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
      expect(v, isNotNull);
      expect(v!.diagnostics!.moatApplied, isFalse,
          reason: 'moatApplied alimenta relatório de cobertura; varredura de '
              'diagnóstico não é veredito');
      expect(
        v.warnings.any((w) => w.contains('imposto')),
        isTrue,
        reason: 'o resultado precisa declarar que é instrumento, não avaliação',
      );
      expect(
        v.warnings.any((w) => w.contains('Vantagem competitiva comprovada')),
        isFalse,
      );
    });
  });
}

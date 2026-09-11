// Encolhimento do beta por precisão, e a desalavancagem de Hamada.
//
// O que estes testes travam é o comportamento nos **dois extremos**: um beta
// preciso decide sozinho, e um beta sem informação não decide nada. É o que
// separa este desenho da proposta que a medição de 10/09/2026 descartou —
// substituir a regressão pela mediana setorial moveria o `Ke` do ativo mediano
// em 2,13 p.p. sem ganho medido.
import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

void main() {
  const prior = BetaPrior(
    unleveredBySector: {'energia': 0.30, 'tecnologia': 1.10},
    unleveredUniverse: 0.46,
    dispersion: 0.53,
  );

  group('Hamada', () {
    test('desalavancar e realavancar fecha o ciclo', () {
      const de = 0.80, t = 0.25;
      final f = BetaShrinkage.leverageFactor(debtToEquity: de, taxRate: t)!;
      final u = BetaShrinkage.unlever(
        leveredBeta: 1.20,
        debtToEquity: de,
        taxRate: t,
      )!;
      expect(f, closeTo(1 + 0.75 * 0.80, 1e-12));
      expect(u * f, closeTo(1.20, 1e-12));
    });

    test('sem dívida o beta desalavancado é o próprio', () {
      expect(
        BetaShrinkage.unlever(leveredBeta: 0.90, debtToEquity: 0, taxRate: 0.3),
        closeTo(0.90, 1e-12),
      );
    });

    test('D/E é confinado no teto', () {
      // A AZUL3 tem D/E de 94,5, e Hamada supõe dívida sem risco: acima de
      // alguma alavancagem o capital próprio é opção sobre os ativos, e a
      // relação linear deixa de descrever. Sem teto, realavancar um prior por
      // 94,5 inventaria um beta de dezenas.
      final noTeto = BetaShrinkage.leverageFactor(
        debtToEquity: BetaShrinkage.maxDebtToEquity,
        taxRate: 0.25,
      );
      final muitoAcima =
          BetaShrinkage.leverageFactor(debtToEquity: 94.5, taxRate: 0.25);
      expect(muitoAcima, noTeto);
    });

    test('entrada não finita devolve nulo', () {
      expect(
        BetaShrinkage.unlever(
          leveredBeta: double.nan,
          debtToEquity: 0.5,
          taxRate: 0.3,
        ),
        isNull,
      );
    });
  });

  group('Encolhimento por precisão', () {
    ShrunkBeta encolher({
      required double beta,
      required double? se,
      String? setor = 'energia',
      double de = 0.0,
    }) =>
        BetaShrinkage.shrink(
          leveredBeta: beta,
          standardError: se,
          prior: prior,
          sectorKey: setor,
          debtToEquity: de,
          taxRate: 0.25,
        );

    test('beta preciso decide sozinho', () {
      // Erro-padrão de 0,07 é a mediana medida no universo, com cinco anos de
      // pregão diário. O peso resultante é 0,98.
      final r = encolher(beta: 1.20, se: 0.07);
      expect(r.weight, greaterThan(0.97));
      expect(r.beta, closeTo(1.20, 0.02));
    });

    test('beta sem informação não decide nada — o caso AZUL3', () {
      // β = 109.108 com ρ = 0,11 sobre 142 pregões dá erro-padrão de 83.228.
      final r = encolher(beta: 109108.81, se: 83227.99);
      expect(r.weight, lessThan(1e-9));
      // A tolerância é 1e-4 e não 1e-9 de propósito: o peso não é zero cravado,
      // é 4e-11, e multiplicado por um beta de 109 mil deixa um resíduo de
      // 4,4e-6. É a conta fazendo exatamente o que deve — o traço do estimador
      // sem informação some, mas não por truncamento.
      expect(r.beta, closeTo(prior.unleveredBySector['energia']!, 1e-4),
          reason: 'sem dívida, o prior alavancado é o próprio desalavancado');
    });

    test('erro-padrão ausente entrega o prior inteiro', () {
      final r = encolher(beta: 2.0, se: null);
      expect(r.weight, 0.0);
      expect(r.beta, closeTo(0.30, 1e-12));
    });

    test('o peso é monótono na precisão', () {
      double peso(double se) => encolher(beta: 1.0, se: se).weight;
      var anterior = 1.1;
      for (final se in [0.05, 0.1, 0.2, 0.4, 0.8, 1.6]) {
        final w = peso(se);
        expect(w, lessThan(anterior));
        anterior = w;
      }
    });

    test('setor desconhecido cai no prior do universo', () {
      final r = encolher(beta: 3.0, se: null, setor: 'inexistente');
      expect(r.beta, closeTo(prior.unleveredUniverse, 1e-12));
      final semSetor = encolher(beta: 3.0, se: null, setor: null);
      expect(semSetor.beta, closeTo(prior.unleveredUniverse, 1e-12));
    });

    test('o prior é realavancado para a estrutura do próprio ativo', () {
      // Duas empresas do mesmo setor com alavancagens diferentes não podem
      // receber o mesmo beta: o risco do negócio é o mesmo, o do acionista não.
      final semDivida = encolher(beta: 1.0, se: null, de: 0.0);
      final comDivida = encolher(beta: 1.0, se: null, de: 1.0);
      expect(comDivida.beta, greaterThan(semDivida.beta));
      expect(comDivida.beta, closeTo(0.30 * (1 + 0.75), 1e-12));
    });

    test('o desalavancado do próprio ativo viaja no resultado', () {
      // É ele que liga `Ke` a `WACC`, e é por isso que sai junto em vez de
      // ficar dentro da conta.
      final r = encolher(beta: 1.75, se: 0.07, de: 1.0);
      expect(r.unlevered, closeTo(1.75 / (1 + 0.75), 1e-12));
    });
  });

  group('ResolveBetaPrior.fromObservations', () {
    BetaObservation obs(double beta, String? setor, {double de = 0.0}) =>
        BetaObservation(
          leveredBeta: beta,
          sectorKey: setor,
          debtToEquity: de,
          taxRate: 0.25,
        );

    test('mediana setorial exige pares suficientes', () {
      final p = ResolveBetaPrior.fromObservations([
        obs(0.8, 'energia'), obs(0.9, 'energia'), obs(1.0, 'energia'),
        obs(2.0, 'raro'), obs(2.2, 'raro'),
      ]);
      expect(p, isNotNull);
      expect(p!.unleveredBySector.containsKey('energia'), isTrue);
      expect(p.unleveredBySector.containsKey('raro'), isFalse,
          reason: 'dois pares não sustentam mediana de setor');
      expect(p.unleveredFor('energia'), closeTo(0.9, 1e-12));
      expect(p.unleveredFor('raro'), p.unleveredUniverse);
    });

    test('a dispersão sai dos betas alavancados', () {
      final p = ResolveBetaPrior.fromObservations([
        for (final b in [0.5, 0.7, 0.9, 1.1, 1.3]) obs(b, 'energia'),
      ])!;
      expect(p.dispersion, greaterThan(0));
      // MAD escalado de {0,5..1,3} com passo 0,2: mediana 0,9, desvios
      // {0,4; 0,2; 0; 0,2; 0,4}, MAD 0,2, escalado por 1,4826.
      expect(p.dispersion, closeTo(0.2 * 1.4826, 1e-3));
    });

    test('sem observação utilizável devolve nulo', () {
      expect(ResolveBetaPrior.fromObservations(const []), isNull);
      expect(
        ResolveBetaPrior.fromObservations([obs(double.nan, 'energia')]),
        isNull,
      );
    });

    test('setor vazio conta como ausência de setor', () {
      final p = ResolveBetaPrior.fromObservations([
        obs(0.8, ''), obs(0.9, '  '), obs(1.0, null), obs(1.1, null),
      ])!;
      expect(p.unleveredBySector, isEmpty);
      expect(p.unleveredFor(''), p.unleveredUniverse);
    });
  });
}

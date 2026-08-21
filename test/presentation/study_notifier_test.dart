import 'package:equisim/data/repositories/portfolio_codec.dart';
import 'package:equisim/data/repositories/portfolio_repository.dart';
import 'package:equisim/di/providers.dart';
import 'package:equisim/presentation/study/study_notifier.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Asset assetOf(String symbol, [String sector = 'financeiro']) => Asset(
      ticker: Ticker.parse(symbol),
      name: symbol,
      sector: Sector.fromKey(sector, label: sector),
    );

Portfolio portfolioOf(
  List<Asset> assets, {
  PortfolioKind kind = PortfolioKind.principal,
}) =>
    Portfolio.equalWeighted(
      id: kind.name,
      name: kind.label,
      kind: kind,
      assets: assets,
    ).unwrap();

/// Repositório de mentira: registra o que foi salvo, sem tocar em Firestore.
class _FakePortfolioRepository implements PortfolioRepository {
  PortfolioStudy? saved;
  bool shouldFail = false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);

  @override
  Future<Result<String>> save(String userId, PortfolioStudy study) async {
    if (shouldFail) {
      return const Err(ComputationFailure('rede indisponível'));
    }
    saved = study;
    return const Ok('estudo-1');
  }
}

ProviderContainer containerWith({
  String? userId = 'usuario-1',
  PortfolioRepository? repository,
}) {
  final container = ProviderContainer(overrides: [
    currentUserIdProvider.overrideWithValue(userId),
    if (repository != null)
      portfolioRepositoryProvider.overrideWithValue(repository),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('StudyNotifier — edição síncrona', () {
    test('começa vazio e sem erro', () {
      final container = containerWith();
      final state = container.read(studyProvider);
      expect(state.study.principal.isEmpty, isTrue);
      expect(state.study.reserva.isEmpty, isTrue);
      expect(state.lastError, isNull);
    });

    test('adicionar ativo reequipondera a carteira', () {
      final container = containerWith();
      final notifier = container.read(studyProvider.notifier);

      notifier.addAsset(assetOf('PETR4', 'energia'), toPrincipal: true);
      notifier.addAsset(assetOf('VALE3', 'materiais'), toPrincipal: true);

      final principal = container.read(studyProvider).study.principal;
      expect(principal.length, 2);
      expect(Weights.sumsToOne(principal.weights), isTrue);
      for (final w in principal.weights) {
        expect(w.value, closeTo(0.5, 1e-9));
      }
    });

    test('promover ativo move entre as carteiras e reequipondera as duas', () {
      final container = containerWith();
      final notifier = container.read(studyProvider.notifier);

      notifier.addAsset(assetOf('PETR4', 'energia'), toPrincipal: true);
      notifier.addAsset(assetOf('VALE3', 'materiais'), toPrincipal: true);
      notifier.addAsset(assetOf('ITUB4'), toPrincipal: false);

      notifier.swap(ticker: Ticker.parse('ITUB4'), toPrincipal: true);

      final study = container.read(studyProvider).study;
      expect(study.principal.length, 3);
      expect(study.reserva.length, 0);
      expect(Weights.sumsToOne(study.principal.weights), isTrue);
    });

    test('erro de operação vira mensagem, não exceção', () {
      final container = containerWith();
      final notifier = container.read(studyProvider.notifier);

      notifier.swap(ticker: Ticker.parse('PETR4'), toPrincipal: true);

      expect(container.read(studyProvider).lastError, isNotNull);
      expect(container.read(studyProvider).lastError, contains('PETR4'));
    });

    test('teto de 15 ativos é recusado com mensagem clara', () {
      final container = containerWith();
      final notifier = container.read(studyProvider.notifier);

      for (var i = 0; i < 15; i++) {
        notifier.addAsset(assetOf('AAAA$i'), toPrincipal: true);
      }
      expect(container.read(studyProvider).study.principal.length, 15);

      notifier.addAsset(assetOf('BBBB1'), toPrincipal: true);
      expect(container.read(studyProvider).study.principal.length, 15);
      expect(container.read(studyProvider).lastError, contains('15'));
    });

    test('pesos customizados exigem soma de 100%', () {
      final container = containerWith();
      final notifier = container.read(studyProvider.notifier);
      notifier.addAsset(assetOf('PETR4', 'energia'), toPrincipal: true);
      notifier.addAsset(assetOf('VALE3', 'materiais'), toPrincipal: true);

      notifier.setWeights(
        {Ticker.parse('PETR4'): 0.6, Ticker.parse('VALE3'): 0.3},
        onPrincipal: true,
      );
      expect(container.read(studyProvider).lastError, contains('90.00%'));

      notifier.setWeights(
        {Ticker.parse('PETR4'): 0.7, Ticker.parse('VALE3'): 0.3},
        onPrincipal: true,
      );
      final state = container.read(studyProvider);
      expect(state.lastError, isNull);
      expect(
        state.study.principal.entries[Ticker.parse('PETR4')]!.weight.value,
        closeTo(0.7, 1e-9),
      );
    });

    test('equalizar restaura pesos iguais após edição manual', () {
      final container = containerWith();
      final notifier = container.read(studyProvider.notifier);
      notifier.addAsset(assetOf('PETR4', 'energia'), toPrincipal: true);
      notifier.addAsset(assetOf('VALE3', 'materiais'), toPrincipal: true);
      notifier.setWeights(
        {Ticker.parse('PETR4'): 0.9, Ticker.parse('VALE3'): 0.1},
        onPrincipal: true,
      );

      notifier.equalize(onPrincipal: true);

      for (final w in container.read(studyProvider).study.principal.weights) {
        expect(w.value, closeTo(0.5, 1e-9));
      }
    });
  });

  group('Concentração setorial reativa', () {
    test('acompanha cada alteração da carteira sem chamada explícita', () {
      final container = containerWith();
      final notifier = container.read(studyProvider.notifier);

      expect(container.read(concentrationProvider).hasAlert, isFalse);

      notifier.addAsset(assetOf('ITUB4', 'financeiro'), toPrincipal: true);
      expect(container.read(concentrationProvider).hasAlert, isFalse);

      notifier.addAsset(assetOf('BBAS3', 'financeiro'), toPrincipal: true);
      final report = container.read(concentrationProvider);
      expect(report.hasAlert, isTrue);
      expect(report.concentrated.first.sector.key, 'financeiro');
      expect(report.concentrated.first.count, 2);
    });

    test('o alerta some quando o ativo é rebaixado para a reserva', () {
      final container = containerWith();
      final notifier = container.read(studyProvider.notifier);
      notifier.addAsset(assetOf('ITUB4', 'financeiro'), toPrincipal: true);
      notifier.addAsset(assetOf('BBAS3', 'financeiro'), toPrincipal: true);
      expect(container.read(concentrationProvider).hasAlert, isTrue);

      notifier.swap(ticker: Ticker.parse('BBAS3'), toPrincipal: false);
      expect(container.read(concentrationProvider).hasAlert, isFalse);
    });

    test('não bloqueia a operação, apenas sinaliza', () {
      final container = containerWith();
      final notifier = container.read(studyProvider.notifier);
      notifier.addAsset(assetOf('ITUB4', 'financeiro'), toPrincipal: true);
      notifier.addAsset(assetOf('BBAS3', 'financeiro'), toPrincipal: true);
      notifier.addAsset(assetOf('SANB11', 'financeiro'), toPrincipal: true);

      expect(container.read(studyProvider).study.principal.length, 3);
      expect(container.read(studyProvider).lastError, isNull,
          reason: 'concentrar é decisão do investidor, não erro');
      expect(container.read(concentrationProvider).hasAlert, isTrue);
    });
  });

  group('StudyNotifier — persistência', () {
    test('salvar exige usuário autenticado', () async {
      final container = containerWith(userId: null);
      final ok = await container.read(studyProvider.notifier).save();
      expect(ok, isFalse);
      expect(container.read(studyProvider).lastError, contains('login'));
    });

    test('salvar guarda o identificador devolvido', () async {
      final repository = _FakePortfolioRepository();
      final container = containerWith(repository: repository);
      final notifier = container.read(studyProvider.notifier);
      notifier.addAsset(assetOf('PETR4', 'energia'), toPrincipal: true);

      final ok = await notifier.save();
      expect(ok, isTrue);
      expect(container.read(studyProvider).study.id, 'estudo-1');
      expect(repository.saved!.principal.length, 1);
    });

    test('falha ao salvar não perde o estado editado', () async {
      final repository = _FakePortfolioRepository()..shouldFail = true;
      final container = containerWith(repository: repository);
      final notifier = container.read(studyProvider.notifier);
      notifier.addAsset(assetOf('PETR4', 'energia'), toPrincipal: true);

      final ok = await notifier.save();
      expect(ok, isFalse);
      expect(container.read(studyProvider).study.principal.length, 1);
      expect(container.read(studyProvider).isSaving, isFalse);
      expect(container.read(studyProvider).lastError, isNotNull);
    });
  });

  group('Serialização do estudo', () {
    test('carteira sobrevive à ida e volta', () {
      final original = portfolioOf([
        assetOf('PETR4', 'energia'),
        assetOf('VALE3', 'materiais'),
        assetOf('ITUB4', 'financeiro'),
      ]);

      final restored = PortfolioStudyCodec.decodePortfolio(
        PortfolioStudyCodec.encodePortfolio(original),
        id: 'principal',
        name: 'Principal',
        kind: PortfolioKind.principal,
      );

      expect(restored.length, original.length);
      expect(restored.tickers, original.tickers);
      for (final ticker in original.tickers) {
        expect(
          restored.entries[ticker]!.weight.value,
          closeTo(original.entries[ticker]!.weight.value, 1e-12),
        );
        expect(
          restored.entries[ticker]!.sector.key,
          original.entries[ticker]!.sector.key,
        );
      }
      expect(Weights.sumsToOne(restored.weights), isTrue);
    });

    test('meta viaja em centavos e não perde precisão', () {
      final goal = FinancialGoal(
        initialContribution: Money.fromReais(10000.55),
        monthlyContribution: Money.fromReais(1500.33),
        months: 120,
        targetWealth: Money.fromReais(999999.99),
      );

      final restored =
          PortfolioStudyCodec.decodeGoal(PortfolioStudyCodec.encodeGoal(goal))!;

      expect(restored.initialContribution.cents, goal.initialContribution.cents);
      expect(restored.monthlyContribution.cents, goal.monthlyContribution.cents);
      expect(restored.targetWealth.cents, goal.targetWealth.cents);
      expect(restored.months, goal.months);
    });

    test('ativo sem setor sobrevive sem inventar classificação', () {
      final portfolio = Portfolio.equalWeighted(
        id: 'p',
        name: 'Principal',
        kind: PortfolioKind.principal,
        assets: [Asset(ticker: Ticker.parse('XXXX3'), name: 'XXXX3')],
      ).unwrap();

      final restored = PortfolioStudyCodec.decodePortfolio(
        PortfolioStudyCodec.encodePortfolio(portfolio),
        id: 'p',
        name: 'Principal',
        kind: PortfolioKind.principal,
      );
      expect(
        restored.entries[Ticker.parse('XXXX3')]!.sector.isUnknown,
        isTrue,
      );
    });

    test('documento corrompido não derruba a leitura', () {
      final restored = PortfolioStudyCodec.decodePortfolio(
        [
          {'ticker': 'PETR4', 'weight': 0.5, 'name': 'PETR4'},
          {'ticker': 'INVALIDO!!', 'weight': 0.3},
          {'weight': 0.2},
          'lixo',
        ],
        id: 'p',
        name: 'Principal',
        kind: PortfolioKind.principal,
      );
      expect(restored.length, 1);
      expect(restored.tickers.first.value, 'PETR4');
    });

    test('meta ausente devolve nulo em vez de valores zerados', () {
      expect(PortfolioStudyCodec.decodeGoal(null), isNull);
      expect(PortfolioStudyCodec.decodeGoal('lixo'), isNull);
      expect(PortfolioStudyCodec.decodeGoal(<String, dynamic>{}), isNull);
    });
  });
}

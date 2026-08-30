import 'package:equisim/data/repositories/portfolio_repository.dart';
import 'package:equisim/di/providers.dart';
import 'package:equisim/presentation/backtest/backtest_page.dart';
import 'package:equisim/presentation/backtest/backtest_providers.dart';
import 'package:equisim/presentation/goals/goal_page.dart';
import 'package:equisim/presentation/shared/theme_bridge.dart';
import 'package:equisim/presentation/shell/app_shell.dart';
import 'package:equisim/presentation/study/study_notifier.dart';
import 'package:equisim/presentation/study/study_page.dart';
import 'package:equisim/presentation/theme/fin_theme.dart';
import 'package:equisim/presentation/valuation/valuation_page.dart';
import 'package:equisim/presentation/valuation/valuation_providers.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'populated_state.dart' show comparisonOf, outcomeOf;
import 'ui_test.dart' show serieLonga;

/// Regressao de layout: nenhuma tela pode estourar em largura suportada nem
/// sob escala de texto ampliada.
///
/// A matriz cruza as tres larguras alvo do projeto com as tres escalas que
/// importam: 1,0x o padrao, 1,3x o primeiro passo comum no Android e no iOS, e
/// 2,0x o teto que o Android oferece em acessibilidade.
///
/// Escrito ANTES das correcoes, e reprovou 13 das 36 combinacoes na primeira
/// execucao. Um teste de regressao que nasce verde nao provou nada.
const _larguras = <double>[320, 390, 1024];
const _escalas = <double>[1.0, 1.3, 2.0];

/// Combinacoes que o codigo ainda nao sustenta.
///
/// **Vazio, e essa e a meta.** Cada entrada aqui e divida MEDIDA -- uma
/// combinacao que reprovou de fato -- com a tarefa que a remove escrita ao
/// lado, e apagar a linha e o criterio de aceite dessa tarefa.
///
/// Historico: nasceu com 13 das 36 combinacoes reprovando. A UI-06 zerou as
/// sete da StudyPage; a UI-16 zerou as seis restantes. Se uma entrada voltar a
/// aparecer, ela e regressao, nao heranca.
const _pendentes = <String, String>{};

/// Divida MEDIDA da BacktestPage populada, no mesmo formato de [_pendentes].
///
/// **Vazio, e essa e a meta -- mesmo criterio de [_pendentes].**
///
/// Historico: nasceu com duas entradas, as duas do `_AssetRow` no cartao de
/// desempenho por ativo -- 7 px em 320 dp @ 1,3x e 65 px em 390 dp @ 2,0x.
/// Eram HERANCA, nao regressao: a matriz nunca cobrira o estado populado,
/// entao o estouro existia sem nunca ter sido medido. Foram removidas quando
/// `_AssetRow` ganhou a disposicao empilhada, que preserva os dois numeros
/// inteiros onde as tres colunas nao cabem.
const _pendentesPopulada = <String, String>{};

String _chave(String tela, double largura, double escala) =>
    '$tela|${largura.toInt()}|$escala';

Asset _asset(String symbol, String sector) => Asset(
  ticker: Ticker.parse(symbol),
  name: symbol,
  sector: Sector.fromKey(sector, label: sector),
);

/// Substitui tudo que tocaria rede, Firestore ou disco.
///
/// LIMITE CONHECIDO E IMPORTANTE: os providers remotos devolvem `null` ou
/// vazio, entao as telas montam em estado VAZIO. `_ComparisonBody`,
/// `_MetricsCard`, `_DividendsCard`, `_PerAssetCard` e os graficos nao chegam
/// a ser construidos -- ou seja, esta matriz NAO cobre as telas populadas, que
/// e onde as colunas numericas densas vivem.
///
/// O que ela cobre ja pegou defeito real (cinco combinacoes da GoalPage e uma
/// da BacktestPage estouram so com formulario e estado vazio).
///
/// A BacktestPage POPULADA saiu desse limite: o grupo do fim do arquivo monta
/// `PortfolioComparison` de verdade e cobre a mesma matriz. Foi o que a tabela
/// comparativa das duas carteiras exigiu -- ela e a coluna numerica mais densa
/// do aplicativo, e a suite nao podia ficar cega justamente ali. StudyPage,
/// GoalPage e ValuationPage seguem cobertas so em estado vazio.
/// [comparacao] entra pelo parametro, e nao por um override adicional na
/// chamada: `comparisonProvider` ja e sobrescrito aqui, e o Riverpod recusa o
/// mesmo provider duas vezes no mesmo container. `null` reproduz o estado
/// vazio, que e o padrao da matriz.
List<Override> _overrides({PortfolioComparison? comparacao}) => <Override>[
  currentUserIdProvider.overrideWithValue(null),
  marketAnchorsProvider.overrideWith((ref) async => MarketAnchors.fallback2026),
  savedStudiesProvider.overrideWith((ref) async => const <PortfolioStudy>[]),
  valuationProvider.overrideWith((ref, ticker) async => null),
  portfolioValuationsProvider.overrideWith(
    (ref) async => const <Ticker, ValuationResult>{},
  ),
  netDividendYieldsProvider.overrideWith(
    (ref) async => const <Ticker, double>{},
  ),
  comparisonProvider.overrideWith((ref) async => comparacao),
  correlationProvider.overrideWith((ref) async => null),
  goalAlignmentProvider.overrideWith((ref) async => null),
  goalFeasibilityProvider.overrideWith((ref) async => null),
];

Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  required double largura,
  required double escala,
  bool comAtivos = false,
  PortfolioComparison? comparacao,
}) async {
  tester.view.devicePixelRatio = 1.0;
  // Altura generosa quando a tela vem populada: o `SliverList` so infla os
  // cartoes que entram na viewport, e um estouro fora dela nao seria visto.
  tester.view.physicalSize = Size(largura, comparacao == null ? 900 : 6000);
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: _overrides(comparacao: comparacao),
  );
  addTearDown(container.dispose);

  // O provider de tema e um StateProvider comum; sem semear, a tela monta no
  // padrao e o teste ainda vale -- mas semear mantem o par tema/paleta
  // coerente com o que `buildFinTheme` entrega.
  container.read(isLightModeProvider.notifier).definir(true);

  if (comAtivos) {
    final notifier = container.read(studyProvider.notifier);
    notifier.addAsset(_asset('PETR4', 'energia'), toPrincipal: true);
    notifier.addAsset(_asset('VALE3', 'materiais'), toPrincipal: true);
    notifier.addAsset(_asset('ITUB4', 'financeiro'), toPrincipal: true);
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildFinTheme(isLight: true),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(largura, 900),
            textScaler: TextScaler.linear(escala),
          ),
          child: Scaffold(body: page),
        ),
      ),
    ),
  );

  await tester.pumpAndSettle();
}

void main() {
  final telas = <String, ({Widget Function() build, bool comAtivos})>{
    // A casca entrou na matriz quando o pacote UI-1 lhe deu uma QUARTA aba:
    // cada rotulo passou a ter um quarto da largura, e "Simulacao" em 320 dp
    // sob escala ampliada e o caso limite. Sem cobertura, a barra seria o
    // unico componente da tela que ninguem mede.
    'AppShell': (build: AppShell.new, comAtivos: true),
    'StudyPage': (build: StudyPage.new, comAtivos: true),
    'BacktestPage': (build: BacktestPage.new, comAtivos: true),
    'GoalPage': (build: GoalPage.new, comAtivos: false),
    'ValuationPage': (
      build: () => ValuationPage(ticker: Ticker.parse('PETR4')),
      comAtivos: false,
    ),
  };

  for (final entry in telas.entries) {
    group(entry.key, () {
      for (final largura in _larguras) {
        for (final escala in _escalas) {
          final pendente = _pendentes[_chave(entry.key, largura, escala)];

          testWidgets(
            // O motivo vai no NOME porque `testWidgets.skip` e booleano, ao
            // contrario de `test.skip`. Assim a saida da suite diz qual tarefa
            // destrava cada combinacao, em vez de so contar pulos.
            'cabe em ${largura.toInt()} dp sob ${escala}x'
            '${pendente == null ? '' : '  [PENDENTE: $pendente]'}',
            (tester) async {
              await _pump(
                tester,
                entry.value.build(),
                largura: largura,
                escala: escala,
                comAtivos: entry.value.comAtivos,
              );

              expect(
                tester.takeException(),
                isNull,
                reason:
                    '${entry.key} estourou o layout em '
                    '${largura.toInt()} dp sob escala ${escala}x.',
              );
            },
            skip: pendente != null,
          );
        }
      }
    });
  }

  // ---------------------------------------------------------------------
  // BacktestPage POPULADA
  //
  // A tela vazia nao constroi `_CarteirasLadoALado` nem `_ProventosLadoALado`,
  // que sao onde vivem as colunas numericas. Sem este grupo, a tabela
  // comparativa entraria no repositorio sem prova nenhuma de que cabe.
  //
  // Nao ha entrada esperada em `_pendentes`: a tabela CAI PARA BLOCOS
  // EMPILHADOS quando a largura nao sustenta as colunas, entao nenhuma
  // combinacao deve estourar. Se alguma estourar, o degrau nao esta
  // funcionando -- e e defeito, nao heranca.
  // ---------------------------------------------------------------------
  group('BacktestPage populada', () {
    for (final largura in _larguras) {
      for (final escala in _escalas) {
        final pendente =
            _pendentesPopulada[_chave('BacktestPage', largura, escala)];

        testWidgets('cabe em ${largura.toInt()} dp sob ${escala}x'
            '${pendente == null ? '' : '  [PENDENTE: $pendente]'}', (
          tester,
        ) async {
          await _pump(
            tester,
            const BacktestPage(),
            largura: largura,
            escala: escala,
            comAtivos: true,
            comparacao: comparisonOf(
              principal: outcomeOf('PETR4', serieLonga(0.05)),
              reserva: outcomeOf('ITUB4', serieLonga(0.12)),
            ),
          );

          expect(
            tester.takeException(),
            isNull,
            reason:
                'BacktestPage populada estourou o layout em '
                '${largura.toInt()} dp sob escala ${escala}x.',
          );
        }, skip: pendente != null);
      }
    }
  });
}

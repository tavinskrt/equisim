/// CAPTURA DE TELA para a lente `tela` do conselheiro.
///
///     npm run ui:capturar
///
/// Nao e teste de regressao visual. Nao ha golden a comparar e nada aqui
/// reprova: o objetivo e PRODUZIR as imagens que o conselheiro vai olhar. Por
/// isso roda sempre com `--update-goldens`, e por isso vive separado de
/// `overflow_test.dart` -- aquela e suite que passa, e nao deve quebrar porque
/// um carregamento de fonte mudou.
///
/// POR QUE O NOME NAO TERMINA EM `_test.dart`: e o que o mantem FORA do
/// `flutter test`. A descoberta padrao procura `test/**_test.dart`, entao este
/// arquivo so roda quando chamado pelo caminho, como faz o `ui:capturar`.
///
/// A razao e concreta, nao teorica. Enquanto ele se chamava `_test.dart`,
/// qualquer alteracao INTENCIONAL de interface deixava `flutter test`
/// vermelho: a comparacao de golden acusava diferenca contra as capturas
/// antigas. Aconteceu na correcao do truncamento das colunas -- oito falhas,
/// nenhuma real, todas resolvidas por regerar as imagens. Um portao que fica
/// vermelho por trabalho legitimo e um portao que sera arrancado, e a
/// reconstrucao da UI que vem pela frente mexeria nessas telas a cada rodada.
///
/// O que se abre mao: deteccao automatica de regressao visual. Ela tem valor,
/// mas nao estava sendo usada como tal -- e o conselheiro olha as capturas de
/// qualquer forma, com julgamento que a comparacao de pixels nao tem.
///
/// DUAS COISAS SEM AS QUAIS ESTE ARQUIVO NAO SERVE PARA NADA:
///
/// 1. FONTE REAL. `FinTypography._family` e `null`, ou seja, o aplicativo usa a
///    fonte padrao da plataforma. Em `flutter test` nao ha fonte padrao
///    carregada e todo texto sai como caixa vazia. Critica de hierarquia
///    tipografica sobre captura sem texto nao e so inutil: e enganosa.
///
/// 2. ESTADO POPULADO. Ver `populated_state.dart`. A matriz de estouro monta as
///    telas vazias de proposito; capturar assim levaria o conselheiro a
///    concluir que a interface e limpa porque o conteudo nunca apareceu.
library;

import 'dart:io';

import 'package:equisim/presentation/backtest/backtest_page.dart';
import 'package:equisim/presentation/goals/goal_page.dart';
import 'package:equisim/presentation/shared/theme_bridge.dart';
import 'package:equisim/presentation/shell/app_shell.dart';
import 'package:equisim/presentation/study/study_notifier.dart';
import 'package:equisim/presentation/study/study_page.dart';
import 'package:equisim/presentation/theme/fin_theme.dart';
import 'package:equisim/presentation/valuation/valuation_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'populated_state.dart';

/// Larguras capturadas. As mesmas de `overflow_test.dart`, de proposito: se
/// uma tela estoura em 320 la, a captura daqui mostra COMO ela estoura.
const _larguras = <double>[320, 390, 1024];

/// Altura generosa: a captura pega a tela inteira, nao a dobra visivel. Cortar
/// no rodape esconderia justamente o que costuma ficar mal resolvido.
const _altura = 1600.0;

/// Escala de texto fixa em 1.0.
///
/// 1.3 e 2.0 sao verificacao de ACESSIBILIDADE, e `overflow_test.dart` ja as
/// cobre com assercao -- que e a ferramenta certa: uma assercao diz "estourou",
/// uma imagem exige alguem olhar. Multiplicar as capturas por tres escalas
/// triplicaria o material do conselheiro sem acrescentar pergunta de direcao.
const _escala = 1.0;

/// Carrega Roboto do proprio SDK do Flutter.
///
/// Vem de `FLUTTER_ROOT`, que o `flutter test` injeta, em vez de um TTF
/// versionado: evita meio megabyte de binario no repositorio e garante que a
/// fonte usada na captura seja a mesma que o SDK entrega ao aplicativo.
///
/// Se a variavel nao existir, GRITA e segue. Falhar em silencio aqui produziria
/// trinta imagens de caixinhas com aparencia de sucesso.
Future<bool> _carregarFontes() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null || root.isEmpty) {
    stderr.writeln(
      '\n!!! FLUTTER_ROOT ausente -- as fontes NAO foram carregadas.\n'
      '!!! As capturas sairao com caixas no lugar do texto e nao servem\n'
      '!!! para analise. Rode via `npm run ui:capturar`.\n',
    );
    return false;
  }

  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) {
    stderr.writeln('\n!!! Fontes do SDK nao encontradas em ${dir.path}\n');
    return false;
  }

  // O aplicativo usa a familia padrao da plataforma, que em teste resolve para
  // "Roboto". Registrar sob esse nome faz o texto renderizar sem tocar no tema.
  final texto = FontLoader('Roboto');
  for (final peso in ['regular', 'medium', 'bold']) {
    final arquivo = File('${dir.path}/roboto-$peso.ttf');
    if (arquivo.existsSync()) {
      texto.addFont(Future.value(arquivo.readAsBytesSync().buffer.asByteData()));
    }
  }
  await texto.load();

  // MaterialIcons e tao necessario quanto o texto. Sem ele todo icone vira
  // caixa vazia, e a lente `tela` reportaria "caixas por toda parte" como
  // achado -- artefato da captura, nao defeito da interface. E a mesma classe
  // de erro que material incompleto ja produziu na lente `registro`.
  final icones = File('${dir.path}/materialicons-regular.otf');
  if (icones.existsSync()) {
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(icones.readAsBytesSync().buffer.asByteData()));
    await loader.load();
  } else {
    stderr.writeln('\n!!! MaterialIcons ausente -- icones sairao em caixas.\n');
    return false;
  }

  return true;
}

/// Um alvo de captura: como montar e como se chama no disco.
typedef Alvo = ({String nome, Widget Function() build, bool comAtivos});

final _alvos = <Alvo>[
  // A casca vem PRIMEIRO e importa mais que as telas soltas: e nela que vivem
  // os rotulos das abas e a relacao entre as frentes de trabalho, que e
  // exatamente o objeto da lente `tela`.
  (nome: 'shell', build: AppShell.new, comAtivos: true),
  (nome: 'estudo', build: StudyPage.new, comAtivos: true),
  (nome: 'backtest', build: BacktestPage.new, comAtivos: true),
  (nome: 'meta', build: GoalPage.new, comAtivos: false),
  // A ABA, e nao a tela empilhada: e o caminho que o pacote UI-1 abriu, e e
  // ele que a lente precisa examinar. `comAtivos` porque sem carteira montada
  // a aba mostra so o estado vazio.
  (nome: 'valuation', build: ValuationTab.new, comAtivos: true),
];

Future<void> _montar(
  WidgetTester tester,
  Alvo alvo, {
  required double largura,
  required bool claro,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(largura, _altura);
  addTearDown(tester.view.reset);

  final container = ProviderContainer(overrides: populatedOverrides());
  addTearDown(container.dispose);
  container.read(isLightModeProvider.notifier).definir(claro);

  if (alvo.comAtivos) {
    final notifier = container.read(studyProvider.notifier);
    for (final (simbolo, setor) in carteiraDemo) {
      notifier.addAsset(assetOf(simbolo, setor), toPrincipal: true);
    }
    // A meta tambem, e nao so os ativos: sem ela a aba Analise nao tem prazo
    // com que confrontar a janela, e a captura mostraria a tela com o
    // confronto de horizontes ausente -- exatamente o estado que a lente
    // leria como "a interface nao declara a relacao".
    notifier.setGoal(metaDemo);
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildFinTheme(isLight: claro),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(largura, _altura),
            textScaler: const TextScaler.linear(_escala),
          ),
          // A casca ja traz o proprio Scaffold; embrulhar de novo criaria uma
          // segunda barra e falsearia a captura.
          child: alvo.nome == 'shell'
              ? alvo.build()
              : Scaffold(body: alvo.build()),
        ),
      ),
    ),
  );

  // `pumpAndSettle` estoura em tela com animacao perpetua. Um numero fixo de
  // quadros resolve os `FutureProvider` e nao trava: a captura e best-effort.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  late bool comFonte;

  setUpAll(() async {
    comFonte = await _carregarFontes();
  });

  for (final alvo in _alvos) {
    group(alvo.nome, () {
      for (final claro in [true, false]) {
        final tema = claro ? 'claro' : 'escuro';
        for (final largura in _larguras) {
          testWidgets('$tema @ ${largura.toInt()}dp', (tester) async {
            expect(
              comFonte,
              isTrue,
              reason: 'Sem fonte real a captura sai em caixas e nao serve.',
            );
            await _montar(tester, alvo, largura: largura, claro: claro);
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile(
                '../../docs/telas/$tema/${alvo.nome}@${largura.toInt()}.png',
              ),
            );
          });
        }
      }
    });
  }
}

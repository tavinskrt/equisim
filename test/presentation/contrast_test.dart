import 'package:equisim/presentation/theme/fin_colors.dart';
import 'package:equisim/presentation/theme/fin_theme.dart';
import 'package:equisim/presentation/theme/fin_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Piso de contraste exigido de cada token de tinta.
///
/// O `switch` e **exaustivo**: acrescentar um valor a [FinInkToken] quebra a
/// compilacao deste arquivo ate que o piso do token novo seja declarado aqui.
/// E o que impede uma cor de texto de entrar no sistema sem medicao.
///
/// AAA (7:1) para o que carrega decisao. AA (4,5:1) para os tres estados de
/// menor frequencia e para o metadado.
///
/// [FinInkToken.textTertiary] fica em AA de proposito: manter tres niveis de
/// hierarquia de texto e exigir AAA nos tres e impossivel -- o terceiro nivel
/// teria de escurecer tanto que deixaria de se distinguir do segundo. O que
/// torna isso aceitavel e a restricao de uso, documentada em [FinColors]:
/// nenhum valor monetario, percentual ou de estado usa esse token.
double _minimumRatio(FinInkToken token) => switch (token) {
      FinInkToken.textPrimary => 7.0,
      FinInkToken.textSecondary => 7.0,
      FinInkToken.negative => 7.0,
      FinInkToken.caution => 7.0,
      FinInkToken.textTertiary => 4.5,
      FinInkToken.positive => 4.5,
      FinInkToken.pending => 4.5,
      FinInkToken.blocked => 4.5,
    };

/// Razao de contraste WCAG 2.1 entre duas cores opacas.
///
/// Usa [Color.computeLuminance] do proprio SDK, que implementa a luminancia
/// relativa da especificacao -- linearizacao por canal e potencia de 2.4.
/// Reimplementar isso a mao e onde o calculo costuma sair errado.
double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

String _hex(Color c) {
  final v = c.toARGB32() & 0xFFFFFF;
  return '#${v.toRadixString(16).toUpperCase().padLeft(6, '0')}';
}

void main() {
  group('Contraste da paleta', () {
    for (final (themeName, palette) in <(String, FinColors)>[
      ('claro', FinColors.light),
      ('escuro', FinColors.dark),
    ]) {
      group('tema $themeName', () {
        for (final token in FinInkToken.values) {
          test('${token.name} atinge o piso em toda superficie', () {
            final ink = palette.ink(token);
            final floor = _minimumRatio(token);
            final surfaces = palette.surfacesFor(token);

            // Medir contra branco apenas e otimista em cerca de meio ponto: e
            // o que fazia a paleta anterior parecer estar em AAA quando, sobre
            // o fundo rebaixado, estava em AA. Cada superficie da lista e um
            // lugar onde o token realmente aparece.
            for (final surface in surfaces) {
              final ratio = _contrastRatio(ink, surface);
              expect(
                ratio,
                greaterThanOrEqualTo(floor),
                reason: 'Tema $themeName: ${token.name} ${_hex(ink)} sobre '
                    '${_hex(surface)} da ${ratio.toStringAsFixed(2)}:1, '
                    'abaixo do piso de ${floor.toStringAsFixed(1)}:1.\n'
                    'Se a cor mudou de proposito, remeça e atualize o '
                    'comentario de razao em fin_colors.dart.',
              );
            }
          });
        }

        test('todo token de tinta foi coberto', () {
          // Guarda contra o caso de alguem remover tokens do enum e o laco
          // acima passar por vacuidade.
          expect(FinInkToken.values, isNotEmpty);
          expect(
            FinInkToken.values.length,
            8,
            reason: 'A contagem de tokens mudou. Confirme que o piso do token '
                'novo foi declarado em _minimumRatio e que o comentario de '
                'razao em fin_colors.dart traz a medida do pior caso.',
          );
        });
      });
    }

    test('a marca nao e token de tinta', () {
      // `brand` reprova contraste como texto (2,71:1 sobre branco) e por isso
      // nao pode entrar em FinInkToken. Ele existe para preenchimento e icone.
      // Este teste documenta a exclusao para que ela nao seja desfeita por
      // engano.
      expect(
        _contrastRatio(FinColors.light.brand, FinColors.light.surface),
        lessThan(4.5),
        reason: 'Se a marca passou a ter contraste de texto, a exclusao pode '
            'ser revista -- mas conscientemente, nao por acidente.',
      );
    });
  });

  group('Escala tipografica', () {
    final type = FinTypography.standard();

    test('todo papel numerico carrega cifras tabulares', () {
      for (final style in type.numericStyles) {
        expect(
          style.fontFeatures,
          contains(const FontFeature.tabularFigures()),
          reason: 'Papel num* sem tabularFigures desalinha a virgula decimal '
              'de uma linha para a outra em coluna alinhada a direita.',
        );
      }
    });

    test('nenhum tamanho e fracionario', () {
      for (final style in [...type.numericStyles, ...type.proseStyles]) {
        final size = style.fontSize!;
        expect(
          size, size.roundToDouble(),
          reason: 'Meio pixel nao e um degrau perceptivel de hierarquia. A '
              'base anterior tinha oito tamanhos fracionarios, todos vindos '
              'de ajuste ate caber.',
        );
      }
    });

    test('nenhum tamanho fica abaixo de 11 px', () {
      for (final style in [...type.numericStyles, ...type.proseStyles]) {
        expect(style.fontSize, greaterThanOrEqualTo(11.0));
      }
    });
  });

  group('Montagem do tema', () {
    testWidgets('as extensoes chegam ao contexto nos dois temas',
        (tester) async {
      for (final isLight in [true, false]) {
        late FinColors seenColors;
        late FinTypography seenType;

        await tester.pumpWidget(
          MaterialApp(
            theme: buildFinTheme(isLight: isLight),
            home: Builder(
              builder: (context) {
                seenColors = context.fin;
                seenType = context.finType;
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        // `MaterialApp` envolve a arvore em `AnimatedTheme`. Sem assentar, a
        // segunda volta do laco leria a paleta ainda a meio caminho entre os
        // dois temas -- e o `lerp` discreto devolveria a anterior.
        await tester.pumpAndSettle();

        expect(seenColors, isLight ? FinColors.light : FinColors.dark);
        expect(seenType.numSm.fontFeatures,
            contains(const FontFeature.tabularFigures()));
      }
    });

    testWidgets('o indicador de progresso herda a marca, nao o azul do Material',
        (tester) async {
      // Regressao direta do defeito A-1: cinco CircularProgressIndicator sem
      // cor explicita giravam em azul M3 sobre telas verdes, porque o tema era
      // semeado em Colors.blue.
      await tester.pumpWidget(
        MaterialApp(
          theme: buildFinTheme(isLight: true),
          home: const Scaffold(body: CircularProgressIndicator()),
        ),
      );

      final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      final context = tester.element(find.byType(CircularProgressIndicator));

      expect(
        indicator.color ?? ProgressIndicatorTheme.of(context).color,
        FinColors.light.brand,
      );
    });
  });

  group('Pontos de quebra', () {
    test('classificam as larguras alvo', () {
      expect(FinBreakpoint.of(320), FinBreakpoint.compact);
      expect(FinBreakpoint.of(375), FinBreakpoint.compact);
      expect(FinBreakpoint.of(599), FinBreakpoint.compact);
      expect(FinBreakpoint.of(600), FinBreakpoint.medium);
      expect(FinBreakpoint.of(768), FinBreakpoint.medium);
      expect(FinBreakpoint.of(899), FinBreakpoint.medium);
      expect(FinBreakpoint.of(900), FinBreakpoint.expanded);
      expect(FinBreakpoint.of(1440), FinBreakpoint.expanded);
    });
  });
}

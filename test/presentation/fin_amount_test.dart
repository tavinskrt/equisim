import 'package:equisim/presentation/components/fin_amount.dart';
import 'package:equisim/presentation/theme/fin_colors.dart';
import 'package:equisim/presentation/theme/fin_theme.dart';
import 'package:equisim/presentation/theme/fin_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, {bool isLight = true, double textScale = 1.0}) =>
    MaterialApp(
      theme: buildFinTheme(isLight: isLight),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(body: child),
      ),
    );

void main() {
  group('FinAmount.trendOf', () {
    test('separa ganho, perda e zero', () {
      expect(FinAmount.trendOf(0.12), FinTrend.positive);
      expect(FinAmount.trendOf(-0.03), FinTrend.negative);
      expect(FinAmount.trendOf(0), FinTrend.neutral);
    });

    test('zero nao e ganho', () {
      // Pintar de verde uma variacao nula diria ao investidor que houve alta
      // onde nao houve nada.
      expect(FinAmount.trendOf(0.0), isNot(FinTrend.positive));
    });

    test('ausencia e nao-finito viram bloqueado', () {
      expect(FinAmount.trendOf(null), FinTrend.blocked);
      expect(FinAmount.trendOf(double.nan), FinTrend.blocked);
      expect(FinAmount.trendOf(double.infinity), FinTrend.blocked);
      expect(FinAmount.trendOf(double.negativeInfinity), FinTrend.blocked);
    });
  });

  group('FinAmount — renderizacao', () {
    testWidgets('pinta o valor com a cor da direcao', (tester) async {
      await tester.pumpWidget(host(
        FinAmount(
          text: '+12,50%',
          style: FinTypography.standard().numSm,
          trend: FinTrend.positive,
        ),
      ));

      final text = tester.widget<Text>(find.text('+12,50%'));
      expect(text.style!.color, FinColors.light.positive);
    });

    testWidgets('carrega cifras tabulares vindas do estilo', (tester) async {
      await tester.pumpWidget(host(
        Builder(
          builder: (context) => FinAmount(
            text: r'R$ 1.111,11',
            style: context.finType.numMd,
          ),
        ),
      ));

      final text = tester.widget<Text>(find.text(r'R$ 1.111,11'));
      expect(
        text.style!.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });

    testWidgets('valor sem direcao le em tinta principal', (tester) async {
      // Regressao: quando `neutral` resolvia para `textSecondary`, toda
      // metrica sem direcao explicita -- patrimonio final, contagem de ativos
      // -- ficava mais apagada que antes sem que ninguem tivesse pedido.
      await tester.pumpWidget(host(
        FinAmount(
          text: r'R$ 40.000,00',
          style: FinTypography.standard().numLg,
        ),
      ));

      final text = tester.widget<Text>(find.text(r'R$ 40.000,00'));
      expect(text.style!.color, FinColors.light.textPrimary);
    });
  });

  group('FinAmount — mascara de privacidade', () {
    testWidgets('oculta o valor e anuncia a ocultacao', (tester) async {
      await tester.pumpWidget(host(
        FinAmount(
          text: r'R$ 128.430,55',
          style: FinTypography.standard().numHero,
          masked: true,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text(r'R$ 128.430,55'), findsNothing);
      expect(find.text(FinAmount.maskedText), findsOneWidget);

      // O texto mascarado nao se le em voz alta: sem rotulo, a tela fica muda
      // para quem depende de leitor de tela.
      final semantics = tester.getSemantics(find.byType(FinAmount));
      expect(semantics.label, 'Valor oculto');
    });

    testWidgets('revela o valor quando a mascara sai', (tester) async {
      Widget build({required bool masked}) => host(
            FinAmount(
              text: r'R$ 128.430,55',
              style: FinTypography.standard().numHero,
              masked: masked,
            ),
          );

      await tester.pumpWidget(build(masked: true));
      await tester.pumpAndSettle();
      expect(find.text(r'R$ 128.430,55'), findsNothing);

      await tester.pumpWidget(build(masked: false));
      await tester.pumpAndSettle();
      expect(find.text(r'R$ 128.430,55'), findsOneWidget);
    });
  });

  group('FinAmount.measure', () {
    testWidgets('acompanha a escala de texto do usuario', (tester) async {
      late double normal;
      late double ampliado;

      await tester.pumpWidget(host(
        Builder(
          builder: (context) {
            normal = FinAmount.measure(
              context,
              r'R$ 1.234.567,89',
              context.finType.numSm,
            );
            return const SizedBox.shrink();
          },
        ),
      ));

      await tester.pumpWidget(host(
        textScale: 2.0,
        Builder(
          builder: (context) {
            ampliado = FinAmount.measure(
              context,
              r'R$ 1.234.567,89',
              context.finType.numSm,
            );
            return const SizedBox.shrink();
          },
        ),
      ));

      // O ponto do metodo: uma coluna dimensionada por ele acompanha a fonte
      // do usuario, onde uma largura em constante -- como o antigo
      // `_upsideColumnWidth = 78` -- truncaria em 1,3x.
      expect(ampliado, greaterThan(normal * 1.8));
    });

    testWidgets('valor mais largo mede mais que o mais estreito',
        (tester) async {
      late double estreito;
      late double largo;

      await tester.pumpWidget(host(
        Builder(
          builder: (context) {
            final style = context.finType.numSm;
            estreito = FinAmount.measure(context, r'R$ 0,00', style);
            largo = FinAmount.measure(context, r'R$ 1.234.567,89', style);
            return const SizedBox.shrink();
          },
        ),
      ));

      expect(largo, greaterThan(estreito));
    });

    testWidgets('coluna medida nao trunca, nem sob escala 2,0x',
        (tester) async {
      const valor = '-1.234,5%';

      for (final escala in <double>[1.0, 1.3, 2.0]) {
        late double largura;

        // Passo 1: medir sob a escala corrente, como faz `_columnWidths`.
        await tester.pumpWidget(host(
          textScale: escala,
          Builder(
            builder: (context) {
              largura = FinAmount.measure(
                context,
                valor,
                context.finType.numSm,
              );
              return const SizedBox.shrink();
            },
          ),
        ));

        // Passo 2: renderizar numa coluna daquela largura exata.
        await tester.pumpWidget(host(
          textScale: escala,
          Builder(
            builder: (context) => SizedBox(
              width: largura,
              child: FinAmount(text: valor, style: context.finType.numSm),
            ),
          ),
        ));

        expect(tester.takeException(), isNull);

        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(valor),
        );
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: 'Em ${escala}x a coluna medida deveria caber o valor '
              'inteiro. Se truncou, `measure` e a renderizacao divergiram.',
        );
      }
    });

    testWidgets('coluna estreita demais trunca de forma VISIVEL',
        (tester) async {
      const valor = '-1.234,5%';

      await tester.pumpWidget(host(
        Builder(
          builder: (context) => const SizedBox(
            width: 24,
            child: FinAmount(
              text: valor,
              style: TextStyle(fontSize: 13),
            ),
          ),
        ),
      ));

      final paragraph = tester.renderObject<RenderParagraph>(
        find.text(valor),
      );

      // O que este teste protege: com `TextOverflow.clip` -- o padrao -- o
      // numero seria cortado SEM marca nenhuma, porque dentro de um `SizedBox`
      // nao aparece a listra amarela de overflow. O usuario leria "-1.2" e nao
      // teria como saber que faltam digitos.
      expect(paragraph.didExceedMaxLines, isTrue);
      expect(paragraph.overflow, TextOverflow.ellipsis);
    });
  });
}

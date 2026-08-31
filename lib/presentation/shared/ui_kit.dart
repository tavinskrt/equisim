import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../components/fin_amount.dart';
import '../theme/fin_colors.dart';
import '../theme/fin_space.dart';
import '../theme/fin_theme.dart';

/// Formatadores compartilhados.
abstract final class Fmt {
  /// Moeda em pt-BR por extenso: `R$ 1.234,56`.
  static final currency = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  /// Moeda abreviada: `R$ 1,2 mi`. Para eixo de gráfico e espaço estreito.
  static final compactCurrency = NumberFormat.compactCurrency(
    locale: 'pt_BR',
    symbol: r'R$',
  );

  /// Data por extenso: `31/12/2026`.
  static final date = DateFormat('dd/MM/yyyy');

  /// Data curta para eixo temporal: `12/26`.
  static final shortDate = DateFormat('MM/yy');

  /// Formata um valor **em reais** — não em centavos.
  ///
  /// Converta com `Money.reais` antes de chamar; passar centavos produz um
  /// número cem vezes maior sem qualquer aviso.
  static String money(double value) => currency.format(value);

  /// Formatadores decimais em pt-BR, um por número de casas.
  ///
  /// Existe porque `toStringAsFixed` **ignora locale**: ele sempre emite ponto
  /// como separador decimal, mesmo com o `intl` configurado em pt_BR. Isso
  /// produzia `14.41%` onde a convenção brasileira pede `14,41%` — defeito que
  /// aparecia em todas as telas de métricas.
  ///
  /// O cache evita reconstruir o formatador a cada quadro: estes métodos são
  /// chamados de dentro de `build`.
  static final Map<int, NumberFormat> _decimals = {};

  static NumberFormat _decimalFormat(int digits) => _decimals.putIfAbsent(
    digits,
    () => NumberFormat.decimalPatternDigits(
      locale: 'pt_BR',
      decimalDigits: digits,
    ),
  );

  /// Percentual a partir de fração, com sinal explícito quando pedido.
  ///
  /// - [fraction]: valor em fração (`0.155` vira `15,50%`).
  /// - [decimals]: casas decimais. Padrão `2`.
  /// - [signed]: prefixa `+` nos positivos. Negativos já trazem o próprio
  ///   sinal; o zero nunca recebe prefixo.
  ///
  /// Valor não finito vira `—`: `NumberFormat` não lança nesse caso, ele
  /// devolve `NaN` ou `∞`, e exibir isso ao investidor é pior que admitir a
  /// ausência do dado.
  static String percent(
    double fraction, {
    int decimals = 2,
    bool signed = false,
  }) {
    final value = fraction * 100;
    if (!value.isFinite) return '—';
    final sign = signed && value > 0 ? '+' : '';
    return '$sign${_decimalFormat(decimals).format(value)}%';
  }

  /// Peso de carteira: percentual em pt-BR, com duas casas.
  ///
  /// Existe porque `Weight.toString()` formata por `toStringAsFixed`, que
  /// **ignora locale** e emite `100.00%`, com ponto — na mesma linha em que a
  /// interface escreve `atual 100,0%` com vírgula. O núcleo é Dart puro e não
  /// pode depender de `intl`, então a conversão para a convenção brasileira só
  /// cabe aqui, na fronteira de apresentação. E cabe num lugar só: três telas
  /// desenham essa mesma grandeza.
  ///
  /// - [fraction]: peso em fração (`0.25` vira `25,00%`).
  static String weight(double fraction) => percent(fraction, decimals: 2);

  /// A maior largura que [weight] chega a desenhar: `100,00%`.
  ///
  /// Mora colado ao formatador de propósito. A amostra que MEDE a coluna e o
  /// texto que ela DESENHA precisam sair da mesma expressão — enquanto a
  /// amostra era um literal escrito longe daqui, a coluna media `100%` e
  /// desenhava `25.00%`, e o número saía truncado sem aviso nenhum.
  static String get weightCeiling => weight(1.0);

  /// Número adimensional — múltiplo, beta, índice de Sharpe.
  static String ratio(double value, {int decimals = 2}) =>
      value.isFinite ? _decimalFormat(decimals).format(value) : '—';

  /// Diferença entre duas taxas, em **pontos percentuais**, com sinal.
  ///
  /// [points] já chega na unidade final: `3.5` vira `+3,5 p.p.`. Não é
  /// fração — `Fmt.percent` é que multiplica por cem.
  ///
  /// Existe porque a mesma expressão estava escrita em três lugares — a
  /// deriva de peso, a folga da meta e a coluna que MEDE a largura da deriva.
  /// Duas cópias que precisam concordar entre si já são uma a mais: se a
  /// medida e o texto divergirem, a coluna trunca sem aviso.
  static String points(double points, {int decimals = 1}) {
    if (!points.isFinite) return '—';
    final sign = points >= 0 ? '+' : '';
    return '$sign${ratio(points, decimals: decimals)} p.p.';
  }

  /// Prazo em meses, por extenso: `120` vira `10 anos e 0 meses`.
  ///
  /// A forma é a que a tela da Meta já usava. Mora aqui para que a aba
  /// Análise possa citar o prazo da meta **com as mesmas palavras** — dois
  /// horizontes escritos em formatos diferentes na mesma sessão de uso é
  /// exatamente o que impede o leitor de compará-los.
  static String months(int months) {
    final anos = months ~/ 12;
    final resto = months % 12;
    return '$anos anos e $resto meses';
  }
}

/// Vocabulário das grandezas que atravessam mais de uma tela.
///
/// Existe porque **rótulo é contrato com o leitor**. A mesma rentabilidade
/// exigida se chamava "Rentabilidade exigida" na aba Meta e "Exigido" na de
/// Análise; quem aprendeu um dos dois não reconhecia o outro como a mesma
/// coisa, e passava a tratar como duas grandezas o que é uma só.
///
/// Cada constante é usada em pelo menos dois arquivos. As de um lugar só —
/// "Volatilidade", "Sharpe", "Preço justo" — continuam escritas no ponto de
/// uso: centralizar rótulo que não viaja só afasta o texto de quem o lê.
///
/// **A ressalva NÃO entra aqui, e é deliberado.** [esperado] aparece na tela
/// de estudo com a premissa de convergência e a cobertura da carteira, e na
/// tela da meta com a composição do número. As duas são verdadeiras, servem a
/// perguntas diferentes, e a que está no estudo foi acrescentada de propósito
/// para não omitir a premissa que sustenta o valor. Uniformizá-las apagaria
/// informação em nome de uma simetria que ninguém pediu — o que precisa
/// coincidir é o NOME da grandeza, não tudo que se diz sobre ela.
abstract final class Lexico {
  /// Rentabilidade que o plano patrimonial exige, ao ano.
  static const String exigido = 'Exigido';

  /// Ressalva de [exigido]. Viaja junto porque a taxa sem a base é ambígua.
  static const String exigidoAoAno = 'ao ano';

  /// Retorno que a avaliação implica — projeção, não evidência.
  static const String esperado = 'Esperado da carteira';

  /// Retorno que o histórico entregou — evidência, não projeção.
  static const String realizado = 'Realizado';

  /// Ressalva de [realizado]: nomeia o indicador para que o leitor o
  /// reconheça no painel de indicadores, onde ele aparece sob a sigla.
  static const String realizadoXirr = 'XIRR, ao ano';

  /// Distância entre o que se espera (ou se obteve) e o que se exige.
  static const String folga = 'Folga';
}

/// Cartão translúcido — a linguagem visual herdada do projeto anterior.
///
/// O efeito de vidro depende de haver variação atrás: sobre cor perfeitamente
/// chapada o desfoque não tem o que borrar. É [ScreenBackground] que fornece
/// essa variação.
class GlassCard extends StatelessWidget {
  /// Conteúdo do cartão.
  final Widget child;

  /// Espaçamento interno.
  final EdgeInsetsGeometry padding;

  /// Contorno alternativo, para destacar estado. Sem ele, usa a borda padrão
  /// da paleta.
  final Color? borderColor;

  /// Declara o cartão.
  const GlassCard({
    super.key,
    required this.child,
    this.padding = FinSpace.cardPadding,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fin;

    // `RepaintBoundary` aqui, e nao no ponto de uso, porque a garantia precisa
    // ser LOCAL ao componente.
    //
    // `ListView` ja envolve os filhos DIRETOS em fronteira de repintura
    // (`addRepaintBoundaries` e `true` por padrao), mas um cartao aninhado --
    // como os de dentro de `_ComparisonBody`, na tela de backtest -- fica sob
    // a fronteira do irmao mais externo e repinta junto com ele. Sem isto,
    // rolar a tela reprocessa o desfoque de seis ou sete cartoes por quadro,
    // e o alvo web deste projeto e onde mais custa.
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor ?? c.border),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Título de seção com ação opcional à direita.
class SectionHeader extends StatelessWidget {
  /// Título da seção. É renderizado em **caixa alta** pelo widget; passe-o na
  /// grafia normal.
  final String title;

  /// Linha de apoio sob o título.
  final String? subtitle;

  /// Widget alinhado à direita — tipicamente um botão ou um [HintIcon].
  final Widget? trailing;

  /// Declara o cabeçalho.
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final t = context.finType;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: t.label.copyWith(color: c.textSecondary),
              ),
              if (subtitle != null) ...[
                const Gap.xs(),
                Text(
                  subtitle!,
                  style: t.caption.copyWith(color: c.textTertiary),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Métrica destacada: rótulo, valor e explicação curta.
class MetricTile extends StatelessWidget {
  /// Nome da métrica.
  final String label;

  /// Valor **já formatado**. Use [Fmt] — o widget não formata nada, o que
  /// mantém a decisão de unidade e casas decimais no ponto de uso.
  final String value;

  /// Nota de rodapé: base de cálculo, janela, ressalva.
  final String? hint;

  /// Direção da grandeza, que escolhe a cor do valor.
  ///
  /// Substituiu o antigo `valueColor: Color?`, que obrigava cada ponto de uso
  /// a resolver a cor por conta própria — e era por onde `context.fin.brand`,
  /// reprovado em contraste, chegava a todo número positivo da interface.
  final FinTrend trend;

  /// Quantas linhas o valor pode ocupar. Padrão 1.
  ///
  /// Passe 2 quando o "valor" for um NOME e não um número. O caso que motivou
  /// isto: o método de valuation aparecia como `DCF simplificado (L…`, e a
  /// sigla cortada é justamente o que distingue um modelo do outro.
  final int valueMaxLines;

  /// Declara o bloco de métrica.
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    this.trend = FinTrend.neutral,
    this.valueMaxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final t = context.finType;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: t.caption.copyWith(color: c.textSecondary)),
        const Gap.xs(),
        // O valor passa por `FinAmount`: é o que garante cifra tabular, de modo
        // que a vírgula decimal não dança de uma métrica para a outra.
        FinAmount(
          text: value,
          style: t.numMd,
          trend: trend,
          align: TextAlign.left,
          maxLines: valueMaxLines,
        ),
        if (hint != null) ...[
          const Gap.xs(),
          Text(hint!, style: t.caption.copyWith(color: c.textTertiary)),
        ],
      ],
    );
  }
}

/// Uma fila de [MetricTile] com as três faixas alinhadas entre si.
///
/// Existe porque a forma ingênua — `Row(children: [Expanded(child:
/// MetricTile(...)), ...])` — empilha cada bloco por conta própria. Um rótulo
/// que quebra em duas linhas empurra o número dele para baixo, e a fila perde
/// a linha de base comum: no cartão "Carteira frente à meta" isso punha
/// "Exigido", "Esperado da carteira" e "Folga" em três alturas diferentes, com
/// o rótulo de um deles na altura do valor do vizinho.
///
/// A `Table` resolve por construção. Rótulos, valores e ressalvas viram três
/// faixas horizontais, cada uma com a altura do seu conteúdo mais alto — então
/// todos os números começam na mesma linha, quaisquer que sejam os rótulos.
/// Alinhar por `IntrinsicHeight` não resolveria: ele iguala a altura das
/// colunas, não a posição das faixas dentro delas.
///
/// Os blocos chegam como [MetricTile] e não como parâmetros soltos para que o
/// ponto de uso não mude de vocabulário ao entrar numa fila — e para que um
/// bloco solto continue sendo o mesmo widget de sempre.
class MetricTileRow extends StatelessWidget {
  /// Blocos da fila, da esquerda para a direita. Todos recebem largura igual.
  final List<MetricTile> tiles;

  /// Declara a fila.
  const MetricTileRow({super.key, required this.tiles});

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) return const SizedBox.shrink();

    final c = context.fin;
    final t = context.finType;
    // Sem nenhuma ressalva a terceira faixa não existe; com uma só, as demais
    // colunas cedem a altura dela e nada desalinha.
    final hasHint = tiles.any((tile) => tile.hint != null);

    TableCell band(Widget child, TableCellVerticalAlignment alignment) =>
        TableCell(
          verticalAlignment: alignment,
          child: Padding(
            padding: const EdgeInsets.only(right: FinSpace.sm),
            child: child,
          ),
        );

    return Table(
      defaultColumnWidth: const FlexColumnWidth(),
      children: [
        TableRow(
          children: [
            for (final tile in tiles)
              // Rótulo colado na FAIXA DE BAIXO: é o número que ele nomeia, e
              // um rótulo de uma linha flutuando no topo de uma faixa de duas
              // parece pertencer ao bloco de cima.
              band(
                Text(
                  tile.label,
                  style: t.caption.copyWith(color: c.textSecondary),
                ),
                TableCellVerticalAlignment.bottom,
              ),
          ],
        ),
        TableRow(
          children: [
            for (final tile in tiles)
              band(
                Padding(
                  padding: const EdgeInsets.only(top: FinSpace.xs),
                  // O `Align` não é decorativo. `FinAmount` embrulha o texto
                  // num `AnimatedSwitcher`, que centraliza o filho na caixa
                  // recebida; dentro de uma `Column` com alinhamento à
                  // esquerda a caixa aperta no conteúdo e ninguém nota, mas a
                  // célula de tabela é larga — sem isto o número flutuava no
                  // meio da coluna, longe do rótulo que o nomeia.
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FinAmount(
                      text: tile.value,
                      style: t.numMd,
                      trend: tile.trend,
                      align: TextAlign.left,
                      maxLines: tile.valueMaxLines,
                    ),
                  ),
                ),
                TableCellVerticalAlignment.top,
              ),
          ],
        ),
        if (hasHint)
          TableRow(
            children: [
              for (final tile in tiles)
                band(
                  tile.hint == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: FinSpace.xs),
                          child: Text(
                            tile.hint!,
                            style: t.caption.copyWith(color: c.textTertiary),
                          ),
                        ),
                  TableCellVerticalAlignment.top,
                ),
            ],
          ),
      ],
    );
  }
}

/// Linha de rótulo à esquerda e valor à direita.
///
/// Existe porque a forma ingênua — `Row(Text, Spacer, Text)` — **estoura**.
/// Nenhum dos dois textos é flexível, então quando a soma deles passa da
/// largura disponível o `Spacer` colapsa a zero e o excedente vira listra
/// amarela. Não é caso extremo: acontecia em 320 dp na escala padrão, e a
/// mesma linha aparecia em duas telas com o defeito idêntico.
///
/// O `Wrap` resolve por construção. Cabendo os dois, ele os separa como o
/// `Spacer` fazia; não cabendo, o valor desce para a segunda linha. Não há
/// largura em que ele possa estourar, e nada é truncado — o que importa num
/// par em que o valor é um número.
class LabelValueRow extends StatelessWidget {
  /// Rótulo, na grafia normal.
  final String label;

  /// Valor **já formatado**.
  final String value;

  /// Direção do valor, quando ele carrega sinal financeiro.
  final FinTrend trend;

  /// Declara a linha.
  const LabelValueRow({
    super.key,
    required this.label,
    required this.value,
    this.trend = FinTrend.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final t = context.finType;

    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: FinSpace.sm,
        runSpacing: FinSpace.xs,
        children: [
          Text(label, style: t.bodySm.copyWith(color: c.textSecondary)),
          FinAmount(
            text: value,
            style: t.numSm,
            trend: trend,
            align: TextAlign.left,
          ),
        ],
      ),
    );
  }
}

/// Faixa de aviso não bloqueante.
///
/// Usada para concentração setorial e para a queda de modelo de avaliação:
/// informa sem impedir, porque as duas situações podem ser decisões
/// conscientes do investidor.
class NoticeBanner extends StatelessWidget {
  /// Texto do aviso, já formulado para o usuário final.
  final String message;

  /// Ícone à esquerda.
  final IconData icon;

  /// Direção do aviso, que escolhe a cor e o fundo tonal.
  ///
  /// Substituiu o antigo `color: Color`, cujo valor-padrão era um âmbar
  /// (`#F59E0B`) que a paleta não conhecia — nem `warning` nem `warningDark`.
  /// Era um literal que ninguém podia corrigir de um lugar só.
  final FinTrend trend;

  /// Declara a faixa de aviso.
  const NoticeBanner({
    super.key,
    required this.message,
    this.icon = Icons.info_outline,
    this.trend = FinTrend.caution,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final accent = c.forTrend(trend);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FinSpace.md,
        vertical: FinSpace.sm,
      ),
      decoration: BoxDecoration(
        color: c.surfaceForTrend(trend),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: accent),
          const Gap.sm(axis: Axis.horizontal),
          Expanded(
            child: Text(
              message,
              style: context.finType.bodySm.copyWith(color: c.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Estado vazio com orientação do próximo passo.
class EmptyState extends StatelessWidget {
  /// Ícone ilustrativo.
  final IconData icon;

  /// Título curto do estado vazio.
  final String title;

  /// Explicação do que falta e de como preencher.
  final String message;

  /// Ação sugerida — o botão que resolve o vazio.
  final Widget? action;

  /// Declara o estado vazio.
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final t = context.finType;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FinSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: c.textTertiary),
            const Gap.md(),
            Text(
              title,
              textAlign: TextAlign.center,
              style: t.titleSm.copyWith(color: c.textPrimary),
            ),
            const Gap.sm(),
            Text(
              message,
              textAlign: TextAlign.center,
              style: t.bodyMd.copyWith(color: c.textSecondary),
            ),
            if (action != null) ...[const Gap.lg(), action!],
          ],
        ),
      ),
    );
  }
}

/// Fundo padrão das telas, com os círculos decorativos da identidade visual.
///
/// O degradê agora percorre `canvas -> surfaceSunken -> canvas`, e não mais o
/// azul-marinho ao verde-petróleo da paleta anterior. É uma atenuação
/// deliberada: os dois tons já passam pelo teste de contraste, o que o par
/// antigo não garantia, e o resultado é a variação mínima de que o
/// [GlassCard] precisa para ter o que desfocar — sem o degradê competir com os
/// números.
class ScreenBackground extends StatelessWidget {
  /// Conteúdo da tela.
  final Widget child;

  /// Declara o fundo. Envolva a tela inteira com ele.
  const ScreenBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.fin;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.canvas, c.surfaceSunken, c.canvas],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Os dois círculos não mudam com a rolagem nem com o conteúdo. Sem a
          // fronteira, eles repintam a cada quadro junto com a lista.
          RepaintBoundary(
            child: SizedBox.expand(
              child: Stack(
                children: [
                  Positioned(
                    top: -100,
                    right: -60,
                    child: _Halo(color: c.brand.withValues(alpha: 0.07)),
                  ),
                  Positioned(
                    bottom: -40,
                    left: -80,
                    child: _Halo(
                      size: 220,
                      color: c.brand.withValues(alpha: 0.05),
                    ),
                  ),
                ],
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Círculo decorativo do fundo.
class _Halo extends StatelessWidget {
  final double size;
  final Color color;

  const _Halo({this.size = 260, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

/// Cabeçalho translúcido das telas.
///
/// Extraído porque `app_shell` e `profile_page` mantinham cópias do mesmo
/// `BackdropFilter` com a mesma borda e a mesma opacidade — e qualquer ajuste
/// precisava ser feito duas vezes, com a segunda sendo esquecida.
///
/// O título e a linha de apoio são `Flexible` com reticências: sem isso a
/// `Row` estourava em 320 dp sob fonte ampliada, que é como o cabeçalho do
/// perfil quebrava.
class AppHeader extends StatelessWidget {
  /// Elemento à esquerda — botão de voltar, marca, avatar.
  final Widget leading;

  /// Título, na grafia normal.
  final String title;

  /// Linha de apoio. Renderizada em **caixa alta** pelo widget.
  final String? subtitle;

  /// Ações à direita.
  final List<Widget> actions;

  /// Declara o cabeçalho.
  const AppHeader({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final t = context.finType;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: FinSpace.lg,
            vertical: FinSpace.md,
          ),
          decoration: BoxDecoration(
            color: c.canvas.withValues(alpha: 0.6),
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                leading,
                const Gap.md(axis: Axis.horizontal),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleSm.copyWith(color: c.textPrimary),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.caption.copyWith(color: c.textSecondary),
                        ),
                    ],
                  ),
                ),
                ...actions,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Verbete de glossário: o rótulo tal como aparece no cartão e o que ele diz.
class HintEntry {
  /// Termo explicado — o jargão como aparece na tela.
  final String term;

  /// Definição em linguagem corrente.
  final String description;

  /// Declara o verbete.
  const HintEntry(this.term, this.description);
}

/// Ícone de ajuda que abre o glossário dos indicadores de um cartão.
///
/// Os números destas telas decidem troca de ativo, e cada um responde a uma
/// pergunta diferente: TWR compara composições, XIRR mede o que o investidor
/// levou. Ler um pelo outro leva à decisão errada, e o verbete a um toque de
/// distância custa menos que a nota de rodapé que ninguém lê.
class HintIcon extends StatelessWidget {
  /// Título do painel de ajuda.
  final String title;

  /// Frase de abertura, quando o conjunto de verbetes precisa de contexto.
  final String? intro;

  /// Verbetes exibidos, na ordem em que aparecem.
  final List<HintEntry> entries;

  /// Declara o ícone de ajuda.
  const HintIcon({
    super.key,
    required this.title,
    required this.entries,
    this.intro,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'O que significa cada indicador',
      // 48 dp explícitos: `VisualDensity.compact` encolheria o alvo para 40.
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      padding: EdgeInsets.zero,
      icon: Icon(
        Icons.help_outline,
        size: 17,
        color: context.fin.textSecondary,
      ),
      onPressed: () => _openGlossary(context),
    );
  }

  void _openGlossary(BuildContext context) {
    final c = context.fin;
    final t = context.finType;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AlertDialog(
          backgroundColor: c.surfaceRaised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: c.border),
          ),
          title: Text(title, style: t.titleSm.copyWith(color: c.textPrimary)),
          content: ConstrainedBox(
            // `maxWidth`, e nao `width`: em 320 dp uma largura exata de 420
            // estoura o diálogo. Com teto, ele ocupa 420 onde couber e a
            // largura disponível onde não couber.
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (intro != null) ...[
                    Text(
                      intro!,
                      style: t.bodySm.copyWith(color: c.textSecondary),
                    ),
                    const Gap.md(),
                  ],
                  for (final entry in entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: FinSpace.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.term,
                            // `positive` e não `brand`: este é texto, e a cor
                            // de marca não tem contraste garantido para texto.
                            style: t.bodySm.copyWith(
                              fontWeight: FontWeight.w600,
                              color: c.positive,
                            ),
                          ),
                          const Gap.xs(),
                          Text(
                            entry.description,
                            style: t.caption.copyWith(color: c.textSecondary),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Entendi',
                style: t.bodyMd.copyWith(color: c.positive),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

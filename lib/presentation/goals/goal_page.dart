import '../theme/fin_space.dart';
import '../components/fin_amount.dart';
import '../shared/theme_bridge.dart';
import 'feasibility_copy.dart';
import '../shared/ui_kit.dart';
import '../study/study_notifier.dart';
import '../theme/fin_colors.dart';
import '../theme/fin_theme.dart';
import '../valuation/valuation_providers.dart';
import 'dart:math' as math;
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tela de planejamento patrimonial.
///
/// O usuário informa aporte inicial, aporte mensal, prazo e valor desejado; o
/// sistema deriva a rentabilidade necessária. A taxa **não é digitada** — é
/// consequência dos quatro parâmetros.
class GoalPage extends ConsumerStatefulWidget {
  const GoalPage({super.key});

  @override
  ConsumerState<GoalPage> createState() => _GoalPageState();
}

class _GoalPageState extends ConsumerState<GoalPage> {
  late final TextEditingController _initial;
  late final TextEditingController _monthly;
  late final TextEditingController _target;
  int _months = 120;

  @override
  void initState() {
    super.initState();
    final goal = ref.read(studyProvider).study.goal;
    _initial = TextEditingController(
      text: goal == null
          ? '10000'
          : goal.initialContribution.reais.toStringAsFixed(0),
    );
    _monthly = TextEditingController(
      text: goal == null
          ? '1000'
          : goal.monthlyContribution.reais.toStringAsFixed(0),
    );
    _target = TextEditingController(
      text: goal == null
          ? '500000'
          : goal.targetWealth.reais.toStringAsFixed(0),
    );
    if (goal != null) _months = goal.months;
    WidgetsBinding.instance.addPostFrameCallback((_) => _apply());
  }

  @override
  void dispose() {
    _initial.dispose();
    _monthly.dispose();
    _target.dispose();
    super.dispose();
  }

  double _parse(TextEditingController controller) =>
      double.tryParse(controller.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;

  void _apply() {
    ref
        .read(studyProvider.notifier)
        .setGoal(
          // `unvalidated`, e não `create`: os campos estão sendo digitados, e
          // um plano ainda incompleto precisa chegar ao estado para que o
          // cartão de viabilidade explique o que falta. Quem recusa o plano
          // inválido é `RequiredReturnSolver`, cujo veredito a tela já mostra.
          FinancialGoal.unvalidated(
            initialContribution: Money.fromReais(_parse(_initial)),
            monthlyContribution: Money.fromReais(_parse(_monthly)),
            months: _months,
            targetWealth: Money.fromReais(_parse(_target)),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final isLight = ref.watch(isLightModeProvider);
    final feasibility = ref.watch(goalFeasibilityProvider);
    final alignment = ref.watch(goalAlignmentProvider);

    // `CustomScrollView`, e nao `ListView`: cada cartao vira um sliver proprio,
    // entao o framework so infla os que entram na viewport -- e cada um ganha a
    // fronteira de repintura que o `SliverList` adiciona.
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(FinSpace.lg),
          sliver: SliverList.list(
            children: [
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionHeader(
                      title: 'Plano patrimonial',
                      subtitle:
                          'A rentabilidade necessária é derivada destes valores',
                    ),
                    const Gap.md(),
                    _MoneyField(
                      isLight: isLight,
                      controller: _initial,
                      label: 'Aporte inicial',
                      onChanged: _apply,
                    ),
                    const Gap.sm(),
                    _MoneyField(
                      isLight: isLight,
                      controller: _monthly,
                      label: 'Aporte mensal',
                      onChanged: _apply,
                    ),
                    const Gap.sm(),
                    _MoneyField(
                      isLight: isLight,
                      controller: _target,
                      label: 'Valor desejado ao final',
                      onChanged: _apply,
                    ),
                    const Gap.lg(),
                    // `Fmt.months`: a aba Analise cita este mesmo prazo ao
                    // declarar a janela da simulacao, e os dois precisam sair
                    // com as mesmas palavras para serem comparaveis.
                    LabelValueRow(
                      label: 'Prazo',
                      value: Fmt.months(_months),
                    ),
                    Slider(
                      value: _months.toDouble(),
                      min: 12,
                      max: 360,
                      divisions: 29,
                      activeColor: context.fin.brand,
                      label: '$_months meses',
                      onChanged: (value) {
                        setState(() => _months = value.round());
                        _apply();
                      },
                    ),
                  ],
                ),
              ),
              const Gap.md(),
              feasibility.when(
                loading: () => const _VerdictSkeleton(),
                error: (error, _) => NoticeBanner(
                  trend: FinTrend.negative,
                  icon: Icons.error_outline,
                  message: 'Não foi possível avaliar a meta: $error',
                ),
                data: (verdict) => verdict == null
                    ? const SizedBox.shrink()
                    : _FeasibilityCard(verdict: verdict, isLight: isLight),
              ),
              const Gap.md(),
              alignment.when(
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
                data: (value) => value == null
                    ? GlassCard(
                        child: EmptyState(
                          icon: Icons.donut_small_outlined,
                          title: 'Sem carteira para comparar',
                          message:
                              'Monte a carteira Principal para confrontar o '
                              'retorno esperado com a rentabilidade exigida.',
                        ),
                      )
                    : _AlignmentCard(alignment: value, isLight: isLight),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Espaço reservado enquanto o veredito de viabilidade é calculado.
///
/// Substitui um indicador centrado com 24 dp de padding, cuja altura era uma
/// fração da do `_FeasibilityCard` que ocupa o lugar dele — então ao chegar o
/// resultado tudo abaixo saltava de uma vez.
class _VerdictSkeleton extends StatelessWidget {
  const _VerdictSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.fin;

    Widget barra(double largura, double altura) => Container(
      width: largura,
      height: altura,
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: BorderRadius.circular(4),
      ),
    );

    return Semantics(
      label: 'Avaliando a meta',
      child: ExcludeSemantics(
        child: GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              barra(140, 12),
              const Gap.md(),
              barra(double.infinity, 44),
              const Gap.md(),
              barra(double.infinity, 44),
              const Gap.md(),
              barra(200, 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// Um dos três valores que o investidor digita no plano patrimonial.
///
/// **A afordância é o ponto deste widget**, não a aparência. Ele nasceu com
/// `borderSide: BorderSide.none` sobre um preenchimento `surfaceSunken`, e a
/// lente `tela` leu o resultado exatamente como ele se apresentava: *"os
/// blocos contendo 'R$ 10000', 'R$ 1000' e 'R$ 500000' são retângulos
/// cinza-claros uniformes sem qualquer indicação visual de que aceitam
/// digitação"*.
///
/// O custo era grande e silencioso: quem usa conclui que os valores são
/// calculados pelo sistema, mexe só no controle de prazo, e nunca personaliza
/// o plano. A funcionalidade existia e ficava invisível.
///
/// **Borda E marca de edição, não uma ou outra.** A borda sozinha não bastaria
/// aqui: `GlassCard` desenha a dele com o MESMO token `border`, então um
/// retângulo preenchido com contorno continuaria se lendo como contêiner —
/// haveria três deles dentro de um quarto. O lápis é o que remove a ambiguidade
/// de uma vez, e por isso o peso visual que ele acrescenta está pago.
///
/// A borda de foco vem de `brand` porque é a única cor da paleta que significa
/// "ativo" nesta interface. Nenhum token novo foi criado: `lib/presentation/
/// theme/` está fora do escopo do pacote UI-2, e precisar de um token seria
/// sinal de que a correção cresceu além dele.
class _MoneyField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool isLight;
  final VoidCallback onChanged;

  const _MoneyField({
    required this.controller,
    required this.label,
    required this.isLight,
    required this.onChanged,
  });

  /// Contorno do campo, na cor e espessura pedidas.
  ///
  /// Sai de uma função porque `InputDecoration` exige o contorno em três
  /// estados — padrão, habilitado e focado — e três literais divergiriam no
  /// primeiro ajuste de raio.
  static OutlineInputBorder _contorno(Color cor, {double espessura = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cor, width: espessura),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.fin;

    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (_) => onChanged(),
      style: TextStyle(color: c.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: context.finType.bodySm.copyWith(color: c.textSecondary),
        prefixText: r'R$ ',
        prefixStyle: TextStyle(color: c.textSecondary),
        filled: true,
        fillColor: c.surfaceSunken,
        // O lápis é a marca de edição, e é decoração no sentido estrito: não
        // recebe toque, porque o campo inteiro já é o alvo. Um ícone tocável
        // ali prometeria uma ação que não existe.
        suffixIcon: Icon(Icons.edit_outlined, size: 16, color: c.textTertiary),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 40,
          minHeight: 40,
        ),
        border: _contorno(c.border),
        enabledBorder: _contorno(c.border),
        focusedBorder: _contorno(c.brand, espessura: 2),
      ),
    );
  }
}

/// Semáforo de viabilidade, com os limiares ancorados em CDI e Ibovespa
/// observados — não em números arbitrários.
class _FeasibilityCard extends StatelessWidget {
  final FeasibilityVerdict verdict;
  final bool isLight;

  const _FeasibilityCard({required this.verdict, required this.isLight});

  /// Veredito traduzido em direcao semantica.
  ///
  /// Antes cada nivel carregava um literal de cor proprio -- inclusive um
  /// ambar #F59E0B que nao existia na paleta e que, por isso, ninguem podia
  /// corrigir de um lugar so.
  FinTrend get _trend => switch (verdict.level) {
    FeasibilityLevel.riskFreeSufficient => FinTrend.pending,
    FeasibilityLevel.plausible => FinTrend.positive,
    FeasibilityLevel.demanding => FinTrend.caution,
    FeasibilityLevel.unrealistic => FinTrend.negative,
  };

  Color _color(BuildContext context) => context.fin.forTrend(_trend);

  IconData get _icon => switch (verdict.level) {
    FeasibilityLevel.riskFreeSufficient => Icons.savings_outlined,
    FeasibilityLevel.plausible => Icons.check_circle_outline,
    FeasibilityLevel.demanding => Icons.warning_amber_outlined,
    FeasibilityLevel.unrealistic => Icons.block,
  };

  String get _title => switch (verdict.level) {
    FeasibilityLevel.riskFreeSufficient => 'Meta sem necessidade de risco',
    FeasibilityLevel.plausible => 'Meta plausível',
    FeasibilityLevel.demanding => 'Meta exigente',
    FeasibilityLevel.unrealistic => 'Meta inviável',
  };

  @override
  Widget build(BuildContext context) {
    // Taxa ausente é meta sem solução: os cartões numéricos somem, e a frase
    // do veredito explica. Ver `FeasibilityVerdict.requiredAnnualRate`.
    final rate = verdict.requiredAnnualRate;
    final showRates = rate != null && rate.isFinite;

    return GlassCard(
      borderColor: _color(context).withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icon, size: 20, color: _color(context)),
              const Gap.sm(axis: Axis.horizontal),
              Text(
                _title,
                style: context.finType.bodyMd.copyWith(
                  color: _color(context),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const Gap.sm(),
          if (showRates)
            MetricTileRow(
              tiles: [
                // `Lexico.exigido`, e nao "Rentabilidade exigida": e a
                // mesma grandeza que a aba Analise confronta com o XIRR, e
                // dois nomes faziam o leitor tratar como duas.
                MetricTile(
                  label: Lexico.exigido,
                  value: Fmt.percent(rate, decimals: 2),
                  hint: Lexico.exigidoAoAno,
                  trend: _trend,
                ),
                MetricTile(
                  label: 'Equivalente mensal',
                  value: Fmt.percent(_monthlyEquivalent(rate), decimals: 2),
                  hint: 'juros compostos',
                ),
              ],
            ),
          const Gap.sm(),
          Text(
            FeasibilityCopy.of(verdict),
            style: context.finType.caption.copyWith(
              color: context.fin.textSecondary,
            ),
          ),
          const Gap.sm(),
          Text(
            'Referências dos últimos ${verdict.anchors.observedYears} anos: '
            'CDI ${Fmt.percent(verdict.anchors.riskFreeCagr)} a.a. · '
            'Ibovespa ${Fmt.percent(verdict.anchors.marketCagr)} a.a.',
            style: context.finType.caption.copyWith(
              color: context.fin.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  /// `(1 + anual)^(1/12) − 1`.
  static double _monthlyEquivalent(double annual) {
    if (!annual.isFinite || annual <= -1) return 0;
    return math.pow(1 + annual, 1 / 12).toDouble() - 1;
  }
}

/// Confronto entre o exigido e o esperado.
class _AlignmentCard extends StatelessWidget {
  final GoalAlignment alignment;
  final bool isLight;

  const _AlignmentCard({required this.alignment, required this.isLight});

  @override
  Widget build(BuildContext context) {
    final meets = alignment.meetsGoal;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Carteira frente à meta',
            subtitle: 'Custo do capital próprio mais prêmio pelo desconto',
          ),
          const Gap.md(),
          // DUAS colunas, e nao tres. A taxa exigida saiu daqui: ela ja
          // aparece no cartao de viabilidade logo acima, que e onde ela
          // nasce, e os dois blocos vinham de providers DIFERENTES --
          // `goalFeasibilityProvider` aguarda um provider assincrono e
          // `goalAlignmentProvider` aguarda quatro, entao enquanto o usuario
          // digitava um deles exibia a taxa da meta anterior. Numero
          // renderizado uma vez so nao pode divergir de si mesmo.
          MetricTileRow(
            tiles: [
              MetricTile(
                label: Lexico.esperado,
                value: Fmt.percent(alignment.expectedReturn),
                // O rótulo dizia "upside anualizado + DY líquido" e estava
                // errado nas duas metades: o DY saiu pela decisão 23, e a
                // anualização do upside saiu quando o esperado passou a ser o
                // estimador transversal.
                // Era "CDI + prêmio pelo desconto relativo", e o CDI saiu
                // daqui pela decisão 58: a âncora de cada ativo passou a ser
                // o `Ke` dele. O rótulo sobreviveu à mudança do número por
                // duas semanas, que é o prazo que um rótulo leva para virar
                // mentira quando ninguém o lê junto com a conta.
                hint: 'Ke do ativo + prêmio pelo desconto relativo',
                trend: meets ? FinTrend.positive : FinTrend.negative,
              ),
              MetricTile(
                label: Lexico.folga,
                // `Fmt.points`, e nao interpolacao a mao: a aba Analise exibe
                // a MESMA grandeza no cartao de confronto, e duas escritas da
                // mesma folga divergem na primeira vez que uma delas mudar.
                value: Fmt.points(alignment.gap),
                // A referencia da folga saiu da propria fila quando a coluna
                // "Exigido" saiu; sem esta ressalva o numero fica sem contra
                // o que ser lido.
                hint: 'sobre o exigido acima',
                trend: FinAmount.trendOf(alignment.gap),
              ),
            ],
          ),
          // Aqui ficava a linha "um dividend yield de X% ao ano fecharia
          // esta lacuna". Ela saiu pela decisão 62: o esperado deixou de ser
          // retorno de preço quando a âncora virou o `Ke` (decisão 58), e
          // `Ke = Rf + β·prêmio` é retorno TOTAL pelo CAPM. Mandar somar um
          // yield a ele contava o provento duas vezes, no sentido que faz a
          // carteira parecer melhor do que é.
          if (alignment.coverageIsWeak) ...[
            const Gap.md(),
            NoticeBanner(
              message:
                  'Apenas '
                  '${Fmt.percent(alignment.valuationCoverage, decimals: 0)} '
                  'do peso da carteira tem avaliação disponível. O retorno '
                  'esperado é pouco representativo.',
            ),
          ],
        ],
      ),
    );
  }
}

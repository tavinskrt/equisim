import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/material.dart';

import '../theme/fin_space.dart';
import '../../presentation/theme/fin_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../components/fin_amount.dart';
import '../shared/charts.dart';
import '../shared/theme_bridge.dart';
import '../shared/ui_kit.dart';
import '../study/study_notifier.dart';
import '../theme/fin_colors.dart';
import 'valuation_providers.dart';

/// A avaliação de um ativo, **sem casca**.
///
/// Existe porque a mesma avaliação passou a ser alcançada por dois caminhos: a
/// aba Valuation, que vive dentro da casca do aplicativo, e a tela empilhada
/// que se abre ao tocar num ticker da carteira. Duplicar o corpo faria as duas
/// divergirem na primeira alteração — e é o corpo, não a casca, que carrega a
/// metodologia que a banca vai ler.
class ValuationView extends ConsumerWidget {
  /// Ativo avaliado.
  final Ticker ticker;

  /// Tema corrente.
  final bool isLight;

  /// Declara o corpo da avaliação.
  const ValuationView({
    super.key,
    required this.ticker,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final valuation = ref.watch(valuationProvider(ticker));

    return valuation.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => EmptyState(
        icon: Icons.error_outline,
        title: 'Falha na avaliação',
        message: '$error',
      ),
      data: (result) => result == null
          ? EmptyState(
              icon: Icons.help_outline,
              title: 'Não foi possível avaliar',
              message:
                  'Os dados disponíveis para ${ticker.value} não sustentam '
                  'nenhum modelo de avaliação.',
            )
          : _ValuationBody(result: result, isLight: isLight),
    );
  }
}

/// Detalhe da avaliação de um ativo, empilhado sobre a tela que o chamou.
///
/// É o caminho de dentro da carteira: toca-se num ticker e a avaliação abre
/// com o símbolo no topo e o botão de voltar. A aba Valuation usa
/// [ValuationTab], que compartilha o corpo mas troca a casca por um seletor.
class ValuationPage extends ConsumerWidget {
  final Ticker ticker;
  const ValuationPage({super.key, required this.ticker});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLight = ref.watch(isLightModeProvider);

    return Scaffold(
      body: ScreenBackground(
        child: SafeArea(
          child: Column(
            children: [
              _Header(ticker: ticker, isLight: isLight),
              Expanded(child: ValuationView(ticker: ticker, isLight: isLight)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Aba de valuation: escolhe o ativo e mostra a avaliação dele.
///
/// A `ValuationPage` exige um ticker já escolhido — é o caminho de dentro da
/// carteira. Como ABA ela precisa existir antes da escolha, então o seletor
/// vem junto: sem ele a aba abriria em branco e o rótulo prometeria algo que
/// a tela não entrega, que é exatamente o defeito que o pacote UI-1 fecha.
///
/// O seletor lista a Principal e a Reserva porque as duas guardam ativos
/// avaliáveis, e a Reserva é justamente onde moram os candidatos que se
/// avalia antes de promover.
class ValuationTab extends ConsumerStatefulWidget {
  const ValuationTab({super.key});

  @override
  ConsumerState<ValuationTab> createState() => _ValuationTabState();
}

class _ValuationTabState extends ConsumerState<ValuationTab> {
  /// Escolha explícita do usuário. `null` enquanto ele não escolheu — aí a
  /// aba mostra o primeiro ativo da carteira, para não abrir vazia tendo o
  /// que mostrar.
  Ticker? _escolhido;

  @override
  Widget build(BuildContext context) {
    final isLight = ref.watch(isLightModeProvider);
    final study = ref.watch(studyProvider).study;

    final disponiveis = <Ticker>[
      ...study.principal.tickers,
      ...study.reserva.tickers,
    ];

    if (disponiveis.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(FinSpace.lg),
        child: GlassCard(
          child: EmptyState(
            icon: Icons.query_stats_outlined,
            title: 'Nenhum ativo para avaliar',
            message:
                'Monte a carteira Principal na aba Estudo. Cada ativo dela '
                'pode ser avaliado aqui, com as premissas à vista.',
          ),
        ),
      );
    }

    // A escolha anterior pode ter saído da carteira enquanto a aba estava em
    // outra tela. Cair para o primeiro ativo é melhor que avaliar um ticker
    // que já não está no estudo.
    final ticker = disponiveis.contains(_escolhido)
        ? _escolhido!
        : disponiveis.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FinSpace.lg,
            FinSpace.lg,
            FinSpace.lg,
            0,
          ),
          child: GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  title: 'Ativo avaliado',
                  subtitle: 'Escolha qual ativo das suas carteiras examinar',
                ),
                const Gap.md(),
                // `Wrap`, e nao `Row`: a quantidade de ativos e do usuario, e
                // uma fila fixa estouraria assim que ele passasse de meia
                // duzia. Aqui os chips descem de linha.
                Wrap(
                  spacing: FinSpace.sm,
                  runSpacing: FinSpace.sm,
                  children: [
                    for (final t in disponiveis)
                      ChoiceChip(
                        label: Text(t.value),
                        selected: t == ticker,
                        onSelected: (_) => setState(() => _escolhido = t),
                        labelStyle: context.finType.bodySm.copyWith(
                          color: t == ticker
                              ? context.fin.textOnBrand
                              : context.fin.textSecondary,
                        ),
                        selectedColor: context.fin.brand,
                        backgroundColor: context.fin.surfaceSunken,
                        side: BorderSide(color: context.fin.border),
                        showCheckmark: false,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(child: ValuationView(ticker: ticker, isLight: isLight)),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final Ticker ticker;
  final bool isLight;
  const _Header({required this.ticker, required this.isLight});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FinSpace.sm,
        FinSpace.sm,
        FinSpace.lg,
        FinSpace.sm,
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              Icons.arrow_back,
              size: 20,
              color: context.fin.textPrimary,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          Text(
            ticker.value,
            style: context.finType.titleSm.copyWith(
              color: context.fin.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ValuationBody extends ConsumerWidget {
  final ValuationResult result;
  final bool isLight;

  const _ValuationBody({required this.result, required this.isLight});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(valuationSettingsProvider);

    // `CustomScrollView`, e nao `ListView`: cada cartao vira um sliver proprio,
    // entao o framework so infla os que entram na viewport -- e cada um ganha a
    // fronteira de repintura que o `SliverList` adiciona.
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(FinSpace.lg),
          sliver: SliverList.list(
            children: [
              _PriceCard(result: result, isLight: isLight),
              const Gap.md(),
              _ModelCard(result: result, isLight: isLight),
              const Gap.md(),
              _CalibratedBandCard(result: result),
              _ScenarioCard(
                result: result,
                settings: settings,
                isLight: isLight,
              ),
              const Gap.md(),
              _SensitivityCard(result: result, isLight: isLight),
              if (result.warnings.isNotEmpty ||
                  (result.diagnostics?.caveats.isNotEmpty ?? false)) ...[
                const Gap.md(),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionHeader(
                        title: 'Ressalvas',
                        subtitle:
                            'A qualidade da estimativa faz parte do resultado',
                      ),
                      const Gap.sm(),
                      // As ressalvas estruturadas vêm primeiro e em uma linha
                      // cada: elas são o resumo do que os avisos detalham, e
                      // quem só olha o topo do cartão precisa levar delas o
                      // essencial.
                      if (result.diagnostics != null)
                        for (final c in result.diagnostics!.caveats)
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: FinSpace.xs),
                            child: Text(
                              '• ${c.label}',
                              style: context.finType.bodySm.copyWith(
                                color: context.fin.textSecondary,
                              ),
                            ),
                          ),
                      if (result.diagnostics?.caveats.isNotEmpty ?? false)
                        const Gap.sm(),
                      for (final warning in result.warnings)
                        Padding(
                          padding: const EdgeInsets.only(bottom: FinSpace.sm),
                          child: NoticeBanner(message: warning),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PriceCard extends StatelessWidget {
  final ValuationResult result;
  final bool isLight;
  const _PriceCard({required this.result, required this.isLight});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  label: 'Preço de mercado',
                  value: Fmt.money(result.marketPrice.reais),
                ),
              ),
              Expanded(
                child: MetricTile(
                  label: 'Preço justo',
                  value: Fmt.money(result.fairValue.reais),
                  hint: 'cenário base',
                ),
              ),
              Expanded(
                child: MetricTile(
                  label: 'Upside',
                  value: Fmt.percent(result.upside, decimals: 1, signed: true),
                  hint: 'total, sem prazo',
                  trend: FinAmount.trendOf(result.upside),
                ),
              ),
            ],
          ),
          if (result.marginOfSafety > 0) ...[
            const Divider(height: 20),
            Text(
              'Com margem de segurança de '
              '${Fmt.percent(result.marginOfSafety, decimals: 0)}, o preço de '
              'compra seria ${Fmt.money(result.safetyPrice.reais)} — '
              '${result.isUndervalued ? 'já atingido' : 'ainda não atingido'}.',
              style: context.finType.caption.copyWith(
                color: context.fin.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  final ValuationResult result;
  final bool isLight;
  const _ModelCard({required this.result, required this.isLight});

  ValuationDiagnostics? get diagnostics => result.diagnostics;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Modelo aplicado',
            subtitle: 'Escolhido pelo que os dados sustentam',
          ),
          const Gap.md(),
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  label: 'Método',
                  value: result.model.label,
                  // O "valor" aqui e nome, nao numero: `DCF simplificado (LPA)`
                  // nao cabe em uma linha ao lado da taxa de desconto, e a
                  // sigla cortada e o que distingue um modelo do outro.
                  valueMaxLines: 2,
                ),
              ),
              Expanded(
                child: MetricTile(
                  label: 'Taxa de desconto',
                  value: Fmt.percent(result.discountRate),
                  hint: result.model == ValuationModel.dcfFcff
                      ? 'WACC'
                      : 'custo do capital próprio',
                ),
              ),
              // O peso do terminal fica ao lado do método porque é da mesma
              // natureza: não é o preço justo, é quanto dele veio de premissa
              // em vez de exercício observado. **Não há nota de confiança** —
              // a decisão 32 mediu que a contagem de ressalvas ordenava ao
              // contrário do retorno realizado, e uma nota assim é falsa
              // precisão num número destinado a decisão patrimonial.
              if (diagnostics != null)
                Expanded(
                  child: MetricTile(
                    label: 'Peso do terminal',
                    value: Fmt.percent(diagnostics!.terminalShare, decimals: 0),
                    hint: 'do preço justo vem da perpetuidade',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Cenários: três faixas nomeadas ou distribuição sorteada.
///
/// O alternador existe porque os dois modos compartilham o mesmo caminho de
/// código — trocar é configuração, não refatoração.
class _ScenarioCard extends ConsumerWidget {
  final ValuationResult result;
  final ValuationSettings settings;
  final bool isLight;

  const _ScenarioCard({
    required this.result,
    required this.settings,
    required this.isLight,
  });

  /// Largura por unidade de escala de texto abaixo da qual o alternador sai do
  /// lado do título: em 320 dp sob 2,0x ele estourava 51 px.
  static const double larguraDoCabecalho = 300;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Empilhado, o rótulo cede e quebra linha: em 320 dp sob 2,0x nem a linha
    // própria cabia o texto ao lado do `Switch`. Ao lado do título ele não pode
    // ser flexível — ali a largura que o `Row` recebe não é limitada.
    Widget alternador({required bool empilhado}) {
      final rotulo = Text(
        'Monte Carlo',
        textAlign: TextAlign.right,
        style: context.finType.caption.copyWith(
          color: context.fin.textSecondary,
        ),
      );
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          empilhado ? Flexible(child: rotulo) : rotulo,
          // Mesmo motivo do alternador de IR na tela de análise: o
          // `Switch` pinta o respingo de tinta no `Material` mais
          // próximo, e o `GlassCard` interpõe um fundo próprio entre os
          // dois. Sem este `Material` transparente o toque não devolve
          // retorno visual e o framework acusa em tempo de execução.
          Material(
            type: MaterialType.transparency,
            child: Switch(
              value: settings.monteCarlo,
              activeThumbColor: context.fin.brand,
              onChanged:
                  ref.read(valuationSettingsProvider.notifier).setMonteCarlo,
            ),
          ),
        ],
      );
    }

    return GlassCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final escala = MediaQuery.textScalerOf(context).scale(1);
          final empilha = constraints.maxWidth < larguraDoCabecalho * escala;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: 'Cenários',
                // Sensibilidade, e não probabilidade: a banda de cenários
                // cobriu 8% do que aconteceu nas coortes, contra 90% nominais
                // (decisão 92).
                subtitle: settings.monteCarlo
                    ? 'Sensibilidade: ${settings.samples} sorteios de premissas'
                    : 'Sensibilidade: três conjuntos fixos de premissas',
                trailing: empilha ? null : alternador(empilhado: false),
              ),
              if (empilha)
                Align(
                  alignment: Alignment.centerRight,
                  child: alternador(empilhado: true),
                ),
              const Gap.md(),
              if (result.distribution != null)
                _DistributionView(
                  isLight: isLight,
                  distribution: result.distribution!,
                  marketPrice: result.marketPrice.reais,
                )
              else if (result.discreteScenarios != null)
                _DiscreteView(
                  isLight: isLight,
                  scenarios: result.discreteScenarios!,
                )
              else
                Text(
                  'Apenas o cenário base pôde ser calculado.',
                  style: context.finType.caption.copyWith(
                    color: context.fin.textSecondary,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Onde o preço mais os proventos caíram, nas coortes (itens C2 e C2b).
///
/// **É a incerteza medida, e não a sensibilidade.** A banda de cenários desloca
/// premissas e cobriu 8% do que aconteceu; esta vem do que aconteceu, com a
/// cobertura fora da amostra declarada. Sem pacote, o cartão não aparece.
///
/// **A faixa mudou de forma em 15/09/2026** (decisão 100). A de antes era a
/// razão entre o realizado e o preço justo, e na montagem corrigida das coortes
/// ela deixou de cobrir. A que cobre sai do preço de hoje, da volatilidade do
/// papel e — com o peso que a validação mediu, pequeno — do preço justo. O
/// cartão diz isso: a faixa não é mais "em torno do preço justo".
class _CalibratedBandCard extends ConsumerWidget {
  final ValuationResult result;

  const _CalibratedBandCard({required this.result});

  /// Frequência apresentada: oito em cada dez.
  static const double nominal = 0.8;

  /// Distância da nominal até onde a faixa se diz calibrada — o critério do R2.
  ///
  /// O cartão só afirma "8 de cada 10" quando a cobertura medida fora da
  /// amostra fica a até esta distância da nominal nos dois horizontes; senão,
  /// diz a cobertura e que a faixa não está calibrada. Na forma fixada antes de
  /// medir no C2b (decisão 100) ela fica: 79,0% em 12 meses e 80,4% em 36.
  static const double folgaDoCriterio = 0.05;

  /// Largura abaixo da qual cada horizonte ganha linha própria, em dp.
  static const double larguraMinimaPorColuna = 220;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabelas = ref.watch(calibratedBandsProvider).value ?? const [];
    final faixas = [
      for (final meses in const [12, 36])
        if (CalibratedBand.select(tabelas, months: meses, nominal: nominal)
            case final t?)
          if (CalibratedBand.of(
                result.fairValue,
                t,
                marketPrice: result.marketPrice,
                volatility: result.priceVolatility,
              )
              case final b?)
            (tabela: t, faixa: b),
    ];
    if (faixas.isEmpty) return const SizedBox.shrink();

    final coberturas = [
      for (final f in faixas)
        if (f.tabela.outOfSampleCoverage case final c?)
          '${Fmt.percent(c, decimals: 1)} em ${f.tabela.months} meses',
    ];
    final calibrada = faixas.every((f) => switch (f.tabela.outOfSampleCoverage) {
          final c? => (c - nominal).abs() <= folgaDoCriterio,
          null => false,
        });
    // A forma diz de onde a faixa sai, e as duas dizem coisas diferentes: a do
    // justo é a razão entre o realizado e ele; a da volatilidade parte do preço
    // de hoje e usa o justo com o peso medido. Prometer "em torno do preço
    // justo" na segunda seria o rótulo velho sobre o número novo.
    final daVolatilidade = faixas.any((f) => f.tabela is VolatilityBandTable);
    final origem = daVolatilidade
        ? 'Ela sai do preço de hoje, da volatilidade do papel e do preço justo, '
            'que entra com o peso que a validação mediu — pequeno, porque o '
            'preço converge pouco ao justo.'
        : 'Ela é a razão entre o realizado e o preço justo nas coortes.';
    final leitura = calibrada
        ? 'Em 8 de cada 10 avaliações passadas, o preço mais os proventos '
            'terminaram nesta faixa'
            '${coberturas.isEmpty ? '' : ' — ${coberturas.join(' e ')}, '
                'medidos fora da amostra'}. $origem'
        : 'Faixa central de 80% das avaliações passadas. Medida fora da '
            'amostra, ela conteve o preço mais os proventos em '
            '${coberturas.isEmpty ? 'uma fração não medida' : coberturas.join(' e ')}'
            ' dos casos — a mais de 5 pontos dos 80% que a nomeiam, e por isso '
            'não está calibrada. $origem';
    return Padding(
      padding: const EdgeInsets.only(bottom: FinSpace.md),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: 'Faixa calibrada',
              subtitle: 'Preço mais proventos no horizonte, medido nas coortes',
            ),
            const Gap.md(),
            // Cada faixa são dois valores em reais: abaixo de
            // [larguraMinimaPorColuna] por horizonte, elas se empilham em vez
            // de espremer os dois números numa coluna estreita.
            LayoutBuilder(
              builder: (context, constraints) {
                final tiles = [
                  for (final f in faixas)
                    MetricTile(
                      label: 'Em ${f.tabela.months} meses',
                      value: '${Fmt.money(f.faixa.low.reais)} a '
                          '${Fmt.money(f.faixa.high.reais)}',
                      hint: 'coortes de ${f.tabela.firstCohort} a '
                          '${f.tabela.lastCohort}',
                      valueMaxLines: 2,
                    ),
                ];
                if (constraints.maxWidth <
                    larguraMinimaPorColuna * tiles.length) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, t) in tiles.indexed) ...[
                        if (i > 0) const Gap.sm(),
                        t,
                      ],
                    ],
                  );
                }
                return Row(
                  children: [for (final t in tiles) Expanded(child: t)],
                );
              },
            ),
            const Gap.sm(),
            Text(
              '$leitura A largura é o tamanho do erro medido contra o que '
              'aconteceu: não é previsão.',
              style: context.finType.caption.copyWith(
                color: context.fin.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscreteView extends StatelessWidget {
  final Map<ScenarioBand, Money> scenarios;
  final bool isLight;

  const _DiscreteView({required this.scenarios, required this.isLight});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final band in ScenarioBand.values)
          if (scenarios[band] != null)
            Expanded(
              child: MetricTile(
                label: band.label,
                value: Fmt.money(scenarios[band]!.reais),
                trend: switch (band) {
                  ScenarioBand.bear => FinTrend.negative,
                  ScenarioBand.base => FinTrend.neutral,
                  ScenarioBand.bull => FinTrend.positive,
                },
              ),
            ),
      ],
    );
  }
}

class _DistributionView extends StatelessWidget {
  final ValueDistribution distribution;
  final double marketPrice;
  final bool isLight;

  const _DistributionView({
    required this.distribution,
    required this.marketPrice,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    final probability = distribution.probabilityAbove(marketPrice);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: MetricTile(
                label: 'P5',
                value: Fmt.money(distribution.p5),
                hint: 'pessimista',
                trend: FinTrend.negative,
              ),
            ),
            Expanded(
              child: MetricTile(
                label: 'Mediana',
                value: Fmt.money(distribution.median),
              ),
            ),
            Expanded(
              child: MetricTile(
                label: 'P95',
                value: Fmt.money(distribution.p95),
                hint: 'otimista',
                trend: FinTrend.positive,
              ),
            ),
          ],
        ),
        const Gap.md(),
        NoticeBanner(
          icon: Icons.casino_outlined,
          trend: probability > 0.5 ? FinTrend.positive : FinTrend.negative,
          message:
              'Em ${Fmt.percent(probability, decimals: 0)} dos sorteios de '
              'premissas o preço justo supera o preço de mercado atual '
              '(${Fmt.money(marketPrice)}). Sorteio de premissa não é '
              'probabilidade de preço.',
        ),
      ],
    );
  }
}

/// Sensibilidade: qual premissa mais move o preço justo.
class _SensitivityCard extends StatelessWidget {
  final ValuationResult result;
  final bool isLight;

  const _SensitivityCard({required this.result, required this.isLight});

  @override
  Widget build(BuildContext context) {
    final scenarios = result.discreteScenarios;
    final distribution = result.distribution;

    final bars = <({String label, double low, double high})>[];
    if (scenarios != null &&
        scenarios[ScenarioBand.bear] != null &&
        scenarios[ScenarioBand.bull] != null) {
      bars.add((
        label: 'Crescimento\ne desconto',
        low: scenarios[ScenarioBand.bear]!.reais,
        high: scenarios[ScenarioBand.bull]!.reais,
      ));
    }
    if (distribution != null) {
      bars.add((
        label: 'Faixa\nsorteada',
        low: distribution.p5,
        high: distribution.p95,
      ));
    }

    if (bars.isEmpty) return const SizedBox.shrink();

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Sensibilidade',
            subtitle: 'Quanto o preço justo se move com as premissas',
          ),
          const Gap.md(),
          TornadoChart(
            isLight: isLight,
            bars: bars,
            baseValue: result.fairValue.reais,
          ),
          const Gap.sm(),
          Text(
            'A linha central é o cenário base '
            '(${Fmt.money(result.fairValue.reais)}).',
            style: context.finType.caption.copyWith(
              color: context.fin.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

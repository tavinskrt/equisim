import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/material.dart';

import '../theme/fin_space.dart';
import '../../presentation/theme/fin_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../components/fin_amount.dart';
import '../shared/charts.dart';
import '../shared/ui_kit.dart';
import '../study/study_notifier.dart';
import '../theme/fin_colors.dart';
import 'manual_valuation_page.dart';
import 'saved_valuations_card.dart';
import 'valuation_providers.dart';
import '../shared/domain_copy.dart';

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

  /// Declara o corpo da avaliação.
  const ValuationView({
    super.key,
    required this.ticker,
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
          : _ValuationBody(result: result),
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

    return Scaffold(
      body: ScreenBackground(
        child: SafeArea(
          child: Column(
            children: [
              _Header(ticker: ticker),
              Expanded(child: ValuationView(ticker: ticker)),
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
  Ticker? _chosen;

  @override
  Widget build(BuildContext context) {
    final study = ref.watch(studyProvider).study;

    final available = <Ticker>[
      ...study.principal.tickers,
      ...study.reserve.tickers,
    ];

    if (available.isEmpty) {
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
    final ticker = available.contains(_chosen)
        ? _chosen!
        : available.first;

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
                    for (final t in available)
                      ChoiceChip(
                        label: Text(t.value),
                        selected: t == ticker,
                        onSelected: (_) => setState(() => _chosen = t),
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
        Expanded(child: ValuationView(ticker: ticker)),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final Ticker ticker;
  const _Header({required this.ticker});

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

  const _ValuationBody({required this.result});

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
              _PriceCard(result: result),
              // Os valuations que o usuário confirmou na edição (decisão 150),
              // logo abaixo do preço do motor com que eles se comparam. Sem
              // nenhum salvo para o ativo, o cartão não ocupa espaço.
              SavedValuationsCard(result: result),
              const Gap.md(),
              _ModelCard(result: result),
              const Gap.md(),
              _CalibratedBandCard(result: result),
              _SensitivityCard(
                result: result,
                settings: settings,
              ),
              if (result.triangulation != null) ...[
                const Gap.md(),
                _PeerCard(result: result),
              ],
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
  const _PriceCard({required this.result});

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
                  hint: 'pelas premissas do motor',
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
          // **O cálculo do usuário** (decisão 147): a conta do motor, aberta
          // para quem discorda dela. Fica no cartão do preço porque é o preço
          // que ele refaz, e só aparece quando a cascata congelou a conta.
          if (result.manual != null) ...[
            const Gap.md(),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: FinSpace.md,
              runSpacing: FinSpace.sm,
              children: [
                FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ManualValuationPage(result: result),
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: context.fin.brand,
                    foregroundColor: context.fin.textOnBrand,
                  ),
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Editar valuation'),
                ),
                Text(
                  'Discorda do motor? Refaça a conta com os seus números.',
                  style: context.finType.caption.copyWith(
                    color: context.fin.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  final ValuationResult result;
  const _ModelCard({required this.result});

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

/// A segunda leitura, por múltiplos de pares (item B5, decisão 118).
///
/// **Ela fica depois da sensibilidade, e antes das ressalvas.** A ordem é de
/// autoridade: primeiro o preço justo e o modelo que o produziu, depois a faixa,
/// e só então a leitura que serve para conferir o nível. Pô-la ao lado do preço
/// justo sugeriria que as duas competem, e elas não competem — uma é o produto,
/// a outra é o teste de sanidade.
class _PeerCard extends StatelessWidget {
  final ValuationResult result;
  const _PeerCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final t = result.triangulation!;
    final applied = [for (final r in t.readings) if (r.applied) r];
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Segunda leitura — múltiplos de pares',
            subtitle: 'Teste de sanidade sobre o nível; o preço justo continua '
                'sendo o do fluxo descontado',
          ),
          const Gap.md(),
          if (applied.isEmpty)
            Text(
              'Nenhum múltiplo se aplicou a este ativo. '
              '${[for (final r in t.readings) '${r.kind.label}: ${r.refusal?.label ?? "—"}'].join("; ")}.',
              style: context.finType.bodySm.copyWith(
                color: context.fin.textSecondary,
              ),
            )
          else ...[
            Row(
              children: [
                for (final r in applied)
                  Expanded(
                    child: MetricTile(
                      label: r.kind.label,
                      value: Fmt.money(r.fairValuePerShare!),
                      hint: '${r.peer!.median.toStringAsFixed(1)}× em '
                          '${r.peer!.peers} pares',
                    ),
                  ),
              ],
            ),
            const Gap.md(),
            Row(
              children: [
                Expanded(
                  child: MetricTile(
                    label: 'Mediana dos múltiplos',
                    value: Fmt.money(t.consolidated!),
                    hint: 'das ${t.applied} leituras que se aplicaram',
                  ),
                ),
                Expanded(
                  child: MetricTile(
                    label: 'Contra o fluxo descontado',
                    value: t.divergence == null
                        ? '—'
                        : Fmt.percent(t.divergence!, decimals: 0),
                    hint: t.diverges
                        ? 'as duas leituras discordam'
                        : 'as duas leituras concordam',
                  ),
                ),
              ],
            ),
          ],
          // As recusas ficam listadas mesmo quando alguma leitura se aplicou:
          // saber que o `EV/EBITDA` não entrou, e por quê, é parte de ler o
          // número que entrou.
          if (applied.isNotEmpty && applied.length < t.readings.length) ...[
            const Gap.sm(),
            Text(
              'Fora: ${[for (final r in t.readings) if (!r.applied) '${r.kind.label} (${r.refusal?.label ?? "—"})'].join("; ")}.',
              style: context.finType.bodySm.copyWith(
                color: context.fin.textSecondary,
              ),
            ),
          ],
        ],
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
  static const double criterionMargin = 0.05;

  /// Largura abaixo da qual cada horizonte ganha linha própria, em dp.
  static const double minWidthPerColumn = 220;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tables = ref.watch(calibratedBandsProvider).value ?? const [];
    final bands = [
      for (final months in const [12, 36])
        if (CalibratedBand.select(tables, months: months, nominal: nominal)
            case final t?)
          if (CalibratedBand.of(
                result.fairValue,
                t,
                marketPrice: result.marketPrice,
                volatility: result.priceVolatility,
              )
              case final b?)
            (table: t, band: b),
    ];
    if (bands.isEmpty) return const SizedBox.shrink();

    final coverages = [
      for (final f in bands)
        if (f.table.outOfSampleCoverage case final c?)
          '${Fmt.percent(c, decimals: 1)} em ${f.table.months} meses',
    ];
    final calibrated = bands.every((f) => switch (f.table.outOfSampleCoverage) {
          final c? => (c - nominal).abs() <= criterionMargin,
          null => false,
        });
    // A forma diz de onde a faixa sai, e as duas dizem coisas diferentes: a do
    // justo é a razão entre o realizado e ele; a da volatilidade parte do preço
    // de hoje e usa o justo com o peso medido. Prometer "em torno do preço
    // justo" na segunda seria o rótulo velho sobre o número novo.
    final fromVolatility = bands.any((f) => f.table is VolatilityBandTable);
    final origin = fromVolatility
        ? 'Ela sai do preço de hoje, da volatilidade do papel e do preço justo, '
            'que entra com o peso que a validação mediu — pequeno, porque o '
            'preço converge pouco ao justo.'
        : 'Ela é a razão entre o realizado e o preço justo nas coortes.';
    final reading = calibrated
        ? 'Em 8 de cada 10 avaliações passadas, o preço mais os proventos '
            'terminaram nesta faixa'
            '${coverages.isEmpty ? '' : ' — ${coverages.join(' e ')}, '
                'medidos fora da amostra'}. $origin'
        : 'Faixa central de 80% das avaliações passadas. Medida fora da '
            'amostra, ela conteve o preço mais os proventos em '
            '${coverages.isEmpty ? 'uma fração não medida' : coverages.join(' e ')}'
            ' dos casos — a mais de 5 pontos dos 80% que a nomeiam, e por isso '
            'não está calibrada. $origin';
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
            // [minWidthPerColumn] por horizonte, elas se empilham em vez
            // de espremer os dois números numa coluna estreita.
            LayoutBuilder(
              builder: (context, constraints) {
                final tiles = [
                  for (final f in bands)
                    MetricTile(
                      label: 'Em ${f.table.months} meses',
                      value: '${Fmt.money(f.band.low.reais)} a '
                          '${Fmt.money(f.band.high.reais)}',
                      hint: 'coortes de ${f.table.firstCohort} a '
                          '${f.table.lastCohort}',
                      valueMaxLines: 2,
                    ),
                ];
                if (constraints.maxWidth <
                    minWidthPerColumn * tiles.length) {
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
              '$reading A largura é o tamanho do erro medido contra o que '
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

/// **Sensibilidade: quanto o preço justo se move com as premissas** (decisão
/// 148).
///
/// Era dois cartões — "Cenários", com os três valores, e "Sensibilidade", com
/// os mesmos dois extremos em barra —, e o primeiro chamava de «Pessimista» e
/// «Otimista» o que é deslocamento de premissa. **É sensibilidade, e não
/// cenário** (decisão 92): a faixa cobriu 8% do que aconteceu nas coortes, e a
/// incerteza medida é a faixa calibrada, logo acima.
///
/// Os rótulos dizem **o que foi mexido**, e o valor diz o que deu. Quando as
/// premissas mais brandas dão preço menor que as mais duras — a empresa rende
/// abaixo do custo de capital, e crescer destrói valor (item B38) —, o cartão
/// diz isso em vez de deixar o leitor supor um erro.
///
/// O alternador existe porque os dois modos compartilham o mesmo caminho de
/// código — trocar é configuração, não refatoração.
class _SensitivityCard extends ConsumerWidget {
  final ValuationResult result;
  final ValuationSettings settings;

  const _SensitivityCard({
    required this.result,
    required this.settings,
  });

  /// Largura por unidade de escala de texto abaixo da qual o alternador sai do
  /// lado do título: em 320 dp sob 2,0x ele estourava 51 px.
  static const double headerWidth = 300;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.fin;
    final t = context.finType;
    final base = result.fairValue.reais;
    final scenarios = result.discreteScenarios;
    final distribution = result.distribution;
    final harsh = scenarios?[ScenarioBand.bear]?.reais;
    final mild = scenarios?[ScenarioBand.bull]?.reais;

    // Empilhado, o rótulo cede e quebra linha: em 320 dp sob 2,0x nem a linha
    // própria cabia o texto ao lado do `Switch`. Ao lado do título ele não pode
    // ser flexível — ali a largura que o `Row` recebe não é limitada.
    Widget toggle({required bool stacked}) {
      final label = Text(
        'Monte Carlo',
        textAlign: TextAlign.right,
        style: t.caption.copyWith(color: c.textSecondary),
      );
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          stacked ? Flexible(child: label) : label,
          // O `Switch` pinta o respingo de tinta no `Material` mais próximo, e
          // o `GlassCard` interpõe um fundo próprio entre os dois. Sem este
          // `Material` transparente o toque não devolve retorno visual e o
          // framework acusa em tempo de execução.
          Material(
            type: MaterialType.transparency,
            child: Switch(
              value: settings.monteCarlo,
              activeThumbColor: c.brand,
              onChanged:
                  ref.read(valuationSettingsProvider.notifier).setMonteCarlo,
            ),
          ),
        ],
      );
    }

    // O tornado desenha do menor ao maior: com a ordem invertida, os
    // extremos trocam de lado, e a barra continua sendo a faixa.
    final bars = <({String label, double low, double high})>[
      if (harsh != null && mild != null)
        (
          // Uma linha: o tornado corta o rótulo na primeira, e o
          // «Crescimento\ne desconto» de antes aparecia só como «Crescimento».
          label: 'Crescimento e taxa',
          low: harsh < mild ? harsh : mild,
          high: harsh < mild ? mild : harsh,
        ),
      if (distribution != null)
        (
          label: 'Faixa sorteada',
          low: distribution.p5,
          high: distribution.p95,
        ),
    ];

    return GlassCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(1);
          final stacks = constraints.maxWidth < headerWidth * scale;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: 'Sensibilidade',
                subtitle: settings.monteCarlo
                    ? 'Quanto o preço justo se move em ${settings.samples} '
                        'sorteios de crescimento, taxa e perpetuidade'
                    : 'Quanto o preço justo se move se o crescimento e a taxa '
                        'mudarem juntos',
                trailing: stacks ? null : toggle(stacked: false),
              ),
              if (stacks)
                Align(
                  alignment: Alignment.centerRight,
                  child: toggle(stacked: true),
                ),
              const Gap.md(),
              if (distribution != null)
                _DistributionView(
                  distribution: distribution,
                  marketPrice: result.marketPrice.reais,
                )
              else if (scenarios != null)
                _DiscreteView(scenarios: scenarios, base: base)
              else
                Text(
                  'Só o preço justo do motor pôde ser calculado.',
                  style: t.caption.copyWith(color: c.textSecondary),
                ),
              if (harsh != null && mild != null && mild < harsh) ...[
                const Gap.md(),
                NoticeBanner(
                  message: 'Aqui as premissas mais brandas dão preço menor que '
                      'as mais duras. A empresa rende abaixo do custo de '
                      'capital, e crescer mais pede reinvestir num negócio que '
                      'não paga o que custa: o crescimento destrói valor em vez '
                      'de criar. Não é erro da conta.',
                ),
              ],
              if (bars.isNotEmpty) ...[
                const Gap.md(),
                TornadoChart(bars: bars, baseValue: base),
              ],
              const Gap.sm(),
              Text(
                'A linha central é o preço justo do motor '
                '(${Fmt.money(base)}). Isto é sensibilidade, e não '
                'probabilidade: a incerteza medida é a faixa calibrada.',
                style: t.caption.copyWith(color: c.textTertiary),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Os três conjuntos fixos de premissas, com o que cada um mexeu.
///
/// A cor sai da posição do valor contra o preço justo, e não do nome: com o
/// crescimento destruindo valor, as premissas mais brandas dão preço menor, e
/// pintá-las de verde diria o contrário.
class _DiscreteView extends StatelessWidget {
  final Map<ScenarioBand, Money> scenarios;
  final double base;

  const _DiscreteView({
    required this.scenarios,
    required this.base,
  });

  @override
  Widget build(BuildContext context) {
    final g = Fmt.ratio(DiscreteScenarios.defaultGrowthDelta * 100, decimals: 0);
    final d =
        Fmt.ratio(DiscreteScenarios.defaultDiscountDelta * 100, decimals: 0);
    // Espaço fixo entre o número e a unidade: em coluna estreita a quebra
    // separava "−3" de "p.p.".
    const e = ' ';
    String note(ScenarioBand band) => switch (band) {
          ScenarioBand.bear => 'crescimento −$g${e}p.p., taxa +$d${e}p.p.',
          ScenarioBand.base => 'o preço justo',
          ScenarioBand.bull => 'crescimento +$g${e}p.p., taxa −$d${e}p.p.',
        };
    return MetricTileRow(
      tiles: [
        for (final band in ScenarioBand.values)
          if (scenarios[band] case final value?)
            MetricTile(
              label: band.label,
              value: Fmt.money(value.reais),
              hint: note(band),
              trend: band == ScenarioBand.base
                  ? FinTrend.neutral
                  : FinAmount.trendOf(value.reais - base),
            ),
      ],
    );
  }
}

/// A distribuição sorteada: os percentis e a fração acima do preço de hoje.
class _DistributionView extends StatelessWidget {
  final ValueDistribution distribution;
  final double marketPrice;

  const _DistributionView({
    required this.distribution,
    required this.marketPrice,
  });

  @override
  Widget build(BuildContext context) {
    final probability = distribution.probabilityAbove(marketPrice);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MetricTileRow(
          tiles: [
            MetricTile(
              label: 'P5',
              value: Fmt.money(distribution.p5),
              hint: '5% dos sorteios abaixo',
            ),
            MetricTile(
              label: 'Mediana',
              value: Fmt.money(distribution.median),
              hint: 'metade abaixo, metade acima',
            ),
            MetricTile(
              label: 'P95',
              value: Fmt.money(distribution.p95),
              hint: '5% dos sorteios acima',
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

import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/fin_amount.dart';
import '../shared/domain_copy.dart';
import '../shared/ui_kit.dart';
import '../theme/fin_colors.dart';
import '../theme/fin_space.dart';
import '../theme/fin_theme.dart';
import 'manual_copy.dart';
import 'normalization_panel.dart';

/// Largura a partir da qual os campos e o resultado ficam lado a lado, em dp.
///
/// Abaixo dela o resultado desce para depois dos campos, e o preço justo do
/// usuário fica numa barra fixa no rodapé: quem edita um campo no celular
/// precisa ver o número mudar sem rolar a tela.
const double _twoColumnWidth = 960;

/// **Editar valuation: o cálculo do usuário** (decisão 147).
///
/// Os campos abrem com os números do motor para o ativo — o lucro de partida,
/// o crescimento, a taxa de desconto, a perpetuidade, o reinvestimento —, e o
/// usuário troca o que discordar. A conta é a do motor, congelada em
/// [ValuationResult.manual]: sem troca, o preço é o do motor ao centavo; com
/// troca, muda só o que foi trocado.
///
/// **O preço do usuário não herda a validação.** A faixa calibrada e a
/// habilidade medida são do preço do motor, e a tela diz isso no rodapé.
class ManualValuationPage extends StatefulWidget {
  /// A avaliação do motor, com a conta congelada.
  final ValuationResult result;

  /// Premissas com que a tela abre. **O aplicativo não o usa** — a tela abre
  /// nos números do motor —; existe para o teste e para a captura da lente
  /// `tela`, que precisam mostrar a tela já editada.
  final ManualPremises? initial;

  /// Declara a tela. [result] precisa trazer [ValuationResult.manual].
  const ManualValuationPage({super.key, required this.result, this.initial});

  @override
  State<ManualValuationPage> createState() => _ManualValuationPageState();
}

class _ManualValuationPageState extends State<ManualValuationPage> {
  late ManualPremises _p;

  /// O campo que "o que o preço de hoje supõe" resolve.
  ManualField _target = ManualField.discountRate;

  /// A última resposta de "o que o preço de hoje supõe", ou `null`. Qualquer
  /// troca de campo a apaga: ela respondia às premissas de antes.
  ManualSolution? _answer;

  ManualValuation get _m => widget.result.manual!;

  @override
  void initState() {
    super.initState();
    _p = widget.initial ?? _m.enginePremises;
  }

  void _swap(ManualPremises p) => setState(() {
        _p = p;
        _answer = null;
      });

  void _resolver() =>
      setState(() => _answer = _m.solve(_target, _p));

  @override
  Widget build(BuildContext context) {
    final m = _m;
    final valuation = m.evaluate(_p);
    final steps = m.attribution(_p);
    final changed = steps.isNotEmpty;
    final isWide = MediaQuery.sizeOf(context).width >= _twoColumnWidth;
    final output = valuation.valueOrNull;
    final failure = valuation.failureOrNull;

    final fields = _Fields(
      m: m,
      p: _p,
      failure: failure,
      output: output,
      changed: changed,
      normalization: widget.result.diagnostics?.baseNormalization,
      onChanged: _swap,
    );
    final result = <Widget>[
      _SummaryCard(m: m, output: output, failure: failure, changed: changed),
      const Gap.md(),
      if (output != null) ...[
        _CalculationCard(m: m, output: output),
        const Gap.md(),
      ],
      _DisagreementCard(m: m, steps: steps),
      const Gap.md(),
      _ReverseCard(
        m: m,
        p: _p,
        target: _target,
        answer: _answer,
        onTarget: (f) => setState(() {
          _target = f;
          _answer = null;
        }),
        onResolver: _resolver,
        onUse: (f, v) => _swap(_p.withValue(f, v)),
      ),
      if (output != null) ...[
        const Gap.md(),
        _YearsCard(m: m, p: _p, output: output),
      ],
      if (output != null && output.notices.isNotEmpty) ...[
        const Gap.md(),
        for (final n in output.notices)
          Padding(
            padding: const EdgeInsets.only(bottom: FinSpace.sm),
            child: NoticeBanner(message: ManualCopy.warning(n)),
          ),
      ],
      const Gap.md(),
      Text(
        'A faixa calibrada e a habilidade medida do Equisim são do preço '
        'justo do motor, porque foi ele que as avaliações passadas testaram. '
        'O preço desta tela é a conta do motor com os seus números: o '
        'resultado da sua opinião, sem validação própria.',
        style: context.finType.caption.copyWith(
          color: context.fin.textTertiary,
        ),
      ),
    ];

    return Scaffold(
      body: ScreenBackground(
        child: SafeArea(
          bottom: isWide,
          child: Column(
            children: [
              _Header(
                ticker: widget.result.ticker,
                changed: changed,
                onBackToEngine: () => _swap(m.enginePremises),
              ),
              Expanded(
                child: isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 11,
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(
                                FinSpace.lg,
                                FinSpace.lg,
                                FinSpace.sm,
                                FinSpace.xl,
                              ),
                              children: [fields],
                            ),
                          ),
                          Expanded(
                            flex: 9,
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(
                                FinSpace.sm,
                                FinSpace.lg,
                                FinSpace.lg,
                                FinSpace.xl,
                              ),
                              children: result,
                            ),
                          ),
                        ],
                      )
                    : ListView(
                        padding: const EdgeInsets.all(FinSpace.lg),
                        children: [
                          fields,
                          const Gap.lg(),
                          ...result,
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: isWide
          ? null
          : _ResultBar(m: m, output: output, changed: changed),
    );
  }
}

// ---------------------------------------------------------------- Cabeçalho --

class _Header extends StatelessWidget {
  final Ticker ticker;
  final bool changed;
  final VoidCallback onBackToEngine;

  const _Header({
    required this.ticker,
    required this.changed,
    required this.onBackToEngine,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    return AppHeader(
      leading: IconButton(
        tooltip: 'Voltar à avaliação',
        icon: Icon(Icons.arrow_back, size: 20, color: c.textPrimary),
        onPressed: () => Navigator.pop(context),
      ),
      title: 'Editar valuation',
      subtitle: '${ticker.value} · seu cálculo',
      // Ícone, e não botão com texto: em 320 dp o rótulo estourava o
      // cabeçalho. O botão com texto mora no cartão "Seus números".
      actions: [
        IconButton(
          tooltip: 'Voltar aos números do motor',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: changed ? onBackToEngine : null,
          icon: Icon(
            Icons.restart_alt,
            size: 20,
            color: changed ? c.positive : c.textTertiary,
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------- Campos --

/// Como o valor de um campo se escreve e se lê.
enum _Unit {
  /// Reais, escritos em milhões com uma casa.
  reais,

  /// Taxa ao ano, em percentual com duas casas.
  rate,

  /// Parcela do lucro, em percentual com uma casa.
  fraction;

  String display(double v) => switch (this) {
        _Unit.reais => Fmt.ratio(v / 1e6, decimals: 1),
        _Unit.rate => Fmt.ratio(v * 100, decimals: 2),
        _Unit.fraction => Fmt.ratio(v * 100, decimals: 1),
      };

  /// O valor escrito como o motor o lê na referência: `R$ 1.234,5 mi`,
  /// `14,09%`.
  String reference(double v) => switch (this) {
        _Unit.reais => 'R\$ ${display(v)} mi',
        _Unit.rate || _Unit.fraction => '${display(v)}%',
      };

  /// Lê o que o usuário digitou, na convenção brasileira, ou `null` quando
  /// não é número.
  ///
  /// Vírgula é decimal. Sem vírgula, o ponto é decimal — exceto em reais,
  /// onde `1.234` com três dígitos depois do ponto é milhar.
  double? read(String text) {
    var s = text
        .replaceAll(RegExp(r'\s'), '')
        .replaceAll('R\$', '')
        .replaceAll('%', '')
        .replaceAll('−', '-');
    if (s.isEmpty || s == '-') return null;
    if (s.contains(',')) {
      s = s.replaceAll('.', '').replaceAll(',', '.');
    } else if (this == _Unit.reais &&
        RegExp(r'^-?\d{1,3}(\.\d{3})+$').hasMatch(s)) {
      s = s.replaceAll('.', '');
    }
    final n = double.tryParse(s);
    if (n == null || !n.isFinite) return null;
    return switch (this) {
      _Unit.reais => n * 1e6,
      _Unit.rate || _Unit.fraction => n / 100,
    };
  }

  /// Diferença abaixo da qual o campo continua "igual ao do motor": metade
  /// da última casa exibida.
  double get tolerance => switch (this) {
        _Unit.reais => 0.05e6,
        _Unit.rate => 0.00005,
        _Unit.fraction => 0.0005,
      };
}

/// Os cartões dos campos, na ordem em que a conta os usa.
class _Fields extends StatelessWidget {
  final ManualValuation m;
  final ManualPremises p;
  final Failure? failure;
  final ManualOutcome? output;
  final bool changed;

  /// Por que o motor normalizou o lucro de partida — o painel do cartão dele.
  final BaseNormalization? normalization;
  final ValueChanged<ManualPremises> onChanged;

  const _Fields({
    required this.m,
    required this.p,
    required this.failure,
    required this.output,
    required this.changed,
    required this.normalization,
    required this.onChanged,
  });

  /// O campo que a recusa nomeia, quando ela nomeia um.
  ManualField? get _refused {
    final f = failure;
    if (f is! InvalidInput) return null;
    return ManualField.values.asNameMap()[f.field];
  }

  String? _error(ManualField field) {
    final r = _refused;
    final f = failure;
    if (r == null || f == null) return null;
    // A margem da perpetuidade é relação entre a taxa e o crescimento perpétuo:
    // os dois campos a mostram.
    final namesField = r == field ||
        (r == ManualField.perpetualGrowth && field == ManualField.discountRate);
    return namesField ? ManualCopy.refusal(f) : null;
  }

  @override
  Widget build(BuildContext context) {
    final engine = m.enginePremises;
    final lane = m.lane;
    final c = context.fin;
    final t = context.finType;

    final published = m.publishedBase;
    final String refBase;
    if (m.rebuiltBase) {
      refBase = 'Motor: ${_Unit.reais.reference(engine.baseProfit)} — '
          'reconstruído do retorno do ciclo, porque o último exercício veio no '
          'prejuízo.';
    } else if (published != null && (m.baseFactor - 1).abs() > 0.005) {
      refBase = 'Motor: ${_Unit.reais.reference(engine.baseProfit)} — o '
          'último exercício, ${_Unit.reais.reference(published)}, '
          'normalizado ${m.baseFactor > 1 ? 'para cima' : 'para baixo'} pelo '
          'ciclo (×${Fmt.ratio(m.baseFactor, decimals: 2)}).';
    } else {
      refBase = 'Motor: ${_Unit.reais.reference(engine.baseProfit)} — o '
          'último exercício publicado.';
    }

    final engineTerminalRate = m.engineTerminalRate;
    final rateRef = 'Motor: ${_Unit.rate.reference(engine.discountRate)} '
        'no ano 1 e ${_Unit.rate.reference(engineTerminalRate)} na '
        'perpetuidade — a curva de juros do Tesouro mais o beta vezes o prêmio '
        'de mercado.';
    final wacc = output?.capitalCostRates;
    final firmNote = lane == ValuationLane.firm && wacc != null
        ? 'Na via da firma, o custo médio do capital do motor '
            '(${_Unit.rate.reference(wacc.first)} no ano 1) continua '
            'guiando o retorno e a perpetuidade da operação: a taxa daqui só '
            'desconta.'
        : null;

    final neutralEngine = engine.terminalReturn == null;
    final newCapitalRef = neutralEngine
        ? 'Motor: igual à taxa (${_Unit.rate.reference(engineTerminalRate)}).'
        : 'Motor: ${_Unit.rate.reference(engine.terminalReturn!)} — vantagem '
            'competitiva medida no histórico da empresa.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: 'Seus números',
                subtitle: 'Os campos abrem com os números do motor. Troque o '
                    'que discordar: o preço muda enquanto você digita.',
              ),
              const Gap.sm(),
              Text(
                lane == ValuationLane.firm
                    ? 'Este ativo é avaliado pela via da firma: a conta parte do '
                        'lucro da operação, desconta o que sobra ao acionista '
                        'depois da dívida e divide pelas ações.'
                    : 'Este ativo é avaliado pela via do acionista: a conta parte '
                        'do lucro líquido, desconta o que sobra depois de '
                        'reinvestir e divide pelas ações.',
                style: t.bodySm.copyWith(color: c.textSecondary),
              ),
              if (changed) ...[
                const Gap.xs(),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _Action(
                    text: 'Voltar aos números do motor',
                    icon: Icons.restart_alt,
                    onPressed: () => onChanged(engine),
                  ),
                ),
              ],
            ],
          ),
        ),
        const Gap.md(),
        _NumericField(
          field: ManualField.baseProfit,
          label: ManualCopy.label(ManualField.baseProfit, lane),
          explanation: ManualCopy.explanation(ManualField.baseProfit, lane),
          reference: refBase,
          value: p.baseProfit,
          engineValue: engine.baseProfit,
          unit: _Unit.reais,
          step: (engine.baseProfit * 0.05).abs(),
          grid: 1e5,
          minimum: 0,
          maximum: engine.baseProfit * 3,
          error: _error(ManualField.baseProfit),
          onChanged: (v) => onChanged(p.copyWith(baseProfit: v)),
          extras: [
            if (published != null &&
                published > 0 &&
                (published - p.baseProfit).abs() > _Unit.reais.tolerance)
              _Action(
                text:
                    'Usar o último exercício (${_Unit.reais.reference(published)})',
                onPressed: () => onChanged(p.copyWith(baseProfit: published)),
              ),
          ],
          detail: normalization == null
              ? null
              : NormalizationPanel(normalization: normalization!),
        ),
        const Gap.md(),
        _NumericField(
          field: ManualField.growth,
          label: ManualCopy.label(ManualField.growth, lane),
          explanation: ManualCopy.explanation(ManualField.growth, lane),
          reference: 'Motor: ${_Unit.rate.reference(engine.growth)} no ano 1, '
              'caindo em linha reta até o crescimento da perpetuidade.',
          value: p.growth,
          engineValue: engine.growth,
          unit: _Unit.rate,
          step: 0.0025,
          grid: 0.0025,
          minimum: -0.20,
          maximum: 0.40,
          error: _error(ManualField.growth),
          onChanged: (v) => onChanged(p.copyWith(growth: v)),
          forcedChanged: p.growthPath != engine.growthPath,
          onBackToEngine: () => onChanged(
            p.copyWith(growth: engine.growth, growthPath: engine.growthPath),
          ),
          modes: _Modes<ManualGrowthPath>(
            value: p.growthPath,
            options: const {
              ManualGrowthPath.decays: 'Cai até a perpetuidade',
              ManualGrowthPath.constant: 'Constante nos 10 anos',
            },
            onChanged: (v) => onChanged(p.copyWith(growthPath: v)),
          ),
        ),
        const Gap.md(),
        _NumericField(
          field: ManualField.perpetualGrowth,
          label: ManualCopy.label(ManualField.perpetualGrowth, lane),
          explanation: ManualCopy.explanation(ManualField.perpetualGrowth, lane),
          reference: 'Motor: '
              '${_Unit.rate.reference(engine.perpetualGrowth)}.',
          value: p.perpetualGrowth,
          engineValue: engine.perpetualGrowth,
          unit: _Unit.rate,
          step: 0.0025,
          grid: 0.0025,
          minimum: -0.02,
          maximum: 0.12,
          error: _error(ManualField.perpetualGrowth),
          onChanged: (v) => onChanged(p.copyWith(perpetualGrowth: v)),
        ),
        const Gap.md(),
        _NumericField(
          field: ManualField.discountRate,
          label: ManualCopy.label(ManualField.discountRate, lane),
          explanation: ManualCopy.explanation(ManualField.discountRate, lane),
          reference: rateRef,
          note: firmNote,
          value: p.discountRate,
          engineValue: engine.discountRate,
          unit: _Unit.rate,
          step: 0.0025,
          grid: 0.0025,
          minimum: 0.04,
          maximum: 0.30,
          error: _error(ManualField.discountRate),
          onChanged: (v) => onChanged(p.copyWith(discountRate: v)),
          forcedChanged: p.ratePath != engine.ratePath,
          onBackToEngine: () => onChanged(
            p.copyWith(discountRate: engine.discountRate, ratePath: engine.ratePath),
          ),
          modes: _Modes<ManualRatePath>(
            value: p.ratePath,
            options: const {
              ManualRatePath.engine: 'Segue a curva, como no motor',
              ManualRatePath.constant: 'Uma taxa só, em todos os anos',
            },
            onChanged: (v) => onChanged(p.copyWith(ratePath: v)),
          ),
        ),
        const Gap.md(),
        _ReinvestmentCard(
          m: m,
          p: p,
          engine: engine,
          error: _error,
          onChanged: onChanged,
        ),
        if (p.reinvestment == ManualReinvestment.byReturn) ...[
          const Gap.md(),
          _NewCapitalCard(
            m: m,
            p: p,
            engine: engine,
            reference: newCapitalRef,
            error: _error(ManualField.terminalReturn),
            onChanged: onChanged,
          ),
        ],
      ],
    );
  }
}

/// O reinvestimento: pelo retorno sobre o capital, como o motor, ou uma
/// parcela fixa do lucro.
class _ReinvestmentCard extends StatelessWidget {
  final ManualValuation m;
  final ManualPremises p;
  final ManualPremises engine;
  final String? Function(ManualField) error;
  final ValueChanged<ManualPremises> onChanged;

  const _ReinvestmentCard({
    required this.m,
    required this.p,
    required this.engine,
    required this.error,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final lane = m.lane;
    final modes = _Modes<ManualReinvestment>(
      value: p.reinvestment,
      options: const {
        ManualReinvestment.byReturn: 'Pelo retorno, como no motor',
        ManualReinvestment.fixedFraction: 'Uma parcela fixa do lucro',
      },
      onChanged: (v) => onChanged(p.copyWith(reinvestment: v)),
    );
    if (p.reinvestment == ManualReinvestment.fixedFraction) {
      return _NumericField(
        field: ManualField.retention,
        label: ManualCopy.label(ManualField.retention, lane),
        explanation: ManualCopy.explanation(ManualField.retention, lane),
        reference: 'Ponto de partida: a parcela do ano 1 no motor, '
            '${_Unit.fraction.reference(engine.retention)}. Com ela fixa, o '
            'crescimento deixa de depender do retorno, e a perpetuidade é '
            'Gordon com a mesma parcela.',
        value: p.retention,
        engineValue: engine.retention,
        unit: _Unit.fraction,
        step: 0.01,
        grid: 0.01,
        minimum: 0,
        maximum: 0.95,
        error: error(ManualField.retention),
        onChanged: (v) => onChanged(p.copyWith(retention: v)),
        modes: modes,
        // A parcela é do usuário, e o motor não a usa: o selo de alterado é o
        // do modo, e não o do valor — e voltar ao motor é voltar ao modo dele.
        forcedChanged: true,
        onBackToEngine: () => onChanged(p.copyWith(
          reinvestment: engine.reinvestment,
          returnOnCapital: engine.returnOnCapital,
          retention: engine.retention,
        )),
      );
    }
    return _NumericField(
      field: ManualField.returnOnCapital,
      label: ManualCopy.label(ManualField.returnOnCapital, lane),
      explanation: ManualCopy.explanation(ManualField.returnOnCapital, lane),
      reference: engine.returnOnCapital > 0
          ? 'Motor: ${_Unit.rate.reference(engine.returnOnCapital)} no ano 1.'
          : 'Motor: sem retorno medido — o motor não reinveste nada para '
              'crescer, e o resultado declara isso.',
      value: p.returnOnCapital,
      engineValue: engine.returnOnCapital,
      unit: _Unit.rate,
      step: 0.0025,
      grid: 0.0025,
      minimum: 0,
      maximum: 0.60,
      error: error(ManualField.returnOnCapital),
      onChanged: (v) => onChanged(p.copyWith(returnOnCapital: v)),
      modes: modes,
    );
  }
}

/// O retorno do capital novo na perpetuidade: igual à taxa, como o motor sem
/// vantagem competitiva, ou o que o usuário disser.
class _NewCapitalCard extends StatelessWidget {
  final ManualValuation m;
  final ManualPremises p;
  final ManualPremises engine;
  final String reference;
  final String? error;
  final ValueChanged<ManualPremises> onChanged;

  const _NewCapitalCard({
    required this.m,
    required this.p,
    required this.engine,
    required this.reference,
    required this.error,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final lane = m.lane;
    final ownTerminal = p.terminalReturn != null;
    // Quem sai do "igual à taxa" parte do retorno do motor, quando há, ou da
    // taxa da perpetuidade mais cinco pontos — um número que já muda a conta.
    final starting = engine.terminalReturn ?? (m.engineTerminalRate + 0.05);
    final modes = _Modes<bool>(
      value: ownTerminal,
      options: const {
        false: 'Igual à taxa: crescer não cria valor',
        true: 'Outro retorno',
      },
      onChanged: (v) =>
          onChanged(p.copyWith(terminalReturn: v ? starting : null)),
    );
    if (!ownTerminal) {
      return _FieldCard(
        label: ManualCopy.label(ManualField.terminalReturn, lane),
        explanation: ManualCopy.explanation(ManualField.terminalReturn, lane),
        changed: engine.terminalReturn != null,
        error: error,
        onBackToEngine: engine.terminalReturn == null
            ? null
            : () => onChanged(p.copyWith(terminalReturn: engine.terminalReturn)),
        children: [
          modes,
          const Gap.sm(),
          Text(
            reference,
            style: context.finType.caption.copyWith(
              color: context.fin.textSecondary,
            ),
          ),
        ],
      );
    }
    return _NumericField(
      field: ManualField.terminalReturn,
      label: ManualCopy.label(ManualField.terminalReturn, lane),
      explanation: ManualCopy.explanation(ManualField.terminalReturn, lane),
      reference: reference,
      value: p.terminalReturn!,
      engineValue: engine.terminalReturn ?? double.nan,
      unit: _Unit.rate,
      step: 0.0025,
      grid: 0.0025,
      minimum: 0.02,
      maximum: 0.50,
      error: error,
      onChanged: (v) => onChanged(p.copyWith(terminalReturn: v)),
      onBackToEngine: () =>
          onChanged(p.copyWith(terminalReturn: engine.terminalReturn)),
      modes: modes,
    );
  }
}

/// O cartão de um campo: título, explicação, selo de alterado e o conteúdo.
///
/// **Cada campo tem cartão próprio**, e é o ponto: a tela existe para ser
/// editada, e um campo agrupado com outros num cartão só se lia como resumo.
/// A borda passa à cor da marca quando o valor deixa o do motor — é o que diz,
/// de longe, onde o usuário discorda.
class _FieldCard extends StatelessWidget {
  final String label;
  final String explanation;
  final bool changed;
  final String? error;
  final VoidCallback? onBackToEngine;
  final List<Widget> children;

  const _FieldCard({
    required this.label,
    required this.explanation,
    required this.changed,
    required this.error,
    required this.onBackToEngine,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final t = context.finType;
    return GlassCard(
      borderColor: error != null
          ? c.negative
          : changed
              ? c.brand
              : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: t.titleSm.copyWith(color: c.textPrimary),
                ),
              ),
              if (changed) ...[
                const Gap.sm(axis: Axis.horizontal),
                _Badge(text: 'Seu número'),
              ],
            ],
          ),
          const Gap.xs(),
          Text(explanation, style: t.caption.copyWith(color: c.textSecondary)),
          const Gap.md(),
          ...children,
          if (changed && onBackToEngine != null) ...[
            const Gap.xs(),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _Action(
                text: 'Usar o do motor',
                icon: Icons.undo,
                onPressed: onBackToEngine!,
              ),
            ),
          ],
          if (error != null) ...[
            const Gap.sm(),
            Text(error!, style: t.bodySm.copyWith(color: c.negative)),
          ],
        ],
      ),
    );
  }
}

/// Um campo numérico em destaque: valor grande, menos e mais, controle
/// deslizante e a referência do motor.
///
/// Segue a afordância do campo da Meta — preenchimento rebaixado, borda, lápis
/// e foco na cor da marca —, maior, porque aqui o campo é o assunto da tela.
class _NumericField extends StatefulWidget {
  /// O campo, que dá a chave do texto para os testes.
  final ManualField field;
  final String label;
  final String explanation;
  final String reference;
  final String? note;
  final double value;
  final double engineValue;
  final _Unit unit;
  final double step;
  final double grid;
  final double minimum;
  final double maximum;
  final String? error;
  final ValueChanged<double> onChanged;
  final VoidCallback? onBackToEngine;
  final Widget? modes;
  final List<Widget> extras;

  /// Conteúdo a mais no pé do cartão — o porquê da normalização, no do lucro.
  final Widget? detail;
  final bool forcedChanged;

  const _NumericField({
    required this.field,
    required this.label,
    required this.explanation,
    required this.reference,
    this.note,
    required this.value,
    required this.engineValue,
    required this.unit,
    required this.step,
    required this.grid,
    required this.minimum,
    required this.maximum,
    required this.error,
    required this.onChanged,
    this.onBackToEngine,
    this.modes,
    this.extras = const [],
    this.detail,
    this.forcedChanged = false,
  });

  @override
  State<_NumericField> createState() => _NumericFieldState();
}

class _NumericFieldState extends State<_NumericField> {
  late final TextEditingController _text;
  final FocusNode _focus = FocusNode();

  /// `true` enquanto o texto digitado não é número.
  bool _unreadable = false;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.unit.display(widget.value));
    _focus.addListener(() {
      // Ao sair do campo, o texto volta à forma canônica do valor que valeu.
      if (!_focus.hasFocus) {
        setState(() => _unreadable = false);
        _text.text = widget.unit.display(widget.value);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _NumericField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // O valor mudou por fora — menos e mais, controle deslizante, "usar o do
    // motor", a resposta do cálculo reverso. Enquanto o usuário digita, o
    // texto é dele: reescrevê-lo moveria o cursor no meio da digitação.
    final parsed = widget.unit.read(_text.text);
    final changed = parsed == null ||
        (parsed - widget.value).abs() > widget.unit.tolerance / 10;
    if (changed && !_focus.hasFocus) {
      _text.text = widget.unit.display(widget.value);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  double _onGrid(double v) =>
      widget.grid > 0 ? (v / widget.grid).roundToDouble() * widget.grid : v;

  void _step(int direction) {
    final v = _onGrid(widget.value + direction * widget.step);
    _text.text = widget.unit.display(v);
    widget.onChanged(v);
  }

  bool get _changed =>
      widget.forcedChanged ||
      !widget.engineValue.isFinite ||
      (widget.value - widget.engineValue).abs() > widget.unit.tolerance;

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final t = context.finType;
    final u = widget.unit;
    // A faixa do controle deslizante sempre contém o valor do motor e o
    // corrente; o campo de texto aceita qualquer número.
    final lo = [
      widget.minimum,
      widget.value,
      if (widget.engineValue.isFinite) widget.engineValue,
    ].reduce((a, b) => a < b ? a : b);
    var hi = [
      widget.maximum,
      widget.value,
      if (widget.engineValue.isFinite) widget.engineValue,
    ].reduce((a, b) => a > b ? a : b);
    if (hi <= lo) hi = lo + (widget.step > 0 ? widget.step * 10 : 1);

    OutlineInputBorder outline(Color color, {double thickness = 1}) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: thickness),
        );
    final error = widget.error != null || _unreadable;

    return _FieldCard(
      label: widget.label,
      explanation: widget.explanation,
      changed: _changed,
      error: widget.error ??
          (_unreadable ? 'Escreva um número, como 12,5.' : null),
      onBackToEngine: widget.engineValue.isFinite
          ? (widget.onBackToEngine ??
              () {
                _text.text = u.display(widget.engineValue);
                widget.onChanged(widget.engineValue);
              })
          : widget.onBackToEngine,
      children: [
        if (widget.modes != null) ...[widget.modes!, const Gap.md()],
        Row(
          children: [
            _StepButton(
              icon: Icons.remove,
              hint: 'Diminuir ${widget.label.toLowerCase()}',
              onPressed: () => _step(-1),
            ),
            const Gap.sm(axis: Axis.horizontal),
            Expanded(
              child: TextField(
                key: ValueKey('campo-${widget.field.name}'),
                controller: _text,
                focusNode: _focus,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9,.\-−]')),
                ],
                style: t.numLg.copyWith(color: c.textPrimary),
                onChanged: (s) {
                  final v = u.read(s);
                  setState(() => _unreadable = v == null);
                  if (v != null) widget.onChanged(v);
                },
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: c.surfaceSunken,
                  prefixText: u == _Unit.reais ? 'R\$ ' : null,
                  prefixStyle: t.bodySm.copyWith(color: c.textSecondary),
                  suffixText: switch (u) {
                    _Unit.reais => 'mi',
                    _Unit.rate => '% a.a.',
                    _Unit.fraction => '%',
                  },
                  suffixStyle: t.bodySm.copyWith(color: c.textSecondary),
                  // O lápis é a marca de edição, como no campo da Meta: o
                  // campo inteiro já é o alvo do toque.
                  prefixIcon: Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: c.textTertiary,
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 40,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: FinSpace.sm,
                    vertical: FinSpace.md,
                  ),
                  border: outline(c.border),
                  enabledBorder: outline(error ? c.negative : c.border),
                  focusedBorder:
                      outline(error ? c.negative : c.brand, thickness: 2),
                ),
              ),
            ),
            const Gap.sm(axis: Axis.horizontal),
            _StepButton(
              icon: Icons.add,
              hint: 'Aumentar ${widget.label.toLowerCase()}',
              onPressed: () => _step(1),
            ),
          ],
        ),
        // `Material` transparente pelo mesmo motivo do alternador de Monte
        // Carlo: o controle pinta o respingo no `Material` mais próximo, e o
        // `GlassCard` interpõe um fundo próprio entre os dois.
        Material(
          type: MaterialType.transparency,
          child: Slider(
            value: widget.value.clamp(lo, hi),
            min: lo,
            max: hi,
            activeColor: c.brand,
            inactiveColor: c.border,
            semanticFormatterCallback: u.reference,
            onChanged: (v) {
              final r = _onGrid(v);
              _text.text = u.display(r);
              widget.onChanged(r);
            },
          ),
        ),
        Text(
          widget.reference,
          style: t.caption.copyWith(color: c.textSecondary),
        ),
        if (widget.note != null) ...[
          const Gap.xs(),
          Text(widget.note!, style: t.caption.copyWith(color: c.textTertiary)),
        ],
        if (widget.extras.isNotEmpty) ...[
          const Gap.xs(),
          Wrap(spacing: FinSpace.sm, children: widget.extras),
        ],
        if (widget.detail != null) ...[
          const Gap.md(),
          widget.detail!,
        ],
      ],
    );
  }
}

/// Botão de menos e mais, com alvo de 48 dp.
class _StepButton extends StatelessWidget {
  final IconData icon;
  final String hint;
  final VoidCallback onPressed;

  const _StepButton({
    required this.icon,
    required this.hint,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    return IconButton(
      tooltip: hint,
      onPressed: onPressed,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      style: IconButton.styleFrom(
        backgroundColor: c.surfaceSunken,
        side: BorderSide(color: c.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(icon, size: 20, color: c.textPrimary),
    );
  }
}

/// Uma ação de texto pequena, na cor de texto positiva.
class _Action extends StatelessWidget {
  final String text;
  final IconData? icon;
  final VoidCallback onPressed;

  const _Action({required this.text, required this.onPressed, this.icon});

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final label = Text(
      text,
      style: context.finType.bodySm.copyWith(color: c.positive),
    );
    // `positive`, e não `brand`: é texto, e a cor de marca não tem contraste
    // garantido para texto.
    return icon == null
        ? TextButton(onPressed: onPressed, child: label)
        : TextButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 16, color: c.positive),
            label: label,
          );
  }
}

/// O selo de campo alterado.
class _Badge extends StatelessWidget {
  final String text;
  const _Badge({required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FinSpace.sm,
        vertical: FinSpace.xxs,
      ),
      decoration: BoxDecoration(
        color: c.brandSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.brand),
      ),
      child: Text(
        text,
        style: context.finType.caption.copyWith(
          color: c.positive,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// As opções de modo de um campo, como fichas — as mesmas da escolha de ativo
/// na aba Valuation.
class _Modes<T> extends StatelessWidget {
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  const _Modes({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    return Material(
      type: MaterialType.transparency,
      child: Wrap(
        spacing: FinSpace.sm,
        runSpacing: FinSpace.sm,
        children: [
          for (final MapEntry(key: k, value: label) in options.entries)
            ChoiceChip(
              label: Text(label),
              selected: k == value,
              onSelected: (_) => onChanged(k),
              labelStyle: context.finType.bodySm.copyWith(
                color: k == value ? c.textOnBrand : c.textSecondary,
              ),
              selectedColor: c.brand,
              backgroundColor: c.surfaceSunken,
              side: BorderSide(color: c.border),
              showCheckmark: false,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Resultado --

/// O preço do usuário contra o do motor e o de mercado.
class _SummaryCard extends StatelessWidget {
  final ManualValuation m;
  final ManualOutcome? output;
  final Failure? failure;
  final bool changed;

  const _SummaryCard({
    required this.m,
    required this.output,
    required this.failure,
    required this.changed,
  });

  /// Largura por coluna abaixo da qual as três métricas se empilham, em dp.
  static const double widthPerColumn = 120;

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final t = context.finType;
    final yours = output?.fairValuePerShare;
    final delta = yours == null ? null : yours - m.engineFairValue;
    final upside = yours == null ? null : yours / m.marketPrice - 1;
    final tiles = [
      MetricTile(
        label: 'Preço justo do motor',
        value: Fmt.money(m.engineFairValue),
      ),
      MetricTile(label: 'Preço de mercado', value: Fmt.money(m.marketPrice)),
      MetricTile(
        label: 'Seu potencial',
        value: upside == null
            ? '—'
            : Fmt.percent(upside, decimals: 1, signed: true),
        hint: 'total, sem prazo',
        trend: FinAmount.trendOf(upside),
      ),
    ];
    return GlassCard(
      borderColor: changed ? c.brand : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Seu preço justo',
            subtitle: changed
                ? 'A conta do motor com os seus números'
                : 'Igual ao do motor: nenhum campo foi trocado',
          ),
          const Gap.md(),
          // O `Align` não é decorativo: `FinAmount` embrulha o texto num
          // `AnimatedSwitcher`, que centraliza o filho na caixa recebida, e a
          // coluna estica a caixa — sem ele o número flutuava no meio do
          // cartão, longe do título que o nomeia (ver `MetricTileRow`).
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FinAmount(
              text: yours == null ? '—' : Fmt.money(yours),
              style: t.numHero,
              align: TextAlign.left,
            ),
          ),
          if (delta != null && changed) ...[
            const Gap.xs(),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FinAmount(
                text: '${delta >= 0 ? '+' : '−'}${Fmt.money(delta.abs())} '
                    '(${Fmt.percent(delta / m.engineFairValue, decimals: 1, signed: true)}) '
                    'contra o motor',
                style: t.numSm,
                trend: FinAmount.trendOf(delta),
                align: TextAlign.left,
                maxLines: 2,
              ),
            ),
          ],
          const Gap.lg(),
          LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(1);
              if (constraints.maxWidth <
                  widthPerColumn * scale * tiles.length) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, tile) in tiles.indexed) ...[
                      if (i > 0) const Gap.sm(),
                      tile,
                    ],
                  ],
                );
              }
              return MetricTileRow(tiles: tiles);
            },
          ),
          if (failure != null) ...[
            const Gap.md(),
            NoticeBanner(
              trend: FinTrend.negative,
              icon: Icons.error_outline,
              message: ManualCopy.refusal(failure!),
            ),
          ],
        ],
      ),
    );
  }
}

/// A barra fixa do rodapé, no celular: o preço do usuário sempre à vista.
class _ResultBar extends StatelessWidget {
  final ManualValuation m;
  final ManualOutcome? output;
  final bool changed;

  const _ResultBar({
    required this.m,
    required this.output,
    required this.changed,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final t = context.finType;
    final yours = output?.fairValuePerShare;
    final upside = yours == null ? null : yours / m.marketPrice - 1;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        border: Border(
          top: BorderSide(color: changed ? c.brand : c.border),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FinSpace.lg,
            vertical: FinSpace.sm,
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: FinSpace.md,
            runSpacing: FinSpace.xs,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Seu preço justo',
                    style: t.caption.copyWith(color: c.textSecondary),
                  ),
                  FinAmount(
                    text: yours == null ? '—' : Fmt.money(yours),
                    style: t.numLg,
                    align: TextAlign.left,
                  ),
                ],
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Motor ${Fmt.money(m.engineFairValue)} · mercado '
                    '${Fmt.money(m.marketPrice)}',
                    style: t.caption.copyWith(color: c.textSecondary),
                  ),
                  FinAmount(
                    text: upside == null
                        ? '—'
                        : '${Fmt.percent(upside, decimals: 1, signed: true)} '
                            'de potencial',
                    style: t.numSm,
                    trend: FinAmount.trendOf(upside),
                    align: TextAlign.left,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reais em milhões, para as linhas da conta.
String _millions(double v) =>
    '${v < 0 ? '−' : ''}R\$ ${Fmt.ratio(v.abs() / 1e6, decimals: 1)} mi';

/// A conta inteira: o valor presente dos anos, o da perpetuidade, a ponte e o
/// preço por ação.
class _CalculationCard extends StatelessWidget {
  final ManualValuation m;
  final ManualOutcome output;

  const _CalculationCard({required this.m, required this.output});

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final t = context.finType;
    final s = output;
    final explicitValue = s.explicitPresentValue;
    final perpetual = s.terminalPresentValue;
    final total = explicitValue.abs() + perpetual.abs();
    final explicitWeight = total > 0 ? explicitValue.abs() / total : 0.5;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'A conta',
            subtitle: m.lane == ValuationLane.firm
                ? 'O valor presente do que sobra ao acionista depois da dívida, '
                    'dividido pelas ações'
                : 'O valor presente do que sobra ao acionista depois de '
                    'reinvestir, dividido pelas ações',
          ),
          const Gap.md(),
          LabelValueRow(
            label: 'Valor presente dos 10 anos',
            value: _millions(explicitValue),
          ),
          const Gap.xs(),
          LabelValueRow(
            label: 'Valor presente da perpetuidade',
            value: _millions(perpetual),
          ),
          if (s.minorityInterest > 0) ...[
            const Gap.xs(),
            LabelValueRow(
              label: '− Parte dos acionistas minoritários das controladas',
              value: _millions(-s.minorityInterest),
            ),
          ],
          if (s.postStatementCapital > 0) ...[
            const Gap.xs(),
            LabelValueRow(
              label: '+ Ações emitidas depois do balanço',
              value: _millions(s.postStatementCapital),
            ),
          ],
          const Divider(height: FinSpace.lg),
          LabelValueRow(
            label: 'Valor do patrimônio (VPL)',
            value: _millions(s.equityValue),
          ),
          const Gap.xs(),
          LabelValueRow(
            label: '÷ Ações',
            value: '${Fmt.ratio(m.shares / 1e6, decimals: 1)} mi',
          ),
          const Gap.xs(),
          LabelValueRow(
            label: '= Seu preço justo por ação',
            value: Fmt.money(s.fairValuePerShare),
            trend: FinTrend.positive,
          ),
          const Gap.lg(),
          Text(
            'De onde vem o valor',
            style: t.caption.copyWith(color: c.textSecondary),
          ),
          const Gap.xs(),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  Expanded(
                    flex: (explicitWeight * 1000).round().clamp(1, 999),
                    child: ColoredBox(color: c.brand),
                  ),
                  Expanded(
                    flex: ((1 - explicitWeight) * 1000).round().clamp(1, 999),
                    child: ColoredBox(color: c.borderStrong),
                  ),
                ],
              ),
            ),
          ),
          const Gap.xs(),
          Wrap(
            spacing: FinSpace.md,
            runSpacing: FinSpace.xs,
            children: [
              _Legend(
                color: c.brand,
                text: '10 anos: ${Fmt.percent(explicitWeight, decimals: 0)}',
              ),
              _Legend(
                color: c.borderStrong,
                text: 'Perpetuidade: '
                    '${Fmt.percent(1 - explicitWeight, decimals: 0)} — '
                    '${s.terminalKind.label}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String text;
  const _Legend({required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Gap.xs(axis: Axis.horizontal),
          Flexible(
            child: Text(
              text,
              style: context.finType.caption.copyWith(
                color: context.fin.textSecondary,
              ),
            ),
          ),
        ],
      );
}

/// "Onde você discorda do motor": do preço do motor ao do usuário, um grupo
/// de premissas de cada vez.
class _DisagreementCard extends StatelessWidget {
  final ManualValuation m;
  final List<ManualStep> steps;

  const _DisagreementCard({required this.m, required this.steps});

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final t = context.finType;
    final values = [
      m.engineFairValue,
      for (final d in steps) ...[d.from, if (d.to != null) d.to!],
    ].where((v) => v.isFinite).toList();
    final lo = values.fold(0.0, (a, b) => a < b ? a : b);
    final hi = values.fold(lo + 1e-9, (a, b) => a > b ? a : b) * 1.05;
    double pos(double v) => ((v - lo) / (hi - lo)).clamp(0.0, 1.0);

    Widget bar(double from, double to, Color color) => LayoutBuilder(
          builder: (context, k) {
            final a = pos(from < to ? from : to) * k.maxWidth;
            final b = pos(from < to ? to : from) * k.maxWidth;
            return SizedBox(
              height: 10,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.surfaceSunken,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Positioned(
                    left: a,
                    width: (b - a).clamp(2.0, k.maxWidth),
                    top: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );

    Widget row(String label, String value, FinTrend trend, Widget b) =>
        Padding(
          padding: const EdgeInsets.only(bottom: FinSpace.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LabelValueRow(label: label, value: value, trend: trend),
              const Gap.xs(),
              b,
            ],
          ),
        );

    final last = steps.isEmpty ? null : steps.last.to;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Onde você discorda do motor',
            subtitle: 'Quanto cada troca move o preço, na ordem em que a conta '
                'as usa',
          ),
          const Gap.md(),
          row(
            'Preço justo do motor',
            Fmt.money(m.engineFairValue),
            FinTrend.neutral,
            bar(lo, m.engineFairValue, c.borderStrong),
          ),
          if (steps.isEmpty)
            Text(
              'Troque um campo para ver quanto cada discordância move o preço.',
              style: t.bodySm.copyWith(color: c.textSecondary),
            ),
          for (final d in steps)
            if (d.to == null)
              row(
                d.groups.map((g) => g.label).join(' e '),
                'sem valor finito',
                FinTrend.blocked,
                bar(d.from, d.from, c.negative),
              )
            else
              row(
                d.groups.map((g) => g.label).join(' e '),
                '${d.delta! >= 0 ? '+' : '−'}${Fmt.money(d.delta!.abs())}',
                FinAmount.trendOf(d.delta),
                bar(d.from, d.to!, d.delta! >= 0 ? c.positive : c.negative),
              ),
          if (last != null) ...[
            const Divider(height: FinSpace.lg),
            row(
              'Seu preço justo',
              Fmt.money(last),
              FinTrend.neutral,
              bar(lo, last, c.brand),
            ),
          ],
        ],
      ),
    );
  }
}

/// "O que o preço de hoje supõe?": o valor de um campo que leva o preço justo
/// ao de mercado, com os outros como estão.
class _ReverseCard extends StatelessWidget {
  final ManualValuation m;
  final ManualPremises p;
  final ManualField target;
  final ManualSolution? answer;
  final ValueChanged<ManualField> onTarget;
  final VoidCallback onResolver;
  final void Function(ManualField, double) onUse;

  const _ReverseCard({
    required this.m,
    required this.p,
    required this.target,
    required this.answer,
    required this.onTarget,
    required this.onResolver,
    required this.onUse,
  });

  static _Unit _unit(ManualField f) => switch (f) {
        ManualField.baseProfit => _Unit.reais,
        ManualField.retention => _Unit.fraction,
        _ => _Unit.rate,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final t = context.finType;
    final options = <ManualField>[
      ManualField.discountRate,
      ManualField.growth,
      ManualField.baseProfit,
      if (p.reinvestment == ManualReinvestment.byReturn)
        ManualField.returnOnCapital
      else
        ManualField.retention,
      if (p.terminalReturn != null) ManualField.terminalReturn,
    ];
    final chosen = options.contains(target) ? target : options.first;
    final r = answer;
    final name = ManualCopy.label(chosen, m.lane).toLowerCase();
    final u = _unit(chosen);
    String? sentence;
    if (r != null && r.field == chosen) {
      final v = r.value;
      if (v != null) {
        sentence = 'Para valer ${Fmt.money(r.target)}, com os outros campos como '
            'estão, $name teria de ser ${u.reference(v)}. Hoje está em '
            '${u.reference(p.valueOf(chosen) ?? double.nan)}.';
      } else if (r.closestValue != null && r.closestPrice != null) {
        sentence = 'Com os outros campos como estão, nenhum valor de $name leva o '
            'preço justo a ${Fmt.money(r.target)}: o mais perto é '
            '${Fmt.money(r.closestPrice!)}, com ${u.reference(r.closestValue!)}.';
      } else {
        sentence = 'Com os outros campos como estão, a conta não fecha para '
            'nenhum valor de $name.';
      }
    }
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'O que o preço de hoje supõe?',
            subtitle: 'O valor de um campo que faz o preço justo bater com o de '
                'mercado (${Fmt.money(m.marketPrice)})',
          ),
          const Gap.md(),
          _Modes<ManualField>(
            value: chosen,
            options: {for (final f in options) f: ManualCopy.label(f, m.lane)},
            onChanged: onTarget,
          ),
          const Gap.md(),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              onPressed: onResolver,
              style: FilledButton.styleFrom(
                backgroundColor: c.brand,
                foregroundColor: c.textOnBrand,
              ),
              icon: const Icon(Icons.calculate_outlined, size: 18),
              label: const Text('Calcular'),
            ),
          ),
          if (sentence != null) ...[
            const Gap.md(),
            Text(sentence, style: t.bodySm.copyWith(color: c.textPrimary)),
            if (r?.value != null) ...[
              const Gap.xs(),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: _Action(
                  text: 'Usar este valor',
                  icon: Icons.check,
                  onPressed: () => onUse(chosen, r!.value!),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Ano a ano: a projeção que a conta fez, em milhões de reais.
class _YearsCard extends StatelessWidget {
  final ManualValuation m;
  final ManualPremises p;
  final ManualOutcome output;

  const _YearsCard({required this.m, required this.p, required this.output});

  @override
  Widget build(BuildContext context) {
    final c = context.fin;
    final t = context.finType;
    final firm = m.lane == ValuationLane.firm;
    final headerRow = <String>[
      'Ano',
      'Crescimento',
      firm ? 'Lucro operacional' : 'Lucro líquido',
      'Reinvestido',
      if (firm) ...['Fluxo da firma', 'Dívida'],
      firm ? 'Fluxo do acionista' : 'Fluxo',
      'Taxa',
      'Fator',
      'Valor presente',
    ];
    String inMillions(double? v) => v == null || !v.isFinite
        ? '—'
        : '${v < 0 ? '−' : ''}${Fmt.ratio(v.abs() / 1e6, decimals: 1)}';
    final rows = <List<String>>[
      for (final y in output.years)
        [
          '${y.year}',
          Fmt.percent(y.growth, decimals: 1),
          inMillions(y.profit),
          Fmt.percent(y.retention, decimals: 0),
          if (firm) ...[inMillions(y.firmFlow), inMillions(y.debtService)],
          inMillions(y.flow),
          Fmt.percent(y.rate, decimals: 2),
          Fmt.ratio(y.discountFactor, decimals: 3),
          inMillions(y.presentValue),
        ],
      [
        'Perpetuidade',
        Fmt.percent(p.perpetualGrowth, decimals: 1),
        '',
        '',
        if (firm) ...['', ''],
        '${inMillions(output.terminalValue)} no ano 10',
        Fmt.percent(output.terminalRate, decimals: 2),
        Fmt.ratio(output.years.last.discountFactor, decimals: 3),
        inMillions(output.terminalPresentValue),
      ],
    ];
    final headerStyle = t.caption.copyWith(color: c.textSecondary);
    final style = t.captionNum.copyWith(color: c.textPrimary);
    TableRow tableRow(List<String> cells, TextStyle s, {Color? background}) =>
        TableRow(
          decoration: background == null ? null : BoxDecoration(color: background),
          children: [
            for (final (i, v) in cells.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: FinSpace.sm,
                  vertical: FinSpace.xs + 2,
                ),
                child: Text(
                  v,
                  textAlign: i == 0 ? TextAlign.left : TextAlign.right,
                  style: s,
                ),
              ),
          ],
        );
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Ano a ano',
            subtitle: 'Em milhões de reais. O fluxo de cada ano chega no meio '
                'dele, como no motor: valor presente = fluxo ÷ fator',
          ),
          const Gap.md(),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: TableBorder(
                horizontalInside: BorderSide(color: c.divider),
              ),
              children: [
                tableRow(headerRow, headerStyle),
                for (final (i, l) in rows.indexed)
                  tableRow(
                    l,
                    style,
                    background: i == rows.length - 1 ? c.surfaceSunken : null,
                  ),
                tableRow([
                  'VPL',
                  for (var i = 1; i < headerRow.length - 1; i++) '',
                  inMillions(output.explicitPresentValue + output.terminalPresentValue),
                ], style.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const Gap.sm(),
          Text(
            firm
                ? 'Fluxo do acionista = fluxo da firma − serviço da dívida '
                    '(juros depois do imposto, menos o rendimento do caixa, '
                    'menos a dívida nova que acompanha o crescimento).'
                : 'Fluxo = lucro × (1 − parcela reinvestida).',
            style: t.caption.copyWith(color: c.textTertiary),
          ),
        ],
      ),
    );
  }
}

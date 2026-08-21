import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../utils/app_colors.dart';
import '../shared/theme_bridge.dart';
import '../shared/ui_kit.dart';
import '../study/study_notifier.dart';
import '../valuation/valuation_providers.dart';

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
      text: goal == null ? '10000' : goal.initialContribution.reais.toStringAsFixed(0),
    );
    _monthly = TextEditingController(
      text: goal == null ? '1000' : goal.monthlyContribution.reais.toStringAsFixed(0),
    );
    _target = TextEditingController(
      text: goal == null ? '500000' : goal.targetWealth.reais.toStringAsFixed(0),
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
    ref.read(studyProvider.notifier).setGoal(FinancialGoal(
          initialContribution: Money.fromReais(_parse(_initial)),
          monthlyContribution: Money.fromReais(_parse(_monthly)),
          months: _months,
          targetWealth: Money.fromReais(_parse(_target)),
        ));
  }

  @override
  Widget build(BuildContext context) {
    final isLight = ref.watch(isLightModeProvider);
    final feasibility = ref.watch(goalFeasibilityProvider);
    final alignment = ref.watch(goalAlignmentProvider);
    final settings = ref.watch(valuationSettingsProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GlassCard(
          isLight: isLight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                isLight: isLight,
                title: 'Plano patrimonial',
                subtitle: 'A rentabilidade necessária é derivada destes valores',
              ),
              const SizedBox(height: 14),
              _MoneyField(
                controller: _initial,
                label: 'Aporte inicial',
                isLight: isLight,
                onChanged: _apply,
              ),
              const SizedBox(height: 10),
              _MoneyField(
                controller: _monthly,
                label: 'Aporte mensal',
                isLight: isLight,
                onChanged: _apply,
              ),
              const SizedBox(height: 10),
              _MoneyField(
                controller: _target,
                label: 'Valor desejado ao final',
                isLight: isLight,
                onChanged: _apply,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    'Prazo',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary(isLight),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_months ~/ 12} anos e ${_months % 12} meses',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary(isLight),
                    ),
                  ),
                ],
              ),
              Slider(
                value: _months.toDouble(),
                min: 12,
                max: 360,
                divisions: 29,
                activeColor: AppColors.primary,
                label: '$_months meses',
                onChanged: (value) {
                  setState(() => _months = value.round());
                  _apply();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        feasibility.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (error, _) => NoticeBanner(
            isLight: isLight,
            color: AppColors.danger,
            icon: Icons.error_outline,
            message: 'Não foi possível avaliar a meta: $error',
          ),
          data: (verdict) => verdict == null
              ? const SizedBox.shrink()
              : _FeasibilityCard(verdict: verdict, isLight: isLight),
        ),
        const SizedBox(height: 12),
        alignment.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (value) => value == null
              ? GlassCard(
                  isLight: isLight,
                  child: EmptyState(
                    isLight: isLight,
                    icon: Icons.donut_small_outlined,
                    title: 'Sem carteira para comparar',
                    message: 'Monte a carteira Principal para confrontar o '
                        'retorno esperado com a rentabilidade exigida.',
                  ),
                )
              : _AlignmentCard(
                  alignment: value,
                  horizonMonths: settings.convergenceHorizonMonths,
                  isLight: isLight,
                ),
        ),
      ],
    );
  }
}

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

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (_) => onChanged(),
      style: TextStyle(color: AppColors.textPrimary(isLight)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          fontSize: 12,
          color: AppColors.textSecondary(isLight),
        ),
        prefixText: r'R$ ',
        prefixStyle: TextStyle(color: AppColors.textSecondary(isLight)),
        filled: true,
        fillColor: AppColors.inputBackground(isLight),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
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

  Color get _color => switch (verdict.level) {
        FeasibilityLevel.riskFreeSufficient => const Color(0xFF3B82F6),
        FeasibilityLevel.plausible => AppColors.primary,
        FeasibilityLevel.demanding => const Color(0xFFF59E0B),
        FeasibilityLevel.unrealistic => AppColors.danger,
      };

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
    final rate = verdict.requiredAnnualRate;
    final showRates = rate.isFinite;

    return GlassCard(
      isLight: isLight,
      borderColor: _color.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icon, size: 20, color: _color),
              const SizedBox(width: 8),
              Text(
                _title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: _color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (showRates)
            Row(
              children: [
                Expanded(
                  child: MetricTile(
                    isLight: isLight,
                    label: 'Rentabilidade exigida',
                    value: Fmt.percent(rate, decimals: 2),
                    hint: 'ao ano',
                    valueColor: _color,
                  ),
                ),
                Expanded(
                  child: MetricTile(
                    isLight: isLight,
                    label: 'Equivalente mensal',
                    value: Fmt.percent(
                      _monthlyEquivalent(rate),
                      decimals: 2,
                    ),
                    hint: 'juros compostos',
                  ),
                ),
              ],
            ),
          const SizedBox(height: 10),
          Text(
            verdict.message,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: AppColors.textSecondary(isLight),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Referências dos últimos ${verdict.anchors.observedYears} anos: '
            'CDI ${Fmt.percent(verdict.anchors.riskFreeCagr)} a.a. · '
            'Ibovespa ${Fmt.percent(verdict.anchors.marketCagr)} a.a.',
            style: TextStyle(
              fontSize: 10,
              color: AppColors.textMuted(isLight),
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
  final int horizonMonths;
  final bool isLight;

  const _AlignmentCard({
    required this.alignment,
    required this.horizonMonths,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    final meets = alignment.meetsGoal;
    return GlassCard(
      isLight: isLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            isLight: isLight,
            title: 'Carteira frente à meta',
            subtitle: 'Convergência assumida em $horizonMonths meses',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  isLight: isLight,
                  label: 'Exigido',
                  value: Fmt.percent(alignment.required.annual),
                  hint: 'ao ano',
                ),
              ),
              Expanded(
                child: MetricTile(
                  isLight: isLight,
                  label: 'Esperado da carteira',
                  value: Fmt.percent(alignment.expectedReturn),
                  hint: 'upside anualizado + DY líquido',
                  valueColor:
                      meets ? AppColors.primary : AppColors.danger,
                ),
              ),
              Expanded(
                child: MetricTile(
                  isLight: isLight,
                  label: 'Folga',
                  value: '${alignment.gap >= 0 ? '+' : ''}'
                      '${alignment.gap.toStringAsFixed(1)} p.p.',
                  valueColor: signedColor(alignment.gap, isLight),
                ),
              ),
            ],
          ),
          if (alignment.coverageIsWeak) ...[
            const SizedBox(height: 12),
            NoticeBanner(
              isLight: isLight,
              message: 'Apenas '
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

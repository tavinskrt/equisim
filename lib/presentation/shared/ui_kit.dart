import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../utils/app_colors.dart';

/// Formatadores compartilhados.
abstract final class Fmt {
  static final currency =
      NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  static final compactCurrency =
      NumberFormat.compactCurrency(locale: 'pt_BR', symbol: r'R$');
  static final date = DateFormat('dd/MM/yyyy');
  static final shortDate = DateFormat('MM/yy');

  static String money(double value) => currency.format(value);

  /// Percentual a partir de fração, com sinal explícito quando pedido.
  static String percent(double fraction, {int decimals = 2, bool signed = false}) {
    final value = fraction * 100;
    final sign = signed && value > 0 ? '+' : '';
    return '$sign${value.toStringAsFixed(decimals)}%';
  }

  static String ratio(double value, {int decimals = 2}) =>
      value.toStringAsFixed(decimals);
}

/// Cartão translúcido — a linguagem visual herdada do projeto anterior.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool isLight;
  final Color? borderColor;

  const GlassCard({
    super.key,
    required this.child,
    required this.isLight,
    this.padding = const EdgeInsets.all(16),
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: AppColors.surface(isLight),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: borderColor ?? AppColors.surfaceBorder(isLight),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Título de seção com ação opcional à direita.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool isLight;

  const SectionHeader({
    super.key,
    required this.title,
    required this.isLight,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                  color: AppColors.textSecondary(isLight),
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted(isLight),
                  ),
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
  final String label;
  final String value;
  final String? hint;
  final Color? valueColor;
  final bool isLight;

  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.isLight,
    this.hint,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            color: AppColors.textSecondary(isLight),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: valueColor ?? AppColors.textPrimary(isLight),
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 1),
          Text(
            hint!,
            style: TextStyle(
              fontSize: 9.5,
              color: AppColors.textMuted(isLight),
            ),
          ),
        ],
      ],
    );
  }
}

/// Faixa de aviso não bloqueante.
///
/// Usada para concentração setorial e para a queda de modelo de avaliação:
/// informa sem impedir, porque as duas situações podem ser decisões
/// conscientes do investidor.
class NoticeBanner extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color color;
  final bool isLight;

  const NoticeBanner({
    super.key,
    required this.message,
    required this.isLight,
    this.icon = Icons.info_outline,
    this.color = const Color(0xFFF59E0B),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: AppColors.textPrimary(isLight),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Estado vazio com orientação do próximo passo.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final bool isLight;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.isLight,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: AppColors.textMuted(isLight)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary(isLight),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppColors.textSecondary(isLight),
              ),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Fundo padrão das telas, com os círculos decorativos da identidade visual.
class ScreenBackground extends StatelessWidget {
  final Widget child;
  final bool isLight;

  const ScreenBackground({
    super.key,
    required this.child,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(gradient: AppColors.backgroundGradient(isLight)),
      child: Stack(
        children: [
          Positioned(
            top: -100,
            right: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.07),
              ),
            ),
          ),
          Positioned(
            bottom: -40,
            left: -80,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.05),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Verde para ganho, vermelho para perda, neutro para zero.
Color signedColor(double value, bool isLight) {
  if (value > 0) return AppColors.primary;
  if (value < 0) return AppColors.danger;
  return AppColors.textSecondary(isLight);
}

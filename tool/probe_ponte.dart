// D7 — o que a fonte publica entre o valor da firma e o do acionista.
//
// A ponte do motor é `E = EV − dívida líquida`. A contabilidade tem mais
// termos: participação de não controladores, investimento em coligada avaliado
// por equivalência patrimonial, arrendamento reconhecido como passivo pelo
// IFRS 16. Antes de decidir o que fazer com cada um, é preciso saber **quais
// existem na fonte** — e o cache guarda só os campos já tipados, de modo que
// esta sonda vai à API buscar o mapa cru.
//
// Uso:
//   dart run tool/probe_ponte.dart PETR4 VALE3 ITUB4
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'validation/context.dart';

/// Palavras que denunciam um termo de ponte no nome do campo.
const _clues = [
  'minor',
  'noncontrol',
  'controlling',
  'participa',
  'equity',
  'affiliate',
  'associate',
  'investment',
  'lease',
  'arrend',
  'pension',
  'provision',
  'goodwill',
  'treasury',
];

Future<void> main(List<String> args) async {
  final targets = args.isEmpty
      ? ['PETR4', 'VALE3', 'ITUB4', 'MGLU3', 'RENT3', 'CSNA3']
      : args;
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    for (final t in targets) {
      final r = await ctx.brapi.rawFundamentals(Ticker.parse(t));
      if (r.isErr) {
        stdout.writeln('$t: ${r.failureOrNull?.message}');
        continue;
      }
      final rows = r.unwrap();
      if (rows.isEmpty) {
        stdout.writeln('$t: sem exercícios');
        continue;
      }
      stdout.writeln('  --- série de equivalência ÷ EBIT ---');
      for (final l in rows) {
        final e = l['equityIncomeResult'];
        final b = l['ebit'];
        if (e is num && b is num && b > 0 && e.abs() > 0) {
          stdout.writeln('    ${l['endDate']}  equiv=${(e / 1e6).toStringAsFixed(1)} mi  '
              'ebit=${(b / 1e6).toStringAsFixed(1)} mi  '
              '${(e / b * 100).toStringAsFixed(1)}%');
        }
      }
      final last = rows.last;
      stdout.writeln('\n=== $t — ${rows.length} exercícios, '
          '${last.length} campos no último ===');
      final keys = last.keys.toList()..sort();
      final suspicious = [
        for (final k in keys)
          if (_clues.any((p) => k.toLowerCase().contains(p))) k
      ];
      for (final k in suspicious) {
        stdout.writeln('  ${k.padRight(38)} ${last[k]}');
      }
      if (suspicious.isEmpty) stdout.writeln('  (nenhum campo de ponte)');

      double? n(String k) {
        final v = last[k];
        if (v is num) return v.toDouble();
        return null;
      }

      final marketValue = n('marketCap');
      final debt = (n('shortLongTermDebt') ?? n('loansAndFinancing') ?? 0) +
          (n('longTermDebt') ?? n('longTermLoansAndFinancing') ?? 0);
      final leases =
          (n('leaseFinancing') ?? 0) + (n('longTermLeaseFinancing') ?? 0);
      final minor = n('minorityInterest') ?? 0;
      final affiliates = n('longTermInvestments') ?? 0;
      String pct(double x) =>
          marketValue == null || marketValue <= 0 ? '—' : '${(x / marketValue * 100).toStringAsFixed(1)}%';
      stdout.writeln('  --- tamanho contra o valor de mercado ---');
      stdout.writeln('  valor de mercado      ${marketValue?.toStringAsFixed(0)}');
      stdout.writeln('  dívida (empréstimos)  ${debt.toStringAsFixed(0)}  '
          '${pct(debt)}');
      stdout.writeln('  arrendamento          ${leases.toStringAsFixed(0)}  '
          '${pct(leases)}');
      stdout.writeln('  não controladores     ${minor.toStringAsFixed(0)}  '
          '${pct(minor)}');
      stdout.writeln('  coligadas             ${affiliates.toStringAsFixed(0)}  '
          '${pct(affiliates)}');
      stdout.writeln('  --- o arrendamento já está na dívida? ---');
      for (final k in [
        'shortLongTermDebt',
        'loansAndFinancing',
        'longTermDebt',
        'longTermLoansAndFinancing',
        'debentures',
        'longTermDebentures',
        'leaseFinancing',
        'longTermLeaseFinancing',
        'loansAndFinancingInNationalCurrency',
        'loansAndFinancingInForeignCurrency',
        'longTermLoansAndFinancingInNationalCurrency',
        'longTermLoansAndFinancingInForeignCurrency',
        'totalLiab',
        'nonCurrentLiabilities',
        '--- ativo ---',
        'nonCurrentAssets',
        'longTermAssets',
        'longTermInvestments',
        'investments',
        'investmentProperties',
        'shareholdings',
        'propertyPlantEquipment',
        'intangibleAsset',
        '--- patrimonio ---',
        'shareholdersEquity',
        'minorityInterest',
        'controllerShareholdersEquity',
        'equityIncomeResult',
        'netIncome',
        'cleanNetIncome',
        'ebit',
        'cleanEbit',
        'cleanNopat',
        'operatingIncome',
        'incomeFromOperations',
      ]) {
        stdout.writeln('  ${k.padRight(30)} ${last[k]}');
      }
    }
  } finally {
    await ctx.dispose();
  }
}

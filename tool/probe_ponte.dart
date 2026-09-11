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
const _pistas = [
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
  final alvos = args.isEmpty
      ? ['PETR4', 'VALE3', 'ITUB4', 'MGLU3', 'RENT3', 'CSNA3']
      : args;
  final ctx = ValidationContext.create(outputDir: 'docs/validacao');
  try {
    for (final t in alvos) {
      final r = await ctx.brapi.rawFundamentals(Ticker.parse(t));
      if (r.isErr) {
        stdout.writeln('$t: ${r.failureOrNull?.message}');
        continue;
      }
      final linhas = r.unwrap();
      if (linhas.isEmpty) {
        stdout.writeln('$t: sem exercícios');
        continue;
      }
      stdout.writeln('  --- série de equivalência ÷ EBIT ---');
      for (final l in linhas) {
        final e = l['equityIncomeResult'];
        final b = l['ebit'];
        if (e is num && b is num && b > 0 && e.abs() > 0) {
          stdout.writeln('    ${l['endDate']}  equiv=${(e / 1e6).toStringAsFixed(1)} mi  '
              'ebit=${(b / 1e6).toStringAsFixed(1)} mi  '
              '${(e / b * 100).toStringAsFixed(1)}%');
        }
      }
      final ultimo = linhas.last;
      stdout.writeln('\n=== $t — ${linhas.length} exercícios, '
          '${ultimo.length} campos no último ===');
      final chaves = ultimo.keys.toList()..sort();
      final suspeitas = [
        for (final k in chaves)
          if (_pistas.any((p) => k.toLowerCase().contains(p))) k
      ];
      for (final k in suspeitas) {
        stdout.writeln('  ${k.padRight(38)} ${ultimo[k]}');
      }
      if (suspeitas.isEmpty) stdout.writeln('  (nenhum campo de ponte)');

      double? n(String k) {
        final v = ultimo[k];
        if (v is num) return v.toDouble();
        return null;
      }

      final vm = n('marketCap');
      final divida = (n('shortLongTermDebt') ?? n('loansAndFinancing') ?? 0) +
          (n('longTermDebt') ?? n('longTermLoansAndFinancing') ?? 0);
      final arrend =
          (n('leaseFinancing') ?? 0) + (n('longTermLeaseFinancing') ?? 0);
      final minor = n('minorityInterest') ?? 0;
      final coligada = n('longTermInvestments') ?? 0;
      String pct(double x) =>
          vm == null || vm <= 0 ? '—' : '${(x / vm * 100).toStringAsFixed(1)}%';
      stdout.writeln('  --- tamanho contra o valor de mercado ---');
      stdout.writeln('  valor de mercado      ${vm?.toStringAsFixed(0)}');
      stdout.writeln('  dívida (empréstimos)  ${divida.toStringAsFixed(0)}  '
          '${pct(divida)}');
      stdout.writeln('  arrendamento          ${arrend.toStringAsFixed(0)}  '
          '${pct(arrend)}');
      stdout.writeln('  não controladores     ${minor.toStringAsFixed(0)}  '
          '${pct(minor)}');
      stdout.writeln('  coligadas             ${coligada.toStringAsFixed(0)}  '
          '${pct(coligada)}');
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
        stdout.writeln('  ${k.padRight(30)} ${ultimo[k]}');
      }
    }
  } finally {
    await ctx.dispose();
  }
}

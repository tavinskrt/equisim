import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'context.dart';
import 'package:equisim/presentation/shared/domain_copy.dart';

/// Validação fora da amostra da arquitetura de portas.
///
/// **Por que existe.** Os treze parâmetros da decisão 25 foram calibrados sobre
/// dezoito ativos cujo volume financeiro diário mediano vai de R$ 36,6 mi a
/// R$ 1.541,9 mi — a amostra inteira está no decil superior de liquidez do
/// mercado, cuja mediana é de R$ 9,2 mi. Aplicar essas regras ao universo sem
/// medir o que acontece seria extrapolar a calibragem em silêncio.
///
/// O que este relatório responde: qual a **distribuição de saídas por porta** no
/// universo elegível, e se as proporções fazem sentido setorialmente. Um
/// parâmetro que separa bem dezoito ativos e classifica 90% do universo na mesma
/// gaveta não está separando nada.
abstract final class OutOfSampleValidation {
  /// Executa a validação e escreve o relatório.
  ///
  /// - [ctx]: contexto com os repositórios de produção.
  /// - [limit]: teto de ativos a avaliar, para execução parcial.
  /// - [outputDir]: destino do relatório.
  static Future<void> run(
    ValidationContext ctx, {
    required String outputDir,
    int limit = 200,
  }) async {
    final today = DateTime(2026, 9, 4);

    stdout.writeln('Levantando o universo negociável...');
    final universe = await ctx.fundamentals.universe();
    if (universe.isErr) {
      stderr.writeln('Universo indisponível: ${universe.failureOrNull!.message}');
      return;
    }
    final tickers = universe.unwrap().take(limit).toList();
    stdout.writeln('  ${tickers.length} ativos a avaliar\n');

    final anchors = (await ResolveMarketAnchors.call(
      macro: ctx.macro,
      benchmark: ctx.benchmark,
      asOf: today,
    ))
        .getOrElse(MarketAnchors.fallback2026);

    stdout.writeln('Âncoras: CDI corrente ${pct(anchors.currentRiskFreeRate)} · '
        'IPCA ${pct(anchors.inflationCagr)} · '
        'PIB real ${pct(anchors.realEconomyGrowth)} · '
        'teto nominal ${pct(anchors.nominalEconomyGrowth)}\n');

    // O log de avaliação é a fonte do diagnóstico por ativo. Sem ele, a única
    // leitura possível de "dois passaram no critério de vantagem" seria análise
    // de texto dos avisos — e a pergunta aqui é metodológica: qual condição
    // barrou cada um, e quantos estavam a que distância dela.
    AuditEvent? last;
    AuditRecorder.attach((e) => last = e);

    final rows = <_Row>[];
    var i = 0;
    for (final ticker in tickers) {
      i++;
      last = null;
      if (i % 10 == 0) stdout.write('  $i/${tickers.length}\r');

      final prepared = await PrepareValuationInputs.call(
        ticker: ticker,
        prices: ctx.prices,
        fundamentals: ctx.fundamentals,
        benchmark: ctx.benchmark,
        riskFreeRate: anchors.currentRiskFreeRate,
        asOf: today,
        perpetualGrowthCap: anchors.nominalEconomyGrowth,
        inflation: anchors.inflationCagr,
        terminalRiskFreeRate: anchors.riskFreeCagr,
      );
      if (prepared.isErr) {
        // Classificado pelo mesmo caminho das recusas da cascata: sem isso, os
        // motivos de "ativo inexistente" e "sem cotação na janela" existiam no
        // classificador sem que nada os alcançasse, e cinco ativos ficavam num
        // balde genérico tendo motivo perfeitamente nomeável.
        final reason = prepared.failureOrNull!.message;
        rows.add(_Row(
          ticker: ticker.value,
          outcome: _classifyRefusal(reason),
          detail: reason,
        ));
        continue;
      }

      final inputs = prepared.unwrap();
      final result = ValuationCascade.evaluate(inputs);
      if (result.isErr) {
        rows.add(_Row(
          ticker: ticker.value,
          outcome: _classifyRefusal(result.failureOrNull!.message),
          detail: result.failureOrNull!.message,
          sector: inputs.sectorKey,
        ));
        continue;
      }

      final v = result.unwrap();
      rows.add(_Row(
        ticker: ticker.value,
        outcome: 'avaliado',
        lane: v.model.label,
        sector: inputs.sectorKey,
        fairValue: v.fairValue.reais,
        price: v.marketPrice.reais,
        upside: v.upside,
        warnings: v.warnings.length,
        growthOrigin: _growthOriginOf(v.warnings),
        moat: _hasMoat(v.warnings),
        diagnostics: _Diagnostics.from(last),
      ));
    }
    AuditRecorder.detach();
    stdout.writeln('\n');

    _report(rows, anchors, outputDir);
  }

  /// Classifica a recusa pela mensagem, para agrupar no relatório.
  ///
  /// Vale tanto para a recusa da cascata quanto para a falha de preparação dos
  /// insumos: a condição de encerramento da decisão 25 exige que **toda** saída
  /// seja nomeada, e um balde genérico não é um nome.
  static String _classifyRefusal(String message) {
    if (message.contains('liquidez insuficiente')) return 'Porta 0 · liquidez';
    if (message.contains('histórico curto')) return 'Porta 0 · histórico';
    if (message.contains('patrimônio líquido não positivo')) {
      return 'Porta 0 · solvência';
    }
    if (message.contains('recuperação judicial')) return 'Porta 0 · continuidade';
    // A mensagem é "Nenhum exercício de X havia sido divulgado" — sem o "não"
    // que este teste procurava. O balde nunca disparava, e nove ativos caíam em
    // "outra recusa" tendo motivo perfeitamente nomeável.
    if (message.contains('havia sido divulgado')) return 'sem exercício';
    if (message.contains('não sustentam nenhuma')) return 'sem via aplicável';
    if (message.contains('não encontrado na fonte')) return 'ativo inexistente';
    if (message.contains('Sem cotações')) return 'sem cotação na janela';
    return 'insumos indisponíveis';
  }

  /// `true` quando a cascata declarou vantagem competitiva residual.
  static bool _hasMoat(List<String> warnings) =>
      warnings.any((w) => w.contains('Vantagem competitiva comprovada'));

  /// Lê a origem do crescimento nos avisos, que é onde a cascata a declara.
  static String _growthOriginOf(List<String> warnings) {
    for (final w in warnings) {
      if (w.contains('Adotada a inflação')) return 'âncora';
      if (w.contains('sem crescimento')) return 'g = 0';
    }
    return 'fundamental';
  }

  static void _report(
    List<_Row> rows,
    MarketAnchors anchors,
    String outputDir,
  ) {
    final buf = StringBuffer()
      ..writeln('# Validação fora da amostra — arquitetura de portas')
      ..writeln()
      ..writeln('Executada em ${DateTime.now().toIso8601String().split("T").first} '
          'sobre ${rows.length} ativos do universo negociável.')
      ..writeln();

    final byOutput = <String, int>{};
    for (final l in rows) {
      byOutput[l.outcome] = (byOutput[l.outcome] ?? 0) + 1;
    }
    buf
      ..writeln('## Distribuição de saídas')
      ..writeln()
      ..writeln('| Saída | Ativos | Fração |')
      ..writeln('|---|---:|---:|');
    final sortedEntries = byOutput.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in sortedEntries) {
      buf.writeln('| ${e.key} | ${e.value} | '
          '${pct(e.value / rows.length, decimals: 1)} |');
    }

    final evaluated = rows.where((l) => l.outcome == 'avaliado').toList();
    if (evaluated.isNotEmpty) {
      final byLane = <String, int>{};
      final byOrigin = <String, int>{};
      for (final l in evaluated) {
        byLane[l.lane ?? '?'] = (byLane[l.lane ?? '?'] ?? 0) + 1;
        byOrigin[l.growthOrigin ?? '?'] =
            (byOrigin[l.growthOrigin ?? '?'] ?? 0) + 1;
      }
      buf
        ..writeln()
        ..writeln('## Entre os avaliados')
        ..writeln()
        ..writeln('| Via | Ativos |')
        ..writeln('|---|---:|');
      for (final e in byLane.entries) {
        buf.writeln('| ${e.key} | ${e.value} |');
      }
      buf
        ..writeln()
        ..writeln('| Origem do crescimento | Ativos |')
        ..writeln('|---|---:|');
      for (final e in byOrigin.entries) {
        buf.writeln('| ${e.key} | ${e.value} |');
      }

      final withMoat = evaluated.where((l) => l.moat).toList();
      buf
        ..writeln()
        ..writeln('| Terminal | Ativos |')
        ..writeln('|---|---:|')
        ..writeln('| estado estacionário (ROIC_inf = WACC_inf) | '
            '${evaluated.length - withMoat.length} |')
        ..writeln('| vantagem competitiva residual | ${withMoat.length} |');
      if (withMoat.isNotEmpty) {
        buf
          ..writeln()
          ..writeln('Com vantagem residual: '
              '${(withMoat.map((l) => l.ticker).toList()..sort()).join(", ")}.');
      }

      _moatSection(buf, evaluated);
      _normalizationSection(buf, evaluated);

      final upsides = [for (final l in evaluated) l.upside!]..sort();
      double q(double p) => upsides[(p * (upsides.length - 1)).round()];
      buf
        ..writeln()
        ..writeln('## Dispersão do potencial de valorização')
        ..writeln()
        ..writeln('| Percentil | Potencial |')
        ..writeln('|---|---:|')
        ..writeln('| mínimo | ${pct(upsides.first, decimals: 1)} |')
        ..writeln('| p10 | ${pct(q(0.10), decimals: 1)} |')
        ..writeln('| p25 | ${pct(q(0.25), decimals: 1)} |')
        ..writeln('| mediana | ${pct(q(0.50), decimals: 1)} |')
        ..writeln('| p75 | ${pct(q(0.75), decimals: 1)} |')
        ..writeln('| p90 | ${pct(q(0.90), decimals: 1)} |')
        ..writeln('| máximo | ${pct(upsides.last, decimals: 1)} |');

      _expectedReturnSection(buf, evaluated, anchors);
    }

    buf
      ..writeln()
      ..writeln('## Ativo a ativo')
      ..writeln()
      ..writeln('| Ativo | Setor | Saída | Via | Crescimento | Justo | Preço | Potencial |')
      ..writeln('|---|---|---|---|---|---:|---:|---:|');
    final sortedRows = [...rows]..sort((a, b) => a.ticker.compareTo(b.ticker));
    for (final l in sortedRows) {
      buf.writeln('| ${l.ticker} | ${l.sector ?? "—"} | ${l.outcome} | '
          '${l.lane ?? "—"} | ${l.growthOrigin ?? "—"} | '
          '${l.fairValue == null ? "—" : num2(l.fairValue!, decimals: 2)} | '
          '${l.price == null ? "—" : num2(l.price!, decimals: 2)} | '
          '${l.upside == null ? "—" : pct(l.upside!, decimals: 1)} |');
    }

    writeReport('$outputDir/validacao_fora_da_amostra.md', buf.toString());
    writeReport(
      '$outputDir/validacao_fora_da_amostra.json',
      const JsonEncoder.withIndent('  ')
          .convert([for (final l in rows) l.toJson()]),
    );
  }
}

/// Distribuição das condições que barraram a vantagem competitiva residual.
///
/// **É o instrumento de calibragem.** Saber que dois de cento e vinte passaram
/// não diz se o critério está apertado ou se o universo é comum; saber quantos
/// reprovaram só pela rentabilidade, e a que distância do corte, diz — e é o
/// que permite mover o parâmetro por medição em vez de por impressão.
void _moatSection(StringBuffer buf, List<_Row> evaluated) {
  final withDiagnostic =
      evaluated.where((l) => l.diagnostics.moatBlocks != null).toList();
  if (withDiagnostic.isEmpty) return;

  final byCondition = <String, int>{};
  final first = <String, int>{};
  for (final l in withDiagnostic) {
    final blocks = l.diagnostics.moatBlocks!;
    if (blocks.isEmpty) continue;
    first[blocks.first] = (first[blocks.first] ?? 0) + 1;
    for (final b in blocks) {
      byCondition[b] = (byCondition[b] ?? 0) + 1;
    }
  }

  buf
    ..writeln()
    ..writeln('### Por que a vantagem residual foi barrada')
    ..writeln()
    ..writeln('Uma linha por condição, contando **todas** as que barraram cada '
        'ativo — os totais somam mais que o número de reprovados, e é essa a '
        'informação: quem reprova por duas condições continuaria reprovado se '
        'só uma fosse afrouxada.')
    ..writeln()
    ..writeln('| Condição | Barrou | Foi a primeira |')
    ..writeln('|---|---:|---:|');
  final sortedEntries = byCondition.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in sortedEntries) {
    buf.writeln(
        '| ${_moatLabel(e.key)} | ${e.value} | ${first[e.key] ?? 0} |');
  }

  final byHealth = withDiagnostic
      .where((l) =>
          l.diagnostics.moatBlocks!.contains('saudeOperacional') &&
          l.diagnostics.operationalDecline != null)
      .toList()
    ..sort((a, b) => b.diagnostics.operationalDecline!
        .compareTo(a.diagnostics.operationalDecline!));
  if (byHealth.isNotEmpty) {
    buf
      ..writeln()
      ..writeln('Os ${byHealth.length} barrados pelo filtro de saúde '
          'operacional — resultado em queda no triênio, por mais alta que a '
          'mediana do ciclo ainda esteja:')
      ..writeln()
      ..writeln('| Ativo | Queda no triênio | ROIC do ciclo |')
      ..writeln('|---|---:|---:|');
    for (final l in byHealth.take(10)) {
      buf.writeln('| ${l.ticker} | '
          '${pct(l.diagnostics.operationalDecline!, decimals: 1)} | '
          '${l.diagnostics.cycleReturn == null ? "—" : pct(l.diagnostics.cycleReturn!, decimals: 1)} |');
    }
  }

  // **Seção inerte desde a decisão 36.** O bloco `rentabilidadeInsuficiente`
  // deixou de existir quando o degrau da vantagem competitiva virou decaimento
  // medido, de modo que `moatBlockedOnlyByReturn` nunca mais é verdadeiro e o
  // retorno antecipado abaixo sempre dispara. Fica como registro do regime
  // anterior; removê-la é limpeza para outra rodada.
  final profitabilityOnly = withDiagnostic
      .where((l) => l.diagnostics.moatBlockedOnlyByReturn)
      .toList();
  if (profitabilityOnly.isEmpty) return;

  final distances = <double>[
    for (final l in profitabilityOnly)
      if (l.diagnostics.cycleReturn != null &&
          l.diagnostics.terminalDiscount != null)
        l.diagnostics.cycleReturn! - l.diagnostics.terminalDiscount!,
  ]..sort();
  if (distances.isEmpty) return;

  double q(double p) => distances[(p * (distances.length - 1)).round()];
  buf
    ..writeln()
    ..writeln('Dos reprovados, ${profitabilityOnly.length} '
        '${profitabilityOnly.length == 1 ? "falhou" : "falharam"} **apenas** na '
        'rentabilidade — cumprem crescimento orgânico e histórico. O excedente '
        'do ciclo sobre o custo de capital de equilíbrio nesses casos:')
    ..writeln()
    ..writeln('| Percentil | Excedente |')
    ..writeln('|---|---:|')
    ..writeln('| p25 | ${pct(q(0.25), decimals: 1)} |')
    ..writeln('| mediana | ${pct(q(0.50), decimals: 1)} |')
    ..writeln('| p75 | ${pct(q(0.75), decimals: 1)} |')
    ..writeln('| p90 | ${pct(q(0.90), decimals: 1)} |')
    ..writeln('| máximo | ${pct(distances.last, decimals: 1)} |');
}

/// Rótulo legível para o nome do `MoatBlock`.
String _moatLabel(String name) => switch (name) {
      'semRetornoDoCiclo' => 'retorno do ciclo não medido',
      'semCustoDeCapital' => 'custo de capital não positivo',
      'historicoCurto' => 'histórico curto',
      'capitalExternoNaoMedido' => 'capital externo não medido',
      'crescimentoInorganico' => 'crescimento inorgânico',
      'rentabilidadeInsuficiente' => 'rentabilidade insuficiente',
      'saudeOperacional' => 'resultado em queda no triênio',
      'excedenteDegenerado' => 'excedente degenerado',
      _ => name,
    };

/// Efeito da correção de precedência da Guarda 2.
///
/// Conta quantos ativos tiveram a base normalizada **apesar** de Φ acima do
/// limiar — o conjunto que, sob a precedência anterior, levava o exercício de
/// pico à perpetuidade como se fosse patamar.
void _normalizationSection(StringBuffer buf, List<_Row> evaluated) {
  bool wasNormalized(_Row l) =>
      l.diagnostics.normalizationFactor != null &&
      (l.diagnostics.normalizationFactor! - 1.0).abs() > 1e-6;

  final unlocked =
      evaluated.where((l) => l.diagnostics.normalizedInorganicBase).toList()
        ..sort((a, b) => a.ticker.compareTo(b.ticker));
  final normalizedCount = evaluated.where(wasNormalized).length;

  buf
    ..writeln()
    ..writeln('### Normalização da base')
    ..writeln()
    ..writeln('| Base | Ativos |')
    ..writeln('|---|---:|')
    ..writeln('| mantida como observada | ${evaluated.length - normalizedCount} |')
    ..writeln('| convergindo ao ciclo | $normalizedCount |')
    ..writeln('| das quais, com Φ acima do limiar | ${unlocked.length} |');
  final cyclicalOnes = evaluated.where((l) => l.diagnostics.cyclePrecedence).toList();
  final unlockedByCycle = cyclicalOnes
      .where((l) => wasNormalized(l) && l.diagnostics.trendVerdict == 'domina')
      .toList()
    ..sort((a, b) => a.ticker.compareTo(b.ticker));
  final saturatedOnes = evaluated
      .where((l) => l.diagnostics.saturated && !l.diagnostics.healthCapped)
      .toList()
    ..sort((a, b) => (b.diagnostics.rawFactor ?? 0)
        .compareTo(a.diagnostics.rawFactor ?? 0));

  final exempt = evaluated.where((l) => l.diagnostics.healthExempt).toList()
    ..sort((a, b) => a.ticker.compareTo(b.ticker));
  final healthLockedOnes = evaluated
      .where((l) => l.diagnostics.healthCapped)
      .toList()
    ..sort((a, b) => (b.diagnostics.rawFactor ?? 0)
        .compareTo(a.diagnostics.rawFactor ?? 0));

  buf
    ..writeln()
    ..writeln('| Trava | Ativos |')
    ..writeln('|---|---:|')
    ..writeln('| em setor cíclico (Guarda 3 com precedência) | '
        '${cyclicalOnes.length} |')
    ..writeln('| normalizados **por** essa precedência | '
        '${unlockedByCycle.length} |')
    ..writeln('| com o fator saturado em [0,33; 3,00] | ${saturatedOnes.length} |')
    ..writeln('| com o teto travado em 1,00 pela saúde operacional | '
        '${healthLockedOnes.length} |')
    ..writeln('| reprovados na saúde mas isentos por setor cíclico | '
        '${exempt.length} |');

  if (exempt.isNotEmpty) {
    buf
      ..writeln()
      ..writeln('Isentos da trava por serem de setor cíclico. A queda entre o '
          'pico e o vale é oscilação do preço do insumo, e a convergência ao '
          'ciclo opera nos dois sentidos — limitada pela saturação, que vale '
          'igual. A vantagem residual não tem trava de saúde desde a decisão '
          '36: para eles também, quem decide é a persistência medida do '
          'excedente.')
      ..writeln()
      ..writeln('| Ativo | Setor | Queda no triênio | Fator | Potencial |')
      ..writeln('|---|---|---:|---:|---:|');
    for (final l in exempt) {
      buf.writeln('| ${l.ticker} | ${l.sector ?? "—"} | '
          '${l.diagnostics.operationalDecline == null ? "—" : pct(l.diagnostics.operationalDecline!, decimals: 1)} | '
          '${num2(l.diagnostics.normalizationFactor!, decimals: 2)} | '
          '${pct(l.upside!, decimals: 1)} |');
    }
  }

  if (healthLockedOnes.isNotEmpty) {
    buf
      ..writeln()
      ..writeln('Onde a saúde operacional proibiu normalizar para cima. **Não é '
          'a mesma coisa que a saturação**: ali o limite é de política sobre '
          'quanta autoridade um exercício tem; aqui a afirmação é que a mediana '
          'de ${ValuationParameters.cycleWindow} exercícios deixou de descrever '
          'a empresa.')
      ..writeln()
      ..writeln('| Ativo | Queda no triênio | Fator bruto | Aplicado | Potencial |')
      ..writeln('|---|---:|---:|---:|---:|');
    for (final l in healthLockedOnes) {
      buf.writeln('| ${l.ticker} | '
          '${l.diagnostics.operationalDecline == null ? "—" : pct(l.diagnostics.operationalDecline!, decimals: 1)} | '
          '${num2(l.diagnostics.rawFactor!, decimals: 2)} | '
          '${num2(l.diagnostics.normalizationFactor!, decimals: 2)} | '
          '${pct(l.upside!, decimals: 1)} |');
    }
  }

  if (unlockedByCycle.isNotEmpty) {
    buf
      ..writeln()
      ..writeln('Em setor cíclico, a tendência deixou de segurar a base nestes '
          '— a perna de alta do ciclo tem a forma de uma tendência, e lê-la '
          'como patamar estrutural era o erro:')
      ..writeln()
      ..writeln('| Ativo | Setor | Retorno corrente | Ciclo | Fator | Potencial |')
      ..writeln('|---|---|---:|---:|---:|---:|');
    for (final l in unlockedByCycle) {
      buf.writeln('| ${l.ticker} | ${l.sector ?? "—"} | '
          '${l.diagnostics.latestReturn == null ? "—" : pct(l.diagnostics.latestReturn!, decimals: 1)} | '
          '${l.diagnostics.cycleReturnOfBase == null ? "—" : pct(l.diagnostics.cycleReturnOfBase!, decimals: 1)} | '
          '${num2(l.diagnostics.normalizationFactor!, decimals: 2)} | '
          '${pct(l.upside!, decimals: 1)} |');
    }
  }

  if (saturatedOnes.isNotEmpty) {
    buf
      ..writeln()
      ..writeln('Onde a saturação prendeu, com o fator que teria sido aplicado '
          'sem ela. **O preço justo destes é conservador por política**, e o '
          'resultado o declara:')
      ..writeln()
      ..writeln('| Ativo | Fator bruto | Aplicado | Potencial |')
      ..writeln('|---|---:|---:|---:|');
    for (final l in saturatedOnes) {
      buf.writeln('| ${l.ticker} | '
          '${num2(l.diagnostics.rawFactor!, decimals: 2)} | '
          '${num2(l.diagnostics.normalizationFactor!, decimals: 2)} | '
          '${pct(l.upside!, decimals: 1)} |');
    }
  }

  final notNormalized = evaluated.where((l) => !wasNormalized(l)).toList();
  final byGuard = <String, int>{};
  for (final l in notNormalized) {
    final g1 = l.diagnostics.trendVerdict;
    final g3 = l.diagnostics.deviationVerdict;
    if (g1 == null || g3 == null) continue;
    final reason = g3 != 'destoa'
        ? 'Guarda 3: o exercício não destoa do ciclo'
        : (g1 == 'domina'
            ? 'Guarda 1: a tendência domina a reversão'
            : 'outro impedimento (retorno corrente não positivo ou não medido)');
    byGuard[reason] = (byGuard[reason] ?? 0) + 1;
  }
  if (byGuard.isNotEmpty) {
    buf
      ..writeln()
      ..writeln('Por que a base **não** foi normalizada, nos que ficaram como '
          'observados:')
      ..writeln()
      ..writeln('| Guarda que decidiu | Ativos |')
      ..writeln('|---|---:|');
    final order = byGuard.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in order) {
      buf.writeln('| ${e.key} | ${e.value} |');
    }
  }

  // A classe da SUZB3: destoa do ciclo, mas a tendência domina e a base fica
  // como observada. É a guarda que efetivamente decide esses casos — e não a de
  // comparabilidade, que a §12.5 do refinamento apontava como suspeita.
  final heldByTrend = notNormalized
      .where((l) =>
          l.diagnostics.deviationVerdict == 'destoa' &&
          l.diagnostics.trendVerdict == 'domina' &&
          l.diagnostics.latestReturn != null &&
          l.diagnostics.cycleReturnOfBase != null)
      .toList()
    ..sort((a, b) => (b.upside ?? 0).compareTo(a.upside ?? 0));
  if (heldByTrend.isNotEmpty) {
    buf
      ..writeln()
      ..writeln('Os ${heldByTrend.length} que **destoam do ciclo e '
          'ainda assim ficam como observados** são segurados pela Guarda 1: a '
          'tendência do retorno domina a reversão à média, e o modelo lê o '
          'nível corrente como estrutural em vez de cíclico. Os dez de maior '
          'potencial:')
      ..writeln()
      ..writeln('| Ativo | Retorno corrente | Ciclo | Φ | Potencial |')
      ..writeln('|---|---:|---:|---:|---:|');
    for (final l in heldByTrend.take(10)) {
      buf.writeln('| ${l.ticker} | '
          '${pct(l.diagnostics.latestReturn!, decimals: 1)} | '
          '${pct(l.diagnostics.cycleReturnOfBase!, decimals: 1)} | '
          '${l.diagnostics.phi == null ? "—" : num2(l.diagnostics.phi!, decimals: 2)} | '
          '${pct(l.upside!, decimals: 1)} |');
    }
  }

  // A tabela dos maiores fatores saiu daqui: com a saturação em [0,33; 3,00],
  // o topo é o próprio teto por construção, e listar dez linhas de "3,00" não
  // informa nada. Quem carrega a informação agora é a tabela de saturação
  // acima, que mostra o fator **bruto** que teria sido aplicado sem o limite.

  if (unlocked.isEmpty) return;

  buf
    ..writeln()
    ..writeln(unlocked.length == 1
        ? 'O único de base inorgânica normalizada é o que a precedência '
            'anterior deixava passar com o exercício corrente como patamar '
            'perene. Fator aplicado sobre o lucro observado:'
        : 'Os ${unlocked.length} de base inorgânica normalizada são os que '
            'a precedência anterior deixava passar com o exercício corrente '
            'como patamar perene. Fator aplicado sobre o lucro observado:')
    ..writeln()
    ..writeln('| Ativo | Φ | Fator |')
    ..writeln('|---|---:|---:|');
  for (final l in unlocked) {
    buf.writeln('| ${l.ticker} | ${num2(l.diagnostics.phi!, decimals: 2)} | '
        '${num2(l.diagnostics.normalizationFactor!, decimals: 3)} |');
  }
}

/// Retorno esperado transversal sobre o universo avaliado.
///
/// **A seção mais larga que o trabalho tem.** É aqui que o estimador faz
/// sentido: medir uma carteira de cinco ativos contra ela mesma a centra no CDI
/// por construção, e a distribuição sobre os avaliados é a referência contra a
/// qual qualquer carteira passa a ser lida.
void _expectedReturnSection(
  StringBuffer buf,
  List<_Row> evaluated,
  MarketAnchors anchors,
) {
  final upsides = <Ticker, double>{
    for (final l in evaluated) Ticker.parse(l.ticker): l.upside!,
  };
  final estimated = ExpectedReturn.crossSection(
    upsides: upsides,
    spotRiskFree: anchors.currentRiskFreeRate,
  );

  final rates = [for (final r in estimated.values) r.expected]..sort();
  double q(double p) => rates[(p * (rates.length - 1)).round()];
  final atFloor = estimated.values.where((r) => r.floored).length;

  // A comparação que justifica a troca: o mesmo conjunto, pelo caminho antigo.
  final annualReturns = [
    for (final l in evaluated) ExpectedReturn.annualizedFromUpside(l.upside!),
  ]..sort();
  double qa(double p) => annualReturns[(p * (annualReturns.length - 1)).round()];
  final negatives = annualReturns.where((r) => r < 0).length;

  buf
    ..writeln()
    ..writeln('## Retorno esperado para otimização')
    ..writeln()
    ..writeln('`E[R_i] = CDI_spot + z(potencial) x prêmio`, com CDI à vista de '
        '${pct(anchors.currentRiskFreeRate)}, prêmio de '
        '${pct(CapmInputs.defaultMarketPremium)} e escore robusto confinado a '
        '${num2(ExpectedReturn.defaultZCap, decimals: 1)} desvios sobre a '
        'seção dos ${evaluated.length} avaliados.')
    ..writeln()
    ..writeln('| Percentil | Transversal | Anualização do potencial |')
    ..writeln('|---|---:|---:|')
    ..writeln('| mínimo | ${pct(rates.first, decimals: 1)} | '
        '${pct(annualReturns.first, decimals: 1)} |')
    ..writeln('| p10 | ${pct(q(0.10), decimals: 1)} | '
        '${pct(qa(0.10), decimals: 1)} |')
    ..writeln('| p25 | ${pct(q(0.25), decimals: 1)} | '
        '${pct(qa(0.25), decimals: 1)} |')
    ..writeln('| mediana | ${pct(q(0.50), decimals: 1)} | '
        '${pct(qa(0.50), decimals: 1)} |')
    ..writeln('| p75 | ${pct(q(0.75), decimals: 1)} | '
        '${pct(qa(0.75), decimals: 1)} |')
    ..writeln('| p90 | ${pct(q(0.90), decimals: 1)} | '
        '${pct(qa(0.90), decimals: 1)} |')
    ..writeln('| máximo | ${pct(rates.last, decimals: 1)} | '
        '${pct(annualReturns.last, decimals: 1)} |')
    ..writeln()
    ..writeln('Pela anualização do potencial, $negatives dos ${annualReturns.length} '
        'avaliados entrariam num otimizador de média-variância com retorno '
        'esperado **negativo** — o que não é ordenação ruim, é ausência de '
        'alocação. Pelo estimador transversal, '
        '${atFloor == 0 ? "nenhum tocou" : "$atFloor tocaram"} o piso de zero, e '
        'a ordenação por potencial é preservada em toda a faixa.');
}

/// O que o log de avaliação registrou sobre as guardas de um ativo.
///
/// Lido do rastro de cálculo, não dos avisos: as chaves são estáveis, e os
/// avisos são texto para o usuário — mudam de redação sem aviso, e um relatório
/// que dependesse deles mediria a redação.
class _Diagnostics {
  /// Condições que barraram a vantagem competitiva residual, pelo nome do
  /// `MoatBlock`. Vazia quando comprovada; nula quando o passo não rodou.
  final List<String>? moatBlocks;

  /// ROIC ou ROE mediano do ciclo, em fração.
  final double? cycleReturn;

  /// Custo de capital de equilíbrio, em fração.
  final double? terminalDiscount;

  /// Φ — capital externo em múltiplos da base inicial da janela.
  final double? phi;

  /// Fator aplicado ao lucro-base: 1,0 quando a base ficou como observada.
  final double? normalizationFactor;

  /// Veredito da Guarda 1: `domina`, `não domina` ou `não avaliável`.
  final String? trendVerdict;

  /// Veredito da Guarda 3: `destoa` ou `dentro da banda e do desvio robusto`.
  final String? deviationVerdict;

  /// Retorno do exercício corrente, em fração.
  final double? latestReturn;

  /// Mediana do ciclo na série da via escolhida, em fração.
  final double? cycleReturnOfBase;

  /// `true` quando o ativo é de setor cíclico pesado e a Guarda 3 teve
  /// precedência sobre a Guarda 1.
  final bool cyclePrecedence;

  /// Fator antes da saturação em `[0,33; 3,00]`.
  final double? rawFactor;

  /// `true` quando a saturação do fator foi acionada.
  final bool saturated;

  /// `true` quando o teto do fator caiu para 1,00 por reprovação na saúde
  /// operacional, impedindo normalizar a base para cima.
  final bool healthCapped;

  /// `true` quando o ativo reprovou na saúde operacional mas é de setor cíclico,
  /// e por isso ficou isento da trava na Porta 2a.
  final bool healthExempt;

  /// Queda de lucro ou EBITDA no triênio recente, em fração.
  final double? operationalDecline;

  const _Diagnostics({
    this.moatBlocks,
    this.cycleReturn,
    this.terminalDiscount,
    this.phi,
    this.normalizationFactor,
    this.trendVerdict,
    this.deviationVerdict,
    this.latestReturn,
    this.cycleReturnOfBase,
    this.cyclePrecedence = false,
    this.rawFactor,
    this.saturated = false,
    this.healthCapped = false,
    this.healthExempt = false,
    this.operationalDecline,
  });

  static const _Diagnostics empty = _Diagnostics();

  /// `true` quando a base foi normalizada apesar de inorgânica — o caso que a
  /// correção de precedência da Guarda 2 destravou.
  bool get normalizedInorganicBase =>
      phi != null &&
      phi! > 1.0 &&
      normalizationFactor != null &&
      (normalizationFactor! - 1.0).abs() > 1e-6;

  /// `true` quando só a rentabilidade barrou a vantagem residual.
  bool get moatBlockedOnlyByReturn =>
      moatBlocks != null &&
      moatBlocks!.length == 1 &&
      moatBlocks!.first == 'rentabilidadeInsuficiente';

  /// Extrai os campos do evento de auditoria da avaliação.
  static _Diagnostics from(AuditEvent? event) {
    if (event == null) return empty;

    // A **última** ocorrência, não a primeira: quando a via da firma reprova na
    // pós-condição da ponte de equity, a cascata reavalia pela via do
    // acionista e o mesmo passo aparece duas vezes. Quem produziu o preço
    // justo é o segundo, e ler o primeiro descreveria uma avaliação
    // descartada.
    CalculationTrace? trace(String name) {
      CalculationTrace? foundValue;
      for (final c in event.calculations) {
        if (c.formulaName == name) foundValue = c;
      }
      return foundValue;
    }

    /// Percentual gravado no rastro, de volta a fração. `null` para 'n/d'.
    double? fraction(Object? v) {
      final n = v is num ? v.toDouble() : null;
      return n == null ? null : n / 100.0;
    }

    final moat = trace('Vantagem competitiva residual na perpetuidade');
    final base = trace('Base do fluxo: normalização pelo ciclo');
    final blockers = moat?.mappedVariables['condições que barraram'];

    return _Diagnostics(
      moatBlocks: blockers is List ? [for (final b in blockers) '$b'] : null,
      cycleReturn: fraction(moat?.mappedVariables['ROIC do ciclo (% a.a.)']),
      terminalDiscount:
          fraction(moat?.mappedVariables['WACC de equilíbrio (% a.a.)']),
      phi: () {
        final v = base?.mappedVariables['capital externo / base (Φ)'];
        return v is num ? v.toDouble() : null;
      }(),
      normalizationFactor: base?.finalValue,
      trendVerdict: base?.mappedVariables['guarda 1 — tendência'] as String?,
      deviationVerdict:
          base?.mappedVariables['guarda 3 — desvio do ciclo'] as String?,
      latestReturn: fraction(base?.mappedVariables['retorno atual (% a.a.)']),
      cycleReturnOfBase:
          fraction(base?.mappedVariables['mediana do ciclo (% a.a.)']),
      cyclePrecedence:
          base?.mappedVariables['precedência do ciclo (setor cíclico)'] == true,
      rawFactor: () {
        final v = base?.mappedVariables['fator bruto'];
        return v is num ? v.toDouble() : null;
      }(),
      saturated: base?.mappedVariables['fator saturado'] == true,
      healthCapped: base?.mappedVariables['teto travado pela saúde'] == true,
      healthExempt:
          base?.mappedVariables['isento da trava por setor cíclico'] == true,
      operationalDecline: fraction(base?.mappedVariables['queda no triênio (%)']) ??
          fraction(moat?.mappedVariables['queda no triênio (%)']),
    );
  }
}

class _Row {
  final String ticker;
  final String outcome;
  final String? lane;
  final String? sector;
  final String? detail;
  final String? growthOrigin;
  final double? fairValue;
  final double? price;
  final double? upside;
  final int warnings;

  /// Vantagem competitiva residual preservada na perpetuidade.
  final bool moat;

  /// O que as guardas registraram no log de avaliação.
  final _Diagnostics diagnostics;

  const _Row({
    required this.ticker,
    required this.outcome,
    this.lane,
    this.sector,
    this.detail,
    this.growthOrigin,
    this.fairValue,
    this.price,
    this.upside,
    this.warnings = 0,
    this.moat = false,
    this.diagnostics = _Diagnostics.empty,
  });

  Map<String, dynamic> toJson() => {
        'ticker': ticker,
        'saida': outcome,
        if (lane != null) 'via': lane,
        if (sector != null) 'setor': sector,
        if (growthOrigin != null) 'crescimento': growthOrigin,
        if (fairValue != null) 'justo': fairValue,
        if (price != null) 'preco': price,
        if (upside != null) 'potencial': upside,
        'avisos': warnings,
        'moat': moat,
        if (diagnostics.moatBlocks != null)
          'moatBarradoPor': diagnostics.moatBlocks,
        if (diagnostics.cycleReturn != null)
          'retornoDoCiclo': diagnostics.cycleReturn,
        if (diagnostics.terminalDiscount != null)
          'custoDeCapitalTerminal': diagnostics.terminalDiscount,
        if (diagnostics.phi != null) 'phi': diagnostics.phi,
        if (diagnostics.normalizationFactor != null)
          'fatorDeNormalizacao': diagnostics.normalizationFactor,
        if (diagnostics.trendVerdict != null)
          'guarda1': diagnostics.trendVerdict,
        if (diagnostics.deviationVerdict != null)
          'guarda3': diagnostics.deviationVerdict,
        if (diagnostics.latestReturn != null)
          'retornoCorrente': diagnostics.latestReturn,
        if (diagnostics.cycleReturnOfBase != null)
          'retornoDoCicloDaBase': diagnostics.cycleReturnOfBase,
        'precedenciaDoCiclo': diagnostics.cyclePrecedence,
        if (diagnostics.rawFactor != null) 'fatorBruto': diagnostics.rawFactor,
        'fatorSaturado': diagnostics.saturated,
        'tetoTravadoPelaSaude': diagnostics.healthCapped,
        'isentoPorSetorCiclico': diagnostics.healthExempt,
        if (diagnostics.operationalDecline != null)
          'quedaNoTrienio': diagnostics.operationalDecline,
        if (detail != null) 'detalhe': detail,
      };
}

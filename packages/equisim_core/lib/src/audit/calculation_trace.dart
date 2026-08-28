import 'dart:math' as math;

/// Um ponto da amostra que sustenta um cálculo agregado.
class TraceSamplePoint {
  /// Rótulo do período — o ano fiscal, tipicamente.
  final String label;

  final double value;

  /// `true` quando o ponto é um dos que **definem** a estatística resumo:
  /// o central numa mediana de amostra ímpar, os dois centrais numa par.
  final bool definesResult;

  /// `true` para o período observado, o que a fórmula trata.
  final bool isObserved;

  const TraceSamplePoint({
    required this.label,
    required this.value,
    this.definesResult = false,
    this.isObserved = false,
  });

  Map<String, dynamic> toJson() => {
        'label': label,
        'value': value,
        'definesResult': definesResult,
        'isObserved': isObserved,
      };

  static TraceSamplePoint fromJson(Map<String, dynamic> json) =>
      TraceSamplePoint(
        label: json['label'] as String? ?? '—',
        value: (json['value'] as num?)?.toDouble() ?? 0,
        definesResult: json['definesResult'] as bool? ?? false,
        isObserved: json['isObserved'] as bool? ?? false,
      );
}

/// A amostra por trás de um cálculo que resume vários períodos num só número.
///
/// Uma mediana apresentada sozinha é indistinguível de um chute: quem confere
/// a conta não consegue dizer quais exercícios entraram nela, qual ficou no
/// meio, nem se a janela pegou os anos que deveria. Este é o material que o
/// painel de auditoria desenha, e é o mesmo que o algoritmo usou — não uma
/// reconstrução feita à parte.
class TraceSample {
  /// O que a amostra mede, para o cabeçalho do gráfico.
  final String title;

  /// Em ordem cronológica.
  final List<TraceSamplePoint> points;

  /// Estatística resumo da amostra — a mediana, no fluxo-base.
  final double? summary;

  /// Como chamar [summary] na legenda.
  final String summaryLabel;

  /// Bordas da banda de aceitação, quando o cálculo define uma.
  final double? lowerBound;
  final double? upperBound;

  /// Valor efetivamente adotado depois do tratamento.
  final double? selected;

  final String unit;

  const TraceSample({
    required this.title,
    required this.points,
    this.summary,
    this.summaryLabel = 'mediana',
    this.lowerBound,
    this.upperBound,
    this.selected,
    this.unit = '',
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'points': [for (final p in points) p.toJson()],
        'summary': summary,
        'summaryLabel': summaryLabel,
        'lowerBound': lowerBound,
        'upperBound': upperBound,
        'selected': selected,
        'unit': unit,
      };

  static TraceSample fromJson(Map<String, dynamic> json) => TraceSample(
        title: json['title'] as String? ?? '',
        points: [
          for (final p in (json['points'] as List? ?? const []))
            if (p is Map) TraceSamplePoint.fromJson(_stringKeyed(p)),
        ],
        summary: (json['summary'] as num?)?.toDouble(),
        summaryLabel: json['summaryLabel'] as String? ?? 'mediana',
        lowerBound: (json['lowerBound'] as num?)?.toDouble(),
        upperBound: (json['upperBound'] as num?)?.toDouble(),
        selected: (json['selected'] as num?)?.toDouble(),
        unit: json['unit'] as String? ?? '',
      );

  static Map<String, dynamic> _stringKeyed(Map<dynamic, dynamic> source) =>
      source.map((k, v) => MapEntry('$k', v));
}

/// Rastro de **um** cálculo: a fórmula, os valores que entraram nela e a
/// aritmética passo a passo até o resultado.
///
/// Existe para auditoria acadêmica. A defesa de um trabalho que produz números
/// exige demonstrar que o número apresentado na tela é o número que a fórmula
/// da metodologia produz — e a única forma honesta de demonstrar isso é expor
/// a substituição de variáveis feita pelo código que roda de verdade, não uma
/// reconstrução escrita à parte que pode divergir dele em silêncio.
///
/// Por isso o rastro é **capturado no ponto do cálculo**, a partir dos mesmos
/// objetos que alimentam o resultado apresentado. Nada aqui recalcula nada.
class CalculationTrace {
  /// Nome do cálculo, como aparece na metodologia.
  final String formulaName;

  /// A fórmula em LaTeX, para renderização em formatação acadêmica.
  final String latexRepresentation;

  /// Símbolo → valor atribuído. As chaves usam o mesmo símbolo do LaTeX,
  /// sem a barra invertida, para que a tabela case com a fórmula renderizada.
  final Map<String, Object?> mappedVariables;

  /// Decomposição da aritmética, uma linha por etapa.
  final List<String> intermediateSteps;

  final double? finalValue;

  /// Unidade do resultado: `R$`, `%`, `×`, `anos`, ou vazio para adimensional.
  final String unit;

  /// A amostra por trás do cálculo, quando ele resume vários períodos.
  ///
  /// Nula na maioria das fórmulas — só existe onde há agregação a auditar.
  final TraceSample? sample;

  const CalculationTrace({
    required this.formulaName,
    required this.latexRepresentation,
    this.mappedVariables = const {},
    this.intermediateSteps = const [],
    this.finalValue,
    this.unit = '',
    this.sample,
  });

  Map<String, dynamic> toJson() => {
        'formulaName': formulaName,
        'latexRepresentation': latexRepresentation,
        'mappedVariables': mappedVariables,
        'intermediateSteps': intermediateSteps,
        'finalValue': finalValue,
        'unit': unit,
        if (sample != null) 'sample': sample!.toJson(),
      };

  static CalculationTrace fromJson(Map<String, dynamic> json) =>
      CalculationTrace(
        formulaName: json['formulaName'] as String? ?? '—',
        latexRepresentation: json['latexRepresentation'] as String? ?? '',
        mappedVariables: (json['mappedVariables'] as Map?)
                ?.map((k, v) => MapEntry('$k', v)) ??
            const {},
        intermediateSteps: [
          for (final step in (json['intermediateSteps'] as List? ?? const []))
            '$step',
        ],
        finalValue: (json['finalValue'] as num?)?.toDouble(),
        unit: json['unit'] as String? ?? '',
        sample: json['sample'] is Map
            ? TraceSample.fromJson(
                (json['sample'] as Map).map((k, v) => MapEntry('$k', v)))
            : null,
      );
}

/// Uma execução completa, do payload de entrada ao payload de saída.
///
/// O contrato de campos é fixo: é o que a página de logs consome e o que sai
/// no arquivo de exportação da auditoria.
class AuditEvent {
  final String transactionId;
  final DateTime timestamp;

  /// Origem da execução. Chamadas de rede trazem o caminho da API; cálculos do
  /// núcleo trazem o caminho interno do serviço — `/core/valuation/PETR4`, por
  /// exemplo. É o campo que separa os dois tipos de evento na interface.
  final String endpoint;

  final Map<String, dynamic> inputPayload;
  final Map<String, dynamic> outputPayload;
  final int executionTimeMs;
  final List<CalculationTrace> calculations;

  const AuditEvent({
    required this.transactionId,
    required this.timestamp,
    required this.endpoint,
    required this.inputPayload,
    required this.outputPayload,
    required this.executionTimeMs,
    this.calculations = const [],
  });

  Map<String, dynamic> toJson() => {
        'transactionId': transactionId,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'endpoint': endpoint,
        'inputPayload': inputPayload,
        'outputPayload': outputPayload,
        'executionTimeMs': executionTimeMs,
        'calculations': [for (final c in calculations) c.toJson()],
      };

  static AuditEvent fromJson(Map<String, dynamic> json) => AuditEvent(
        transactionId: json['transactionId'] as String? ?? '—',
        timestamp:
            DateTime.tryParse(json['timestamp'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
        endpoint: json['endpoint'] as String? ?? '—',
        inputPayload: _asMap(json['inputPayload']),
        outputPayload: _asMap(json['outputPayload']),
        executionTimeMs: (json['executionTimeMs'] as num?)?.toInt() ?? 0,
        calculations: [
          for (final c in (json['calculations'] as List? ?? const []))
            if (c is Map) CalculationTrace.fromJson(_asMap(c)),
        ],
      );

  static Map<String, dynamic> _asMap(Object? value) => value is Map
      ? value.map((k, v) => MapEntry('$k', v))
      : <String, dynamic>{};
}

/// Identificadores de transação.
///
/// Gerador próprio em vez do pacote `uuid` porque o núcleo é declaradamente
/// sem dependências de runtime — regra verificada por `purity_test.dart`.
abstract final class AuditIds {
  static final math.Random _random = math.Random();

  /// UUID v4 conforme a RFC 4122: 122 bits sorteados, versão 4 e variante 10.
  static String uuidV4() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final hex = [
      for (final b in bytes) b.toRadixString(16).padLeft(2, '0'),
    ].join();

    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}

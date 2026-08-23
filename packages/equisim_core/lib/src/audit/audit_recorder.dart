import 'calculation_trace.dart';

/// Destino dos eventos de auditoria.
typedef AuditEventSink = void Function(AuditEvent event);

/// Ponto único de coleta dos rastros de cálculo.
///
/// **Desligado por padrão.** Sem consumidor acoplado, [begin] devolve `null` e
/// todas as chamadas de instrumentação viram `null?.step(...)` — nenhum objeto
/// criado, nenhuma string formatada, nenhum custo. Isso é o que permite deixar
/// a instrumentação permanentemente no caminho do cálculo em vez de mantê-la
/// atrás de uma bifurcação que só é exercitada na apresentação.
///
/// O acoplamento é feito pela camada de aplicação ([attach]), que sabe para
/// onde mandar — no alvo web, a janela paralela de auditoria.
///
/// **Limite conhecido:** o coletor é estático e, portanto, local à isolate.
/// Uma avaliação executada em `compute()` — o que só acontece em Monte Carlo
/// com 20 mil sorteios ou mais, e nunca no alvo web, que não tem isolates —
/// roda com o coletor desligado e não emite rastro.
abstract final class AuditRecorder {
  static AuditEventSink? _sink;

  /// `true` quando há consumidor acoplado.
  static bool get isActive => _sink != null;

  static void attach(AuditEventSink sink) => _sink = sink;

  static void detach() => _sink = null;

  /// Abre uma transação, ou devolve `null` se ninguém estiver ouvindo.
  static AuditTransaction? begin(
    String endpoint, {
    Map<String, dynamic> inputPayload = const {},
  }) {
    final sink = _sink;
    if (sink == null) return null;
    return AuditTransaction._(endpoint, inputPayload, sink);
  }

  /// Emite um evento já montado — usado pela camada de rede, que mede a
  /// requisição inteira e não tem cálculo a decompor.
  static void emit(AuditEvent event) => _sink?.call(event);
}

/// Transação aberta: acumula rastros e, ao ser concluída, emite o evento.
class AuditTransaction {
  final String transactionId = AuditIds.uuidV4();
  final DateTime startedAt = DateTime.now();
  final String endpoint;
  final Map<String, dynamic> inputPayload;
  final List<CalculationTrace> _calculations = [];
  final AuditEventSink _sink;
  final Stopwatch _watch = Stopwatch()..start();
  bool _closed = false;

  AuditTransaction._(this.endpoint, this.inputPayload, this._sink);

  /// Registra um cálculo. Sobrecarga nomeada para caber numa linha no ponto
  /// de uso, que é onde a legibilidade importa.
  void step({
    required String formulaName,
    required String latex,
    Map<String, Object?> variables = const {},
    List<String> steps = const [],
    double? result,
    String unit = '',
  }) =>
      _calculations.add(CalculationTrace(
        formulaName: formulaName,
        latexRepresentation: latex,
        mappedVariables: variables,
        intermediateSteps: steps,
        finalValue: result,
        unit: unit,
      ));

  void add(CalculationTrace trace) => _calculations.add(trace);

  /// Encerra a transação com sucesso e emite o evento.
  void complete(Map<String, dynamic> outputPayload) =>
      _close(outputPayload);

  /// Encerra a transação sem resultado utilizável.
  ///
  /// O caminho de falha é tão auditável quanto o de sucesso: a banca pergunta
  /// por que um ativo não foi avaliado, e a resposta precisa estar registrada
  /// junto dos modelos que foram tentados antes de desistir.
  void abort(String reason, {Map<String, dynamic> extra = const {}}) =>
      _close({'status': 'falha', 'motivo': reason, ...extra});

  void _close(Map<String, dynamic> outputPayload) {
    if (_closed) return;
    _closed = true;
    _watch.stop();
    _sink(AuditEvent(
      transactionId: transactionId,
      timestamp: startedAt,
      endpoint: endpoint,
      inputPayload: inputPayload,
      outputPayload: outputPayload,
      executionTimeMs: _watch.elapsedMilliseconds,
      calculations: List.unmodifiable(_calculations),
    ));
  }
}

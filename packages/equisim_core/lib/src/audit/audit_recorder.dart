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

  /// Acopla o consumidor e liga a instrumentação.
  ///
  /// **Substitui silenciosamente** qualquer coletor anterior: há um único slot,
  /// e a segunda chamada desliga a primeira sem avisar. O acoplamento é
  /// responsabilidade exclusiva da camada de aplicação, chamado uma vez na
  /// composição — não em construtor de widget nem em `setUp` de teste que não
  /// faça [detach] depois.
  ///
  /// - [sink]: destino dos eventos. Recebe cada [AuditEvent] de forma síncrona,
  ///   no fim da transação que o produziu; um [sink] lento atrasa o cálculo.
  static void attach(AuditEventSink sink) => _sink = sink;

  /// Desliga a instrumentação e devolve o custo a zero.
  ///
  /// Transações já abertas continuam válidas e ainda emitem para o coletor que
  /// capturaram na abertura — [AuditTransaction] guarda a referência, não relê
  /// o slot estático.
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
  /// UUID v4 sorteado na abertura. Correlaciona o evento com a linha da
  /// interface de logs.
  final String transactionId = AuditIds.uuidV4();

  /// Instante da abertura. **Relógio do sistema** — é metadado de observação,
  /// nunca entra em cálculo, e por isso não viola o determinismo do núcleo.
  final DateTime startedAt = DateTime.now();

  /// Origem da execução, no formato de caminho. Ver [AuditEvent.endpoint].
  final String endpoint;

  /// Payload de entrada, capturado na abertura. Não é copiado: alterar o mapa
  /// depois de abrir a transação altera o que será emitido.
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
    TraceSample? sample,
  }) =>
      _calculations.add(CalculationTrace(
        formulaName: formulaName,
        latexRepresentation: latex,
        mappedVariables: variables,
        intermediateSteps: steps,
        finalValue: result,
        unit: unit,
        sample: sample,
      ));

  /// Anexa um rastro já montado, para quem o constrói fora do ponto de uso.
  void add(CalculationTrace trace) => _calculations.add(trace);

  /// Encerra a transação com sucesso e emite o evento.
  ///
  /// **Idempotente**: chamadas após o primeiro encerramento não fazem nada e
  /// não emitem evento duplicado — o que permite chamar [complete] e [abort]
  /// em caminhos que possam se cruzar sem coordenação.
  ///
  /// - [outputPayload]: resultado a registrar no evento.
  void complete(Map<String, dynamic> outputPayload) =>
      _close(outputPayload);

  /// Encerra a transação sem resultado utilizável.
  ///
  /// O caminho de falha é tão auditável quanto o de sucesso: a banca pergunta
  /// por que um ativo não foi avaliado, e a resposta precisa estar registrada
  /// junto dos modelos que foram tentados antes de desistir.
  ///
  /// - [reason]: motivo da desistência, gravado em `motivo`.
  /// - [extra]: campos adicionais mesclados no payload de saída. Chaves
  ///   `status` e `motivo` são sobrescritas por [extra], não o contrário.
  ///
  /// Idempotente, como [complete].
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

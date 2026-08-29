import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/foundation.dart';

/// Pedido de avaliação, serializável para atravessar a fronteira de isolate.
///
/// Só carrega dados — nenhuma função. Closures não podem ser enviadas a outra
/// isolate, então a decisão de qual modelo aplicar acontece **dentro** dela,
/// via [ValuationCascade], em vez de ser injetada de fora.
class ValuationRequest {
  /// Insumos já resolvidos. É o que domina o custo de cópia entre isolates.
  final ValuationInputs inputs;

  /// `true` para sortear cenários; `false` para os três discretos.
  final bool monteCarlo;

  /// Sorteios quando [monteCarlo] é `true`. Também decide se a execução vale
  /// uma isolate — ver [ValuationRunner.isolateThresholdSamples].
  final int samples;

  /// Semente do gerador. Fixa por reprodutibilidade.
  final int seed;

  /// Declara o pedido.
  const ValuationRequest({
    required this.inputs,
    this.monteCarlo = false,
    this.samples = 10000,
    this.seed = 42,
  });
}

/// Executa avaliações, decidindo por medição se vale pagar por uma isolate.
///
/// **A decisão é empírica, não dogmática.** O benchmark da Fase 0 mediu:
/// 10 mil cenários de Monte Carlo custam 2,6 ms — bem abaixo do orçamento de
/// 16,7 ms de um quadro a 60 fps —, enquanto 100 mil custam 17,8 ms e já
/// consomem um quadro inteiro. Abaixo do limiar, a troca de isolate custaria
/// mais (0,18 ms de criação, ~2 ms de cópia do payload) do que o próprio
/// cálculo.
///
/// O gargalo real de CPU do sistema não é este cálculo: é o `jsonDecode` das
/// respostas grandes, tratado na camada de rede.
abstract final class ValuationRunner {
  /// Acima disto o cálculo passa a ameaçar o orçamento de um quadro.
  static const int isolateThresholdSamples = 20000;

  /// Avalia um ativo, em isolate própria só quando o volume justifica.
  ///
  /// - [request]: pedido completo.
  ///
  /// A isolate só entra quando o modo é Monte Carlo **e** os sorteios atingem
  /// [isolateThresholdSamples]. Abaixo disso resolve em linha, num `Future` já
  /// completo.
  ///
  /// **No alvo web `compute` executa em linha**, porque não há isolates no
  /// navegador. Aceitável: lá o gargalo é a rede. A consequência colateral é
  /// que o coletor de auditoria, sendo estático e local à isolate, **não emite
  /// rastro** quando a execução de fato migra — o que só ocorre fora do web e
  /// acima do limiar.
  ///
  /// Propaga a falha de `ValuationCascade.evaluate` sem traduzir.
  static Future<Result<ValuationResult>> run(ValuationRequest request) {
    final needsIsolate =
        request.monteCarlo && request.samples >= isolateThresholdSamples;

    if (!needsIsolate) {
      return Future.value(_evaluate(request));
    }
    return compute(_evaluate, request);
  }

  /// Ponto de entrada da isolate: precisa ser função de topo ou estática.
  static Result<ValuationResult> _evaluate(ValuationRequest request) =>
      ValuationCascade.evaluate(
        request.inputs,
        scenarioBuilder:
            request.monteCarlo ? StochasticScenarios.around : null,
        monteCarloSamples: request.samples,
        seed: request.seed,
      );

  /// Avalia vários ativos em sequência.
  ///
  /// A sequência é deliberada: com 15 ativos no teto e ~2,6 ms por avaliação,
  /// o total fica em dezenas de milissegundos. Paralelizar exigiria um pool de
  /// isolates e cópia de payload para cada uma, trocando simplicidade por um
  /// ganho que não existe nesta escala.
  ///
  /// - [requests]: pedidos, um por ativo.
  /// - [onFailure]: notificado por ativo que falhou, com a falha. Sem ele, as
  ///   falhas são **silenciosamente omitidas** do mapa.
  ///
  /// Retorna apenas os ativos avaliados com sucesso — o mapa pode ser menor
  /// que [requests], e comparar os tamanhos é a forma de detectar omissões
  /// quando [onFailure] não é informado.
  static Future<Map<Ticker, ValuationResult>> runAll(
    List<ValuationRequest> requests, {
    void Function(Ticker ticker, Failure failure)? onFailure,
  }) async {
    final out = <Ticker, ValuationResult>{};
    for (final request in requests) {
      final result = await run(request);
      result.fold(
        (valuation) => out[valuation.ticker] = valuation,
        (failure) => onFailure?.call(request.inputs.ticker, failure),
      );
    }
    return out;
  }
}

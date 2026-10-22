import 'dart:convert';

import 'package:equisim_core/equisim_core.dart';

/// Prior transversal do beta empacotado com o aplicativo (item B11).
///
/// **Por que vem empacotado.** Resolvê-lo é varrer o universo inteiro — cinco
/// anos de cotação, o histórico de fundamentos e o perfil de cada papel — para
/// avaliar **um** ativo. Sem ele não há beta desalavancado, e o motor cai no
/// beta cru e no WACC estático, que são o recuo das decisões 40 e 41: o
/// caminho de taxas resolvido, a rota derivada com taxas coerentes e a recusa
/// de estrutura nunca agiam em produção. Gerado por
/// `tool/beta_prior_empacotar.dart` e versionado, como o pacote da curva.
///
/// **Sem pacote, o repositório é transparente**: devolve `null`, e a avaliação
/// segue com o beta cru — o comportamento anterior, declarado na tela.
class BetaPriorRepository {
  /// Lê o conteúdo do pacote.
  final Future<String> Function() loadPackage;

  /// Data de referência, para medir a defasagem do pacote.
  final DateTime Function() today;

  /// Declara o repositório.
  BetaPriorRepository({required this.loadPackage, DateTime Function()? today})
      : today = today ?? DateTime.now;

  /// Defasagem máxima aceita do pacote, em dias.
  ///
  /// **Um ano, e a folga é medida.** O prior é mediana transversal de betas
  /// desalavancados sobre janela de cinco anos: um dia entra e outro sai, e a
  /// mediana quase não anda — medido em `beta_prior.md`. O limite existe para
  /// que um pacote esquecido por anos não continue passando por atual, e não
  /// porque a grandeza expire depressa. Compare-se com os sete dias da curva
  /// (decisão 86), que é taxa de um dia.
  static const int validityDays = 365;

  Future<BetaPriorPackage?>? _package;

  Future<BetaPriorPackage?> _read() async {
    try {
      final json = jsonDecode(await loadPackage());
      return json is Map<String, dynamic> ? BetaPriorCodec.decode(json) : null;
    } on Object {
      return null;
    }
  }

  /// O prior e a ressalva, quando há o que ressalvar.
  ///
  /// A ressalva não é aviso de erro: ela diz **qual motor rodou**. Sem prior, o
  /// beta é o cru e as taxas não são resolvidas, e quem lê o preço justo tem de
  /// saber disso.
  Future<({BetaPrior? prior, String? note})> reading() async {
    final p = await (_package ??= _read());
    if (p == null) {
      return (
        prior: null,
        note: 'O prior transversal do beta não veio no pacote do build: o beta '
            'é o da regressão crua, sem encolhimento, e o custo de capital não '
            'é resolvido contra a alavancagem da própria projeção.',
      );
    }
    // **Dia civil, e não instante.** `difference().inDays` soma horas
    // absolutas, e no salto do horário de verão o resultado cai uma hora antes
    // ou depois — o bastante para a validade valer 364 ou 366 dias conforme a
    // época. É a mesma correção que `_coversStart` já traz.
    final now = today();
    final days = DateTime.utc(now.year, now.month, now.day)
        .difference(DateTime.utc(
            p.generatedAt.year, p.generatedAt.month, p.generatedAt.day))
        .inDays;
    if (days > validityDays) {
      return (
        prior: null,
        note: 'O prior transversal do beta é de '
            '${p.generatedAt.toIso8601String().substring(0, 10)}, mais de '
            '$validityDays dias atrás: não foi usado, e o beta é o da '
            'regressão crua.',
      );
    }
    return (prior: p.prior, note: null);
  }
}

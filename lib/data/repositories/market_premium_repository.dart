import 'dart:convert';

import 'package:equisim_core/equisim_core.dart';

/// O prêmio de risco de mercado do CAPM, da série do prêmio implícito
/// empacotada com o aplicativo (decisão 142).
///
/// **Por que vem empacotado.** O prêmio implícito iguala o valor de mercado
/// somado das companhias listadas ao dinheiro que elas distribuem — somar a
/// bolsa inteira, os proventos de doze meses de cada companhia e a contagem de
/// ações de cada data para avaliar **um** ativo não cabe no aplicativo. A série
/// trimestral é medida por `tool/premio_implicito.dart` e versionada; a média de
/// dez anos, que é o prêmio, sai dela aqui, pelo núcleo.
///
/// **Sem pacote, o prêmio é o parametrizado de 5,5%** — o anterior à decisão
/// 142 —, e a ressalva diz isso. Diferente do prior do beta, o pacote velho
/// continua valendo: a média de dez anos anda devagar (um trimestre a mais move
/// um quadragésimo dela), e trocá-la pelos 5,5% seria um salto muito maior que
/// a defasagem. A ressalva só diz de quando ela é.
class MarketPremiumRepository {
  /// Lê o conteúdo do pacote.
  final Future<String> Function() carregarPacote;

  /// Data de referência, para medir a defasagem do pacote.
  final DateTime Function() hoje;

  /// Declara o repositório.
  MarketPremiumRepository({
    required this.carregarPacote,
    DateTime Function()? hoje,
  }) : hoje = hoje ?? DateTime.now;

  /// Defasagem a partir da qual a ressalva aparece, em dias.
  ///
  /// **Seis meses**: o pacote ganha um trimestre a cada três meses, e com dois
  /// trimestres sem regravação a média já deixou de ser a da série publicada.
  static const int diasSemRessalva = 183;

  Future<ImpliedPremiumPackage?>? _pacote;

  Future<ImpliedPremiumPackage?> _ler() async {
    try {
      final json = jsonDecode(await carregarPacote());
      return json is Map<String, dynamic>
          ? ImpliedPremiumCodec.decode(json)
          : null;
    } on Object {
      return null;
    }
  }

  /// O prêmio, de onde ele veio e a ressalva, quando há o que ressalvar.
  Future<({double premium, MarketPremiumSource source, String? note})>
      reading() async {
    const semPacote = (
      premium: CapmInputs.defaultMarketPremium,
      source: MarketPremiumSource.parameterized,
      note: 'A série do prêmio implícito não veio no pacote do build: o '
          'prêmio de mercado é o parametrizado de 5,5%, e não a média de dez '
          'anos do prêmio implícito no preço da bolsa (decisão 142).',
    );
    final p = await (_pacote ??= _ler());
    if (p == null) return semPacote;
    // **Dia civil, e não instante**, pelo mesmo motivo do prior do beta: no
    // salto do horário de verão `difference().inDays` erra um dia, e a data do
    // pacote é um dia em UTC.
    final agora = hoje();
    final dia = DateTime.utc(agora.year, agora.month, agora.day);
    // A média é a da data do pacote. Calculada até hoje, com o pacote
    // defasado, a janela perderia os trimestres antigos sem ganhar os novos.
    final media = p.normalizedAt(dia.isBefore(p.geradoEm) ? dia : p.geradoEm);
    if (media == null) return semPacote;
    final dias = dia.difference(p.geradoEm).inDays;
    if (dias > diasSemRessalva) {
      return (
        premium: media,
        source: MarketPremiumSource.impliedNormalized,
        note: 'O prêmio de mercado é a média de dez anos do prêmio implícito '
            'medida em ${p.geradoEm.toIso8601String().substring(0, 10)}, mais '
            'de $diasSemRessalva dias atrás: os trimestres seguintes ainda não '
            'entraram nela.',
      );
    }
    return (
      premium: media,
      source: MarketPremiumSource.impliedNormalized,
      note: null,
    );
  }
}

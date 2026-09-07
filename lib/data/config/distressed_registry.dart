import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Registro externo de ativos sem continuidade operacional.
///
/// **Existe por necessidade, não por escolha.** A Porta 0 recusa empresa em
/// recuperação judicial ou extrajudicial, porque o fluxo descontado e o valor da
/// capacidade de gerar lucro pressupõem continuidade. Mas a fonte de dados não
/// publica essa situação: o campo `isActive` marca **negociabilidade**, não
/// continuidade, e os 786 tickers do universo vêm todos com ele verdadeiro.
///
/// É a única exclusão da Porta 0 que não se automatiza com o que a fonte
/// oferece, e a decisão 25 a registra como dependência assumida.
///
/// O arquivo é `config/distressed_tickers.json`, declarado como asset.
class DistressedRegistry {
  /// Tickers em recuperação, em maiúsculas e sem sufixo fracionário.
  final Set<String> tickers;

  const DistressedRegistry(this.tickers);

  /// Registro vazio — nenhum ativo excluído.
  ///
  /// É o estado degradado quando o arquivo não carrega. **Degradar para vazio é
  /// deliberado**: um registro que falha em carregar não pode barrar o universo
  /// inteiro, e um falso negativo aqui produz uma avaliação a mais, não uma
  /// avaliação errada em silêncio — o ativo em recuperação apareceria com os
  /// avisos que a própria cascata emite.
  static const DistressedRegistry empty = DistressedRegistry({});

  /// Caminho do arquivo no bundle.
  static const String assetPath = 'config/distressed_tickers.json';

  /// Carrega o registro do bundle, tolerando ausência e JSON malformado.
  static Future<DistressedRegistry> load() async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      return parse(raw);
    } catch (_) {
      return empty;
    }
  }

  /// Interpreta o conteúdo do arquivo.
  ///
  /// Separado de [load] para ser testável sem bundle.
  static DistressedRegistry parse(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return empty;
      final lista = json['emRecuperacao'];
      if (lista is! List) return empty;
      return DistressedRegistry({
        for (final item in lista)
          if (item is String && item.trim().isNotEmpty)
            item.trim().toUpperCase()
          else if (item is Map && item['ticker'] is String)
            (item['ticker'] as String).trim().toUpperCase(),
      });
    } catch (_) {
      return empty;
    }
  }

  /// `true` quando o ativo está em recuperação.
  bool contains(String ticker) => tickers.contains(ticker.toUpperCase());
}

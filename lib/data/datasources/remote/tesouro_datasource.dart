import 'package:equisim_core/equisim_core.dart';

import '../../network/api_client.dart';

/// Cotações do dia dos títulos prefixados do Tesouro Direto (item A2.1).
///
/// Lê o arquivo **direto**, e só o começo: ele vem em ordem decrescente de
/// data-base, e as linhas do dia mais recente estão nos primeiros quilobytes de
/// um arquivo de 14,5 MB. A leitura para na primeira linha de outra data.
///
/// **Só no nativo.** O arquivo libera CORS apenas para o domínio do próprio
/// Tesouro, e o navegador não pode lê-lo: na web o aplicativo nem chama esta
/// fonte, e a curva vem do pacote do build (decisão 86).
class TreasuryDatasource {
  /// Cliente HTTP compartilhado.
  final ApiClient client;

  /// Catálogo CKAN do conjunto de taxas do Tesouro.
  ///
  /// O endereço do arquivo vem dele a cada leitura: o identificador do recurso
  /// muda quando o Tesouro republica o conjunto.
  static const String catalog =
      'https://www.tesourotransparente.gov.br/ckan/api/3/action/package_show'
      '?id=taxas-dos-titulos-ofertados-pelo-tesouro-direto';

  /// Declara a fonte.
  TreasuryDatasource(this.client);

  /// Cotações da data-base mais recente publicada.
  Future<Result<List<TreasuryQuote>>> latest() async {
    final package = await client.getJson(catalog);
    if (package.isErr) return Err(package.failureOrNull!);
    final csv = _csvUrl(package.unwrap());
    if (csv == null) {
      return const Err(
          InsufficientData('O catálogo do Tesouro não lista o arquivo CSV.'));
    }

    DateTime? first;
    var header = true;
    final rows = await client.readLinesUntil(csv, stop: (row) {
      if (header) {
        header = false;
        return false;
      }
      final base = TreasuryCsv.baseDateOf(row);
      if (base == null) return false;
      first ??= base;
      return base != first;
    });
    return rows.flatMap((l) {
      final quotes = TreasuryCsv.parse(l);
      return quotes.isEmpty
          ? const Err(InsufficientData('O arquivo do Tesouro não trouxe '
              'título prefixado na data mais recente.'))
          : Ok(quotes);
    });
  }

  static String? _csvUrl(Object? package) {
    if (package is! Map<String, dynamic>) return null;
    final result = package['result'];
    if (result is! Map<String, dynamic>) return null;
    final resources = result['resources'];
    if (resources is! List) return null;
    for (final r in resources) {
      if (r is! Map<String, dynamic>) continue;
      final format = '${r['format'] ?? ''}'.toUpperCase();
      final url = r['url'];
      if (format == 'CSV' && url is String && url.isNotEmpty) return url;
    }
    return null;
  }
}

import 'package:equisim_core/equisim_core.dart';

import '../../network/api_client.dart';

/// Cotações do dia dos títulos prefixados do Tesouro Direto (item A2.1).
///
/// **Dois caminhos, porque o navegador não pode ler o arquivo do Tesouro**: o
/// CORS dele só libera o domínio do próprio Tesouro.
///
/// - Com [ApiClient.config] trazendo `tesouroProxyUrl`, pergunta à função
///   `tesouro`, que lê o arquivo no servidor e devolve o dia em JSON.
/// - Sem ela, lê o arquivo **direto**, e só o começo: ele vem em ordem
///   decrescente de data-base, e as linhas do dia mais recente estão nos
///   primeiros quilobytes de um arquivo de 14,5 MB. A leitura para na
///   primeira linha de outra data.
///
/// No alvo web sem a função, o caminho direto falha — e o repositório recua
/// para a curva empacotada.
class TesouroDatasource {
  /// Cliente HTTP compartilhado.
  final ApiClient client;

  /// Catálogo CKAN do conjunto de taxas do Tesouro.
  ///
  /// O endereço do arquivo vem dele a cada leitura: o identificador do recurso
  /// muda quando o Tesouro republica o conjunto.
  static const String catalogo =
      'https://www.tesourotransparente.gov.br/ckan/api/3/action/package_show'
      '?id=taxas-dos-titulos-ofertados-pelo-tesouro-direto';

  /// Declara a fonte.
  TesouroDatasource(this.client);

  /// Cotações da data-base mais recente publicada.
  Future<Result<List<TreasuryQuote>>> latest() async {
    final proxy = client.config.tesouroProxyUrl;
    if (proxy != null) return _pelaFuncao(proxy);
    return _direto();
  }

  Future<Result<List<TreasuryQuote>>> _pelaFuncao(String url) async {
    final r = await client.getJson(url);
    return r.flatMap((body) {
      if (body is! Map<String, dynamic>) {
        return const Err(
            ComputationFailure('Resposta inesperada da função tesouro.'));
      }
      final cotacoes = TreasuryQuotesCodec.decode(body);
      return cotacoes.isEmpty
          ? const Err(InsufficientData('A função tesouro não trouxe cotação.'))
          : Ok(cotacoes);
    });
  }

  Future<Result<List<TreasuryQuote>>> _direto() async {
    final pacote = await client.getJson(catalogo);
    if (pacote.isErr) return Err(pacote.failureOrNull!);
    final csv = _enderecoDoCsv(pacote.unwrap());
    if (csv == null) {
      return const Err(
          InsufficientData('O catálogo do Tesouro não lista o arquivo CSV.'));
    }

    DateTime? primeira;
    var cabecalho = true;
    final linhas = await client.readLinesUntil(csv, stop: (linha) {
      if (cabecalho) {
        cabecalho = false;
        return false;
      }
      final base = TreasuryCsv.baseDateOf(linha);
      if (base == null) return false;
      primeira ??= base;
      return base != primeira;
    });
    return linhas.flatMap((l) {
      final cotacoes = TreasuryCsv.parse(l);
      return cotacoes.isEmpty
          ? const Err(InsufficientData('O arquivo do Tesouro não trouxe '
              'título prefixado na data mais recente.'))
          : Ok(cotacoes);
    });
  }

  static String? _enderecoDoCsv(Object? pacote) {
    if (pacote is! Map<String, dynamic>) return null;
    final result = pacote['result'];
    if (result is! Map<String, dynamic>) return null;
    final recursos = result['resources'];
    if (recursos is! List) return null;
    for (final r in recursos) {
      if (r is! Map<String, dynamic>) continue;
      final formato = '${r['format'] ?? ''}'.toUpperCase();
      final url = r['url'];
      if (formato == 'CSV' && url is String && url.isNotEmpty) return url;
    }
    return null;
  }
}

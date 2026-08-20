/// Validade de cada tipo de dado.
///
/// A regra que mais importa é a primeira: **cotação de pregão encerrado é fato
/// passado e não muda**. Guardá-la permanentemente derruba a segunda execução
/// de uma simulação de ~3,5 s para praticamente zero e — o que vale mais para
/// o trabalho — torna os resultados reprodutíveis, já que a mesma simulação
/// deixa de depender do que a API devolve naquele instante.
abstract final class CachePolicy {
  /// Cotações de pregões já encerrados: imutáveis.
  static const Duration historicalPrices = Duration(days: 365 * 10);

  /// Fundamentos anuais: atualizam uma vez por ano, com folga.
  static const Duration fundamentals = Duration(days: 30);

  /// Perfil e setor: praticamente estáticos.
  static const Duration profile = Duration(days: 90);

  /// Proventos: novos eventos são anunciados ao longo do mês.
  static const Duration dividends = Duration(days: 1);

  /// CDI e IPCA: publicação diária.
  static const Duration macro = Duration(days: 1);

  /// Universo de tickers: entram e saem poucas empresas por ano.
  static const Duration universe = Duration(days: 7);

  static String pricesKey(String ticker) => 'prices:$ticker';
  static String dividendsKey(String ticker) => 'dividends:$ticker';
  static String fundamentalsKey(String ticker) => 'fundamentals:$ticker';
  static String profileKey(String ticker) => 'profile:$ticker';
  static String macroKey(int seriesId) => 'macro:$seriesId';
  static const String universeKey = 'universe';
}

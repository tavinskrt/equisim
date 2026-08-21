/// Validade de cada tipo de dado.
///
/// Cotação de pregão encerrado é fato passado e não muda: as linhas já
/// guardadas nunca são descartadas, e é isso que derruba a segunda execução de
/// uma simulação de ~3,5 s para praticamente zero.
///
/// O que envelhece não é a linha, é a **ponta da série** — a cada pregão
/// existe um dia a mais para buscar. A validade abaixo governa só isso: quando
/// expira, a série é rebuscada e as linhas novas são somadas às antigas.
abstract final class CachePolicy {
  /// Ponta da série de cotações.
  ///
  /// Meio dia: recarrega no máximo uma vez por turno de trabalho e ainda assim
  /// alcança o pregão do dia. Um prazo longo aqui congelava a simulação na
  /// data em que o cache foi preenchido — os aportes paravam ali, meses antes
  /// de hoje, sem nenhum aviso.
  static const Duration historicalPrices = Duration(hours: 12);

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

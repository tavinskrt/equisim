class StockPrice {
  final String date;
  final double close;

  StockPrice({required this.date, required this.close});
  // O factory pode: criar o objeto, retornar outro objeto, aplicar lógica antes.
  // O fromJson é um padrão comum para criar objetos a partir de dados JSON.
  // Ele recebe um Map<String, dynamic> (o formato típico de um JSON decodificado)
  // e retorna uma instância de StockPrice.
  factory StockPrice.fromJson(Map<String, dynamic> json) {
    return StockPrice(
      date: json['trade_date'] ?? '',
      close: (json['close'] as num).toDouble(),
    );
  }
}


class StockFundamentals {
  final double lpa;
  final double vpa;
  final double pl;

  StockFundamentals({required this.lpa, required this.vpa, required this.pl});
  factory StockFundamentals.fromJson(Map<String, dynamic> json) {
    return StockFundamentals(
      lpa: (json['lpa'] as num).toDouble(),
      vpa: (json['vpa'] as num).toDouble(),
      pl: (json['pl'] as num).toDouble(),
    );
  }
}
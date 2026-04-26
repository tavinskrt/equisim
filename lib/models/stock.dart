class Stock {
  final String date;
  final double close;

  Stock({required this.date, required this.close});
  // O factory pode: criar o objeto, retornar outro objeto, aplicar lógica antes.
  // O fromJson é um padrão comum para criar objetos a partir de dados JSON.
  // Ele recebe um Map<String, dynamic> (o formato típico de um JSON decodificado) e retorna uma instância de Stock.
  factory Stock.fromJson(Map<String, dynamic> json) {
    return Stock(
      date: json['trade_date'] ?? '',
      close: (json['close'] as num).toDouble(),
    );
  }
}
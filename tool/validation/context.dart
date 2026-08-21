import 'dart:io';

import 'package:drift/native.dart';
import 'package:equisim/data/config/api_config.dart';
import 'package:equisim/data/datasources/local/cache_database.dart';
import 'package:equisim/data/datasources/remote/bcb_datasource.dart';
import 'package:equisim/data/datasources/remote/brapi_datasource.dart';
import 'package:equisim/data/network/api_client.dart';
import 'package:equisim/data/repositories/market_repositories.dart';
import 'package:equisim_core/equisim_core.dart';

/// Dependências do executor de validação.
///
/// Monta **exatamente** a mesma camada de dados que o aplicativo usa — os
/// mesmos datasources, os mesmos mapeadores, os mesmos repositórios. É o que
/// sustenta a afirmação de que os números da monografia vêm do código
/// entregue, e não de uma reimplementação paralela que poderia divergir.
///
/// A única diferença é a infraestrutura que o hospedeiro fornece: aqui o cache
/// é SQLite em arquivo e o JSON é decodificado em linha, porque não há
/// interface a proteger.
class ValidationContext {
  final ApiClient client;
  final BrapiDatasource brapi;
  final BcbDatasource bcb;
  final CacheDatabase cache;
  final PriceRepository prices;
  final DividendRepository dividends;
  final FundamentalsRepository fundamentals;
  final BenchmarkRepository benchmark;
  final MacroRepository macro;

  ValidationContext._({
    required this.client,
    required this.brapi,
    required this.bcb,
    required this.cache,
    required this.prices,
    required this.dividends,
    required this.fundamentals,
    required this.benchmark,
    required this.macro,
  });

  static const String cacheFileName = 'validation_cache.sqlite';

  /// Monta o contexto, resolvendo a credencial na mesma ordem do aplicativo.
  ///
  /// O cache em arquivo é deliberado: entre execuções, os dados já baixados
  /// são reaproveitados. Isso poupa a API e — o que importa mais para o
  /// trabalho — torna os relatórios **reprodutíveis**, já que deixam de
  /// depender do que a fonte devolve naquele instante.
  static ValidationContext create({
    required String outputDir,
    bool verbose = false,
  }) {
    final config = ApiConfig.resolve(
      fallbackToken: _readEnvFile('BRAPI_TOKEN') ??
          Platform.environment['BRAPI_TOKEN'],
      fallbackBaseUrl: _readEnvFile('BRAPI_BASE_URL'),
    );

    if (!config.hasCredential) {
      stderr.writeln(
        'Sem credencial da brapi. Preencha BRAPI_TOKEN no .env da raiz do '
        'projeto ou exporte a variável de ambiente.',
      );
      exit(2);
    }

    Directory(outputDir).createSync(recursive: true);
    final cache = CacheDatabase(
      NativeDatabase(File('$outputDir/$cacheFileName')),
    );

    final client = ApiClient(
      config,
      logRequests: verbose,
      logSink: stdout.writeln,
    );
    final brapi = BrapiDatasource(client);
    final bcb = BcbDatasource(client);

    return ValidationContext._(
      client: client,
      brapi: brapi,
      bcb: bcb,
      cache: cache,
      prices: PriceRepositoryImpl(remote: brapi, cache: cache),
      dividends: DividendRepositoryImpl(remote: brapi, cache: cache),
      fundamentals: FundamentalsRepositoryImpl(remote: brapi, cache: cache),
      benchmark: BenchmarkRepositoryImpl(brapi),
      macro: MacroRepositoryImpl(remote: bcb, cache: cache),
    );
  }

  Future<void> dispose() async {
    client.close();
    await cache.close();
  }

  /// Lê uma chave do `.env` da raiz sem depender de pacote de Flutter.
  static String? _readEnvFile(String key) {
    final file = File('.env');
    if (!file.existsSync()) return null;
    for (final line in file.readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final separator = trimmed.indexOf('=');
      if (separator <= 0) continue;
      if (trimmed.substring(0, separator).trim() == key) {
        final value = trimmed.substring(separator + 1).trim();
        return value.isEmpty ? null : value;
      }
    }
    return null;
  }
}

/// Amostra padrão para as varreduras.
///
/// Cobre perfis distintos de propósito: forte pagadora de JCP (ITUB4, BBAS3),
/// commodity cíclica (PETR4, VALE3), crescimento com pouco provento (WEGE3),
/// utilidade pública com dividendo alto (TAEE11, EGIE3) e varejo em
/// dificuldade (MGLU3) — para que os relatórios não descrevam só o caso fácil.
const List<String> defaultSample = [
  'PETR4', 'VALE3', 'ITUB4', 'BBAS3', 'BBDC4', 'WEGE3', 'ABEV3',
  'TAEE11', 'EGIE3', 'CMIG4', 'ITSA4', 'B3SA3', 'RENT3', 'MGLU3',
  'SUZB3', 'KLBN11', 'RADL3', 'PRIO3', 'CSAN3', 'VIVT3',
];

/// Escreve um arquivo de saída e informa o caminho.
void writeReport(String path, String content) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
  stdout.writeln('  → $path (${(file.lengthSync() / 1024).toStringAsFixed(1)} KB)');
}

/// Formata fração como percentual com vírgula decimal.
String pct(double fraction, {int decimals = 2}) =>
    '${(fraction * 100).toStringAsFixed(decimals).replaceAll('.', ',')}%';

/// Formata número com vírgula decimal, para colar em planilha brasileira.
String num2(double value, {int decimals = 4}) =>
    value.toStringAsFixed(decimals).replaceAll('.', ',');

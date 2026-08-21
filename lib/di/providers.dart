import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/config/api_config.dart';
import '../data/datasources/local/cache_database.dart';
import '../data/datasources/remote/bcb_datasource.dart';
import '../data/datasources/remote/brapi_datasource.dart';
import '../data/network/api_client.dart';
import '../data/repositories/market_repositories.dart';
import '../data/repositories/portfolio_repository.dart';

/// Raiz de composição.
///
/// Providers escritos à mão, sem geração de código: são poucos, e explícitos
/// eles se leem melhor por quem for avaliar o trabalho do que atrás de
/// anotações e arquivos gerados.
///
/// Todo provider de infraestrutura é sobrescrevível, o que permite montar um
/// `ProviderContainer` sem Flutter — requisito do executor de validação da
/// Fase 5, que precisa reusar exatamente este grafo de dependências.

// ----------------------------------------------------------- Infraestrutura --

final apiConfigProvider = Provider<ApiConfig>((ref) {
  final config = ApiConfig.resolve(
    fallbackToken: _dotenv('BRAPI_TOKEN'),
    fallbackBaseUrl: _dotenv('BRAPI_BASE_URL'),
  );
  if (config.credentialIsExposed) {
    debugPrint(
      '⚠️  Credencial da brapi lida de .env (asset embarcado no bundle). '
      'Para distribuição use --dart-define-from-file ou o proxy de custódia.',
    );
  }
  return config;
});

String? _dotenv(String key) {
  try {
    return dotenv.env[key];
  } catch (_) {
    return null; // dotenv não inicializado (testes ou asset ausente)
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(
    ref.watch(apiConfigProvider),
    // Payloads grandes vão para outra isolate: um histórico de dez anos para
    // dez ativos traz ~25 mil pontos, e decodificar isso na thread de
    // interface derruba quadros. É o único gargalo real de CPU do sistema.
    heavyDecoder: (body) => compute(jsonDecode, body),
    logRequests: kDebugMode,
    logSink: debugPrint,
  );
  ref.onDispose(client.close);
  return client;
});

/// Cache local. **Pode ser `null`** — é otimização, não requisito.
///
/// No alvo web o Drift exige `sqlite3.wasm` e `drift_worker.js` servidos junto
/// da aplicação; sem eles, `driftDatabase()` lança na própria construção. Sem
/// o `try`, essa exceção derrubaria o provider, e com ele todos os
/// repositórios que dele dependem — o sintoma era a tela de ativos acusar
/// "universo indisponível" mesmo com a rede funcionando.
///
/// Degradar aqui mantém a aplicação utilizável em qualquer plataforma: sem
/// cache ela apenas volta à rede com mais frequência.
final cacheDatabaseProvider = Provider<CacheDatabase?>((ref) {
  try {
    final db = CacheDatabase(driftDatabase(
      name: 'equisim_cache',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    ));
    ref.onDispose(db.close);
    return db;
  } catch (error) {
    debugPrint(
      '⚠️  Cache local indisponível ($error). A aplicação continua '
      'funcionando; os dados serão buscados da rede a cada consulta.',
    );
    return null;
  }
});

/// `true` quando o cache está ativo — para a interface poder informar.
final cacheAvailableProvider =
    Provider<bool>((ref) => ref.watch(cacheDatabaseProvider) != null);

final firestoreProvider =
    Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);

final firebaseAuthProvider =
    Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);

/// Usuário autenticado, reativo — as telas reagem a login e logout sem
/// precisar consultar o `FirebaseAuth` diretamente.
final authStateProvider = StreamProvider<User?>(
  (ref) => ref.watch(firebaseAuthProvider).authStateChanges(),
);

final currentUserIdProvider = Provider<String?>(
  (ref) => ref.watch(authStateProvider).valueOrNull?.uid,
);

// -------------------------------------------------------------- Datasources --

final brapiDatasourceProvider = Provider<BrapiDatasource>(
  (ref) => BrapiDatasource(ref.watch(apiClientProvider)),
);

final bcbDatasourceProvider = Provider<BcbDatasource>(
  (ref) => BcbDatasource(ref.watch(apiClientProvider)),
);

// ------------------------------------------------------------ Repositórios --

final priceRepositoryProvider = Provider<PriceRepository>(
  (ref) => PriceRepositoryImpl(
    remote: ref.watch(brapiDatasourceProvider),
    cache: ref.watch(cacheDatabaseProvider),
  ),
);

final dividendRepositoryProvider = Provider<DividendRepository>(
  (ref) => DividendRepositoryImpl(
    remote: ref.watch(brapiDatasourceProvider),
    cache: ref.watch(cacheDatabaseProvider),
  ),
);

final fundamentalsRepositoryProvider = Provider<FundamentalsRepository>(
  (ref) => FundamentalsRepositoryImpl(
    remote: ref.watch(brapiDatasourceProvider),
    cache: ref.watch(cacheDatabaseProvider),
  ),
);

final benchmarkRepositoryProvider = Provider<BenchmarkRepository>(
  (ref) => BenchmarkRepositoryImpl(ref.watch(brapiDatasourceProvider)),
);

final macroRepositoryProvider = Provider<MacroRepository>(
  (ref) => MacroRepositoryImpl(
    remote: ref.watch(bcbDatasourceProvider),
    cache: ref.watch(cacheDatabaseProvider),
  ),
);

final portfolioRepositoryProvider = Provider<PortfolioRepository>(
  (ref) => PortfolioRepository(ref.watch(firestoreProvider)),
);

// ------------------------------------------------------- Dados de mercado --

/// Âncoras de CDI e Ibovespa, calculadas a partir das séries observadas.
///
/// Alimentam os limiares de viabilidade da meta. Recalcular a cada sessão faz
/// os limites acompanharem o mercado, em vez de envelhecerem no código.
final marketAnchorsProvider = FutureProvider<MarketAnchors>((ref) async {
  final result = await ResolveMarketAnchors.call(
    macro: ref.watch(macroRepositoryProvider),
    benchmark: ref.watch(benchmarkRepositoryProvider),
  );
  // Sem rede, os valores medidos em 19/08/2026 mantêm a tela utilizável.
  return result.getOrElse(MarketAnchors.fallback2026);
});

/// Taxa livre de risco anual corrente, para o CAPM e o índice de Sharpe.
final riskFreeRateProvider = FutureProvider<double>((ref) async {
  final anchors = await ref.watch(marketAnchorsProvider.future);
  return anchors.riskFreeCagr;
});

/// Universo de ações da B3, para o seletor de ativos.
final universeProvider = FutureProvider<List<Ticker>>((ref) async {
  final result = await ref.watch(fundamentalsRepositoryProvider).universe();
  return result.getOrElse(const []);
});

/// Perfil cadastral de um ativo.
final assetProfileProvider =
    FutureProvider.family<Asset?, Ticker>((ref, ticker) async {
  final result = await ref.watch(fundamentalsRepositoryProvider).profile(ticker);
  return result.valueOrNull;
});

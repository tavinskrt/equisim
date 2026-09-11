import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audit/audit_network_interceptor.dart';
import '../data/config/api_config.dart';
import '../data/config/distressed_registry.dart';
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
  // O interceptador de auditoria fica sempre montado: ele próprio verifica se
  // há alguém ouvindo e, quando não há, não chega a construir o evento. Montar
  // condicionalmente exigiria recriar o cliente ao ligar o painel.
  client.raw.interceptors.add(AuditNetworkInterceptor());
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

final firestoreProvider =
    Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);

final firebaseAuthProvider =
    Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);

/// Usuário autenticado, reativo — as telas reagem a login e logout sem
/// precisar consultar o `FirebaseAuth` diretamente.
final authStateProvider = StreamProvider<User?>(
  (ref) => ref.watch(firebaseAuthProvider).authStateChanges(),
);

/// Identificador do usuário autenticado.
///
/// A leitura combina duas fontes de propósito. `authStateChanges()` é um
/// `Stream` que só emite no microtask seguinte à assinatura: quem cria este
/// provider e o lê no mesmo instante — o botão de salvar era exatamente esse
/// caso — encontrava `AsyncLoading`, cujo `valueOrNull` é `null`, e concluía
/// que não havia ninguém logado. `FirebaseAuth.currentUser` é **síncrono** e já
/// reflete a sessão restaurada, então responde corretamente nesse intervalo.
///
/// Assim que o fluxo emite, ele passa a mandar: é ele quem carrega o logout.
final currentUserIdProvider = Provider<String?>((ref) {
  final streamed = ref.watch(authStateProvider);
  if (streamed.hasValue) return streamed.value?.uid;
  return ref.watch(firebaseAuthProvider).currentUser?.uid;
});

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

/// Taxa livre de risco anual **da janela informada**.
///
/// **O Sharpe compara o retorno de uma janela com a renda fixa dela**
/// (decisão 58). [riskFreeRateProvider] devolve o CAGR decenal do CDI, e a
/// simulação pode correr três anos: confrontar as duas mede a diferença entre
/// os períodos, não o prêmio pelo risco. A Selic saiu de 2% para 14% no
/// intervalo que o cache cobre, e o descasamento vale mais que o próprio
/// índice.
///
/// **A janela chega por parâmetro**, e não é montada aqui a partir do relógio:
/// quem simula já a tem, e derivá-la de novo tornaria o provedor não
/// determinístico. `DateRange` compara por valor, de modo que a família
/// reaproveita o resultado entre observadores da mesma janela.
///
/// Recua para o decenal quando a série da janela não vem — sem rede, cache
/// vazio, janela sem pregão.
final riskFreeRateForWindowProvider =
    FutureProvider.family<double, DateRange>((ref, janela) async {
  final serie = await ref.watch(macroRepositoryProvider).riskFreeDaily(janela);
  if (serie.isOk && !serie.unwrap().isEmpty) return serie.unwrap().annualized();
  return ref.watch(riskFreeRateProvider.future);
});

/// Registro de ativos em recuperação judicial, lido do bundle.
///
/// A Porta 0 os recusa. Vem de arquivo porque a fonte de dados não publica a
/// informação — ver `DistressedRegistry` e a decisão 25.
final distressedRegistryProvider = FutureProvider<DistressedRegistry>(
  (ref) => DistressedRegistry.load(),
);

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

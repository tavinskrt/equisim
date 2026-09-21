import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audit/audit_network_interceptor.dart';
import '../data/config/api_config.dart';
import '../data/config/distressed_registry.dart';
import '../data/datasources/local/cache_database.dart';
import '../data/datasources/remote/bcb_datasource.dart';
import '../data/datasources/remote/brapi_datasource.dart';
import '../data/network/api_client.dart';
import '../data/datasources/remote/tesouro_datasource.dart';
import '../data/repositories/b3_registry_repository.dart';
import '../data/repositories/peer_multiples_repository.dart';
import '../data/repositories/beta_prior_repository.dart';
import '../data/repositories/unit_composition_repository.dart';
import '../data/repositories/cash_dividends_repository.dart';
import '../data/repositories/calibrated_band_repository.dart';
import '../data/repositories/skill_reading_repository.dart';
import '../data/repositories/concession_term_repository.dart';
import '../data/repositories/cvm_fundamentals_repository.dart';
import '../data/repositories/market_repositories.dart';
import '../data/repositories/portfolio_repository.dart';
import '../data/repositories/risk_free_curve_repository.dart';

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

/// Caminho do pacote da CVM empacotado com o aplicativo (item A1.9).
///
/// Gerado por `tool/cvm_empacotar.dart` e versionado (decisão 80). Ausente, a
/// avaliação segue só com a fonte de mercado, e a ressalva diz isso — ver
/// [cvmCoverageNoteProvider].
const String cvmPackageAsset = 'assets/cvm/documentos.json';

final fundamentalsRepositoryProvider = Provider<FundamentalsRepository>(
  (ref) => OfficialSectorFundamentalsRepository(
    inner: CvmFundamentalsRepository(
      mercado: FundamentalsRepositoryImpl(
        remote: ref.watch(brapiDatasourceProvider),
        cache: ref.watch(cacheDatabaseProvider),
      ),
      carregarPacote: () => rootBundle.loadString(cvmPackageAsset),
      // A data da avaliação é a do dia, e a camada de aplicativo é o lugar de
      // perguntá-la: o núcleo recebe a data pronta.
      hoje: DateTime.now,
    ),
    // O setor é o da B3, por emissor (item A5, decisão 87).
    classificacao: ref.watch(b3RegistryRepositoryProvider).classificationFor,
  ),
);

/// A ressalva de cobertura da CVM para a avaliação de um ativo, ou `null`.
///
/// Só existe quando o repositório de fundamentos é o da CVM: um teste que o
/// substitui por um falso não ganha ressalva de pacote que ele não usa.
final cvmCoverageNoteProvider =
    FutureProvider.family<String?, Ticker>((ref, ticker) async {
  final externo = ref.watch(fundamentalsRepositoryProvider);
  final repo = externo is OfficialSectorFundamentalsRepository
      ? externo.inner
      : externo;
  return repo is CvmFundamentalsRepository ? repo.coverageNote(ticker) : null;
});

/// Caminho do registro de emissores da B3 empacotado (item A3.3).
const String b3RegistryAsset = 'assets/b3/emissores.json';

/// Caminho do prior transversal do beta empacotado (item B11).
const String betaPriorAsset = 'assets/mercado/beta_prior.json';

/// Pacote das medianas de múltiplos por grupo de pares (item B5, decisão 118).
const String peerMultiplesAsset = 'assets/mercado/multiplos_setoriais.json';

/// Caminho da composição declarada das units, da FCA da CVM (item B16).
const String unitCompositionAsset = 'assets/cvm/units.json';

/// Caminho dos proventos da B3 empacotados (item A4).
const String cashDividendsAsset = 'assets/b3/proventos.json';

final cashDividendsRepositoryProvider = Provider<CashDividendsRepository>(
  (ref) => CashDividendsRepository(
    carregarPacote: () => rootBundle.loadString(cashDividendsAsset),
  ),
);

/// Proventos da classe de um ativo: o beta sai do retorno total (decisão 89).
final cashDividendsProvider = FutureProvider.family<List<CashDividend>, Ticker>(
    (ref, ticker) =>
        ref.watch(cashDividendsRepositoryProvider).dividendsFor(ticker));

/// Caminho do prazo das outorgas empacotado (item A6).
const String concessionTermsAsset = 'assets/cvm/outorgas.json';

final concessionTermRepositoryProvider = Provider<ConcessionTermRepository>(
  (ref) => ConcessionTermRepository(
    carregarPacote: () => rootBundle.loadString(concessionTermsAsset),
  ),
);

/// Fim do contrato de concessão de um ativo, ou `null` (decisão 88).
final concessionEndProvider = FutureProvider.family<DateTime?, Ticker>(
    (ref, ticker) =>
        ref.watch(concessionTermRepositoryProvider).endFor(ticker));

/// Caminho da faixa calibrada empacotada (item C2).
const String calibratedBandAsset = 'assets/validacao/banda_calibrada.json';

final calibratedBandRepositoryProvider = Provider<CalibratedBandRepository>(
  (ref) => CalibratedBandRepository(
    carregarPacote: () => rootBundle.loadString(calibratedBandAsset),
  ),
);

/// Faixas do valor realizado em torno do preço justo, medidas nas coortes
/// (decisão 92). Vazio sem pacote.
final calibratedBandsProvider = FutureProvider<List<CalibratedBandTable>>(
    (ref) => ref.watch(calibratedBandRepositoryProvider).tables());

/// Caminho da leitura da habilidade empacotada (item B1.0).
const String skillReadingAsset = 'assets/validacao/habilidade.json';

final skillReadingRepositoryProvider = Provider<SkillReadingRepository>(
  (ref) => SkillReadingRepository(
    carregarPacote: () => rootBundle.loadString(skillReadingAsset),
  ),
);

/// A habilidade do potencial medida nas coortes (decisão 96), ou `null` sem
/// pacote.
final skillReadingProvider = FutureProvider<SkillReading?>(
    (ref) => ref.watch(skillReadingRepositoryProvider).reading());

/// Caminho das cotações recentes do Tesouro empacotadas (item A2.1).
const String tesouroQuotesAsset = 'assets/tesouro/curva.json';

final b3RegistryRepositoryProvider = Provider<B3RegistryRepository>(
  (ref) => B3RegistryRepository(
    carregarPacote: () => rootBundle.loadString(b3RegistryAsset),
  ),
);

final betaPriorRepositoryProvider = Provider<BetaPriorRepository>(
  (ref) => BetaPriorRepository(
    carregarPacote: () => rootBundle.loadString(betaPriorAsset),
  ),
);

/// O prior do beta do pacote, e a ressalva quando ele não pôde ser usado
/// (item B11).
///
/// Sem prior não há beta desalavancado, e a cascata recua para o beta cru e o
/// WACC estático — as decisões 40 e 41 declaram esse recuo, e a ressalva diz ao
/// usuário qual dos dois motores produziu o número.
final betaPriorReadingProvider =
    FutureProvider<({BetaPrior? prior, String? note})>((ref) async {
  try {
    return await ref.watch(betaPriorRepositoryProvider).reading();
  } on Object {
    return (prior: null, note: null);
  }
});

/// As medianas de múltiplos dos pares, do pacote do build (item B5).
///
/// A mediana é do **universo**, e a cascata avalia um ativo por vez: calculá-la
/// em tempo de execução seria varrer a bolsa inteira para abrir uma tela. Sem
/// pacote, a triangulação some e a avaliação sai como sempre saiu.
final peerMultiplesRepositoryProvider = Provider<PeerMultiplesRepository>(
  (ref) => PeerMultiplesRepository(
    carregarPacote: () => rootBundle.loadString(peerMultiplesAsset),
  ),
);

/// As medianas que valem para um ticker, ou `null`.
final peerMultiplesProvider =
    FutureProvider.family<PeerMultipleSet?, Ticker>((ref, ticker) async {
  try {
    return await ref.watch(peerMultiplesRepositoryProvider).forTicker(ticker);
  } on Object {
    return null;
  }
});

final unitCompositionRepositoryProvider = Provider<UnitCompositionRepository>(
  (ref) => UnitCompositionRepository(
    carregarPacote: () => rootBundle.loadString(unitCompositionAsset),
    // A data da avaliação é a do dia, e a camada de aplicativo é o lugar de
    // perguntá-la — a mesma convenção do pacote da CVM.
    hoje: DateTime.now,
  ),
);

/// Ações na unit de um ativo, pela composição que a companhia declara na FCA
/// (item B16), ou `null` — e aí a razão volta a ser inferida.
final declaredSharesPerUnitProvider =
    FutureProvider.family<int?, Ticker>((ref, ticker) async {
  try {
    return await ref
        .watch(unitCompositionRepositoryProvider)
        .sharesPerUnitFor(ticker);
  } on Object {
    return null;
  }
});

/// Contagem oficial de ações do emissor de um ativo, ou `null` (decisão 83).
final officialSharesProvider =
    FutureProvider.family<OfficialShareCount?, Ticker>((ref, ticker) =>
        ref.watch(b3RegistryRepositoryProvider).officialSharesFor(ticker));

final tesouroDatasourceProvider = Provider<TesouroDatasource>(
  (ref) => TesouroDatasource(ref.watch(apiClientProvider)),
);

final riskFreeCurveRepositoryProvider = Provider<RiskFreeCurveRepository>(
  (ref) => RiskFreeCurveRepository(
    // Na web o navegador não lê o arquivo do Tesouro, e o aplicativo nem tenta:
    // a curva vem só do pacote do build (decisão 86).
    remote: kIsWeb ? null : ref.watch(tesouroDatasourceProvider),
    carregarPacote: () => rootBundle.loadString(tesouroQuotesAsset),
  ),
);

/// Curva de juros da avaliação de hoje e, sem ela, a razão (decisões 84 e 86).
final riskFreeCurveReadingProvider = FutureProvider<CurveReading>((ref) async {
  try {
    return await ref
        .watch(riskFreeCurveRepositoryProvider)
        .readAt(DateTime.now());
  } on Object {
    return (curve: null, note: null);
  }
});

/// Curva de juros da avaliação de hoje, ou `null` — e aí a cascata recua para
/// os dois pontos do CDI, declarando (decisão 84).
final riskFreeCurveProvider = FutureProvider<YieldCurve?>((ref) async =>
    (await ref.watch(riskFreeCurveReadingProvider.future)).curve);

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

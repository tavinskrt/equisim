import 'dart:convert';

import 'package:equisim_core/equisim_core.dart';

/// Registro de emissores da B3 empacotado com o aplicativo (item A3.3).
///
/// Dá à ponte por papel a **contagem oficial de ações** — o árbitro que as duas
/// contagens da fonte de preços não tinham (decisão 83). Gerado por
/// `tool/b3_empacotar.dart` e versionado, como o pacote da CVM.
///
/// **Sem pacote, o repositório é transparente**: sem contagem oficial, a ponte
/// segue a regra da fonte, que é a de antes.
class B3RegistryRepository {
  /// Lê o conteúdo do pacote.
  final Future<String> Function() loadPackage;

  /// Declara o repositório.
  B3RegistryRepository({required this.loadPackage});

  Future<Map<String, B3Issuer>>? _issuers;

  Future<Map<String, B3Issuer>> _loaded() => _issuers ??= _read();

  Future<Map<String, B3Issuer>> _read() async {
    try {
      final json = jsonDecode(await loadPackage());
      return json is Map<String, dynamic>
          ? B3RegistryCodec.decodePackage(json)
          : const {};
    } on Object {
      return const {};
    }
  }

  /// Contagem oficial do emissor de [ticker], ou `null`.
  ///
  /// O emissor é a raiz de quatro letras: `PETR3` e `PETR4` são a mesma
  /// companhia, e a contagem é o total das classes.
  Future<OfficialShareCount?> officialSharesFor(Ticker ticker) async {
    final t = ticker.value;
    if (t.length < 4) return null;
    final e = (await _loaded())[t.substring(0, 4)];
    final total = e?.totalShares;
    if (e == null || total == null) return null;
    return OfficialShareCount(total: total, asOf: e.consultedOn);
  }

  /// Classificação setorial oficial do emissor de [ticker], ou `null`
  /// (item A5, decisão 87).
  Future<B3Classification?> classificationFor(Ticker ticker) async {
    final t = ticker.value;
    if (t.length < 4) return null;
    return (await _loaded())[t.substring(0, 4)]?.classification;
  }
}

/// Perfil com a classificação setorial **oficial da B3**, sobre o perfil de
/// outra fonte (item A5, decisão 87).
///
/// **A B3 arbitra o setor; o resto do perfil segue da fonte.** O nome continua
/// o da fonte de preços. Onde a B3 não classifica o emissor, o perfil passa
/// intacto — recuo para a taxonomia da fonte, que é a de antes.
///
/// **E a classificação sobrevive à falha do perfil.** A Porta 1 depende do
/// setor, e o setor oficial está no pacote: um perfil que a fonte não entregou
/// não pode mandar um banco para a via da firma. Sem o nome, o ativo leva o
/// próprio código.
class OfficialSectorFundamentalsRepository implements FundamentalsRepository {
  /// Fonte do histórico, do universo e do nome.
  final FundamentalsRepository inner;

  /// De onde vem a classificação.
  final Future<B3Classification?> Function(Ticker) classification;

  /// Declara o repositório.
  OfficialSectorFundamentalsRepository({
    required this.inner,
    required this.classification,
  });

  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker ticker) =>
      inner.history(ticker);

  @override
  Future<Result<List<Ticker>>> universe() => inner.universe();

  @override
  Future<Result<Asset>> profile(Ticker ticker) async {
    final profile = await inner.profile(ticker);
    final B3Classification? official;
    try {
      official = await classification(ticker);
    } on Object {
      return profile;
    }
    if (official == null) return profile;
    final sector = Sector(key: official.sectorKey, label: official.sector);
    final industry = official.industry.isEmpty ? null : official.industry;
    return Ok(Asset(
      ticker: ticker,
      name: profile.isOk ? profile.unwrap().name : ticker.value,
      sector: sector,
      industry: industry,
    ));
  }
}

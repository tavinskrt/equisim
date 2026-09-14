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
  final Future<String> Function() carregarPacote;

  /// Declara o repositório.
  B3RegistryRepository({required this.carregarPacote});

  Future<Map<String, B3Issuer>>? _emissores;

  Future<Map<String, B3Issuer>> _lidos() => _emissores ??= _ler();

  Future<Map<String, B3Issuer>> _ler() async {
    try {
      final json = jsonDecode(await carregarPacote());
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
    final e = (await _lidos())[t.substring(0, 4)];
    final total = e?.totalShares;
    if (e == null || total == null) return null;
    return OfficialShareCount(total: total, asOf: e.consultedOn);
  }

  /// Classificação setorial oficial do emissor de [ticker], ou `null`
  /// (item A5, decisão 87).
  Future<B3Classification?> classificationFor(Ticker ticker) async {
    final t = ticker.value;
    if (t.length < 4) return null;
    return (await _lidos())[t.substring(0, 4)]?.classification;
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
  final Future<B3Classification?> Function(Ticker) classificacao;

  /// Declara o repositório.
  OfficialSectorFundamentalsRepository({
    required this.inner,
    required this.classificacao,
  });

  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker ticker) =>
      inner.history(ticker);

  @override
  Future<Result<List<Ticker>>> universe() => inner.universe();

  @override
  Future<Result<Asset>> profile(Ticker ticker) async {
    final perfil = await inner.profile(ticker);
    final B3Classification? oficial;
    try {
      oficial = await classificacao(ticker);
    } on Object {
      return perfil;
    }
    if (oficial == null) return perfil;
    final setor = Sector(key: oficial.sectorKey, label: oficial.sector);
    final industria = oficial.industry.isEmpty ? null : oficial.industry;
    return Ok(Asset(
      ticker: ticker,
      name: perfil.isOk ? perfil.unwrap().name : ticker.value,
      sector: setor,
      industry: industria,
    ));
  }
}

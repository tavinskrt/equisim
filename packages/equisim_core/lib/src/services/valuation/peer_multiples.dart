import '../../entities/fundamentals.dart';
import 'financial_sectors.dart';

/// Qual múltiplo produziu uma leitura.
enum MultipleKind {
  /// Preço sobre lucro por ação.
  precoLucro,

  /// Preço sobre valor patrimonial por ação.
  precoPatrimonio,

  /// Valor da firma sobre EBITDA.
  firmaEbitda;
}

/// Por que um múltiplo não se aplicou a um ativo.
enum MultipleRefusal {
  /// O grupo de pares não tem observações suficientes.
  paresInsuficientes,

  /// A grandeza de baixo não é positiva — lucro, patrimônio ou EBITDA.
  baseNaoPositiva,

  /// A grandeza de baixo não está publicada.
  baseAusente,

  /// EBITDA de instituição financeira não descreve geração operacional.
  instituicaoFinanceira,

  /// A ponte de dívida líquida não fecha em valor positivo do acionista.
  ponteNaoPositiva;
}

/// A mediana de um múltiplo num grupo de pares, com o tamanho do grupo.
class PeerMultiple {
  /// Mediana do múltiplo entre os pares.
  final double median;

  /// Quantos pares entraram na mediana.
  final int peers;

  /// Chave do grupo que produziu a mediana — subsetor, setor ou `mercado`.
  final String group;

  /// Declara a mediana.
  const PeerMultiple({
    required this.median,
    required this.peers,
    required this.group,
  });
}

/// O conjunto de medianas setoriais que a triangulação consome.
///
/// **O núcleo não sabe calcular isto**, e é deliberado: a mediana é do
/// universo, e o núcleo avalia um ativo por vez. Quem mede é
/// `tool/multiplos_empacotar.dart`, que grava um pacote versionado; quem carrega
/// é o aplicativo. É o mesmo arranjo do prior do beta (decisão 40) e do registro
/// da B3 (decisão 82).
class PeerMultipleSet {
  /// Medianas por múltiplo.
  final Map<MultipleKind, PeerMultiple> byKind;

  /// Data em que as medianas foram apuradas.
  final DateTime asOf;

  /// Declara o conjunto.
  const PeerMultipleSet({required this.byKind, required this.asOf});

  /// `true` quando não há múltiplo algum a aplicar.
  bool get isEmpty => byKind.isEmpty;
}

/// Uma leitura por múltiplo: o preço justo que ela implica, ou a recusa.
class MultipleReading {
  /// Qual múltiplo.
  final MultipleKind kind;

  /// Preço justo por papel implicado, em reais. `null` quando recusado.
  final double? fairValuePerShare;

  /// A mediana usada. `null` quando não havia grupo.
  final PeerMultiple? peer;

  /// Por que não se aplicou. `null` quando se aplicou.
  final MultipleRefusal? refusal;

  /// Declara a leitura.
  const MultipleReading({
    required this.kind,
    this.fairValuePerShare,
    this.peer,
    this.refusal,
  });

  /// `true` quando a leitura produziu preço.
  bool get applied => fairValuePerShare != null;
}

/// A triangulação por múltiplos de pares, ao lado do fluxo descontado.
///
/// **É segunda leitura, e não é preço.** O produto do motor continua sendo o
/// preço justo do DCF ([decisão 103](../../../../../docs/decisoes/103-o-premio-do-retorno-esperado-sai-da-ordenacao-comprovada-e-hoje-nao-ha.md));
/// o que esta classe acrescenta é um teste de sanidade sobre o **nível**, que
/// até aqui só existia em prosa. A divergência entre as duas leituras é
/// declarada, e não reconciliada: reconciliá-las seria escolher uma média que
/// nenhuma das duas sustenta.
class PeerValuation {
  PeerValuation._();

  /// Distância a partir da qual a divergência entre DCF e múltiplos vira
  /// ressalva na avaliação.
  ///
  /// **Meia ordem de grandeza.** Abaixo disso, duas leituras de modelos
  /// diferentes sobre a mesma companhia estão dizendo a mesma coisa com ruído;
  /// acima, uma delas está descrevendo outro negócio, e quem lê o preço justo
  /// precisa saber.
  static const double divergenceLimit = 0.50;

  /// Mínimo de pares para que uma mediana setorial seja usável.
  ///
  /// Abaixo de cinco, a mediana é o próprio ativo e mais alguns — e o múltiplo
  /// deixa de ser de pares para ser de vizinhos.
  static const int minimumPeers = 5;

  /// Calcula as três leituras.
  ///
  /// - [latest] é o exercício-base, o mesmo que o DCF usa.
  /// - [shares] é o **divisor da ponte**, e não a contagem da fonte: as duas
  ///   leituras precisam dividir pelo mesmo número, ou a comparação mede a
  ///   ponte em vez do modelo (decisão 83).
  /// - [sectorKey] e [industry] entram só para desligar `EV/EBITDA` em
  ///   instituição financeira, onde a captação é insumo e não financiamento
  ///   (decisão 102). **Os dois**, porque é o par que `FinancialSectors`
  ///   consulta — na taxonomia oficial da B3 a chave sozinha não separa banco
  ///   de seguradora de administradora de recebíveis (decisão 87).
  static List<MultipleReading> readings({
    required FundamentalsSnapshot latest,
    required double shares,
    required PeerMultipleSet peers,
    String? sectorKey,
    String? industry,
  }) {
    final out = <MultipleReading>[];
    for (final kind in MultipleKind.values) {
      out.add(_uma(
        kind: kind,
        latest: latest,
        shares: shares,
        peers: peers,
        sectorKey: sectorKey,
        industry: industry,
      ));
    }
    return out;
  }

  static MultipleReading _uma({
    required MultipleKind kind,
    required FundamentalsSnapshot latest,
    required double shares,
    required PeerMultipleSet peers,
    String? sectorKey,
    String? industry,
  }) {
    MultipleReading recusa(MultipleRefusal r, [PeerMultiple? p]) =>
        MultipleReading(kind: kind, refusal: r, peer: p);

    final financeira = FinancialSectors.isFinancial(
      sectorKey: sectorKey,
      industry: industry,
    );
    if (kind == MultipleKind.firmaEbitda && financeira) {
      return recusa(MultipleRefusal.instituicaoFinanceira);
    }

    final p = peers.byKind[kind];
    if (p == null || p.peers < minimumPeers || !p.median.isFinite) {
      return recusa(MultipleRefusal.paresInsuficientes, p);
    }
    if (p.median <= 0) return recusa(MultipleRefusal.baseNaoPositiva, p);
    if (shares <= 0 || !shares.isFinite) {
      return recusa(MultipleRefusal.baseAusente, p);
    }

    switch (kind) {
      case MultipleKind.precoLucro:
        final lucro = latest.netIncome;
        if (lucro == null) return recusa(MultipleRefusal.baseAusente, p);
        if (lucro <= 0) return recusa(MultipleRefusal.baseNaoPositiva, p);
        // **Pelo lucro total dividido pelo divisor**, e não pelo `LPA` da
        // fonte: o `LPA` publicado usa a contagem da companhia, e a ponte já
        // arbitrou outra. Misturar as duas mede a ponte.
        return MultipleReading(
          kind: kind,
          fairValuePerShare: p.median * lucro / shares,
          peer: p,
        );

      case MultipleKind.precoPatrimonio:
        final pl = latest.totalStockholderEquity;
        if (pl == null) return recusa(MultipleRefusal.baseAusente, p);
        if (pl <= 0) return recusa(MultipleRefusal.baseNaoPositiva, p);
        return MultipleReading(
          kind: kind,
          fairValuePerShare: p.median * pl / shares,
          peer: p,
        );

      case MultipleKind.firmaEbitda:
        final ebitda = latest.ebitda;
        if (ebitda == null) return recusa(MultipleRefusal.baseAusente, p);
        if (ebitda <= 0) return recusa(MultipleRefusal.baseNaoPositiva, p);
        // O valor da firma vira valor do acionista pela **mesma ponte** do DCF:
        // menos a dívida líquida. Caixa líquido soma, e é legítimo.
        final equity = p.median * ebitda - latest.netDebt;
        if (equity <= 0) {
          return recusa(MultipleRefusal.ponteNaoPositiva, p);
        }
        return MultipleReading(
          kind: kind,
          fairValuePerShare: equity / shares,
          peer: p,
        );
    }
  }

  /// A leitura consolidada: a **mediana** das que se aplicaram.
  ///
  /// Mediana, e não média: com três leituras, uma delas muito fora tem de ser
  /// a que o consolidado ignora, e não a que o arrasta.
  static double? consolidated(List<MultipleReading> readings) {
    final v = <double>[
      for (final r in readings)
        if (r.fairValuePerShare != null) r.fairValuePerShare!,
    ]..sort();
    if (v.isEmpty) return null;
    final meio = v.length ~/ 2;
    return v.length.isOdd ? v[meio] : (v[meio - 1] + v[meio]) / 2;
  }

  /// Distância relativa do consolidado contra o preço justo do fluxo
  /// descontado: `múltiplos ÷ DCF − 1`.
  ///
  /// `null` quando não há leitura aplicável, ou quando o DCF não é positivo —
  /// dividir por zero para declarar divergência seria inventar número.
  static double? divergence({
    required List<MultipleReading> readings,
    required double dcfFairValue,
  }) {
    final m = consolidated(readings);
    if (m == null || dcfFairValue <= 0 || !dcfFairValue.isFinite) return null;
    return m / dcfFairValue - 1;
  }
}

/// A triangulação inteira, como ela chega ao resultado da avaliação.
class PeerTriangulation {
  /// As três leituras, aplicadas ou recusadas.
  final List<MultipleReading> readings;

  /// A mediana das aplicadas, em reais por papel. `null` quando nenhuma
  /// se aplicou.
  final double? consolidated;

  /// `múltiplos ÷ DCF − 1`. `null` quando não é calculável.
  final double? divergence;

  /// Data em que as medianas de pares foram apuradas.
  final DateTime asOf;

  /// Declara a triangulação.
  const PeerTriangulation({
    required this.readings,
    required this.consolidated,
    required this.divergence,
    required this.asOf,
  });

  /// Quantas leituras produziram preço.
  int get applied => readings.where((r) => r.applied).length;

  /// `true` quando a divergência passa do limite declarado.
  bool get diverges =>
      divergence != null &&
      divergence!.abs() > PeerValuation.divergenceLimit;

  /// Monta a triangulação a partir dos insumos, ou devolve `null` quando não há
  /// pacote de pares.
  static PeerTriangulation? build({
    required FundamentalsSnapshot latest,
    required double shares,
    required PeerMultipleSet? peers,
    required double dcfFairValue,
    String? sectorKey,
    String? industry,
  }) {
    if (peers == null || peers.isEmpty) return null;
    final rs = PeerValuation.readings(
      latest: latest,
      shares: shares,
      peers: peers,
      sectorKey: sectorKey,
      industry: industry,
    );
    return PeerTriangulation(
      readings: rs,
      consolidated: PeerValuation.consolidated(rs),
      divergence: PeerValuation.divergence(
        readings: rs,
        dcfFairValue: dcfFairValue,
      ),
      asOf: peers.asOf,
    );
  }
}

/// Leitura do pacote versionado de medianas setoriais.
///
/// **Fica no núcleo, e não na camada de dados**, porque o formato é do
/// contrato: quem grava é `tool/multiplos_empacotar.dart` e quem lê é o
/// aplicativo, e as duas pontas precisam da mesma leitura. O codec não toca
/// disco — recebe o mapa já decodificado.
abstract final class PeerMultipleCodec {
  /// Versão do formato do pacote.
  static const int versao = 1;

  /// Decodifica o pacote inteiro, indexado por ticker.
  ///
  /// Devolve mapa vazio quando o pacote não tem a seção esperada: pacote
  /// ilegível desliga a triangulação, e a avaliação sai como sempre saiu.
  static Map<String, PeerMultipleSet> decode(Map<String, Object?> json) {
    final porTicker = json['porTicker'];
    if (porTicker is! Map) return const {};
    final data = DateTime.tryParse(json['geradoEm'] as String? ?? '');
    if (data == null) return const {};

    final out = <String, PeerMultipleSet>{};
    for (final e in porTicker.entries) {
      final ticker = e.key;
      final v = e.value;
      if (ticker is! String || v is! Map) continue;
      final byKind = <MultipleKind, PeerMultiple>{};
      for (final k in MultipleKind.values) {
        final m = v[k.name];
        if (m is! Map) continue;
        final mediana = (m['mediana'] as num?)?.toDouble();
        final pares = (m['pares'] as num?)?.toInt();
        final grupo = m['grupo'] as String?;
        if (mediana == null || pares == null || grupo == null) continue;
        if (!mediana.isFinite || mediana <= 0) continue;
        byKind[k] = PeerMultiple(
          median: mediana,
          peers: pares,
          group: grupo,
        );
      }
      if (byKind.isNotEmpty) {
        out[ticker] = PeerMultipleSet(byKind: byKind, asOf: data);
      }
    }
    return out;
  }
}

/// Curva de juros observada, a partir dos títulos públicos prefixados.
///
/// **O que ela substitui.** Até a decisão 74 a taxa livre de risco de cada ano
/// da projeção era uma interpolação linear entre **dois pontos do CDI**: o
/// corrente e a média decenal (§2.9). Não era curva — não tinha vértice, e a
/// forma linear era escolha, não observação.
///
/// **O que ela usa.** O Tesouro Direto publica, por dia desde 2004, a taxa dos
/// títulos prefixados: o *Tesouro Prefixado* (LTN), cupom zero, que dá a taxa à
/// vista do vértice diretamente; e o *Prefixado com Juros Semestrais* (NTN-F),
/// que alcança dez anos. Conferido em 14/09/2026: em toda data amostrada desde
/// 2015 a curva nominal tem vértices de 0,3 a cerca de 10 anos.
///
/// **As aproximações, declaradas.**
///
/// 1. **Prazo em dias úteis ÷ 252**, contado da liquidação até o vencimento
///    pelo calendário conhecido na data-base (`BrazilianCalendar`). A taxa do
///    Tesouro é efetiva anual na base 252, e a primeira versão media o prazo em
///    `dias corridos ÷ 365,25`: o erro relativo no prazo tinha mediana de 0,4% e
///    passava de 1% em um vértice a cada dez. Nos forwards anuais que a
///    projeção usa, isso chegava a 4,7 bp, e na perpetuidade a menos de 0,5 bp
///    — pouco, mas não a "fração de ponto base" que estava declarada aqui.
///    Conferido contra o PU: 99,13% das LTN desde 2010 com o `du` exato
///    (decisão 79).
/// 2. **A taxa da NTN-F entra como taxa à vista**, embora seja taxa interna de
///    um título com cupom. Numa curva quase plana a diferença é pequena —
///    medido em 10/09/2026, LTN e NTN-F de mesmo prazo diferem em −20 bp aos
///    2,3 anos e +2 bp aos 4,3 —, e onde as duas existem vence a LTN.
/// 3. **Interpolação flat-forward** — linear no logaritmo do fator de desconto
///    —, que é a convenção de mercado para curva de títulos e não produz forward
///    negativo entre vértices positivos.
/// 4. **Extrapolação pelo último forward**: além do último vértice a curva
///    segue plana no forward do último segmento.
library;

import 'dart:math' as math;

import '../../time/brazilian_calendar.dart';

/// Um vértice: prazo em anos e taxa à vista efetiva anual.
class CurveVertex {
  /// Prazo, em anos de 252 dias úteis.
  final double years;

  /// Taxa à vista efetiva anual, em fração.
  final double rate;

  /// Declara o vértice.
  const CurveVertex(this.years, this.rate);
}

/// Curva de juros com interpolação flat-forward.
class YieldCurve {
  /// Data de referência da curva.
  final DateTime referenceDate;

  /// Vértices em ordem crescente de prazo, sem prazo repetido.
  final List<CurveVertex> vertices;

  YieldCurve._(this.referenceDate, this.vertices);

  /// Número mínimo de vértices para a curva existir.
  ///
  /// Com dois pontos ela volta a ser a interpolação que veio substituir.
  static const int minVertices = 3;

  /// Monta a curva, ou devolve `null` quando os vértices não sustentam uma.
  ///
  /// Descarta prazo não positivo, taxa não finita e taxa fora de `(−50%,
  /// 100%)` — isso é registro corrompido, não mercado. Prazos repetidos ficam
  /// com o primeiro informado, e é por isso que quem monta passa a LTN antes da
  /// NTN-F.
  static YieldCurve? of(DateTime referenceDate, Iterable<CurveVertex> vertices) {
    // Chave inteira, em dias úteis: dois títulos de mesmo vencimento caem no
    // mesmo dia, e `double` não serve de chave de mapa.
    final porPrazo = <int, CurveVertex>{};
    for (final v in vertices) {
      if (!v.years.isFinite || v.years <= 0) continue;
      if (!v.rate.isFinite || v.rate <= -0.5 || v.rate >= 1.0) continue;
      porPrazo.putIfAbsent((v.years * 252).round(), () => v);
    }
    if (porPrazo.length < minVertices) return null;
    final ordenados = porPrazo.values.toList()
      ..sort((a, b) => a.years.compareTo(b.years));
    return YieldCurve._(referenceDate, List.unmodifiable(ordenados));
  }

  /// `ln` do fator de desconto até [t] anos.
  double _lnDesconto(double t) {
    if (t <= 0) return 0;
    final v = vertices;
    // Antes do primeiro vértice: taxa à vista plana.
    if (t <= v.first.years) return -t * math.log(1 + v.first.rate);

    for (var i = 1; i < v.length; i++) {
      if (t <= v[i].years) {
        final l0 = -v[i - 1].years * math.log(1 + v[i - 1].rate);
        final l1 = -v[i].years * math.log(1 + v[i].rate);
        final w = (t - v[i - 1].years) / (v[i].years - v[i - 1].years);
        return l0 + (l1 - l0) * w;
      }
    }
    // Além do último vértice: segue o forward do último segmento.
    final a = v[v.length - 2], b = v.last;
    final la = -a.years * math.log(1 + a.rate);
    final lb = -b.years * math.log(1 + b.rate);
    final inclinacao = (lb - la) / (b.years - a.years);
    return lb + inclinacao * (t - b.years);
  }

  /// Taxa à vista efetiva anual para o prazo [t], em anos.
  double spotRate(double t) {
    if (t <= 0) return vertices.first.rate;
    return math.exp(-_lnDesconto(t) / t) - 1;
  }

  /// Forward efetivo anual entre [t0] e [t1], em anos.
  ///
  /// É a taxa que a curva de hoje atribui a um dinheiro aplicado de `t0` a
  /// `t1`. Para o ano `t` da projeção, `forwardRate(t − 1, t)`.
  double forwardRate(double t0, double t1) {
    if (t1 <= t0) return spotRate(t0);
    return math.exp((_lnDesconto(t0) - _lnDesconto(t1)) / (t1 - t0)) - 1;
  }

  /// Taxa de cada ano da projeção: o forward de um ano, do ano 1 ao [n].
  List<double> annualForwards(int n) => [
        for (var t = 1; t <= n; t++) forwardRate(t - 1.0, t.toDouble()),
      ];

  /// Taxa da perpetuidade: o forward depois do fim da projeção.
  ///
  /// Mede-se entre `n` e `n + 1` — para `n` além do último vértice, é o
  /// forward extrapolado do último segmento.
  double terminalRate(int n) => forwardRate(n.toDouble(), n + 1.0);
}

/// Um título, como o Tesouro Direto o publica.
class TreasuryQuote {
  /// `Tipo Titulo`.
  final String type;

  /// `Data Vencimento`.
  final DateTime maturity;

  /// `Data Base` — o dia da taxa.
  final DateTime baseDate;

  /// `Taxa Compra Manha`, em fração.
  final double rate;

  /// Declara o título.
  const TreasuryQuote({
    required this.type,
    required this.maturity,
    required this.baseDate,
    required this.rate,
  });
}

/// Monta a curva nominal a partir dos títulos do Tesouro Direto.
abstract final class TreasuryCurve {
  /// Cupom zero prefixado — taxa à vista exata.
  static const String ltn = 'Tesouro Prefixado';

  /// Prefixado com cupom semestral — alcança os prazos longos.
  static const String ntnF = 'Tesouro Prefixado com Juros Semestrais';

  /// Quantos dias para trás procurar a data-base mais recente.
  ///
  /// O Tesouro não publica em fim de semana e feriado; uma avaliação num
  /// domingo usa a curva de sexta.
  static const int diasDeRecuo = 7;

  /// Curva nominal na data-base mais recente até [asOf].
  ///
  /// **Nunca olha para a frente**: uma data-base posterior a [asOf] não entra,
  /// e é isso que permite montar a curva de cada coorte do backtest com o que
  /// era conhecido nela.
  static YieldCurve? at(Iterable<TreasuryQuote> quotes, DateTime asOf) {
    final dia = DateTime.utc(asOf.year, asOf.month, asOf.day);
    DateTime? base;
    for (final q in quotes) {
      final b = DateTime.utc(q.baseDate.year, q.baseDate.month, q.baseDate.day);
      if (b.isAfter(dia)) continue;
      if (dia.difference(b).inDays > diasDeRecuo) continue;
      if (base == null || b.isAfter(base)) base = b;
    }
    if (base == null) return null;

    final doDia = [
      for (final q in quotes)
        if (q.baseDate.year == base.year &&
            q.baseDate.month == base.month &&
            q.baseDate.day == base.day)
          q,
    ];
    // Da liquidação ao vencimento, em dias úteis do calendário que se
    // conhecia na data-base — é a conta do PU do próprio Tesouro.
    final liquidacao = BrazilianCalendar.treasurySettlement(base);
    double anos(TreasuryQuote q) =>
        BrazilianCalendar.businessDaysBetween(liquidacao, q.maturity,
            knownAt: base) /
        252;

    return YieldCurve.of(base, [
      // LTN primeiro: em prazo repetido, fica o cupom zero.
      for (final q in doDia)
        if (q.type == ltn) CurveVertex(anos(q), q.rate),
      for (final q in doDia)
        if (q.type == ntnF) CurveVertex(anos(q), q.rate),
    ]);
  }
}

/// Leitura do arquivo de taxas do Tesouro Direto.
///
/// O arquivo do Tesouro Transparente é `latin-1`, separado por `;`, com taxa em
/// percentual e vírgula decimal, e vem em **ordem decrescente de data-base**:
/// conferido em 14/09/2026, zero inversões em 176.042 linhas, e as 58 linhas do
/// dia mais recente nos primeiros bytes. É o que permite ao aplicativo ler só o
/// começo do arquivo e parar (item A2.1).
abstract final class TreasuryCsv {
  static DateTime? _data(String s) {
    final p = s.trim().split('/');
    if (p.length != 3) return null;
    final d = int.tryParse(p[0]), m = int.tryParse(p[1]), a = int.tryParse(p[2]);
    if (d == null || m == null || a == null) return null;
    return DateTime.utc(a, m, d);
  }

  /// Uma linha do arquivo, ou `null` quando não é título prefixado ou não se
  /// lê. O cabeçalho cai aqui por não ter data.
  static TreasuryQuote? parseLine(String linha) {
    final c = linha.split(';');
    if (c.length < 4) return null;
    final tipo = c[0].trim();
    if (tipo != TreasuryCurve.ltn && tipo != TreasuryCurve.ntnF) return null;
    final venc = _data(c[1]);
    final base = _data(c[2]);
    final taxa = double.tryParse(c[3].trim().replaceAll(',', '.'));
    if (venc == null || base == null || taxa == null || taxa <= 0) return null;
    return TreasuryQuote(type: tipo, maturity: venc, baseDate: base, rate: taxa / 100);
  }

  /// Todos os títulos prefixados das [linhas].
  static List<TreasuryQuote> parse(Iterable<String> linhas) => [
        for (final l in linhas)
          if (parseLine(l) case final TreasuryQuote q) q,
      ];

  /// Data-base de uma linha de **qualquer** título, ou `null`. Serve para
  /// saber onde termina o bloco do dia mais recente, que também tem títulos
  /// que a curva não usa.
  static DateTime? baseDateOf(String linha) {
    final c = linha.split(';');
    return c.length < 3 ? null : _data(c[2]);
  }
}

/// Formato das cotações empacotadas e da resposta da função de nuvem.
///
/// As duas pontas — `tool/curva_empacotar.dart` e a função `tesouro` de um
/// lado, o aplicativo do outro — precisam concordar sobre o formato, e ele mora
/// aqui pela mesma razão do `CvmDocumentCodec`.
abstract final class TreasuryQuotesCodec {
  /// Versão do formato.
  static const int versao = 1;

  static String _dia(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Grava as cotações.
  static Map<String, Object> encode(Iterable<TreasuryQuote> cotacoes,
          {required DateTime geradoEm}) =>
      {
        'versao': versao,
        'geradoEm': _dia(geradoEm),
        'cotacoes': [
          for (final q in cotacoes)
            {
              'tipo': q.type,
              'vencimento': _dia(q.maturity),
              'dataBase': _dia(q.baseDate),
              'taxa': q.rate,
            },
        ],
      };

  /// Lê as cotações. Versão desconhecida devolve lista vazia.
  static List<TreasuryQuote> decode(Map<String, dynamic> json) {
    if (json['versao'] != versao) return const [];
    final brutas = json['cotacoes'];
    if (brutas is! List) return const [];
    DateTime? data(Object? v) {
      if (v is! String || v.length < 10) return null;
      return DateTime.tryParse('${v.substring(0, 10)}T00:00:00Z');
    }

    final out = <TreasuryQuote>[];
    for (final b in brutas) {
      if (b is! Map<String, dynamic>) continue;
      final tipo = b['tipo'];
      final venc = data(b['vencimento']);
      final base = data(b['dataBase']);
      final taxa = b['taxa'];
      if (tipo is! String || venc == null || base == null || taxa is! num) {
        continue;
      }
      if (!taxa.isFinite || taxa <= -0.5 || taxa >= 1) continue;
      out.add(TreasuryQuote(
          type: tipo, maturity: venc, baseDate: base, rate: taxa.toDouble()));
    }
    return out;
  }
}

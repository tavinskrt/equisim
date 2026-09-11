/// Séries de capital, retorno e retenção que alimentam as guardas da Porta 2.
library;

import '../../entities/fundamentals.dart';
import 'inference.dart';

/// De quem é o fluxo que se desconta.
///
/// Decide a base de capital, o retorno medido sobre ela e o desconto aplicado —
/// as três coisas andam juntas e não se combinam entre vias.
enum ValuationLane {
  /// Fluxo da firma: capital investido, ROIC, WACC, com ponte de dívida.
  firm('firma'),

  /// Fluxo do acionista: patrimônio líquido, ROE, Ke, sem ponte.
  shareholder('acionista');

  final String label;
  const ValuationLane(this.label);
}

/// Um exercício com base de capital e lucro na convenção da via.
class CapitalPoint {
  /// Ano fiscal.
  final int year;

  /// Base de capital no fecho do exercício.
  final double base;

  /// Lucro do exercício na convenção da via: NOPAT na firma, lucro líquido no
  /// acionista. `null` quando a fonte não publica.
  final double? profit;

  const CapitalPoint({
    required this.year,
    required this.base,
    required this.profit,
  });
}

/// Série de capital de um ativo, já limpa e na convenção de uma via.
///
/// **A limpeza é por vizinhança, não por mediana global.** Um corte contra a
/// mediana de toda a série descarta anos legítimos de empresa que cresceu ordens
/// de magnitude: a PRIO3 multiplicou a base por trinta em oito anos, e o filtro
/// global apagava os exercícios recentes — os únicos que descrevem a empresa de
/// hoje. O critério de vizinhança pega o que se quer pegar, que é falha pontual
/// da fonte: o `bookValue` da ABEV3 em 2012 vem R$ 0,062 contra R$ 2,81 no ano
/// seguinte.
class CapitalSeries {
  /// Exercícios utilizáveis, em ordem cronológica.
  final List<CapitalPoint> points;

  /// Via cuja convenção a série segue.
  final ValuationLane lane;

  const CapitalSeries({required this.points, required this.lane});

  /// Fator de destoamento tolerado contra a vizinhança.
  ///
  /// **Deliberadamente largo.** Este filtro existe para falha da fonte, que é de
  /// ordem de grandeza — o `bookValue` da ABEV3 em 2012 vem R$ 0,062 contra
  /// R$ 2,81 no ano seguinte, um fator de 45. Salto real de base, como o de uma
  /// incorporação, fica entre 2 e 9 vezes e **precisa passar**: quem o julga é a
  /// guarda de comparabilidade, que mede quanto da expansão veio de capital
  /// externo. Um filtro apertado o apagaria antes, e a guarda mediria uma série
  /// da qual o próprio evento já teria sido removido.
  static const double neighbourFactor = 8.0;

  /// Monta a série a partir dos exercícios publicados.
  ///
  /// - [snapshots]: exercícios em ordem cronológica, já filtrados por
  ///   publicação.
  /// - [lane]: convenção a aplicar.
  /// - [firmTaxRate]: alíquota estrutural da via da firma, de
  ///   [structuralTaxRate]. Nula reproduz o comportamento anterior, que é a
  ///   alíquota estatutária embutida pela fonte no `NOPAT` publicado.
  static CapitalSeries build(
    List<FundamentalsSnapshot> snapshots,
    ValuationLane lane, {
    double? firmTaxRate,
  }) {
    final brutos = <CapitalPoint>[];
    for (final s in snapshots) {
      final base = lane == ValuationLane.firm
          ? s.investedCapital
          : s.equityBookValue;
      if (base == null || base <= 0) continue;
      brutos.add(CapitalPoint(
        year: s.fiscalPeriodEnd.year,
        base: base,
        profit: lane == ValuationLane.firm
            ? s.nopatAtRate(firmTaxRate)
            : s.netIncome,
      ));
    }
    return CapitalSeries(points: _cleanByNeighbour(brutos), lane: lane);
  }

  /// Exercícios mínimos com alíquota medível para a estrutural ser usada.
  ///
  /// Cinco. Abaixo disso a mediana descreve poucos anos e um único exercício
  /// atípico a domina — e o recuo, que é a estatutária, é conservador na
  /// direção que este projeto já assume.
  static const int minTaxObservations = 5;

  /// Alíquota **estrutural** de imposto do ativo: a mediana dos exercícios.
  ///
  /// **Mediana e não último exercício, de propósito.** É ela que separa
  /// incentivo estrutural de evento: prejuízo fiscal compensado num ano move a
  /// alíquota daquele ano e não a mediana de quinze. Medido em 10/09/2026, a
  /// dispersão robusta dentro da empresa é de 7,5 p.p. na mediana — a alíquota
  /// brasileira é regime, e um regime é o que se projeta.
  ///
  /// Confinada em `[0, alíquota estatutária]`. O teto existe porque pagar mais
  /// que a marginal em perpetuidade é transitório — reversão de diferido,
  /// operação no exterior —, e a fonte já aplicou a estatutária; ir além
  /// penalizaria duas vezes.
  ///
  /// Devolve `null` com menos de [minTaxObservations] exercícios medíveis, o
  /// que faz o chamador recuar para o `NOPAT` publicado.
  static double? structuralTaxRate(
    List<FundamentalsSnapshot> snapshots, {
    required double statutoryRate,
  }) {
    final taxas = <double>[];
    for (final s in snapshots) {
      final t = s.effectiveTaxRate;
      if (t != null && t.isFinite) taxas.add(t);
    }
    if (taxas.length < minTaxObservations) return null;
    final m = Inference.median(taxas);
    if (m == null || !m.isFinite) return null;
    return m.clamp(0.0, statutoryRate).toDouble();
  }

  /// Quantos vizinhos de cada lado formam a referência local.
  static const int neighbourRadius = 2;

  /// Descarta o ponto que destoa da **mediana dos vizinhos próximos**.
  ///
  /// A referência é a mediana de até [neighbourRadius] pontos de cada lado, e
  /// não o vizinho imediato. A diferença importa na ponta: com um vizinho só, um
  /// exercício legítimo adjacente a uma falha da fonte seria descartado junto —
  /// o bom seria julgado contra o ruim, e os dois cairiam.
  static List<CapitalPoint> _cleanByNeighbour(List<CapitalPoint> s) {
    if (s.length < 4) return s;
    final ok = <CapitalPoint>[];
    for (var i = 0; i < s.length; i++) {
      final vizinhos = <double>[];
      for (var j = i - neighbourRadius; j <= i + neighbourRadius; j++) {
        if (j == i || j < 0 || j >= s.length) continue;
        vizinhos.add(s[j].base);
      }
      if (vizinhos.length < 2) {
        ok.add(s[i]);
        continue;
      }
      vizinhos.sort();
      final m = vizinhos.length ~/ 2;
      final referencia = vizinhos.length.isOdd
          ? vizinhos[m]
          : (vizinhos[m - 1] + vizinhos[m]) / 2;
      if (referencia <= 0) {
        ok.add(s[i]);
        continue;
      }
      final razao = s[i].base / referencia;
      if (razao < 1 / neighbourFactor || razao > neighbourFactor) continue;
      ok.add(s[i]);
    }
    return ok;
  }

  /// Exercícios na série.
  int get length => points.length;

  /// `true` quando não há pontos suficientes para qualquer estatística.
  bool get isTooShort => points.length < 4;

  /// Base do exercício mais recente.
  ///
  /// É contra ela que o retorno do ciclo é aplicado quando o exercício
  /// corrente vem no prejuízo: `fluxo-base = retorno do ciclo × capital de
  /// hoje` é a mesma conta que o fator de normalização faz, escrita de um
  /// jeito que sobrevive a um denominador não positivo (decisão 53).
  double? get latestBase => points.isEmpty ? null : points.last.base;

  /// Variações anuais da base, só entre exercícios **consecutivos**.
  ///
  /// Buraco na série interrompe o par: comparar 2019 com 2021 como se fosse um
  /// ano mediria dois anos de crescimento.
  List<double> get annualVariations {
    final v = <double>[];
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      if (b.year - a.year != 1 || a.base <= 0) continue;
      v.add(b.base / a.base - 1);
    }
    return v;
  }

  /// Retorno sobre a base de **abertura**, por exercício.
  ///
  /// Abertura e não fecho: o lucro do ano foi produzido pelo capital que existia
  /// no começo dele. Usar o fecho subestima o retorno de quem cresceu.
  ///
  /// **Exercício de prejuízo entra, com o sinal que tem.** Descartá-lo era viés
  /// de sobrevivência dentro da própria empresa: a mediana do ciclo passava a
  /// descrever apenas os anos bons dela, e o ciclo é justamente o que alterna
  /// bons e maus. Medido em 07/09/2026 sobre o universo elegível, 52 dos 120
  /// avaliados tinham ao menos um exercício descartado, e a mediana do ciclo
  /// saía inflada em até 33 pontos percentuais — a CVCB3 acusava 33,8% de ROIC
  /// mediano contra 0,55% com os quatro anos de prejuízo no lugar, e a MGLU3
  /// 22,4% contra 11,2%. Como o fator de normalização é `ciclo / atual` e o DCF
  /// é homogêneo de grau 1 no fluxo-base, o viés ia inteiro para o preço justo.
  ///
  /// Exercício **sem lucro publicado** continua fora: ausência de dado não é
  /// retorno nulo, e incluí-la como zero inventaria observação.
  List<({int year, double value})> get returns {
    final r = <({int year, double value})>[];
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      if (b.year - a.year != 1 || a.base <= 0) continue;
      final l = b.profit;
      if (l == null) continue;
      r.add((year: b.year, value: l / a.base));
    }
    return r;
  }

  /// Retenção observada por exercício, em `[0, 1]`.
  ///
  /// `ΔBase / lucro` — a fração do lucro que ficou na empresa. Confinada porque
  /// valor fora do intervalo não é retenção: acima de 1 houve capital externo,
  /// abaixo de 0 houve distribuição além do lucro, e os dois casos são tratados
  /// pela guarda de comparabilidade, não aqui.
  List<double> get retentions {
    final b = <double>[];
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], c = points[i];
      if (c.year - a.year != 1 || a.base <= 0) continue;
      final l = c.profit;
      if (l == null || l <= 0) continue;
      b.add(((c.base - a.base) / l).clamp(0.0, 1.0));
    }
    return b;
  }

  /// Mediana do retorno na janela do ciclo, excluindo o exercício corrente.
  ///
  /// - [window]: exercícios do ciclo. O corrente fica de fora porque é
  ///   justamente ele que se quer comparar contra o ciclo.
  double? cycleReturn({required int window}) {
    final r = returns;
    if (r.length < 4) return null;
    final ini = r.length - 1 - window;
    final janela = r.sublist(ini < 0 ? 0 : ini, r.length - 1);
    if (janela.length < 3) return null;
    return Inference.median([for (final x in janela) x.value]);
  }

  /// Fração dos retornos da janela do ciclo que são positivos.
  ///
  /// **Separa o vale do declínio.** A mediana do ciclo pode sair positiva com
  /// metade dos anos no prejuízo — e nesse caso ela descreve uma empresa que
  /// alterna, não uma que caiu num ano ruim. Medido em 11/09/2026: a AZEV4
  /// tinha mediana de retorno sobre patrimônio de +10,2% com quatro dos oito
  /// exercícios negativos.
  ///
  /// Devolve `null` com a mesma janela curta que [cycleReturn] recusa, para
  /// que as duas medidas nunca discordem sobre haver ciclo.
  double? positiveShare({required int window}) {
    final r = returns;
    if (r.length < 4) return null;
    final ini = r.length - 1 - window;
    final janela = r.sublist(ini < 0 ? 0 : ini, r.length - 1);
    if (janela.length < 3) return null;
    return janela.where((x) => x.value > 0).length / janela.length;
  }

  /// Retorno do exercício mais recente.
  double? get latestReturn {
    final r = returns;
    return r.isEmpty ? null : r.last.value;
  }

  /// Retenção mediana observada, ou `null` sem pares suficientes.
  double? get medianRetention {
    final b = retentions;
    return b.length < 5 ? null : Inference.median(b);
  }
}

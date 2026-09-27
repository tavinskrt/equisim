/// Eventos societários inferidos da série bruta de cotações da B3.
///
/// **De onde vem.** O COTAHIST, arquivo histórico oficial da B3, publica o
/// fechamento **bruto** de todo papel negociado em cada ano — inclusive os que
/// depois deixaram de existir — e o `DISMES`, número de distribuição do papel,
/// que **incrementa a cada evento**. Conferido em 14/09/2026 sobre o BBAS3 de
/// 2024: o fechamento cai de R$ 56,46 para R$ 27,91 em 16/04/2024 (razão 0,494)
/// na bonificação de 100%, e o `DISMES` passa de 321 para 322.
///
/// **O que o `DISMES` não diz.** Ele muda também em provento: o mesmo BBAS3
/// tem nove trocas em 2024, e oito são quedas de 1% a 4% nas datas ex. O
/// número marca que houve evento, não qual.
///
/// **Por isso o fator é inferido, e com recusa.** Em cada troca de `DISMES`, a
/// razão entre os fechamentos antes e depois é aproximada pela fração simples
/// mais próxima — ½, ⅓, 2, 10... —, e só vira evento de ações quando está
/// longe de 1 **e** perto de uma fração. Uma queda de 40% num dia de crise que
/// coincida com data ex de dividendo não está perto de fração nenhuma, e fica
/// de fora.
///
/// **A série ajustada não é, ainda, série de retorno.** Bonificação de até 20%
/// fica abaixo de [CorporateEvents.minDesvio] e não é detectada: a queda de
/// preço dela sai como perda, e numa carteira que não credita provento essa
/// perda não volta por lugar nenhum — em banco que bonifica 10% todo ano, é
/// −9% por evento. Hoje nada no aplicativo lê esta série; ligá-la a retorno de
/// carteira ou de coorte **espera o registro oficial de eventos** (item A3.1
/// do plano), que declara o fator em vez de inferi-lo.
///
/// Ver a decisão 75.
library;

import 'dart:math' as math;

import '../../entities/price_series.dart';

/// Um fechamento bruto, com o número de distribuição do dia.
class RawQuote {
  /// Dia do pregão.
  final DateTime date;

  /// Fechamento sem ajuste nenhum.
  final double close;

  /// `DISMES` — número de distribuição do papel naquele dia.
  final int distribution;

  /// Declara o fechamento.
  const RawQuote(this.date, this.close, this.distribution);
}

/// Um evento de ações: desdobramento, grupamento ou bonificação.
class ShareEvent {
  /// Primeiro pregão já com a nova base.
  final DateTime exDate;

  /// Quantas ações passaram a existir para cada uma que existia.
  ///
  /// `2` num desdobramento de 1 para 2 ou numa bonificação de 100%; `1/3` num
  /// grupamento de 3 para 1. O preço se divide por este número.
  final double factor;

  /// Razão observada entre os fechamentos, antes de aproximar.
  final double observedRatio;

  /// Declara o evento.
  const ShareEvent({
    required this.exDate,
    required this.factor,
    required this.observedRatio,
  });
}

/// Inferência dos eventos e ajuste da série.
abstract final class CorporateEvents {
  /// Distância mínima de 1 para que a razão seja candidata a evento de ações.
  ///
  /// **Bonificação de até 20% não é detectável pelo preço**, e a régua não
  /// finge que é. Uma bonificação de 10% dá razão de 0,909; uma queda de 8,5%
  /// em data ex de dividendo dá 0,915 — a 0,6% uma da outra. O teste que
  /// tentava separá-las falhou, e com razão. Abaixo de 19% de desvio a troca
  /// de `DISMES` é tratada como provento, e as bonificações pequenas ficam
  /// declaradas como não detectadas.
  static const double minDesvio = 0.19;

  /// Maior distância, em dias corridos, entre os dois pregões comparados.
  ///
  /// Evento só se infere entre pregões vizinhos. Um papel suspenso por semanas
  /// pode voltar com `DISMES` novo **e** preço muito diferente, e atribuir o
  /// salto inteiro a evento de ações seria inventar um fator.
  static const int maxDiasEntrePregoes = 7;

  /// Folga relativa entre a razão observada e a fração que a explica, **para
  /// fração longe de 1** — desdobramento e grupamento.
  ///
  /// O fechamento do dia ex não é o do dia anterior dividido pelo fator: o
  /// mercado também andou. Seis por cento acomodam um pregão comum e recusam a
  /// crise que coincide com data ex.
  static const double tolerancia = 0.06;

  /// Folga **para fração perto de 1** — bonificação.
  ///
  /// Uma bonificação de 10% e uma queda de 9% em data ex de dividendo produzem
  /// razões vizinhas, e a folga de seis por cento as confundiria. Aqui ela
  /// aperta: só casa o que está a 1,5% da fração.
  static const double toleranciaBonificacao = 0.015;

  /// Frações plausíveis de evento, como `ações depois ÷ ações antes`.
  ///
  /// São as que a B3 registra na prática — desdobramentos e grupamentos de 2
  /// a 100, bonificações de 10% a 200%. Uma razão que não esteja perto de
  /// nenhuma não é explicada por evento, e é recusada.
  static final List<double> fatores = () {
    // Lista, e não conjunto: os valores são distintos por construção, e
    // `double` não serve de elemento de `Set`.
    final out = <double>[];
    for (final n in [2, 3, 4, 5, 6, 8, 10, 15, 20, 25, 50, 100]) {
      out.add(n.toDouble());
      out.add(1 / n);
    }
    // Bonificações a partir de 25% — abaixo disso, ver [minDesvio].
    out.addAll(const [1.25, 1.3, 1.5]);
    return out..sort();
  }();

  /// Eventos de ações na série, em ordem de data.
  ///
  /// - [quotes]: fechamentos brutos, em qualquer ordem. Dias sem fechamento
  ///   positivo são ignorados.
  static List<ShareEvent> detect(List<RawQuote> quotes) {
    final s = [
      for (final q in quotes)
        if (q.close.isFinite && q.close > 0) q,
    ]..sort((a, b) => a.date.compareTo(b.date));

    final out = <ShareEvent>[];
    for (var i = 1; i < s.length; i++) {
      final antes = s[i - 1], depois = s[i];
      if (depois.distribution == antes.distribution) continue;
      // Em dias de calendário, e não em horas: datas em hora local cruzando o
      // horário de verão perdiam uma hora, e oito dias contavam como sete.
      if (_dias(antes.date, depois.date) > maxDiasEntrePregoes) {
        continue;
      }
      final razao = depois.close / antes.close;
      if ((razao - 1).abs() < minDesvio) continue;

      // O preço se divide pelo fator: razão ≈ 1 / fator.
      final fatorObservado = 1 / razao;
      double? melhor;
      var menorErro = double.infinity;
      for (final f in fatores) {
        final erro = (fatorObservado / f - 1).abs();
        if (erro < menorErro) {
          menorErro = erro;
          melhor = f;
        }
      }
      if (melhor == null) continue;
      // "Perto de 1" em escala logarítmica, onde ½ e 2 são simétricos: medir
      // `|fator − 1|` daria folga apertada a um grupamento de 2 para 1.
      final folga = math.log(melhor).abs() < math.log(1.6)
          ? toleranciaBonificacao
          : tolerancia;
      if (menorErro > folga) continue;
      out.add(ShareEvent(
        exDate: depois.date,
        factor: melhor,
        observedRatio: razao,
      ));
    }
    return out;
  }

  /// Data ex de um evento **declarado** — pela CVM, no Formulário de
  /// Referência —, localizada no preço (item A3.4).
  ///
  /// O formulário dá o fator, pela contagem antes e depois, e a **data de
  /// aprovação**, que não é a data ex: entre a assembleia e o primeiro pregão
  /// sem direito correm dias ou meses. A data ex é o primeiro pregão, a partir
  /// da aprovação e dentro de [windowDays] dias, em que o fechamento se divide
  /// pelo fator declarado, com a mesma folga de [detect].
  ///
  /// Fator perto de 1 — bonificação pequena — não se distingue de provento
  /// pelo preço. Para ele vale a primeira troca de `DISMES` na janela, que é
  /// onde a B3 marca o evento, e o [ShareEvent] sai com `observedRatio` da
  /// troca.
  ///
  /// **Fator longe de 1 tem uma segunda chance.** O grupamento de papel em
  /// crise acontece no dia em que o mercado também despenca, e a folga de 6%
  /// o recusa. Mas um fator de 25 não se confunde com oscilação: vale a
  /// primeira troca de `DISMES` em que a razão está a [toleranciaDeclarada] do
  /// declarado. Sem troca nem razão que case, `null`: evento que não se
  /// localiza não ajusta nada.
  static ShareEvent? locate(
    List<RawQuote> quotes, {
    required double factor,
    required DateTime approvedOn,
    int windowDays = 365,
  }) {
    if (!(factor > 0) || !factor.isFinite) return null;
    final inicio = DateTime.utc(approvedOn.year, approvedOn.month, approvedOn.day);
    final fim = inicio.add(Duration(days: windowDays));
    final s = [
      for (final q in quotes)
        if (q.close.isFinite && q.close > 0) q,
    ]..sort((a, b) => a.date.compareTo(b.date));
    final pertoDeUm = math.log(factor).abs() < math.log(1.6);
    final folga = pertoDeUm ? toleranciaBonificacao : tolerancia;

    ShareEvent? primeiraTroca;
    ShareEvent? trocaQueCasa;
    for (var i = 1; i < s.length; i++) {
      final antes = s[i - 1], depois = s[i];
      final dia = DateTime.utc(depois.date.year, depois.date.month, depois.date.day);
      if (dia.isBefore(inicio)) continue;
      if (dia.isAfter(fim)) break;
      if (_dias(antes.date, depois.date) > maxDiasEntrePregoes) continue;
      final razao = depois.close / antes.close;
      if (((1 / razao) / factor - 1).abs() <= folga &&
          (!pertoDeUm || (razao - 1).abs() >= minDesvio)) {
        return ShareEvent(exDate: dia, factor: factor, observedRatio: razao);
      }
      if (depois.distribution != antes.distribution) {
        final ev = ShareEvent(exDate: dia, factor: factor, observedRatio: razao);
        primeiraTroca ??= ev;
        if (trocaQueCasa == null &&
            !pertoDeUm &&
            math.log((1 / razao) / factor).abs() <
                math.log(1 + toleranciaDeclarada)) {
          trocaQueCasa = ev;
        }
      }
    }
    return pertoDeUm ? primeiraTroca : trocaQueCasa;
  }

  /// Folga da segunda chance de [locate]: fator declarado longe de 1, com
  /// troca de `DISMES`, a 25% da razão observada — em escala logarítmica, onde
  /// ½ e 2 são simétricos.
  static const double toleranciaDeclarada = 0.25;

  static int _dias(DateTime a, DateTime b) =>
      DateTime.utc(b.year, b.month, b.day)
          .difference(DateTime.utc(a.year, a.month, a.day))
          .inDays;

  /// Série ajustada **para trás** pelos eventos de ações, na base de hoje.
  ///
  /// Cada fechamento anterior a um evento é dividido pelo fator dele, de modo
  /// que a série inteira fique na quantidade de ações corrente — que é a
  /// convenção do `close` da fonte de mercado. **Provento não entra**: o
  /// retorno do projeto é de preço, pela decisão 23.
  static List<({DateTime date, double close})> adjust(
    List<RawQuote> quotes,
    List<ShareEvent> events,
  ) {
    final s = [...quotes]..sort((a, b) => a.date.compareTo(b.date));
    final ev = [...events]..sort((a, b) => a.exDate.compareTo(b.exDate));
    return [
      for (final q in s)
        (
          date: q.date,
          close: () {
            var c = q.close;
            for (final e in ev) {
              if (q.date.isBefore(e.exDate)) c /= e.factor;
            }
            return c;
          }(),
        ),
    ];
  }

  /// **Completa o ajuste que a fonte de preços deixou de fazer** (item B29).
  ///
  /// O `close` da fonte de mercado vem ajustado por desdobramento e
  /// grupamento, mas **não por toda bonificação**. Medido em 24/09/2026 sobre o
  /// cache da validação: das mudanças de contagem do FRE com salto no
  /// fechamento bruto, a fonte ajustou 67 e deixou 133 como vieram — as
  /// bonificações anuais do Bradesco de 2018 a 2022, a de 100% da SLC em 2019,
  /// as da Renner, da Itaúsa, da Klabin em 2024. Numa série assim, o dia ex é
  /// uma queda de `1 − 1/fator` que não aconteceu: ela entra no beta, na
  /// volatilidade da faixa e em todo retorno que atravessa a data.
  ///
  /// Para cada evento de [events], compara o fechamento do último pregão antes
  /// da data ex com o do primeiro a partir dela. **Se o salto é o do evento, e
  /// não o de um dia comum**, divide os fechamentos anteriores pelo fator e
  /// multiplica o volume por ele — o financeiro do dia não muda. Se a série já
  /// estava contínua na data, o evento já estava ajustado, e nada muda.
  ///
  /// A regra do salto tem duas condições, e as duas são necessárias:
  /// - ele está mais perto de `1/fator` que de 1, em escala logarítmica — a
  ///   série ajustada é contínua na data, e a não ajustada cai pelo fator;
  /// - ele está a [toleranciaDaFonte] de `1/fator` — a
  ///   [toleranciaDaFonteBonificacao], em bonificação —, ou seja, o que sobra
  ///   além do evento é um pregão comum.
  ///
  /// **É a regra de quem não tem o preço bruto** — o aplicativo. Quem tem o
  /// COTAHIST sabe, pelo fator entre o bruto e a fonte, exatamente quais
  /// eventos ficaram sem ajuste, e usa [applyToSeries].
  ///
  /// Evento cuja data ex não tem pregão vizinho na série, a até
  /// [maxDiasEntrePregoes], não ajusta nada.
  static ({PriceSeries series, List<ShareEvent> applied}) completeAdjustment(
    PriceSeries series,
    List<ShareEvent> events,
  ) {
    if (series.isEmpty || events.isEmpty) {
      return (series: series, applied: const []);
    }
    final pts = series.points;
    final aplicados = <ShareEvent>[];
    for (final e in events) {
      if (!(e.factor > 0) || !e.factor.isFinite) continue;
      // Abaixo de 3% o salto do evento não se separa de um provento ou de um
      // pregão comum: um banco que paga 3% de dividendo no dia passaria por
      // bonificação não ajustada.
      if (math.log(e.factor).abs() < fatorMinimoDaFonte) continue;
      final ex = DateTime(e.exDate.year, e.exDate.month, e.exDate.day);
      var i = 0;
      while (i < pts.length && pts[i].date.isBefore(ex)) {
        i++;
      }
      if (i == 0 || i >= pts.length) continue;
      final antes = pts[i - 1], depois = pts[i];
      if (_dias(antes.date, depois.date) > maxDiasEntrePregoes) continue;
      if (_dias(ex, depois.date) > maxDiasEntrePregoes) continue;
      if (!(antes.close > 0) || !(depois.close > 0)) continue;
      final salto = math.log(depois.close / antes.close);
      final semAjuste = (salto + math.log(e.factor)).abs();
      final folga = math.log(e.factor).abs() < math.log(1.6)
          ? toleranciaDaFonteBonificacao
          : toleranciaDaFonte;
      if (semAjuste < salto.abs() && semAjuste <= folga) aplicados.add(e);
    }
    if (aplicados.isEmpty) return (series: series, applied: const []);
    return (series: applyToSeries(series, aplicados), applied: aplicados);
  }

  /// A série com os fechamentos anteriores a cada evento divididos pelo fator
  /// dele, e o volume multiplicado — **sem perguntar se a fonte já ajustou**.
  ///
  /// É para quem sabe a resposta: o backtest, que compara o bruto do COTAHIST
  /// com a fonte e passa só os eventos que ficaram sem ajuste. Passar um evento
  /// já ajustado ajustaria duas vezes.
  static PriceSeries applyToSeries(PriceSeries series, List<ShareEvent> events) {
    final aplicados = [
      for (final e in events)
        if (e.factor > 0 && e.factor.isFinite && (e.factor - 1).abs() > 1e-9) e,
    ];
    if (series.isEmpty || aplicados.isEmpty) return series;
    final pts = series.points;
    return PriceSeries(
      ticker: series.ticker,
      points: [
        for (final p in pts)
          () {
            var f = 1.0;
            var antesDeAlgum = false;
            for (final e in aplicados) {
              final ex = DateTime(e.exDate.year, e.exDate.month, e.exDate.day);
              if (p.date.isBefore(ex)) {
                f *= e.factor;
                antesDeAlgum = true;
              }
            }
            return !antesDeAlgum
                ? p
                : PricePoint(
                    date: p.date,
                    close: p.close / f,
                    adjustedClose:
                        p.adjustedClose == null ? null : p.adjustedClose! / f,
                    volume: p.volume == null ? null : p.volume! * f,
                  );
          }(),
      ],
    );
  }

  /// Folga entre o salto do dia ex e `1/fator` em [completeAdjustment].
  ///
  /// **Seis por cento, a mesma de [tolerancia].** Aqui o fator é declarado — do
  /// FRE ou do registro da B3 — e não inferido, e a pergunta não é se houve
  /// evento, mas se a fonte o ajustou. A condição de estar mais perto de
  /// `1/fator` que de 1 é a que separa as duas respostas; a folga só recusa o
  /// dia em que o mercado andou tanto que nenhuma das duas explica o salto.
  static const double toleranciaDaFonte = 0.06;

  /// A mesma folga **para bonificação**, fator abaixo de 1,6: três por cento.
  ///
  /// Numa bonificação de 10%, a série ajustada que tivesse um pregão de −5% no
  /// dia ex já estaria mais perto de `1/fator` que de 1, e a folga de seis por
  /// cento a ajustaria de novo — inventando uma alta de 10% no lugar da queda
  /// que se queria tirar. Com três, o dia comum que confunde as duas precisa
  /// cair mais de 6%, o que é raro; e a bonificação não ajustada só escapa
  /// quando o mercado andou mais de 3% no mesmo pregão.
  static const double toleranciaDaFonteBonificacao = 0.03;

  /// Menor fator, em log, que [completeAdjustment] examina: 3%. Ver o
  /// comentário no laço.
  static const double fatorMinimoDaFonte = 0.03;
}

// O crescimento fundamental `g = ROE × (1 − payout)`, e o do PIB do setor para
// quem cresce sem reter — medição, sem ligar nada no motor.
//
// **A pergunta.** O motor tira o `g` da mediana das variações anuais da base
// de capital — o patrimônio na via do acionista, o capital investido na da
// firma (decisão 25). Pela identidade do lucro limpo, `Δpatrimônio = lucro ×
// retenção` quando não entra nem sai capital, e a variação da base **é** o
// `ROE × retenção` realizado ano a ano. A proposta do orientador é a versão
// que olha para a frente: o ROE normalizado vezes a retenção que o payout
// observado implica; e, para quem cresce sem precisar reter — as de pouco
// capital e as que distribuem quase tudo —, o crescimento nominal do setor.
//
// **As regras, fixadas antes de medir.**
//
//     ROE normalizado = mediana dos últimos 8 retornos sobre o patrimônio de
//                       abertura, com o do último exercício (≥ 4)
//     payout          = dividendos e JCP pagos ÷ lucro líquido, somados nos
//                       últimos 5 exercícios (≥ 3), do fluxo de caixa da DFP
//     g fundamental   = ROE normalizado × (1 − payout), retenção em [0; 1]
//
//     regra combinada:
//       commodity (a lista de precedência do ciclo do motor) → g = inflação
//       payout ≥ 75% ou receita ÷ capital investido ≥ 2      → g = PIB nominal
//                                                              do setor, 10 anos
//       o resto                                               → g fundamental
//
// Para commodity a proposta é crescimento real zero sobre a base normalizada
// pelo ciclo: preço real de commodity não tem tendência positiva de longo
// prazo, e o motor já põe a base no meio do ciclo. A variante que cresce pelo
// reinvestimento ao retorno do ciclo é a do `g` fundamental, medida ao lado.
//
// **Duas medições.**
//
// 1. Na entrada congelada, o universo reavaliado com cada `g`, imposto pelo
//    ponto de diagnóstico do motor (`withOverrides(growth:)`): o decaimento
//    até `g∞`, o teto da economia e o freio `g ≤ 0,95 × ROIC` continuam.
// 2. No histórico: em cada exercício de 2014 a 2022, o `g` que cada regra
//    daria com os dados até ele, contra o crescimento que aconteceu nos três
//    exercícios seguintes. É a régua de «projeção real».
//
//   python tool/cvm/dividendos_pagos.py        # data/cvm/dividendos_pagos.json
//   python tool/pib_setorial_baixar.py         # data/indices/pib_setorial.json
//   dart run tool/crescimento_fundamental.dart # grava crescimento_fundamental.json
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

import 'validation/congelado.dart';
import 'validation/ibovespa_longo.dart';
import 'validation/regression.dart';

const _saida = 'docs/validacao/crescimento_fundamental.json';

/// Payout a partir do qual a companhia é alta pagadora.
const _payoutAlto = 0.75;

/// Receita ÷ capital investido a partir da qual o negócio é de pouco capital.
const _vendasSobreCapital = 2.0;

/// Exercícios somados no payout, e o mínimo presente.
const _anosDoPayout = 5;
const _minimoDoPayout = 3;

/// Retornos na mediana do ROE normalizado, e o mínimo.
const _janelaDoRoe = 8;
const _minimoDoRoe = 4;

/// Anos do crescimento do setor.
const _anosDoSetor = 10;

/// Dias entre o fim do trimestre e a publicação das Contas Nacionais.
const _defasagemDoPib = 70;

/// Exercícios do crescimento realizado.
const _anosRealizados = 3;

/// A atividade do IBGE de cada setor e subsetor da B3, fixada antes de medir.
const Map<String, String> _atividade = {
  'Bens Industriais|Comércio': 'Comércio',
  'Bens Industriais|Construção e Engenharia': 'Construção',
  'Bens Industriais|Material de Transporte': 'Indústrias de transformação',
  'Bens Industriais|Máquinas e Equipamentos': 'Indústrias de transformação',
  'Bens Industriais|Serviços': 'Outras atividades de serviços',
  'Bens Industriais|Transporte': 'Transporte, armazenagem e correio',
  'Comunicações|Telecomunicações': 'Informação e comunicação',
  'Consumo Cíclico|Automóveis e Motocicletas': 'Indústrias de transformação',
  'Consumo Cíclico|Comércio': 'Comércio',
  'Consumo Cíclico|Construção Civil': 'Construção',
  'Consumo Cíclico|Diversos': 'Outras atividades de serviços',
  'Consumo Cíclico|Hoteis e Restaurantes': 'Outras atividades de serviços',
  'Consumo Cíclico|Tecidos. Vestuário e Calçados':
      'Indústrias de transformação',
  'Consumo Cíclico|Utilidades Domésticas': 'Indústrias de transformação',
  'Consumo Cíclico|Viagens e Lazer': 'Outras atividades de serviços',
  'Consumo não Cíclico|Agropecuária': 'Agropecuária - total',
  'Consumo não Cíclico|Alimentos Processados': 'Indústrias de transformação',
  'Consumo não Cíclico|Bebidas': 'Indústrias de transformação',
  'Consumo não Cíclico|Comércio e Distribuição': 'Comércio',
  'Consumo não Cíclico|Produtos de Uso Pessoal e de Limpeza':
      'Indústrias de transformação',
  'Financeiro|Exploração de Imóveis': 'Atividades imobiliárias',
  'Financeiro|Holdings Diversificadas':
      'Atividades financeiras, de seguros e serviços relacionados',
  'Financeiro|Intermediários Financeiros':
      'Atividades financeiras, de seguros e serviços relacionados',
  'Financeiro|Previdência e Seguros':
      'Atividades financeiras, de seguros e serviços relacionados',
  'Financeiro|Serviços Diversos':
      'Atividades financeiras, de seguros e serviços relacionados',
  'Financeiro|Serviços Financeiros Diversos':
      'Atividades financeiras, de seguros e serviços relacionados',
  'Materiais Básicos|Embalagens': 'Indústrias de transformação',
  'Materiais Básicos|Madeira e Papel': 'Indústrias de transformação',
  'Materiais Básicos|Materiais Diversos': 'Indústrias de transformação',
  'Materiais Básicos|Mineração': 'Indústrias extrativas',
  'Materiais Básicos|Químicos': 'Indústrias de transformação',
  'Materiais Básicos|Siderurgia e Metalurgia': 'Indústrias de transformação',
  'Petróleo. Gás e Biocombustíveis|Petróleo. Gás e Biocombustíveis':
      'Indústrias extrativas',
  'Saúde|Comércio e Distribuição': 'Comércio',
  'Saúde|Equipamentos': 'Indústrias de transformação',
  'Saúde|Medicamentos e Outros Produtos': 'Indústrias de transformação',
  'Saúde|Serv.Méd.Hospit..Análises e Diagnósticos':
      'Outras atividades de serviços',
  'Tecnologia da Informação|Computadores e Equipamentos':
      'Indústrias de transformação',
  'Tecnologia da Informação|Programas e Serviços': 'Informação e comunicação',
  'Utilidade Pública|Energia Elétrica':
      'Eletricidade e gás, água, esgoto, atividades de gestão de resíduos',
  'Utilidade Pública|Gás':
      'Eletricidade e gás, água, esgoto, atividades de gestão de resíduos',
  'Utilidade Pública|Água e Saneamento':
      'Eletricidade e gás, água, esgoto, atividades de gestão de resíduos',
};

/// Sem subsetor mapeado, o valor adicionado da economia inteira.
const _economia = 'Valor adicionado a preços básicos';

String _pct(double? v, [int casas = 2]) =>
    v == null ? '—' : '${(v * 100).toStringAsFixed(casas)}%';

double? _mediana(List<double> v) => v.isEmpty ? null : Inference.median(v);

// ---------------------------------------------------------------------------
// Fontes
// ---------------------------------------------------------------------------

/// O valor adicionado por atividade, de `tool/pib_setorial_baixar.py`.
class _PibSetorial {
  _PibSetorial(this._series);
  final Map<String, Map<DateTime, double>> _series;

  static _PibSetorial ler() {
    final f = File('data/indices/pib_setorial.json');
    if (!f.existsSync()) {
      throw StateError(
        'Falta data/indices/pib_setorial.json. Rode antes: '
        'python tool/pib_setorial_baixar.py',
      );
    }
    final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    return _PibSetorial({
      for (final e in (j['atividades'] as Map<String, dynamic>).entries)
        e.key: {
          for (final p in (e.value as List).cast<List>())
            _fimDoTrimestre(p[0] as String): (p[1] as num).toDouble(),
        },
    });
  }

  /// `201904` é o quarto trimestre de 2019; devolve o último dia dele, em UTC.
  static DateTime _fimDoTrimestre(String codigo) {
    final ano = int.parse(codigo.substring(0, 4));
    final t = int.parse(codigo.substring(4));
    return DateTime.utc(ano, t * 3 + 1, 0);
  }

  /// Crescimento anual composto das quatro últimas leituras publicadas até
  /// [data] contra as mesmas quatro, [anos] antes.
  double? crescimento(
    String atividade,
    DateTime data, {
    int anos = _anosDoSetor,
  }) {
    final s = _series[atividade];
    if (s == null) return null;
    final limite = DateTime.utc(
      data.year,
      data.month,
      data.day,
    ).subtract(const Duration(days: _defasagemDoPib));
    final publicados = s.keys.where((d) => !d.isAfter(limite)).toList()..sort();
    if (publicados.length < 4) return null;
    final ultimos = publicados.sublist(publicados.length - 4);
    var hoje = 0.0, antes = 0.0;
    for (final d in ultimos) {
      final velho = DateTime.utc(d.year - anos, d.month + 1, 0);
      final v = s[velho];
      if (v == null) return null;
      hoje += s[d]!;
      antes += v;
    }
    if (!(antes > 0) || !(hoje > 0)) return null;
    return math.pow(hoje / antes, 1 / anos).toDouble() - 1;
  }
}

/// Dividendos e JCP pagos por CNPJ e exercício, em centavos, de
/// `tool/cvm/dividendos_pagos.py`.
Map<String, Map<int, int>> _lerDividendos() {
  final f = File('data/cvm/dividendos_pagos.json');
  if (!f.existsSync()) {
    throw StateError(
      'Falta data/cvm/dividendos_pagos.json. Rode antes: '
      'python tool/cvm/dividendos_pagos.py',
    );
  }
  final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final e in (j['companhias'] as Map<String, dynamic>).entries)
      e.key: {
        for (final a in (e.value as Map<String, dynamic>).entries)
          int.parse(
            a.key,
          ): (((a.value as Map<String, dynamic>)['pago'] as num) * 100)
              .round(),
      },
  };
}

// ---------------------------------------------------------------------------
// As grandezas de cada regra, com os dados até o exercício [ano]
// ---------------------------------------------------------------------------

/// Os exercícios até [ano], um por ano (o de fim mais tardio).
List<FundamentalsSnapshot> _ate(List<FundamentalsSnapshot> fs, int ano) {
  final porAno = <int, FundamentalsSnapshot>{};
  for (final s in fs) {
    final y = s.fiscalPeriodEnd.year;
    if (y > ano) continue;
    final atual = porAno[y];
    if (atual == null || s.fiscalPeriodEnd.isAfter(atual.fiscalPeriodEnd)) {
      porAno[y] = s;
    }
  }
  return [for (final y in porAno.keys.toList()..sort()) porAno[y]!];
}

/// Mediana dos últimos [_janelaDoRoe] retornos sobre o patrimônio de abertura.
double? _roeNormalizado(List<FundamentalsSnapshot> ate) {
  final r = CapitalSeries.build(ate, ValuationLane.shareholder).returns;
  if (r.length < _minimoDoRoe) return null;
  final janela = r.sublist(math.max(0, r.length - _janelaDoRoe));
  return _mediana([for (final x in janela) x.value]);
}

/// Dividendos pagos ÷ lucro, somados nos últimos [_anosDoPayout] exercícios.
double? _payout(List<FundamentalsSnapshot> ate, Map<int, int>? pagos, int ano) {
  if (pagos == null) return null;
  var pago = 0, lucro = 0, n = 0;
  for (final s in ate) {
    final y = s.fiscalPeriodEnd.year;
    if (y <= ano - _anosDoPayout || y > ano) continue;
    final d = pagos[y];
    final l = s.netIncome;
    if (d == null || l == null || !l.isFinite) continue;
    pago += d;
    lucro += (l * 100).round();
    n++;
  }
  if (n < _minimoDoPayout || lucro <= 0) return null;
  return pago / lucro;
}

/// Receita ÷ capital investido, mediana dos três últimos exercícios.
double? _vendasPorCapital(List<FundamentalsSnapshot> ate) {
  final v = <double>[
    for (final s in ate.sublist(math.max(0, ate.length - 3)))
      if ((s.totalRevenue ?? 0) > 0 && (s.investedCapital ?? 0) > 0)
        s.totalRevenue! / s.investedCapital!,
  ];
  return v.length < 2 ? null : _mediana(v);
}

enum _Grupo { commodity, altaPagadora, poucoCapital, fundamental, semDado }

String _nomeDo(_Grupo g) => switch (g) {
  _Grupo.commodity => 'commodity',
  _Grupo.altaPagadora => 'alta pagadora',
  _Grupo.poucoCapital => 'pouco capital',
  _Grupo.fundamental => 'ROE × retenção',
  _Grupo.semDado => 'sem dado',
};

/// O que as duas propostas dão para uma companhia num exercício.
class _Leitura {
  _Leitura({
    required this.roe,
    required this.payout,
    required this.vendasPorCapital,
    required this.gFundamental,
    required this.gSetor,
    required this.atividade,
    required this.grupo,
    required this.gRegra,
  });
  final double? roe;
  final double? payout;
  final double? vendasPorCapital;
  final double? gFundamental;
  final double? gSetor;
  final String atividade;
  final _Grupo grupo;
  final double? gRegra;
}

_Leitura _ler({
  required List<FundamentalsSnapshot> fs,
  required int ano,
  required Map<int, int>? pagos,
  required bool commodity,
  required String atividade,
  required _PibSetorial pib,
  required DateTime data,
  required double inflacao,
}) {
  final ate = _ate(fs, ano);
  final roe = _roeNormalizado(ate);
  final payout = _payout(ate, pagos, ano);
  final vpc = _vendasPorCapital(ate);
  final gFund = (roe == null || payout == null)
      ? null
      : roe * (1 - payout).clamp(0.0, 1.0);
  final gSetor = pib.crescimento(atividade, data);
  final _Grupo grupo;
  final double? gRegra;
  if (commodity) {
    grupo = _Grupo.commodity;
    gRegra = inflacao;
  } else if ((payout ?? 0) >= _payoutAlto) {
    grupo = _Grupo.altaPagadora;
    gRegra = gSetor;
  } else if ((vpc ?? 0) >= _vendasSobreCapital) {
    grupo = _Grupo.poucoCapital;
    gRegra = gSetor;
  } else if (gFund != null) {
    grupo = _Grupo.fundamental;
    gRegra = gFund;
  } else {
    grupo = _Grupo.semDado;
    gRegra = null;
  }
  return _Leitura(
    roe: roe,
    payout: payout,
    vendasPorCapital: vpc,
    gFundamental: gFund,
    gSetor: gSetor,
    atividade: atividade,
    grupo: grupo,
    gRegra: gRegra,
  );
}

/// O `g` que a regra do motor dá com os dados até [ano], na via [via]: a
/// mediana das variações da base quando a dispersão a identifica; a inflação
/// quando não identifica e a retenção a financia; zero no resto (`_saida2`).
double? _gDoMotor(
  List<FundamentalsSnapshot> ate,
  ValuationLane via,
  double inflacao,
) {
  final serie = CapitalSeries.build(ate, via);
  final d = GrowthGuards.dispersion(serie);
  if (d == null) return null;
  if (d.isIdentified) return d.medianGrowth;
  final ciclo = serie.cycleReturn(window: ValuationParameters.cycleWindow);
  return GrowthGuards.anchorIsFundable(
        inflation: inflacao,
        cycleReturn: ciclo,
        observedRetention: serie.medianRetention,
      )
      ? inflacao
      : 0.0;
}

/// Crescimento anual composto dos três primeiros anos do caminho que o motor
/// projeta a partir de [g]: decai em linha reta até `g∞ = min(g, teto)`, em
/// [−5%; teto]. Composto, e não média das taxas, porque o realizado contra o
/// qual se compara também é composto.
double? _mediaDoCaminho(double g, double teto, {int anos = 10}) {
  final gInf = GrowthEstimator.perpetual(
    explicitGrowth: g,
    economyGrowth: teto,
  );
  var fator = 1.0;
  for (var t = 1; t <= _anosRealizados; t++) {
    fator *= 1 + g - (g - gInf) * ((t - 1) / (anos - 1));
  }
  // Taxa abaixo de −100% num ano não tem caminho composto: fica sem leitura.
  if (!(fator > 0)) return null;
  return math.pow(fator, 1 / _anosRealizados).toDouble() - 1;
}

/// Crescimento realizado do lucro: da média dos três exercícios até [ano] à
/// dos três seguintes, anualizado em três anos. `null` se uma média não é
/// positiva ou falta exercício.
double? _realizadoDoLucro(List<FundamentalsSnapshot> fs, int ano) {
  final porAno = {
    for (final s in _ate(fs, ano + _anosRealizados)) s.fiscalPeriodEnd.year: s,
  };
  double? media(int de, int ate) {
    final v = <double>[];
    for (var y = de; y <= ate; y++) {
      final l = porAno[y]?.netIncome;
      if (l == null || !l.isFinite) return null;
      v.add(l);
    }
    final m = v.reduce((a, b) => a + b) / v.length;
    return m > 0 ? m : null;
  }

  final antes = media(ano - 2, ano);
  final depois = media(ano + 1, ano + _anosRealizados);
  if (antes == null || depois == null) return null;
  return math.pow(depois / antes, 1 / _anosRealizados).toDouble() - 1;
}

/// Crescimento realizado do patrimônio em três exercícios.
double? _realizadoDoPatrimonio(List<FundamentalsSnapshot> fs, int ano) {
  final porAno = {
    for (final s in _ate(fs, ano + _anosRealizados)) s.fiscalPeriodEnd.year: s,
  };
  final a = porAno[ano]?.equityBookValue;
  final b = porAno[ano + _anosRealizados]?.equityBookValue;
  if (a == null || b == null || !(a > 0) || !(b > 0)) return null;
  return math.pow(b / a, 1 / _anosRealizados).toDouble() - 1;
}

// ---------------------------------------------------------------------------

class _Ativo {
  _Ativo(this.ticker, this.setor, this.leitura);
  final String ticker;
  final String setor;
  final _Leitura leitura;
  double? g0;
  ValuationLane? via;
  final Map<String, int?> justo = {};
  final Map<String, double?> potencial = {};
  double? preco;
}

Future<void> main(List<String> args) async {
  final c = await Congelado.montar();
  try {
    final ponte =
        ((jsonDecode(File('docs/validacao/ponte_cvm.json').readAsStringSync())
                    as Map<String, dynamic>)['ponte']
                as Map<String, dynamic>)
            .cast<String, String>();
    final dividendos = _lerDividendos();
    final pib = _PibSetorial.ler();
    final hoje = hojeCongelado;
    final diaDeHoje = DateTime.utc(hoje.year, hoje.month, hoje.day);
    final inflacaoHoje = c.anchors.inflationCagr;
    final tetoHoje = c.anchors.nominalEconomyGrowth;

    // -----------------------------------------------------------------------
    // 1. A entrada congelada
    // -----------------------------------------------------------------------
    final ativos = <_Ativo>[];
    final historicos = <String, List<FundamentalsSnapshot>>{};
    final cnpjDo = <String, String?>{};
    final commodityDo = <String, bool>{};
    final atividadeDo = <String, String>{};
    final avaliadasBase = <Ticker, ValuationResult?>{};
    final semMapa = <String>[];
    var i = 0;
    for (final t in c.universo) {
      i++;
      if (i % 50 == 0) stderr.write('  $i/${c.universo.length}   \r');
      final prep = await c.preparar(t);
      if (prep.isErr) continue;
      final inputs = prep.unwrap();
      final r0 = ValuationCascade.evaluate(inputs);
      avaliadasBase[t] = r0.valueOrNull;

      final classif = c.emissor(t)?.classification;
      final chave = classif == null || classif.subsector == null
          ? ''
          : '${classif.sector}|${classif.subsector}';
      final atividade = _atividade[chave] ?? _economia;
      if (!_atividade.containsKey(chave)) semMapa.add('${t.value} «$chave»');
      final commodity = CyclicalSectors.hasCyclePrecedence(
        sectorKey: inputs.sectorKey,
        industry: inputs.industry,
      );
      final cnpj = ponte[t.value];
      final ultimoAno = _ate(
        inputs.fundamentals,
        hoje.year,
      ).lastOrNull?.fiscalPeriodEnd.year;
      if (ultimoAno == null) continue;
      final leitura = _ler(
        fs: inputs.fundamentals,
        ano: ultimoAno,
        pagos: cnpj == null ? null : dividendos[cnpj],
        commodity: commodity,
        atividade: atividade,
        pib: pib,
        data: diaDeHoje,
        inflacao: inflacaoHoje,
      );
      final a = _Ativo(t.value, chave.replaceAll('|', ' / '), leitura);
      historicos[t.value] = inputs.fundamentals;
      cnpjDo[t.value] = cnpj;
      commodityDo[t.value] = commodity;
      atividadeDo[t.value] = atividade;
      a.preco = inputs.marketPrice;

      void guardar(String rotulo, Result<ValuationResult> r) {
        final v = r.valueOrNull;
        a.justo[rotulo] = v?.fairValue.cents;
        a.potencial[rotulo] = v?.upside;
      }

      guardar('motor', r0);
      a.g0 = r0.valueOrNull?.diagnostics?.growthRate;
      a.via = switch (r0.valueOrNull?.model) {
        ValuationModel.dcfFcff => ValuationLane.firm,
        ValuationModel.dcfEarnings => ValuationLane.shareholder,
        null => null,
      };
      final gF = leitura.gFundamental;
      guardar(
        'fundamental',
        gF == null
            ? r0
            : ValuationCascade.evaluate(inputs.withOverrides(growth: gF)),
      );
      final gR = leitura.gRegra;
      guardar(
        'combinada',
        gR == null
            ? r0
            : ValuationCascade.evaluate(inputs.withOverrides(growth: gR)),
      );
      ativos.add(a);
    }
    stderr.write('                    \r');
    if (semMapa.isNotEmpty) {
      stderr.writeln(
        'sem atividade mapeada (vai a economia inteira): '
        '${semMapa.join(', ')}',
      );
    }

    final divergentes = await c.conferirContraGabarito(avaliadasBase);
    if (divergentes != null && divergentes.isNotEmpty) {
      stderr.writeln(
        'ERRO: a montagem diverge do gabarito em '
        '${divergentes.length}: ${divergentes.take(8).join(', ')}',
      );
      exitCode = 1;
      return;
    }

    final variantes = ['motor', 'fundamental', 'combinada'];
    final avaliados =
        ativos.where((a) => variantes.any((v) => a.justo[v] != null)).toList()
          ..sort((x, y) => x.ticker.compareTo(y.ticker));

    stdout.writeln('-- a entrada congelada: o g de cada regra --');
    stdout.writeln(
      '  ticker   grupo            payout   ROE norm  g motor  '
      'g fund   g setor  g regra   justo motor  justo fund  justo regra   preço',
    );
    String r$(int? centavos) =>
        centavos == null ? 'recusada' : (centavos / 100).toStringAsFixed(2);
    for (final a in avaliados) {
      final l = a.leitura;
      stdout.writeln(
        '  ${a.ticker.padRight(7)}  '
        '${_nomeDo(l.grupo).padRight(15)}  ${_pct(l.payout, 0).padLeft(6)}  '
        '${_pct(l.roe, 1).padLeft(8)}  ${_pct(a.g0, 1).padLeft(7)}  '
        '${_pct(l.gFundamental, 1).padLeft(6)}  ${_pct(l.gSetor, 1).padLeft(7)}  '
        '${_pct(l.gRegra, 1).padLeft(7)}   ${r$(a.justo['motor']).padLeft(11)}  '
        '${r$(a.justo['fundamental']).padLeft(10)}  '
        '${r$(a.justo['combinada']).padLeft(11)}  '
        '${a.preco?.toStringAsFixed(2)}',
      );
    }

    final resumo = <Map<String, Object?>>[];
    stdout.writeln('');
    stdout.writeln('-- o universo com cada regra --');
    stdout.writeln(
      '  regra         avaliados  potencial mediano  acima de zero  '
      'distância mediana ao preço  justo vs motor  postos',
    );
    for (final v in variantes) {
      final com = [
        for (final a in avaliados)
          if (a.justo[v] != null) a,
      ];
      final pots = [for (final a in com) ?a.potencial[v]];
      // O logaritmo só existe com as duas pontas positivas.
      final dist = [
        for (final a in com)
          if ((a.preco ?? 0) > 0 && a.justo[v]! > 0)
            (math.log(a.justo[v]! / 100 / a.preco!)).abs(),
      ];
      final comuns = [
        for (final a in avaliados)
          if (a.justo[v] != null &&
              a.justo['motor'] != null &&
              a.potencial[v] != null &&
              a.potencial['motor'] != null)
            a,
      ];
      final variacao = [
        for (final a in comuns)
          if (a.justo['motor']! != 0) a.justo[v]! / a.justo['motor']! - 1,
      ];
      final rho = comuns.length < 3
          ? null
          : Regression.spearman(
              [for (final a in comuns) a.potencial['motor']!],
              [for (final a in comuns) a.potencial[v]!],
            );
      final medPot = _mediana(pots);
      final medDist = _mediana(dist);
      final medVar = _mediana(variacao);
      final acima = pots.where((p) => p > 0).length;
      stdout.writeln(
        '  ${v.padRight(12)}  ${com.length.toString().padLeft(9)}  '
        '${_pct(medPot, 1).padLeft(17)}  ${'$acima de ${com.length}'.padLeft(13)}  '
        '${(medDist == null ? '—' : medDist.toStringAsFixed(3)).padLeft(26)}  '
        '${_pct(medVar, 1).padLeft(14)}  ${rho?.toStringAsFixed(3) ?? '—'}',
      );
      resumo.add({
        'regra': v,
        'avaliados': com.length,
        'potencialMediano': medPot,
        'acimaDeZero': acima,
        'distanciaMedianaAoPreco': medDist,
        'justoMedianoContraMotor': medVar,
        'spearmanContraMotor': rho,
      });
    }

    // Por grupo da regra combinada.
    final porGrupo = <Map<String, Object?>>[];
    stdout.writeln('');
    stdout.writeln('-- por grupo da regra combinada --');
    for (final g in _Grupo.values) {
      final doGrupo = [
        for (final a in avaliados)
          if (a.leitura.grupo == g) a,
      ];
      if (doGrupo.isEmpty) continue;
      double? med(double? Function(_Ativo) f) =>
          _mediana([for (final a in doGrupo) ?f(a)]);
      final linha = {
        'grupo': _nomeDo(g),
        'ativos': doGrupo.length,
        'gMotor': med((a) => a.g0),
        'gFundamental': med((a) => a.leitura.gFundamental),
        'gRegra': med((a) => a.leitura.gRegra),
        'potencialMotor': med((a) => a.potencial['motor']),
        'potencialFundamental': med((a) => a.potencial['fundamental']),
        'potencialCombinada': med((a) => a.potencial['combinada']),
      };
      porGrupo.add(linha);
      stdout.writeln(
        '  ${_nomeDo(g).padRight(15)} ${doGrupo.length.toString().padLeft(3)}  '
        'g motor ${_pct(linha['gMotor'] as double?, 1)}  '
        'g fund ${_pct(linha['gFundamental'] as double?, 1)}  '
        'g regra ${_pct(linha['gRegra'] as double?, 1)}  '
        'potencial ${_pct(linha['potencialMotor'] as double?, 1)} → '
        '${_pct(linha['potencialFundamental'] as double?, 1)} / '
        '${_pct(linha['potencialCombinada'] as double?, 1)}',
      );
    }

    // -----------------------------------------------------------------------
    // 2. O histórico: qual g acertou o crescimento seguinte
    // -----------------------------------------------------------------------
    final indice = await IbovespaLongo.montar(
      c.ctx.benchmark,
      janelaDaFonte: DateRange(
        DateTime(hoje.year - 10, hoje.month, hoje.day),
        hoje,
      ),
    );
    final painel = <Map<String, Object?>>[];
    for (var ano = 2014; ano <= 2022; ano++) {
      final ancoras = (await ResolveMarketAnchors.call(
        macro: c.ctx.macro,
        benchmark: indice,
        asOf: DateTime(ano, 12, 31),
      )).unwrap();
      final inflacao = ancoras.inflationCagr;
      final teto = ancoras.nominalEconomyGrowth;
      final data = DateTime.utc(ano + 1, 3, 31);
      for (final a in avaliados) {
        final fs = historicos[a.ticker]!;
        final via = a.via ?? ValuationLane.shareholder;
        final ate = _ate(fs, ano);
        if (ate.isEmpty || ate.last.fiscalPeriodEnd.year != ano) continue;
        final gMotor = _gDoMotor(ate, via, inflacao);
        final l = _ler(
          fs: fs,
          ano: ano,
          pagos: cnpjDo[a.ticker] == null ? null : dividendos[cnpjDo[a.ticker]],
          commodity: commodityDo[a.ticker]!,
          atividade: atividadeDo[a.ticker]!,
          pib: pib,
          data: data,
          inflacao: inflacao,
        );
        final lucro = _realizadoDoLucro(fs, ano);
        final patrimonio = _realizadoDoPatrimonio(fs, ano);
        painel.add({
          'ticker': a.ticker,
          'ano': ano,
          'grupo': _nomeDo(l.grupo),
          'gMotor': gMotor == null ? null : _mediaDoCaminho(gMotor, teto),
          'gFundamental': l.gFundamental == null
              ? null
              : _mediaDoCaminho(l.gFundamental!, teto),
          'gCombinada': l.gRegra == null
              ? null
              : _mediaDoCaminho(l.gRegra!, teto),
          'realizadoLucro': lucro,
          'realizadoPatrimonio': patrimonio,
        });
      }
    }

    final testes = <Map<String, Object?>>[];
    stdout.writeln('');
    stdout.writeln(
      '-- o histórico: o g de cada regra contra o crescimento dos três '
      'exercícios seguintes (2014 a 2022) --',
    );
    stdout.writeln(
      '  alvo         regra         pares  erro absoluto mediano  '
      'viés mediano  postos',
    );
    for (final alvo in ['realizadoLucro', 'realizadoPatrimonio']) {
      // Só os pares em que as três regras existem: a comparação é no mesmo
      // conjunto.
      final pares = [
        for (final p in painel)
          if (p[alvo] != null &&
              p['gMotor'] != null &&
              p['gFundamental'] != null &&
              p['gCombinada'] != null)
            p,
      ];
      for (final regra in ['gMotor', 'gFundamental', 'gCombinada']) {
        final erros = [
          for (final p in pares) (p[regra] as double) - (p[alvo] as double),
        ];
        final abs = [for (final e in erros) e.abs()];
        final rho = pares.length < 3
            ? null
            : Regression.spearman(
                [for (final p in pares) p[regra] as double],
                [for (final p in pares) p[alvo] as double],
              );
        final linha = {
          'alvo': alvo,
          'regra': regra,
          'pares': pares.length,
          'erroAbsolutoMediano': _mediana(abs),
          'viesMediano': _mediana(erros),
          'spearman': rho,
        };
        testes.add(linha);
        stdout.writeln(
          '  ${alvo.padRight(11)}  ${regra.padRight(12)}  '
          '${pares.length.toString().padLeft(5)}  '
          '${_pct(linha['erroAbsolutoMediano'] as double?).padLeft(21)}  '
          '${_pct(linha['viesMediano'] as double?).padLeft(12)}  '
          '${rho?.toStringAsFixed(3) ?? '—'}',
        );
      }
    }

    File(_saida).writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert({
        'geradoPor': 'tool/crescimento_fundamental.dart',
        'dataDaEntrada': hoje.toIso8601String().substring(0, 10),
        'inflacao': inflacaoHoje,
        'teto': tetoHoje,
        'regras': {
          'payoutAlto': _payoutAlto,
          'vendasSobreCapital': _vendasSobreCapital,
          'anosDoPayout': _anosDoPayout,
          'janelaDoRoe': _janelaDoRoe,
          'anosDoSetor': _anosDoSetor,
        },
        'ativos': [
          for (final a in avaliados)
            {
              'ticker': a.ticker,
              'setor': a.setor,
              'atividade': a.leitura.atividade,
              'grupo': _nomeDo(a.leitura.grupo),
              'payout': a.leitura.payout,
              'roeNormalizado': a.leitura.roe,
              'vendasPorCapital': a.leitura.vendasPorCapital,
              'gMotor': a.g0,
              'gFundamental': a.leitura.gFundamental,
              'gSetor': a.leitura.gSetor,
              'gRegra': a.leitura.gRegra,
              'preco': a.preco,
              'justoCentavos': a.justo,
              'potencial': a.potencial,
            },
        ],
        'resumo': resumo,
        'porGrupo': porGrupo,
        'historico': {'testes': testes, 'painel': painel},
      }),
    );
    stdout.writeln('');
    stdout.writeln('escrito $_saida');
  } finally {
    await c.ctx.dispose();
  }
}

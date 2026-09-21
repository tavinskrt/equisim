// B19 — a rentabilidade reverte à média? Em quanto tempo, e para onde?
//
// **A pergunta que o B12 deixou.** O terminal neutro mantém, para sempre, o
// retorno que o capital instalado alcança na projeção — e medido, esse retorno
// é de 0,71 vez o custo de capital na mediana
// ([terminal_excedente.md](../docs/validacao/terminal_excedente.md)). A
// [decisão 107](../docs/decisoes/107-o-terminal-neutro-e-do-capital-novo-e-o-instalado-mantem-o-retorno-que-tem.md)
// manteve o número por não haver medição de reversão à média; trocá-lo por
// `capital_N` move +14,1% do preço justo na mediana. Esta é a medição.
//
// **Duas perguntas, e só as duas juntas decidem.**
//
//   1. **Velocidade.** O quanto da vantagem — ou da desvantagem — de um ano
//      sobrevive ao seguinte? Persistência `φ` por AR(1) sobre o spread do
//      `ROIC` contra a mediana transversal do ano, no painel inteiro e ativo a
//      ativo, com a meia-vida que ela implica.
//   2. **Destino.** Reverter **para onde**? Converger o terminal ao custo de
//      capital supõe que a rentabilidade do mercado chega lá. Se a mediana do
//      `ROIC` do universo vive abaixo do custo de capital, convergir o terminal
//      a `r` não é reversão à média — é inventar uma rentabilidade que a seção
//      transversal nunca teve.
//
// **O `ROIC` é o do motor**, de `CapitalSeries.returns`: `lucro_t ÷ base_{t−1}`,
// na convenção da via da firma, sobre a mesma série limpa que a cascata usa.
//
// Uso:
//   dart run tool/gabarito_cascata.dart      # congela a entrada
//   dart run tool/reversao_roic.dart
import 'dart:convert';
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'validation/congelado.dart';
import 'validation/regression.dart';

const _saida = 'docs/validacao/reversao_roic.json';

/// Mínimo de exercícios para um ativo entrar no AR(1) próprio.
///
/// Oito pares: abaixo disso o estimador de `φ` é dominado pelo viés de
/// pequena amostra, que é da ordem de `−(1 + 3φ)/n`.
const _minimoDePares = 8;

/// Horizontes em que o spread é seguido, em anos.
const _horizontes = [1, 3, 5, 10];

double? _mediana(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

double? _quantil(List<double> v, double p) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  return s[(p * (s.length - 1)).round()];
}

String _pc(double? v) => v == null ? '—' : '${(v * 100).toStringAsFixed(1)}%';
String _n(double? v, [int c = 3]) => v == null ? '—' : v.toStringAsFixed(c);

/// Meia-vida implícita numa persistência anual: `ln(0,5) ÷ ln(φ)`.
///
/// `null` fora de `(0, 1)`: com `φ` não positivo não há decaimento a medir, e
/// com `φ ≥ 1` não há reversão.
double? _meiaVida(double phi) {
  if (!(phi > 0 && phi < 1)) return null;
  const ln2 = 0.6931471805599453;
  return ln2 / -_ln(phi);
}

double _ln(double x) {
  // Série de Newton sobre `exp`, para não trazer `dart:math` só por um log —
  // o núcleo é puro e as ferramentas seguem a mesma economia.
  var y = 0.0;
  for (var i = 0; i < 80; i++) {
    final e = _exp(y);
    y += 2 * (x - e) / (x + e);
  }
  return y;
}

double _exp(double x) {
  var termo = 1.0, soma = 1.0;
  for (var i = 1; i < 60; i++) {
    termo *= x / i;
    soma += termo;
  }
  return soma;
}

Future<void> main() async {
  final c = await Congelado.montar();
  try {
    // --- O painel de ROIC, do mesmo jeito que a cascata o lê ---------------
    final serieDe = <String, Map<int, double>>{};
    final custoDe = <String, double>{};
    final avaliadas = <Ticker, ValuationResult?>{};
    var i = 0;
    for (final t in c.universo) {
      i++;
      if (i % 25 == 0) stderr.write('  $i/${c.universo.length}   \r');
      final prep = await c.preparar(t);
      if (prep.isErr) continue;
      final insumos = prep.unwrap();
      final r = ValuationCascade.evaluate(insumos);
      avaliadas[t] = r.valueOrNull;
      final custo = r.valueOrNull?.diagnostics?.terminalDiscountRate;
      if (custo != null) custoDe[t.value] = custo;

      final publicados =
          PointInTimeView(hojeCongelado).published(insumos.fundamentals);
      final serie = CapitalSeries.build(publicados, ValuationLane.firm);
      final retornos = serie.returns;
      if (retornos.length < 3) continue;
      serieDe[t.value] = {for (final x in retornos) x.year: x.value};
    }
    stderr.writeln('');

    final divergentes = await c.conferirContraGabarito(avaliadas);

    // --- A mediana transversal de cada ano ---------------------------------
    final anos = <int>{for (final s in serieDe.values) ...s.keys}.toList()
      ..sort();
    final medianaDoAno = <int, double>{};
    final contagemDoAno = <int, int>{};
    for (final ano in anos) {
      final xs = [
        for (final s in serieDe.values)
          if (s[ano] != null) s[ano]!,
      ];
      contagemDoAno[ano] = xs.length;
      // Anos de ponta têm poucos papéis, e uma mediana de cinco ativos não é
      // a do mercado: eles entram no painel mas não definem referência.
      if (xs.length >= 20) medianaDoAno[ano] = _mediana(xs)!;
    }

    // --- O spread contra a mediana do ano ----------------------------------
    final spread = <String, Map<int, double>>{};
    for (final e in serieDe.entries) {
      final m = <int, double>{};
      for (final x in e.value.entries) {
        final med = medianaDoAno[x.key];
        if (med == null) continue;
        m[x.key] = x.value - med;
      }
      if (m.length >= 3) spread[e.key] = m;
    }

    // --- 1. AR(1) no painel inteiro ----------------------------------------
    final x0 = <double>[];
    final x1 = <double>[];
    for (final s in spread.values) {
      for (final e in s.entries) {
        final proximo = s[e.key + 1];
        if (proximo == null) continue;
        x0.add(e.value);
        x1.add(proximo);
      }
    }
    final painel = Regression.ols([x0], x1);

    // --- 2. AR(1) ativo a ativo --------------------------------------------
    final phis = <double>[];
    final paresPorAtivo = <int>[];
    for (final s in spread.entries) {
      final a = <double>[];
      final b = <double>[];
      for (final e in s.value.entries) {
        final proximo = s.value[e.key + 1];
        if (proximo == null) continue;
        a.add(e.value);
        b.add(proximo);
      }
      if (a.length < _minimoDePares) continue;
      final ols = Regression.ols([a], b);
      if (ols == null) continue;
      phis.add(ols.coefficients[1]);
      paresPorAtivo.add(a.length);
    }

    // --- 3. O que sobra do spread depois de h anos, sem supor AR(1) --------
    //
    // A leitura direta: dos que estavam no quinto superior, quanto do spread
    // deles restava h anos depois? Não supõe forma funcional nenhuma.
    final sobrevivencia = <int, Map<String, double>>{};
    for (final h in _horizontes) {
      final pares = <({double de, double para})>[];
      for (final s in spread.entries) {
        for (final e in s.value.entries) {
          final depois = s.value[e.key + h];
          if (depois == null) continue;
          pares.add((de: e.value, para: depois));
        }
      }
      if (pares.length < 30) continue;
      final ordenados = [for (final p in pares) p.de]..sort();
      final corteAlto = _quantil(ordenados, 0.8)!;
      final corteBaixo = _quantil(ordenados, 0.2)!;
      final altos = [for (final p in pares) if (p.de >= corteAlto) p];
      final baixos = [for (final p in pares) if (p.de <= corteBaixo) p];
      double? razao(List<({double de, double para})> xs) {
        final de = _mediana([for (final x in xs) x.de]);
        final para = _mediana([for (final x in xs) x.para]);
        if (de == null || para == null || de.abs() < 1e-9) return null;
        return para / de;
      }

      sobrevivencia[h] = {
        'pares': pares.length.toDouble(),
        'spreadInicialAlto': _mediana([for (final x in altos) x.de])!,
        'spreadFinalAlto': _mediana([for (final x in altos) x.para])!,
        'sobraAlto': razao(altos) ?? double.nan,
        'spreadInicialBaixo': _mediana([for (final x in baixos) x.de])!,
        'spreadFinalBaixo': _mediana([for (final x in baixos) x.para])!,
        'sobraBaixo': razao(baixos) ?? double.nan,
      };
    }

    // --- 4. O destino: o nível do mercado contra o custo de capital --------
    final custos = custoDe.values.toList();
    final nivel = <Map<String, dynamic>>[
      for (final ano in anos)
        if (medianaDoAno[ano] != null)
          {
            'ano': ano,
            'medianaRoic': medianaDoAno[ano],
            'ativos': contagemDoAno[ano],
          },
    ];

    final resultado = {
      'medidoEm': hojeCongelado.toIso8601String().substring(0, 10),
      'conferidoContraOGabarito': divergentes?.length,
      'ativosComSerie': serieDe.length,
      'painel': {
        'pares': x0.length,
        'phi': painel?.coefficients[1],
        't': painel?.tStats[1],
        'r2': painel?.r2,
        'meiaVidaAnos':
            painel == null ? null : _meiaVida(painel.coefficients[1]),
      },
      'porAtivo': {
        'ativos': phis.length,
        'paresMedianos': _mediana([for (final x in paresPorAtivo) x.toDouble()]),
        'phiP25': _quantil(phis, 0.25),
        'phiMediano': _mediana(phis),
        'phiP75': _quantil(phis, 0.75),
      },
      // Chave em texto: o `JsonEncoder` não serializa mapa de chave inteira.
      'sobrevivenciaDoSpread': {
        for (final e in sobrevivencia.entries) '${e.key}': e.value,
      },
      'nivelDoMercado': {
        'medianaRoicPorAno': nivel,
        'medianaRoicDoPeriodo':
            _mediana([for (final e in medianaDoAno.entries) e.value]),
        'medianaCustoDeCapital': _mediana(custos),
        'ativosComCusto': custos.length,
      },
    };

    File(_saida).writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(resultado),
    );
    _imprimir(resultado, divergentes);
    stderr.writeln('\nescrito $_saida');
  } finally {
    await c.ctx.dispose();
  }
}

void _imprimir(Map<String, dynamic> r, List<String>? divergentes) {
  if (divergentes == null) {
    stdout.writeln('\n!! sem gabarito para conferir');
  } else if (divergentes.isNotEmpty) {
    stdout.writeln('\n!! a montagem DIVERGE do gabarito em '
        '${divergentes.length} ativo(s) — os números abaixo não valem');
  } else {
    stdout.writeln('\nmontagem idêntica à do gabarito.');
  }

  double? d(Map<String, dynamic> m, String k) => (m[k] as num?)?.toDouble();

  stdout.writeln('\n=== B19 — A REVERSÃO DA RENTABILIDADE À MÉDIA ===');
  stdout.writeln('ativos com série de ROIC: ${r['ativosComSerie']}');

  final p = r['painel'] as Map<String, dynamic>;
  stdout.writeln('\n-- 1. velocidade: AR(1) do spread contra a mediana do ano --');
  stdout.writeln('  painel:  φ = ${_n(d(p, 'phi'))}  t = ${_n(d(p, 't'), 1)}  '
      'R² = ${_n(d(p, 'r2'))}  pares = ${p['pares']}  '
      'meia-vida = ${_n(d(p, 'meiaVidaAnos'), 1)} anos');
  final a = r['porAtivo'] as Map<String, dynamic>;
  stdout.writeln('  por ativo (${a['ativos']} com ≥ $_minimoDePares pares, '
      'mediana de ${_n(d(a, 'paresMedianos'), 0)}): '
      'φ p25 ${_n(d(a, 'phiP25'))}  mediana ${_n(d(a, 'phiMediano'))}  '
      'p75 ${_n(d(a, 'phiP75'))}');
  final phiPainel = d(p, 'phi');
  final pares = (p['pares'] as num).toDouble();
  if (phiPainel != null && pares > 0) {
    // Viés de Kendall do AR(1): `−(1 + 3φ)/n`. No painel ele é desprezível; no
    // estimador por ativo, com dez pares, é da ordem de −0,3.
    stdout.writeln('  viés de Kendall: painel '
        '${_n(-(1 + 3 * phiPainel) / pares, 4)}  '
        'por ativo com 10 pares ${_n(-(1 + 3 * phiPainel) / 10, 3)}');
  }

  stdout.writeln('\n-- 2. o que sobra do spread, sem supor forma funcional --');
  final s = r['sobrevivenciaDoSpread'] as Map;
  for (final h in _horizontes) {
    final m = s['$h'] ?? s[h];
    if (m == null) continue;
    final mm = (m as Map).cast<String, dynamic>();
    stdout.writeln('  $h ano(s): quinto superior '
        '${_pc(d(mm, 'spreadInicialAlto'))} → ${_pc(d(mm, 'spreadFinalAlto'))} '
        '(sobra ${_n(d(mm, 'sobraAlto'), 2)})   quinto inferior '
        '${_pc(d(mm, 'spreadInicialBaixo'))} → '
        '${_pc(d(mm, 'spreadFinalBaixo'))} '
        '(sobra ${_n(d(mm, 'sobraBaixo'), 2)})   n = ${d(mm, 'pares')?.toInt()}');
  }

  final nv = r['nivelDoMercado'] as Map<String, dynamic>;
  stdout.writeln('\n-- 3. destino: reverter para onde? --');
  stdout.writeln('  ROIC mediano do universo, mediana dos anos: '
      '${_pc(d(nv, 'medianaRoicDoPeriodo'))}');
  stdout.writeln('  custo de capital de equilíbrio mediano: '
      '${_pc(d(nv, 'medianaCustoDeCapital'))} '
      '(${nv['ativosComCusto']} avaliados)');
  stdout.writeln('  por ano:');
  for (final x in (nv['medianaRoicPorAno'] as List).cast<Map>()) {
    stdout.writeln('    ${x['ano']}  ${_pc((x['medianaRoic'] as num).toDouble())}'
        '   (${x['ativos']} ativos)');
  }
}

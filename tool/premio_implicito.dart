// O prêmio de risco implícito no preço do mercado, e a versão normalizada —
// medição, sem ligar nada no motor.
//
// **A pergunta.** O prêmio histórico (`tool/premio_historico.dart`) sai
// negativo na maior parte das datas: o que aconteceu não é o que o investidor
// esperava. O método que olha para a frente é o de Damodaran: a taxa de
// retorno que faz o valor de mercado das ações igualar o dinheiro que elas vão
// distribuir, menos a taxa livre de risco.
//
// **A conta, em cada data `t`.**
//
//     P      = valor de mercado somado das companhias
//     CF₀    = dividendos e JCP pagos nos doze meses anteriores, somados
//     g      = crescimento nominal da economia na data (o teto de `g∞` do motor)
//     r      = CF₀·(1 + g) ÷ P + g                 (Gordon)
//     prêmio = (1 + r) ÷ (1 + prefixado de 10 anos) − 1
//
// O modelo de Damodaran projeta cinco anos com o crescimento dos analistas e
// depois uma perpetuidade; sem consenso de analistas, os dois estágios usam o
// mesmo `g`, e o de dois estágios colapsa no de Gordon.
//
// **A versão normalizada** é a média dos prêmios implícitos trimestrais dos
// últimos cinco e dos últimos dez anos até a data — o que suaviza o ciclo, como
// a média de dez anos que Damodaran publica ao lado do implícito do mês.
//
// **De onde vem cada peça**, em datas trimestrais desde 31/03/2011:
//
// - valor de mercado: a contagem de ações do Formulário de Referência na data,
//   corrigida pelos eventos que ele não absorveu (B30), vezes o fechamento
//   bruto do COTAHIST de cada espécie — `ValorDeMercado.naData`, o mesmo do
//   backtest;
// - caixa distribuído: os proventos em dinheiro da B3 (`data/b3/complemento`),
//   pela soma dos rendimentos de cada provento na classe mais negociada
//   (`valor ÷ preço com direito`), vezes o valor de mercado da companhia;
// - crescimento: `ResolveMarketAnchors` na data (IPCA e IBC-Br de dez anos);
// - taxa livre de risco: o prefixado de dez anos da curva do Tesouro na data.
//
// **As companhias são as listadas hoje** (as dos proventos da B3). As que saíram
// da bolsa não têm os proventos no arquivo, e somar o valor delas sem o caixa
// derrubaria o rendimento. O agregado das datas antigas é, portanto, o das
// sobreviventes — declarado no relatório.
//
//   dart run tool/premio_implicito.dart              # grava premio_implicito.json
//   dart run tool/premio_implicito.dart --so-serie   # só a série e o pacote
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

import 'b3/proventos.dart';
import 'coortes/base_da_data.dart';
import 'coortes/contagem_conferida.dart';
import 'coortes/eventos_de_acoes.dart';
import 'curva_ligar.dart' show lerTesouro;
import 'cvm/codigos_fca.dart';
import 'cvm/emissoes_fre.dart';
import 'validation/congelado.dart';
import 'validation/ibovespa_longo.dart';
import 'validation/regression.dart';

const _saida = 'docs/validacao/premio_implicito.json';

/// O pacote que o aplicativo e o backtest leem (decisão 142).
const _pacote = 'assets/mercado/premio_implicito.json';
const _referencia = CapmInputs.defaultMarketPremium;

/// Fração mínima de trimestres presentes para uma média normalizada valer.
const _coberturaMinima = 0.8;

String _pct(double v, [int casas = 2]) =>
    '${(v * 100).toStringAsFixed(casas)}%';

/// A mediana de [v], ou `null` sem valor — o JSON não grava NaN.
double? _mediana(List<double> v) {
  final o = [...v]..sort();
  if (o.isEmpty) return null;
  final m = o.length ~/ 2;
  return o.length.isOdd ? o[m] : (o[m - 1] + o[m]) / 2;
}

/// Uma entrada da contagem que o preço não confirmou, com a companhia.
typedef _Descartada = ({
  String cnpj,
  DateTime desde,
  double acoes,
  double anterior,
  String? fonte,
});

/// A contagem por data de uma listada, como veio de
/// `data/b3/listadas_contagem.json`, com a fonte de cada entrada.
class _Contagem {
  _Contagem(this.bruta, this.classes);
  final List<({DateTime desde, double acoes, String? fonte})> bruta;
  final ClassesDoCapital classes;

  static Map<String, _Contagem> ler() {
    final f = File('data/b3/listadas_contagem.json');
    if (!f.existsSync()) {
      throw StateError(
        'sem data/b3/listadas_contagem.json: rode '
        'dart run tool/b3_deslistadas_contagem.dart',
      );
    }
    return {
      for (final e
          in (jsonDecode(f.readAsStringSync()) as Map<String, dynamic>).entries)
        e.key: _Contagem(
          [
            for (final p
                in ((e.value as Map<String, dynamic>)['contagem'] as List)
                    .cast<Map<String, dynamic>>())
              (
                desde: DateTime.parse('${p['desde']}T00:00:00Z'),
                acoes: (p['acoes'] as num).toDouble(),
                fonte: p['fonte'] as String?,
              ),
          ]..sort((a, b) => a.desde.compareTo(b.desde)),
          ClassesDoCapital.fromJson(
            (e.value as Map<String, dynamic>)['classes'] as List?,
          ),
        ),
    };
  }
}

/// Uma companhia listada, com o que a conta precisa dela.
class _Companhia {
  _Companhia(
    this.cnpj,
    this.raiz,
    this.aceitas,
    this.primeiraBruta,
    this.classes,
    this.papeis,
    this.eventos,
  );
  final String cnpj;

  /// Raiz de quatro letras de hoje: é por ela que os proventos são lidos.
  final String raiz;

  /// A contagem conferida contra o preço, de `conferirContagem` (item B43).
  final List<({DateTime desde, double acoes})> aceitas;

  /// A data da primeira contagem do formulário, conferida ou não.
  final DateTime? primeiraBruta;
  final ClassesDoCapital classes;

  /// Pregões brutos de cada código de espécie, já encadeados.
  final Map<String, List<Pregao>> papeis;
  final List<ShareEvent> eventos;
}

/// O último pregão de [s] até [data], a até [folgaDoPregao] dias.
Pregao? _pregaoAte(List<Pregao> s, DateTime data) =>
    pregaoAte(s, data, folgaDias: folgaDoPregao);

/// Volume financeiro dos 21 pregões até [data].
double _financeiro(List<Pregao> s, DateTime data) {
  var soma = 0.0;
  var n = 0;
  for (var i = s.length - 1; i >= 0 && n < 21; i--) {
    if (s[i].date.isAfter(data)) continue;
    soma += s[i].financeiro ?? 0;
    n++;
  }
  return soma;
}

/// O agregado de uma data.
class _Agregado {
  _Agregado(
    this.data,
    this.valorEmCentavos,
    this.caixaEmCentavos,
    this.companhias,
    this.comProvento,
    this.maior,
    this.porCompanhia,
    this.foraPelaContagem,
  );
  final DateTime data;

  /// Valor de mercado somado, em centavos.
  final int valorEmCentavos;

  /// Dinheiro distribuído nos doze meses, somado, em centavos.
  final int caixaEmCentavos;

  /// Em reais, só para a saída.
  double get valorDeMercado => valorEmCentavos / 100;
  double get caixa => caixaEmCentavos / 100;
  final int companhias;
  final int comProvento;

  /// A companhia de maior valor na data, para conferir a escala.
  final ({String raiz, double valor})? maior;

  /// Valor e rendimento de cada companhia, para a conferência de `--datas`.
  final List<({String raiz, double valor, double rendimento})> porCompanhia;

  /// Raízes das companhias fora da soma porque a contagem da data não
  /// concorda com o preço.
  final List<String> foraPelaContagem;
  double get rendimento => caixaEmCentavos / valorEmCentavos;
}

/// O agregado da data [t].
///
/// Proventos, contagem e pregões vêm em meia-noite UTC; a data do trimestre é
/// local, como a do motor (a curva e as âncoras leem [t]). As comparações com
/// os dados da ferramenta usam o mesmo dia em UTC, [dia].
_Agregado _agregar(
  DateTime t,
  List<_Companhia> companhias,
  Map<String, List<CashDividend>> proventos,
) {
  final dia = DateTime.utc(t.year, t.month, t.day);
  // As somas em centavos inteiros: o valor de uma companhia cabe com folga
  // num `int` de 64 bits (R$ 1 trilhão são 10¹⁴ centavos).
  var valor = 0, caixa = 0;
  var n = 0, comProvento = 0;
  ({String raiz, double valor})? maior;
  final porCompanhia = <({String raiz, double valor, double rendimento})>[];
  final foraPelaContagem = <String>[];
  // Doze meses de calendário, e não 365 dias: no ano bissexto o dia do ano
  // anterior sairia da janela.
  final inicio = DateTime.utc(dia.year - 1, dia.month, dia.day);
  for (final c in companhias) {
    final acoes = acoesComEventos(c.aceitas, dia, c.eventos).acoes;
    if (acoes == null || !(acoes > 0)) {
      // Havia contagem no formulário, e nenhuma que o preço confirmasse.
      if (c.primeiraBruta != null &&
          !c.primeiraBruta!.isAfter(dia) &&
          c.papeis.values.any((s) => _pregaoAte(s, dia) != null)) {
        foraPelaContagem.add(c.raiz);
      }
      continue;
    }
    final vm = ValorDeMercado.naData(
      acoes: acoes,
      fracaoOrdinarias: c.classes.at(dia),
      papeis: c.papeis,
      data: dia,
    );
    if (vm == null || !(vm.valor > 0)) continue;

    // A classe mais negociada na data é a que dá o rendimento: dividendo por
    // ação dividido pelo preço daquela ação.
    String? principal;
    var melhor = -1.0;
    for (final e in c.papeis.entries) {
      if (_pregaoAte(e.value, dia) == null) continue;
      final f = _financeiro(e.value, dia);
      if (f > melhor) {
        melhor = f;
        principal = e.key;
      }
    }
    if (principal == null) continue;
    final classe = principal.substring(4);
    final eventos = proventosDo(proventos, '${c.raiz}$classe');
    var rendimento = 0.0;
    for (final p in eventos) {
      if (!p.exDate.isAfter(inicio) || p.exDate.isAfter(dia)) continue;
      // Preço com direito publicado pela B3; sem ele, o fechamento bruto do
      // último pregão antes da data ex — as duas grandezas na base de ações
      // da época, como o valor do provento.
      final preco =
          p.closeWithRights ??
          _pregaoAte(
            c.papeis[principal]!,
            p.exDate.subtract(const Duration(days: 1)),
          )?.close;
      if (preco == null || !(preco > 0) || !(p.amount > 0)) continue;
      rendimento += p.amount / preco;
    }
    valor += (vm.valor * 100).round();
    caixa += (rendimento * vm.valor * 100).round();
    porCompanhia.add((raiz: c.raiz, valor: vm.valor, rendimento: rendimento));
    if (maior == null || vm.valor > maior.valor) {
      maior = (raiz: c.raiz, valor: vm.valor);
    }
    n++;
    if (rendimento > 0) comProvento++;
  }
  return _Agregado(
    t,
    valor,
    caixa,
    n,
    comProvento,
    maior,
    porCompanhia,
    foraPelaContagem,
  );
}

/// O prefixado de dez anos da curva: a média geométrica dos forwards anuais.
double? _prefixado10(YieldCurve? curva) {
  if (curva == null) return null;
  final fw = curva.annualForwards(10);
  if (fw.isEmpty) return null;
  var fator = 1.0;
  for (final f in fw) {
    fator *= 1 + f;
  }
  return math.pow(fator, 1 / fw.length).toDouble() - 1;
}

/// Os trimestres do pacote gravado que a série medida agora devolve diferentes.
///
/// Compara o retorno implícito e o prefixado de cada trimestre presente nos
/// dois, com folga de 1e-9; sem pacote gravado, nada mudou.
List<String> _trimestresQueMudaram(ImpliedPremiumPackage novo) {
  final arquivo = File(_pacote);
  if (!arquivo.existsSync()) return const [];
  final gravado = ImpliedPremiumCodec.decode(
      jsonDecode(arquivo.readAsStringSync()) as Map<String, dynamic>);
  if (gravado == null) return const [];
  final porData = {for (final q in gravado.quarters) q.date: q};
  return [
    for (final q in novo.quarters)
      if (porData[q.date] case final g?)
        if ((g.impliedReturn - q.impliedReturn).abs() > 1e-9 ||
            (g.riskFree - q.riskFree).abs() > 1e-9)
          q.date.toIso8601String().substring(0, 10),
  ];
}

/// As datas: o último dia de cada trimestre, de 31/03/2011 a 30/06/2026, e a
/// data da entrada congelada.
List<DateTime> _datas() => [
  for (var ano = 2011; ano <= 2026; ano++)
    for (final mes in const [3, 6, 9, 12])
      if (!(ano == 2026 && mes > 6)) DateTime(ano, mes + 1, 0),
  hojeCongelado,
];

class _Leitura {
  _Leitura(this.rotulo, this.premio);
  final String rotulo;
  final double premio;
  final Map<String, int> justo = {};
  final Map<String, double> potencial = {};
}

Future<void> main(List<String> args) async {
  final c = await Congelado.montar();
  try {
    // -------------------------------------------------------------------
    // As companhias
    // -------------------------------------------------------------------
    final ponte =
        ((jsonDecode(File('docs/validacao/ponte_cvm.json').readAsStringSync())
                    as Map<String, dynamic>)['ponte']
                as Map<String, dynamic>)
            .cast<String, String>();
    final descartadas = <_Descartada>[];
    final contagens = _Contagem.ler();
    final fca = CodigosFca.ler();
    final proventos = lerProventos();
    final eventosDeAcoes = EventosDeAcoes.ler(emissoes: EmissoesFre.ler());

    final tickersDoCnpj = <String, Set<String>>{};
    for (final e in ponte.entries) {
      (tickersDoCnpj[e.value] ??= <String>{}).add(e.key);
    }
    final codigosDo = <String, Set<String>>{
      for (final e in tickersDoCnpj.entries)
        e.key: codigosDaCompanhia({...e.value, ...?fca.porCnpj[e.key]}),
    };
    final bruto = lerCotahistBruto({for (final s in codigosDo.values) ...s});

    final companhias = <_Companhia>[];
    var semProvento = 0, semContagem = 0;
    for (final e in tickersDoCnpj.entries) {
      final cnpj = e.key;
      final contagem = contagens[cnpj];
      if (contagem == null) {
        semContagem++;
        continue;
      }
      // A raiz dos proventos é a de hoje: entre os códigos da companhia, a que
      // tem arquivo na B3.
      final raiz = [
        for (final t in e.value.toList()..sort()) t.substring(0, 4),
      ].where(proventos.containsKey).firstOrNull;
      if (raiz == null) {
        semProvento++;
        continue;
      }
      final codigos = codigosDo[cnpj]!;
      final papeis = <String, List<Pregao>>{
        for (final cod in codigos)
          if (especieDo(cod) == Especie.ordinaria ||
              especieDo(cod) == Especie.preferencial)
            cod: encadear(cod, codigos, bruto),
      }..removeWhere((_, v) => v.isEmpty);
      if (papeis.isEmpty) continue;
      final principal = (e.value.toList()..sort()).first;
      final eventos = eventosDeAcoes.doPapel(
        cnpj: cnpj,
        ticker: principal,
        brutos: encadear(principal, codigos, bruto),
      );
      final conferida = conferirContagem(
        contagem.bruta,
        papeis.values,
        ate: DateTime.utc(
          hojeCongelado.year,
          hojeCongelado.month,
          hojeCongelado.day,
        ),
      );
      for (final d in conferida.descartadas) {
        descartadas.add((
          cnpj: cnpj,
          desde: d.desde,
          acoes: d.acoes,
          anterior: d.posterior,
          fonte: d.fonte,
        ));
      }
      companhias.add(
        _Companhia(
          cnpj,
          raiz,
          conferida.aceitas,
          contagem.bruta.firstOrNull?.desde,
          contagem.classes,
          papeis,
          eventos,
        ),
      );
    }
    stderr.writeln(
      'contagem: ${descartadas.length} entradas sem o salto do preço',
    );
    if (args.contains('--contagens')) {
      final raizDo = {for (final c in companhias) c.cnpj: c.raiz};
      for (final d in descartadas) {
        stdout.writeln(
          '  ${raizDo[d.cnpj]}  ${d.desde.toIso8601String().substring(0, 10)}  '
          '${d.anterior.toStringAsExponential(3)} -> '
          '${d.acoes.toStringAsExponential(3)}  ${d.fonte}',
        );
      }
      for (final c in companhias) {
        final a = c.aceitas;
        final grandes = [
          for (var i = 1; i < a.length; i++)
            if (a[i].acoes / a[i - 1].acoes > mudancaGrandeDaContagem ||
                a[i - 1].acoes / a[i].acoes > mudancaGrandeDaContagem)
              '${a[i].desde.toIso8601String().substring(0, 10)} ${a[i].acoes.toStringAsExponential(3)}',
        ];
        if (grandes.isNotEmpty) {
          stdout.writeln(
            '  aceita pelo salto: ${c.raiz}  ${grandes.join('; ')}',
          );
        }
      }
      return;
    }
    stderr.writeln(
      'companhias: ${companhias.length} '
      '($semProvento sem o histórico de proventos da B3, '
      '$semContagem sem contagem por data)',
    );

    final tesouro = lerTesouro('data/tesouro/precotaxatesourodireto.csv');
    final hoje = hojeCongelado;
    final indice = await IbovespaLongo.montar(
      c.ctx.benchmark,
      janelaDaFonte: DateRange(
        DateTime(hoje.year - 10, hoje.month, hoje.day),
        hoje,
      ),
    );

    // -------------------------------------------------------------------
    // O prêmio implícito em cada data
    // -------------------------------------------------------------------
    stdout.writeln('-- o prêmio implícito, data a data --');
    stdout.writeln(
      '  data        companhias  valor (R\$ bi)  rendimento  '
      'g nominal   r implícito  prefixado 10a   prêmio    r − Rf   maior     fora',
    );
    final serie = <Map<String, Object?>>[];
    final soAsDatas = [
      for (final a in args)
        if (a.startsWith('--datas='))
          for (final d in a.substring(8).split(',')) DateTime.parse(d),
    ];
    for (final t in soAsDatas.isEmpty ? _datas() : soAsDatas) {
      final a = _agregar(t, companhias, proventos);
      if (a.companhias == 0 || !(a.valorDeMercado > 0)) {
        stdout.writeln('  ${t.toIso8601String().substring(0, 10)}  sem dado');
        continue;
      }
      final ancoras = (await ResolveMarketAnchors.call(
        macro: c.ctx.macro,
        benchmark: indice,
        asOf: t,
      )).unwrap();
      final g = ancoras.nominalEconomyGrowth;
      final curva = TreasuryCurve.at(tesouro, t);
      final rf = _prefixado10(curva);
      final r = a.rendimento * (1 + g) + g;
      final premio = rf == null ? null : (1 + r) / (1 + rf) - 1;
      serie.add({
        'data': t.toIso8601String().substring(0, 10),
        'companhias': a.companhias,
        'companhiasComProvento': a.comProvento,
        'valorDeMercado': a.valorDeMercado,
        'caixaDistribuido': a.caixa,
        'rendimento': a.rendimento,
        'crescimentoNominal': g,
        'retornoImplicito': r,
        'prefixado10': rf,
        'premio': premio,
        'foraPelaContagem': a.foraPelaContagem,
        'maiorCompanhia': a.maior?.raiz,
        'fatiaDaMaior': a.maior == null
            ? null
            : a.maior!.valor / a.valorDeMercado,
        'premioComGMenos1': rf == null
            ? null
            : (1 + a.rendimento * (1 + g - 0.01) + g - 0.01) / (1 + rf) - 1,
        'premioComGMais1': rf == null
            ? null
            : (1 + a.rendimento * (1 + g + 0.01) + g + 0.01) / (1 + rf) - 1,
      });
      stdout.writeln(
        '  ${t.toIso8601String().substring(0, 10)}  '
        '${a.companhias.toString().padLeft(10)}  '
        '${(a.valorDeMercado / 1e9).toStringAsFixed(0).padLeft(13)}  '
        '${_pct(a.rendimento).padLeft(10)}  ${_pct(g).padLeft(9)}   '
        '${_pct(r).padLeft(11)}  ${(rf == null ? '—' : _pct(rf)).padLeft(13)}   '
        '${(premio == null ? '—' : _pct(premio)).padLeft(7)}   '
        '${(rf == null ? '—' : _pct(r - rf)).padLeft(7)}   '
        '${a.maior?.raiz} ${_pct(a.maior!.valor / a.valorDeMercado, 0)}   '
        '${a.foraPelaContagem.length}',
      );
      if (soAsDatas.isNotEmpty) {
        final ordem = [...a.porCompanhia]
          ..sort((x, y) => y.valor.compareTo(x.valor));
        for (final p in ordem.take(12)) {
          stdout.writeln(
            '      ${p.raiz}  R\$ ${(p.valor / 1e9).toStringAsFixed(1)} bi  '
            '${_pct(p.valor / a.valorDeMercado, 1)}  rendimento ${_pct(p.rendimento)}',
          );
        }
      }
    }

    // -------------------------------------------------------------------
    // A versão normalizada: médias de cinco e de dez anos
    // -------------------------------------------------------------------
    for (final linha in serie) {
      final t = DateTime.parse(linha['data'] as String);
      for (final anos in const [5, 10]) {
        final inicio = DateTime(t.year - anos, t.month, t.day);
        final janela = [
          for (final l in serie)
            if (DateTime.parse(l['data'] as String).isAfter(inicio) &&
                !DateTime.parse(l['data'] as String).isAfter(t) &&
                l['premio'] != null &&
                // A data congelada não é trimestre: não entra na média dos
                // trimestres, só a recebe.
                l['data'] != hoje.toIso8601String().substring(0, 10))
              l['premio'] as double,
        ];
        final esperado = anos * 4;
        linha['normalizado$anos'] = janela.length >= esperado * _coberturaMinima
            ? janela.reduce((x, y) => x + y) / janela.length
            : null;
        linha['trimestresNaMedia$anos'] = janela.length;
      }
    }

    // -------------------------------------------------------------------
    // O pacote: a série trimestral que o aplicativo e o backtest leem
    // (decisão 142). A média que o motor usa sai do núcleo, sobre `r − Rf`.
    // -------------------------------------------------------------------
    final diaDaEntrada = hoje.toIso8601String().substring(0, 10);
    final pacote = ImpliedPremiumPackage(
      geradoEm: DateTime.utc(hoje.year, hoje.month, hoje.day),
      quarters: [
        for (final l in serie)
          if (l['data'] != diaDaEntrada &&
              l['retornoImplicito'] != null &&
              l['prefixado10'] != null)
            ImpliedPremiumQuarter(
              date: DateTime.parse('${l['data']}T00:00:00Z'),
              impliedReturn: l['retornoImplicito'] as double,
              riskFree: l['prefixado10'] as double,
            ),
      ],
    );
    for (final linha in serie) {
      final t = DateTime.parse(linha['data'] as String);
      final r = linha['retornoImplicito'] as double?;
      final rf = linha['prefixado10'] as double?;
      linha['premioSomado'] = (r == null || rf == null) ? null : r - rf;
      linha['premioDoMotor'] = pacote.normalizedAt(t);
      linha['trimestresDoMotor'] = pacote.window(t).length;
      // A média de cinco anos na mesma forma, só para comparação.
      final cinco = [
        for (final q in pacote.quarters)
          if (q.date.isAfter(DateTime.utc(t.year - 5, t.month, t.day)) &&
              !q.date.isAfter(DateTime.utc(t.year, t.month, t.day)))
            q.premium,
      ];
      linha['premioSomado5'] = cinco.length >= 20 * _coberturaMinima
          ? cinco.reduce((x, y) => x + y) / cinco.length
          : null;
    }
    if (soAsDatas.isEmpty) {
      // **O passado não muda em silêncio** (item B48). Um trimestre já gravado
      // é fato histórico; se a série medida agora o devolve diferente, a causa
      // é dado que mudou por baixo — em 02/10/2026, as âncoras de 2011 e 2012
      // dependiam de a rede devolver o IBC-Br anterior à entrada congelada, e
      // sem ela o crescimento caía no recuo de 2026. Só regrava com
      // `--aceitar-mudanca-do-passado`, depois de entender a diferença.
      final mudou = _trimestresQueMudaram(pacote);
      if (mudou.isNotEmpty && !args.contains('--aceitar-mudanca-do-passado')) {
        stderr.writeln(
          'ERRO: ${mudou.length} trimestre(s) já gravado(s) em $_pacote mudaram '
          '(${mudou.take(6).join(', ')}${mudou.length > 6 ? '…' : ''}); o pacote '
          'não foi regravado. Confira a causa e, se a mudança for intencional, '
          'rode de novo com --aceitar-mudanca-do-passado.',
        );
        exitCode = 1;
        return;
      }
      File(_pacote).writeAsStringSync(
        jsonEncode(ImpliedPremiumCodec.encode(pacote)),
      );
      stdout.writeln(
        'escrito $_pacote: ${pacote.quarters.length} trimestres; o prêmio do '
        'motor em $diaDaEntrada é ${_pct(pacote.normalizedAt(hoje) ?? double.nan)}',
      );
    }

    stdout.writeln('');
    // Na forma que o motor soma (`r − Rf`); as médias da forma de Fisher
    // ficam no JSON (`normalizado5`, `normalizado10`).
    stdout.writeln('-- implícito e normalizado nas datas das coortes (r − Rf) --');
    stdout.writeln('  data        implícito   média 5 anos   média 10 anos (o motor)');
    for (final l in serie) {
      final d = DateTime.parse(l['data'] as String);
      if (d.year < 2018) continue;
      String f(Object? v) => v == null ? '—' : _pct(v as double);
      stdout.writeln(
        '  ${l['data']}  ${f(l['premioSomado']).padLeft(9)}   '
        '${f(l['premioSomado5']).padLeft(12)}   ${f(l['premioDoMotor']).padLeft(13)}',
      );
    }

    if (args.contains('--so-serie')) return;

    // -------------------------------------------------------------------
    // O que cada um faz ao aplicativo, sobre a entrada congelada
    // -------------------------------------------------------------------
    final daEntrada = serie.lastWhere((l) => l['data'] == diaDaEntrada);
    final doMotor = pacote.normalizedAt(hoje);
    if (doMotor == null) {
      stderr.writeln('ERRO: a série não tem trimestres para a média de dez anos');
      exitCode = 1;
      return;
    }
    // A montagem do aplicativo lê o pacote que estava em disco quando a
    // entrada congelada foi montada; se a série medida agora for outra, a
    // conferência contra o gabarito compararia montagens diferentes.
    if ((c.premio.valor - doMotor).abs() > 1e-12) {
      stderr.writeln(
        'ERRO: o pacote em disco dava ${_pct(c.premio.valor)} e a série medida '
        'agora dá ${_pct(doMotor)}. O pacote foi regravado: rode de novo, e '
        'regrave o gabarito antes (tool/gabarito_cascata.dart).',
      );
      exitCode = 1;
      return;
    }
    // A média de cinco anos, na mesma forma `r − Rf`, para comparação.
    final cincoAnos = [
      for (final q in pacote.quarters)
        if (q.date.isAfter(DateTime.utc(hoje.year - 5, hoje.month, hoje.day)))
          q.premium,
    ];
    final candidatos = <(String, double?)>[
      // A primeira é a do aplicativo (`premio` nulo: o do pacote), e é a que
      // se confere contra o gabarito.
      ('média de 10 anos — o motor', null),
      ('5,5% (até a decisão 142)', _referencia),
      if (daEntrada['premioSomado'] case final double p) ('implícito', p),
      if (cincoAnos.length >= 20)
        ('média de 5 anos', cincoAnos.reduce((a, b) => a + b) / cincoAnos.length),
    ];
    final leituras = <_Leitura>[];
    for (final (rotulo, premio) in candidatos) {
      final l = _Leitura(rotulo, premio ?? doMotor);
      final avaliadas = <Ticker, ValuationResult?>{};
      var i = 0;
      for (final t in c.universo) {
        i++;
        if (i % 50 == 0) {
          stderr.write('  $rotulo: $i/${c.universo.length}   \r');
        }
        final prep = await c.preparar(t, premio: premio);
        if (prep.isErr) continue;
        final r = ValuationCascade.evaluate(prep.unwrap());
        if (identical(rotulo, candidatos.first.$1)) {
          avaliadas[t] = r.valueOrNull;
        }
        if (r.isErr) continue;
        l.justo[t.value] = r.unwrap().fairValue.cents;
        l.potencial[t.value] = r.unwrap().upside;
      }
      if (identical(rotulo, candidatos.first.$1)) {
        final div = await c.conferirContraGabarito(avaliadas);
        if (div != null && div.isNotEmpty) {
          stderr.writeln(
            'ERRO: a montagem do aplicativo diverge do gabarito em '
            '${div.length}: ${div.take(8).join(', ')}',
          );
          exitCode = 1;
          return;
        }
      }
      leituras.add(l);
    }
    stderr.write('                                        \r');

    final base = leituras.first;
    final efeitos = <Map<String, Object?>>[];
    stdout.writeln('');
    stdout.writeln('-- o universo reavaliado sobre a entrada congelada --');
    stdout.writeln(
      '  prêmio                  avaliados   potencial mediano   '
      'acima de zero   preço justo vs o motor   postos',
    );
    for (final l in leituras) {
      final pots = l.potencial.values.toList();
      final comuns = l.justo.keys.where(base.justo.containsKey).toList()
        ..sort();
      final variacao = <double>[
        for (final k in comuns)
          if (base.justo[k]! != 0) l.justo[k]! / base.justo[k]! - 1,
      ];
      final rho = comuns.length < 3
          ? null
          : Regression.spearman(
              [for (final k in comuns) base.potencial[k]!],
              [for (final k in comuns) l.potencial[k]!],
            );
      final acima = pots.where((p) => p > 0).length;
      final medPot = _mediana(pots);
      final medVar = _mediana(variacao);
      stdout.writeln(
        '  ${'${l.rotulo} (${_pct(l.premio)})'.padRight(24)}'
        '${l.justo.length.toString().padLeft(9)}   '
        '${(medPot == null ? '—' : _pct(medPot)).padLeft(17)}   '
        '${'$acima de ${pots.length}'.padLeft(13)}   '
        '${(medVar == null ? '—' : _pct(medVar)).padLeft(19)}   '
        '${rho == null ? '—' : rho.toStringAsFixed(3)}',
      );
      efeitos.add({
        'rotulo': l.rotulo,
        'premio': l.premio,
        'avaliados': l.justo.length,
        'potencialMediano': medPot,
        'acimaDeZero': acima,
        'precoJustoMedianoContraReferencia': medVar,
        'spearmanContraReferencia': rho,
        'casos': {
          for (final t in const ['WEGE3', 'ITUB4', 'VALE3', 'SAPR11', 'RENT3'])
            t: {'justoCentavos': l.justo[t], 'potencial': l.potencial[t]},
        },
      });
    }

    File(_saida).writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert({
        'geradoPor': 'tool/premio_implicito.dart',
        'dataDaEntrada': hoje.toIso8601String().substring(0, 10),
        'companhias': companhias.length,
        'contagensSemSalto': [
          for (final d in descartadas)
            {
              'cnpj': d.cnpj,
              'desde': d.desde.toIso8601String().substring(0, 10),
              'acoes': d.acoes,
              'anterior': d.anterior,
              'fonte': d.fonte,
            },
        ],
        'serie': serie,
        'efeitos': efeitos,
      }),
    );
    stdout.writeln('');
    stdout.writeln('escrito $_saida');
  } finally {
    await c.ctx.dispose();
  }
}

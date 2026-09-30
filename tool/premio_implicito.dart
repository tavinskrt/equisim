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
//   dart run tool/premio_implicito.dart --so-serie   # só a série, sem gravar
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

import 'b3/proventos.dart';
import 'coortes/base_da_data.dart';
import 'coortes/eventos_de_acoes.dart';
import 'curva_ligar.dart' show lerTesouro;
import 'cvm/codigos_fca.dart';
import 'cvm/emissoes_fre.dart';
import 'validation/congelado.dart';
import 'validation/ibovespa_longo.dart';
import 'validation/regression.dart';

const _saida = 'docs/validacao/premio_implicito.json';
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

/// Mudança de contagem, em vezes, a partir da qual o preço tem de confirmá-la.
const _mudancaGrande = 3.0;

/// Dias depois da contagem nova em que o salto do preço ainda a confirma: a
/// aprovação do desdobramento vem meses antes da data ex (a da PRIO, de
/// 28/01/2021, para a data ex de 06/05/2021). É o prazo do B30.
const _prazoDoSalto = 400;

/// Folga, em vezes, entre o salto do preço e o inverso da mudança da contagem.
const _toleranciaDoSalto = 1.4;

/// Uma entrada da contagem que o preço não confirmou.
typedef _Descartada = ({
  String cnpj,
  DateTime desde,
  double acoes,
  double anterior,
  String? fonte,
});

/// Se a consulta de proventos da B3 de [raiz] falhou sem erro.
///
/// A consulta é pelo nome de pregão, e o nome com barra — `AMBEV S/A`,
/// `KLABIN S/A` — volta vazio: os nove emissores com barra no nome vieram sem
/// provento nenhum, e nenhum com barra veio com provento. Vazio, ali, é falta
/// do dado, e não companhia que não pagou: somá-la com caixa zero derrubaria o
/// rendimento.
bool _consultaFalhou(String raiz) {
  final f = File('data/b3/complemento/$raiz.json');
  if (!f.existsSync()) return true;
  final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  final nome =
      ((j['detalhe'] as Map<String, dynamic>?)?['tradingName'] as String?) ??
      '';
  return ((j['proventos'] as List?) ?? const []).isEmpty && nome.contains('/');
}

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

/// O primeiro pregão entre [de] e [ate] em que o preço bruto de algum papel
/// saltou [fator] vezes, com folga de [_toleranciaDoSalto].
DateTime? _saltoDoPreco(
  Map<String, List<Pregao>> papeis,
  double fator,
  DateTime de,
  DateTime ate,
) {
  final alvo = math.log(fator);
  final folga = math.log(_toleranciaDoSalto);
  DateTime? primeiro;
  for (final s in papeis.values) {
    for (var i = 1; i < s.length; i++) {
      final a = s[i - 1], b = s[i];
      if (b.date.isBefore(de) || b.date.isAfter(ate)) continue;
      if (b.date.difference(a.date).inDays > 30) continue;
      if (!(a.close > 0) || !(b.close > 0)) continue;
      if ((math.log(b.close / a.close) - alvo).abs() >= folga) continue;
      if (primeiro == null || b.date.isBefore(primeiro)) primeiro = b.date;
      break;
    }
  }
  return primeiro;
}

/// A contagem conferida contra o preço, em ordem de data.
///
/// **Por que conferir.** A contagem do formulário erra de escala nos dois
/// sentidos. A correção reenviada às vezes repete a contagem de antes de um
/// grupamento: a Ampla agrupou 40.000 para 1 em dezembro de 2015, e a correção
/// de maio de 2016 volta aos 3,9 trilhões de ações — vezes o preço de depois,
/// R$ 142 trilhões de valor de mercado. E às vezes a correção é o **único**
/// registro de um grupamento de verdade: a Magazine Luiza agrupou 10 para 1 em
/// 2024, e a contagem só cai de 7,39 bilhões para 739 milhões na correção de
/// maio de 2025. A fonte da entrada não separa os dois casos; o preço separa.
///
/// **A regra.** Parte da contagem mais recente até [ate] e anda para trás. Cada
/// entrada é comparada com a última aceita depois dela: a diferença de até
/// [_mudancaGrande] vezes vale como veio (emissão, recompra, conversão); a
/// maior só vale se o preço bruto deu o salto correspondente — grupamento de
/// dez para um, preço dez vezes maior — entre a data da entrada e
/// [_prazoDoSalto] dias depois da aceita, e a aceita passa a valer **no dia do
/// salto**, para que ação e preço mudem de base juntos. Se o salto veio antes da
/// entrada, ela repete a contagem de antes do evento, e não vale. Sem o salto, a entrada vai para
/// [descartadas] e o trecho dela fica com a contagem anterior a ela.
///
/// A âncora é a contagem mais recente porque é a que o formulário de hoje
/// confirma: a primeira da série não tem com quem ser comparada, e a da TIM
/// começa em julho de 2020 com 423 milhões — a da TIM S.A. antes da
/// incorporação —, contra os 2,42 bilhões que a ação tem desde então.
List<({DateTime desde, double acoes})> _conferida(
  String cnpj,
  _Contagem contagem,
  Map<String, List<Pregao>> papeis,
  DateTime ate,
  List<_Descartada> descartadas,
) {
  final entradas = [
    for (final p in contagem.bruta)
      if (p.acoes > 0 && !p.desde.isAfter(ate)) p,
  ];
  // Da mais recente para a mais antiga; `desde` da aceita pode recuar ao dia
  // do salto do preço.
  final aceitas = <({DateTime desde, double acoes})>[];
  DateTime? dataDaAceita;
  for (final p in entradas.reversed) {
    if (aceitas.isEmpty || dataDaAceita == null) {
      aceitas.add((desde: p.desde, acoes: p.acoes));
      dataDaAceita = p.desde;
      continue;
    }
    final posterior = aceitas.last;
    final mudanca = posterior.acoes / p.acoes;
    if (mudanca <= _mudancaGrande && mudanca >= 1 / _mudancaGrande) {
      aceitas.add((desde: p.desde, acoes: p.acoes));
      dataDaAceita = p.desde;
      continue;
    }
    final salto = _saltoDoPreco(
      papeis,
      1 / mudanca,
      p.desde,
      dataDaAceita.add(const Duration(days: _prazoDoSalto)),
    );
    if (salto == null) {
      descartadas.add((
        cnpj: cnpj,
        desde: p.desde,
        acoes: p.acoes,
        anterior: posterior.acoes,
        fonte: p.fonte,
      ));
      continue;
    }
    // As entradas da contagem nova anteriores ao salto — a aprovação costuma
    // vir antes da data ex — passam a valer no dia dele.
    var daNova = posterior.acoes;
    while (aceitas.isNotEmpty && aceitas.last.desde.isBefore(salto)) {
      daNova = aceitas.removeLast().acoes;
    }
    aceitas
      ..add((desde: salto, acoes: daNova))
      ..add((desde: p.desde, acoes: p.acoes));
    dataDaAceita = p.desde;
  }
  return aceitas.reversed.toList();
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

  /// A contagem conferida contra o preço, de [_conferida].
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
      if (raiz == null || _consultaFalhou(raiz)) {
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
      companhias.add(
        _Companhia(
          cnpj,
          raiz,
          _conferida(
            cnpj,
            contagem,
            papeis,
            DateTime.utc(
              hojeCongelado.year,
              hojeCongelado.month,
              hojeCongelado.day,
            ),
            descartadas,
          ),
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
            if (a[i].acoes / a[i - 1].acoes > _mudancaGrande ||
                a[i - 1].acoes / a[i].acoes > _mudancaGrande)
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
      'g nominal   r implícito  prefixado 10a   prêmio   maior     fora',
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

    stdout.writeln('');
    stdout.writeln('-- implícito e normalizado nas datas das coortes --');
    stdout.writeln('  data        implícito   média 5 anos   média 10 anos');
    for (final l in serie) {
      final d = DateTime.parse(l['data'] as String);
      if (d.year < 2018) continue;
      String f(Object? v) => v == null ? '—' : _pct(v as double);
      stdout.writeln(
        '  ${l['data']}  ${f(l['premio']).padLeft(9)}   '
        '${f(l['normalizado5']).padLeft(12)}   ${f(l['normalizado10']).padLeft(13)}',
      );
    }

    if (args.contains('--so-serie')) return;

    // -------------------------------------------------------------------
    // O que cada um faz ao aplicativo, sobre a entrada congelada
    // -------------------------------------------------------------------
    final daEntrada = serie.lastWhere(
      (l) => l['data'] == hoje.toIso8601String().substring(0, 10),
    );
    final candidatos = <(String, double)>[
      ('5,5% fixo', _referencia),
      if (daEntrada['premio'] case final double p) ('implícito', p),
      if (daEntrada['normalizado5'] case final double p) ('média 5 anos', p),
      if (daEntrada['normalizado10'] case final double p) ('média 10 anos', p),
    ];
    final leituras = <_Leitura>[];
    for (final (rotulo, premio) in candidatos) {
      final l = _Leitura(rotulo, premio);
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
            'ERRO: a montagem de 5,5% diverge do gabarito em '
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
      'acima de zero   preço justo vs 5,5%   postos',
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

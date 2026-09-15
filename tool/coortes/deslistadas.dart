// As companhias deslistadas, prontas para entrar nas coortes (item C1b).
//
// Tudo o que o A3.4 deixou em `data/b3/deslistadas_contagem.json` — contagem de
// ações por data, eventos localizados no preço, eventos não localizados e
// proventos —, mais o fechamento e o volume do COTAHIST filtrados pelo ISIN do
// papel, os documentos da CVM pelo CNPJ e o setor: o da B3, quando o portal
// responde para a companhia, e o representante do setor de atividade da FCA
// (`setor_cvm.dart`) quando não responde.
//
// **Uma coorte vê só o que existia na data dela.** O preço é ajustado pelos
// eventos com data ex até o fim da janela pedida, e não pelos posteriores; a
// contagem é a vigente na data; a CVM é a recebida até ali.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

import '../b3/proventos.dart';
import '../cvm/documentos.dart';
import '../cvm/setor_cvm.dart';
import 'base_da_data.dart';

/// Um papel de companhia deslistada.
class PapelDeslistado {
  final Ticker ticker;
  final String cnpj;
  final String nome;

  /// Pregões brutos do COTAHIST, com volume financeiro.
  final List<Pregao> pregoes;

  /// Eventos localizados no preço e inferidos, um por data ex.
  final List<ShareEvent> eventos;

  /// Aprovações de evento declarado com pregão e sem data ex no preço.
  final List<DateTime> naoLocalizados;

  /// Contagem total de ações, em ordem de vigência.
  final List<({DateTime desde, double acoes})> contagem;

  /// Proventos da classe do papel.
  final List<CashDividend> proventos;

  final B3Classification? classificacao;

  /// `b3`, `cvm` ou `nenhuma`.
  final String origemDoSetor;

  /// Eventos descartados por dividirem a data ex com outro mais próximo do
  /// preço observado.
  final int eventosDuplicados;

  /// Divisão do capital entre ordinárias e preferenciais (item C3).
  final ClassesDoCapital classes;

  PapelDeslistado({
    required this.ticker,
    required this.cnpj,
    required this.nome,
    required this.pregoes,
    required this.eventos,
    required this.naoLocalizados,
    required this.contagem,
    required this.proventos,
    required this.classificacao,
    required this.origemDoSetor,
    required this.eventosDuplicados,
    required this.classes,
  });

  /// Contagem vigente em [data], ou `null` antes do primeiro ponto.
  double? acoesEm(DateTime data) {
    final dia = DateTime.utc(data.year, data.month, data.day);
    double? ultima;
    for (final p in contagem) {
      if (p.desde.isAfter(dia)) break;
      ultima = p.acoes;
    }
    return ultima;
  }

  /// Série de preço na base de [ate]: eventos com data ex depois dele não
  /// ajustam, porque não tinham acontecido. O volume vira ações, para que
  /// `fechamento × volume` continue sendo o financeiro do dia.
  PriceSeries serie(DateRange janela, {required DateTime ate}) {
    final fim = DateTime.utc(ate.year, ate.month, ate.day);
    final eventosAte = [
      for (final e in eventos)
        if (!e.exDate.isAfter(fim)) e,
    ];
    final pontos = <PricePoint>[];
    for (final p in pregoes) {
      if (!janela.contains(p.date)) continue;
      var c = p.close;
      for (final e in eventosAte) {
        if (p.date.isBefore(e.exDate)) c /= e.factor;
      }
      final fin = p.financeiro;
      pontos.add(PricePoint(
        date: p.date,
        close: c,
        volume: (fin == null || c <= 0) ? null : fin / c,
      ));
    }
    return PriceSeries(ticker: ticker, points: pontos);
  }

  /// Maior razão entre pregões vizinhos que a série ajustada ainda pode ter
  /// sem ser tratada como evento que escapou.
  static const double saltoMaximo = 3.0;

  /// Distância máxima, em dias corridos, entre os dois pregões do salto: além
  /// disso é suspensão, e o preço de volta é o que o papel passou a valer.
  static const int diasDoSalto = 90;

  /// Pregões em que a série **já ajustada** muda mais de [saltoMaximo] vezes
  /// em relação ao pregão anterior, a até [diasDoSalto] dias dele.
  ///
  /// São os eventos que o FRE não declarou e o preço não permitiu inferir —
  /// o grupamento de 2024 da KRSA3 e da NGRD3, a TOYB3 dividida por 270 mil
  /// em 2015 —, e a série não está ajustada por eles. O ajuste divide todos os
  /// pregões antes da data ex pelo mesmo fator, então a razão entre vizinhos
  /// não depende da base: a lista vale para qualquer data de coorte.
  late final List<DateTime> saltos = () {
    final s = serie(DateRange(DateTime.utc(1990), DateTime.utc(2100)),
            ate: DateTime.utc(2100))
        .points;
    return [
      for (var i = 1; i < s.length; i++)
        if (s[i - 1].close > 0 &&
            s[i].close > 0 &&
            s[i].date.difference(s[i - 1].date).inDays <= diasDoSalto &&
            (math.log(s[i].close / s[i - 1].close)).abs() >
                math.log(saltoMaximo))
          s[i].date,
    ];
  }();

  /// `true` quando algum evento não localizado cai em `[de, ate]`.
  bool eventoNaoLocalizadoEntre(DateTime de, DateTime ate) =>
      naoLocalizados.any((d) => !d.isBefore(de) && !d.isAfter(ate));

  /// `true` quando `(de, ate]` atravessa evento não localizado ou salto: a
  /// série não estaria ajustada por ele, e a janela sai.
  bool janelaSuspeita(DateTime de, DateTime ate) =>
      eventoNaoLocalizadoEntre(de, ate) ||
      saltos.any((d) => d.isAfter(de) && !d.isAfter(ate));
}

class Deslistadas {
  Deslistadas._(this.papeis, this.documentos, this.setorCvm);

  final Map<String, PapelDeslistado> papeis;

  /// Papéis de cada companhia, para o valor de mercado espécie a espécie.
  late final Map<String, List<PapelDeslistado>> porCnpj = () {
    final out = <String, List<PapelDeslistado>>{};
    for (final p in papeis.values) {
      (out[p.cnpj] ??= []).add(p);
    }
    return out;
  }();

  /// Valor de mercado da companhia de [papel] em [data], com os papéis dela e a
  /// contagem da data (item C3). `null` sem contagem ou sem papel de espécie
  /// negociando.
  ValorDeMercado? valorDeMercado(PapelDeslistado papel, DateTime data) {
    final acoes = papel.acoesEm(data);
    if (acoes == null) return null;
    return ValorDeMercado.naData(
      acoes: acoes,
      fracaoOrdinarias: papel.classes.at(data),
      papeis: {
        for (final p in porCnpj[papel.cnpj] ?? [papel])
          p.ticker.value: p.pregoes,
      },
      data: data,
    );
  }

  /// Documentos da CVM por ticker de deslistada.
  final Map<String, List<CvmPeriodDocument>> documentos;

  final SetorCvm? setorCvm;

  static DateTime _dia(String s) => DateTime.parse('${s.substring(0, 10)}T00:00:00Z');

  /// Lê as deslistadas. `null` sem os arquivos do A3.4.
  ///
  /// - [classificacaoListadas]: CNPJ da listada → classificação da B3, para
  ///   medir o setor da CVM.
  static Deslistadas? ler(Map<String, B3Classification> classificacaoListadas) {
    final ponteArq = File('data/b3/ponte_deslistadas.json');
    final contagemArq = File('data/b3/deslistadas_contagem.json');
    if (!ponteArq.existsSync() || !contagemArq.existsSync()) return null;
    final ponte = (jsonDecode(ponteArq.readAsStringSync()) as Map<String, dynamic>)
        .cast<String, Map<String, dynamic>>();
    final a34 = (jsonDecode(contagemArq.readAsStringSync()) as Map<String, dynamic>)
        .cast<String, Map<String, dynamic>>();
    final setorCvm = SetorCvm.ler(classificacaoListadas);

    final isins = <String, String>{};
    final tickersPorCnpj = <String, List<String>>{};
    for (final e in ponte.entries) {
      final papeis = (e.value['papeis'] as Map<String, dynamic>);
      for (final p in papeis.entries) {
        if (Ticker.tryParse(p.key) == null) continue;
        isins[p.key] = (p.value as Map<String, dynamic>)['isin'] as String;
        (tickersPorCnpj[e.key] ??= []).add(p.key);
      }
    }
    final cotahist = lerCotahistBruto(isins.keys.toSet(), isins: isins);
    final documentos = carregarDocumentos('data/cvm_exercicios.json',
        soTickers: isins.keys.toSet(), tickersPorCnpj: tickersPorCnpj);

    final papeis = <String, PapelDeslistado>{};
    for (final e in tickersPorCnpj.entries) {
      final cnpj = e.key;
      final registro = a34[cnpj];
      if (registro == null) continue;
      final contagem = [
        for (final p in (registro['contagem'] as List).cast<Map<String, dynamic>>())
          (desde: _dia(p['desde'] as String), acoes: (p['acoes'] as num).toDouble()),
      ]..sort((a, b) => a.desde.compareTo(b.desde));
      if (contagem.isEmpty) continue;

      final arquivo = File('data/b3/complemento_deslistadas/'
          '${cnpj.replaceAll(RegExp(r'[./-]'), '')}.json');
      final complemento = arquivo.existsSync()
          ? jsonDecode(arquivo.readAsStringSync()) as Map<String, dynamic>
          : const <String, dynamic>{};
      final daB3 = B3Classification.parse(
          (complemento['detalhe'] as Map<String, dynamic>?)?['industryClassification']);
      final daCvm = daB3 == null ? setorCvm?.classificacaoDe(cnpj) : null;

      for (final t in e.value) {
        final dados = (registro['papeis'] as Map<String, dynamic>)[t]
            as Map<String, dynamic>?;
        final pregoes = cotahist[t];
        if (dados == null || pregoes == null || pregoes.length < 2) continue;

        // Eventos de mesma data ex: fica o que o preço observado explica.
        final porData = <DateTime, List<double>>{};
        for (final ev in (dados['eventos'] as List).cast<Map<String, dynamic>>()) {
          (porData[_dia(ev['dataEx'] as String)] ??= [])
              .add((ev['fator'] as num).toDouble());
        }
        var duplicados = 0;
        final eventos = <ShareEvent>[];
        for (final d in porData.entries) {
          final observado = _razaoNaData(pregoes, d.key);
          var melhor = d.value.first;
          if (d.value.length > 1 && observado != null) {
            for (final f in d.value) {
              if ((math.log(f) - math.log(observado)).abs() <
                  (math.log(melhor) - math.log(observado)).abs()) {
                melhor = f;
              }
            }
          }
          duplicados += d.value.length - 1;
          eventos.add(ShareEvent(
              exDate: d.key, factor: melhor, observedRatio: observado ?? melhor));
        }
        eventos.sort((a, b) => a.exDate.compareTo(b.exDate));

        final classe = B3CashDividends.shareClassOf(t);
        final proventos = <CashDividend>[
          for (final p in (dados['proventos'] as List).cast<Map<String, dynamic>>())
            if (classe != null)
              CashDividend(
                shareClass: classe,
                kind: CashDividendKind.values.byName(p['tipo'] as String),
                // A data com é o pregão anterior à ex; a conta do retorno total
                // só usa a data ex e o preço com direito.
                lastDateWithRights:
                    _dia(p['dataEx'] as String).subtract(const Duration(days: 1)),
                exDate: _dia(p['dataEx'] as String),
                amount: (p['valor'] as num).toDouble(),
                closeWithRights: (p['precoComDireito'] as num?)?.toDouble(),
              ),
        ];

        papeis[t] = PapelDeslistado(
          ticker: Ticker.parse(t),
          cnpj: cnpj,
          nome: (ponte[cnpj]?['nome'] as String?) ?? t,
          pregoes: pregoes,
          eventos: eventos,
          naoLocalizados: [
            for (final d in (dados['eventosNaoLocalizados'] as List).cast<String>())
              _dia(d),
          ],
          contagem: contagem,
          proventos: proventos,
          classificacao: daB3 ?? daCvm,
          origemDoSetor: daB3 != null ? 'b3' : (daCvm != null ? 'cvm' : 'nenhuma'),
          eventosDuplicados: duplicados,
          classes: ClassesDoCapital.fromJson(registro['classes'] as List?),
        );
      }
    }
    return Deslistadas._(papeis, documentos, setorCvm);
  }

  /// `P_anterior / P_ex` na data ex: o fator que o preço observou.
  static double? _razaoNaData(List<Pregao> s, DateTime ex) {
    for (var i = 1; i < s.length; i++) {
      if (s[i].date.isAtSameMomentAs(ex)) {
        final a = s[i - 1].close, b = s[i].close;
        return (a > 0 && b > 0) ? a / b : null;
      }
    }
    return null;
  }
}

/// Fundamentos de uma deslistada numa data de coorte.
///
/// A CVM dá as demonstrações; o que ela não dá — valor de mercado e contagem,
/// que a decisão 70 manda nunca tirar dela — vem de exercícios de mercado
/// sintéticos, um por DFP recebida até a data: a contagem do FRE no fim do
/// exercício, a contagem vigente na data e o valor de mercado da companhia na
/// data. É a mesma reconstrução que a coorte faz com as listadas, cuja fonte
/// repete o valor de mercado de hoje em todo exercício.
///
/// **O valor de mercado é o da companhia, espécie a espécie** (item C3), e não
/// `contagem × preço do papel`, que dava razão de unidade 1 por construção. Sem
/// ele, recua para o produto.
class FundamentosDeslistada implements FundamentalsRepository {
  FundamentosDeslistada(this.papel, this.documentos, this.data, this.preco,
      {this.valorDeMercado, this.ancorada = false});

  final PapelDeslistado papel;
  final List<CvmPeriodDocument> documentos;
  final DateTime data;

  /// Fechamento bruto do papel na data.
  final double preco;

  /// Valor de mercado da companhia na data, de [Deslistadas.valorDeMercado].
  final double? valorDeMercado;

  /// Série de doze meses ancorada no trimestre (item C1c), ou a de DFPs.
  final bool ancorada;

  @override
  Future<Result<List<FundamentalsSnapshot>>> history(Ticker t) async {
    final publicado = PointInTimeView(data).isPublished;
    final hoje = papel.acoesEm(data);
    if (hoje == null || hoje <= 0) {
      return Err(InsufficientData('sem contagem de ${t.value} na data',
          subject: t.value));
    }
    final mercado = <FundamentalsSnapshot>[
      for (final d in documentos)
        if (d.kind == CvmDocumentKind.dfp && publicado(d.current))
          FundamentalsSnapshot(
            ticker: t,
            fiscalPeriodEnd: d.periodEnd,
            sharesOutstanding: hoje,
            sharesOutstandingAsOf: papel.acoesEm(d.periodEnd),
            marketCap: valorDeMercado ?? hoje * preco,
          ),
    ];
    return Ok(CvmSeries.build(
      documentos: documentos,
      mercado: mercado,
      asOf: data,
      publicado: publicado,
      ancorada: ancorada,
    ).series);
  }

  @override
  Future<Result<Asset>> profile(Ticker t) async {
    final c = papel.classificacao;
    return Ok(Asset(
      ticker: t,
      name: papel.nome,
      sector: c == null
          ? Sector.fromKey('', label: '')
          : Sector(key: c.sectorKey, label: c.sector),
      industry: (c == null || c.industry.isEmpty) ? null : c.industry,
    ));
  }

  @override
  Future<Result<List<Ticker>>> universe() async => const Ok([]);
}

/// Preços de uma deslistada, na base da data da coorte.
class PrecosDeslistada implements PriceRepository {
  PrecosDeslistada(this.papel, this.ate);

  final PapelDeslistado papel;
  final DateTime ate;

  @override
  Future<Result<PriceSeries>> daily(Ticker t, DateRange range) async =>
      Ok(papel.serie(range, ate: ate));

  @override
  Future<Result<Map<Ticker, PriceSeries>>> dailyBatch(
          List<Ticker> tickers, DateRange range) async =>
      Ok({for (final t in tickers) t: papel.serie(range, ate: ate)});

  @override
  Future<Result<PriceSeries>> adjustedCloseRaw(Ticker t, DateRange range) =>
      daily(t, range);
}

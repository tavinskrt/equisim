// As emissões de ações por valor do Formulário de Referência, com a data em
// que cada uma ficou pública (item B28).
//
// O quadro «aumentos do capital social» do FRE declara, emissão a emissão, a
// data da deliberação e da emissão, o valor total, a quantidade de ações, o
// preço, o tipo de subscrição e a forma de integralização. **É o valor que
// entrou**, e não uma inferência pela contagem: a CMIG de 2018 aparece com R$
// 1,31 bilhão em dinheiro, a Fleury de 2023 com R$ 2,16 bilhões pela
// incorporação da Pardini.
//
// **Três coisas saem**, porque não trazem valor à companhia: a capitalização
// sem emissão de ações, a emissão sem quantidade ou sem valor, e a bonificação
// — que o FRE registra como «subscrição particular» com o valor da reserva
// capitalizada: a SHUL4 de 2021 tem 89 milhões de ações por R$ 22,9 milhões, a
// R$ 0,26 cada, com a forma «Ações Bonificadas»; a SLCE3 de 2023 tem 21
// milhões por R$ 500 milhões, com preço de emissão zero e forma em branco — a
// bonificação de 10% de 05/05/2023. **Emissão por valor tem preço de emissão
// positivo**, e a que não tem sai.
//
// **Cada versão do formulário conta a partir do dia em que foi recebida**
// (`DT_RECEB`): a coorte de uma data só vê a emissão que já estava num
// formulário público, e com os números daquele formulário — a primeira versão
// da CMIG de 2018 tinha R$ 1,0 bilhão, a subscrição ainda em curso.
//
// **Vale o formulário mais recente, inteiro, e não a soma dos formulários.**
// Cada versão relista os aumentos dos exercícios anteriores com um
// identificador novo — a ALPA4 de 2019 aparece em cinco documentos com cinco
// identificadores —, e juntar por identificador somaria a mesma emissão cinco
// vezes. O quadro de cada versão é completo para os três últimos exercícios,
// que cobrem com folga o intervalo entre o balanço e a coorte.
//
// **O quadro de aumentos parou em 2023** — o formulário novo da CVM não o tem,
// nem o de desdobramentos: o último aumento lido é de maio de 2023. Dali em
// diante a segunda fonte é o quadro de **capital social**, que continua: cada
// versão diz o capital integralizado em reais e a contagem. A variação entre
// duas versões é o capital que entrou — a Minerva de 2026, R$ 1,46 bilhão com
// 393 milhões de ações novas; a Casas Bahia, R$ 1,68 bilhão com a conversão da
// dívida. **É um piso**: o ágio da subscrição pode ir para reserva de capital,
// e aí não aparece. E **não distingue bonificação**, que também aumenta o
// capital, por capitalização de reserva: quem a separa é o preço, e por isso
// quem usa esta fonte descarta a variação que um evento de ações explica
// ([pelaVariacaoDoCapital]).
import 'dart:io';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

import 'csv.dart';

class _Registro {
  _Registro({
    required this.documento,
    required this.recebido,
    required this.versao,
    required this.data,
    required this.valor,
    required this.acoes,
  });
  final String documento;
  final DateTime recebido;
  final int versao;
  final DateTime data;
  final double valor;
  final double acoes;
}

/// Uma versão do quadro de capital social: o capital integralizado e a
/// contagem, com a aprovação que a produziu.
class _Capital {
  _Capital(this.recebido, this.aprovacao, this.valor, this.acoes, this.documento);
  final DateTime recebido;
  final DateTime aprovacao;
  final double valor;
  final double acoes;
  final String documento;
}

/// As emissões por valor do FRE, por CNPJ.
class EmissoesFre {
  EmissoesFre._(this._porCnpj, this._documentos, this._capital);

  /// Desde quando vale a variação do capital: o quadro de aumentos cobre até
  /// aqui, e somar as duas fontes antes disso contaria a emissão duas vezes.
  static final DateTime inicioDoCapital = DateTime.utc(2023, 7, 1);

  /// Versões do quadro de capital integralizado, por CNPJ.
  final Map<String, List<_Capital>> _capital;

  /// Emissões com valor, por CNPJ, de todas as versões.
  final Map<String, List<_Registro>> _porCnpj;

  /// Toda versão com o quadro preenchido — inclusive só com capitalização sem
  /// ação nova —, por CNPJ, com o recebimento.
  final Map<String, Map<String, DateTime>> _documentos;

  /// Quantas companhias têm alguma emissão lida.
  int get companhias => _porCnpj.length;

  /// Forma de integralização que é bonificação ou capitalização de reserva.
  static final RegExp _semValor = RegExp(
      r'bonific|reserva|lucros? acumulad|lucros? retid',
      caseSensitive: false);

  /// Lê os formulários de [pasta], ou devolve `null` sem eles.
  static EmissoesFre? ler({String pasta = 'data/cvm/fre'}) {
    final dir = Directory(pasta);
    if (!dir.existsSync()) return null;
    final arquivos = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final recebidos = <String, DateTime>{};
    for (final f in arquivos) {
      if (!RegExp(r'^fre_cia_aberta_\d{4}\.csv$')
          .hasMatch(f.uri.pathSegments.last)) {
        continue;
      }
      for (final r in lerCsvCvm(f)) {
        final id = r['ID_DOC'];
        final dia = DateTime.tryParse('${r['DT_RECEB']}T00:00:00Z');
        if (id != null && dia != null) recebidos[id] = dia;
      }
    }
    final capital = <String, List<_Capital>>{};
    for (final f in arquivos) {
      if (!RegExp(r'^fre_cia_aberta_capital_social_\d{4}\.csv$')
          .hasMatch(f.uri.pathSegments.last)) {
        continue;
      }
      for (final r in lerCsvCvm(f)) {
        if (r['Tipo_Capital'] != 'Capital Integralizado') continue;
        final cnpj = r['CNPJ_Companhia'];
        final documento = r['ID_Documento'];
        final recebido = recebidos[documento ?? ''];
        final aprovacao =
            DateTime.tryParse('${r['Data_Autorizacao_Aprovacao']}T00:00:00Z');
        final valor = double.tryParse(r['Valor_Capital'] ?? '');
        final acoes = double.tryParse(r['Quantidade_Total_Acoes'] ?? '');
        if (cnpj == null || documento == null || recebido == null) continue;
        if (aprovacao == null || valor == null || acoes == null) continue;
        if (!(valor > 0) || !(acoes > 0)) continue;
        (capital[cnpj] ??= [])
            .add(_Capital(recebido, aprovacao, valor, acoes, documento));
      }
    }
    for (final v in capital.values) {
      v.sort((a, b) {
        final c = a.recebido.compareTo(b.recebido);
        return c != 0 ? c : a.documento.compareTo(b.documento);
      });
    }
    final porCnpj = <String, List<_Registro>>{};
    final documentos = <String, Map<String, DateTime>>{};
    for (final f in arquivos) {
      if (!RegExp(r'^fre_cia_aberta_capital_social_aumento_\d{4}\.csv$')
          .hasMatch(f.uri.pathSegments.last)) {
        continue;
      }
      for (final r in lerCsvCvm(f)) {
        final cnpj = r['CNPJ_Companhia'];
        final documento = r['ID_Documento'];
        final recebido = recebidos[documento ?? ''];
        if (cnpj == null || documento == null || recebido == null) continue;
        (documentos[cnpj] ??= {})[documento] = recebido;
        if ((r['Tipo_Subscricao'] ?? '').toLowerCase().contains('sem emiss')) {
          continue;
        }
        if (_semValor.hasMatch(r['Forma_Integralizacao'] ?? '') ||
            _semValor.hasMatch(r['Tipo_Subscricao'] ?? '')) {
          continue;
        }
        final valor = double.tryParse(r['Valor_Total_Emissao'] ?? '');
        final acoes = double.tryParse(r['Quantidade_Total_Acoes'] ?? '');
        final preco = double.tryParse(r['Preco_Emissao'] ?? '');
        if (valor == null || acoes == null || !(valor > 0) || !(acoes > 0)) {
          continue;
        }
        if (preco == null || !(preco > 0)) continue;
        final data = DateTime.tryParse('${r['Data_Emissao']}T00:00:00Z') ??
            DateTime.tryParse('${r['Data_Deliberacao']}T00:00:00Z');
        if (data == null) continue;
        (porCnpj[cnpj] ??= []).add(_Registro(
          documento: documento,
          recebido: recebido,
          versao: int.tryParse(r['Versao'] ?? '') ?? 0,
          data: data,
          valor: valor,
          acoes: acoes,
        ));
      }
    }
    return EmissoesFre._(porCnpj, documentos, capital);
  }

  /// As emissões de [cnpj] no formulário mais recente recebido até [t] que
  /// tem o quadro de aumentos preenchido.
  ///
  /// Dentro do mesmo formulário, a mesma emissão repetida — mesma data, mesma
  /// quantidade — entra uma vez.
  List<ShareIssue> conhecidas(String cnpj, DateTime t) {
    final dia = DateTime.utc(t.year, t.month, t.day);
    String? ultimo;
    DateTime? quando;
    for (final e in (_documentos[cnpj] ?? const <String, DateTime>{}).entries) {
      if (e.value.isAfter(dia)) continue;
      if (quando == null ||
          e.value.isAfter(quando) ||
          (!e.value.isBefore(quando) && e.key.compareTo(ultimo!) > 0)) {
        ultimo = e.key;
        quando = e.value;
      }
    }
    if (ultimo == null) return const [];
    final vistos = <String>{};
    return [
      for (final r in (_porCnpj[cnpj] ?? const <_Registro>[])
          .where((r) => r.documento == ultimo)
          .toList()
        ..sort((a, b) => a.data.compareTo(b.data)))
        if (vistos.add('${r.data.toIso8601String()}|${r.acoes}'))
          ShareIssue(
              date: r.data,
              amount: Money.fromReais(r.valor),
              shares: r.acoes.round()),
    ];
  }

  /// As variações do capital integralizado entre versões do FRE recebidas até
  /// [t], com a aprovação a partir de [inicioDoCapital]: cada aumento de
  /// contagem de 1% ou mais com capital maior sai como emissão pelo capital
  /// que entrou, e com a razão entre as contagens.
  ///
  /// **Quem usa descarta a que um evento de ações explica** — a bonificação
  /// também aumenta o capital —, pela razão e pela data. Ver o comentário do
  /// arquivo.
  List<({ShareIssue emissao, double razao})> pelaVariacaoDoCapital(
      String cnpj, DateTime t) {
    final dia = DateTime.utc(t.year, t.month, t.day);
    final versoes = [
      for (final c in _capital[cnpj] ?? const <_Capital>[])
        if (!c.recebido.isAfter(dia)) c,
    ];
    final out = <({ShareIssue emissao, double razao})>[];
    for (var i = 1; i < versoes.length; i++) {
      final a = versoes[i - 1], b = versoes[i];
      if (b.aprovacao.isBefore(inicioDoCapital)) continue;
      if (!b.aprovacao.isAfter(a.aprovacao)) continue;
      final razao = b.acoes / a.acoes;
      final entrou = Money.fromReais(b.valor) - Money.fromReais(a.valor);
      if (math.log(razao) < math.log(1.01) || !entrou.isPositive) continue;
      out.add((
        emissao: ShareIssue(
            date: b.aprovacao,
            amount: entrou,
            shares: (b.acoes - a.acoes).round()),
        razao: razao,
      ));
    }
    return out;
  }
}

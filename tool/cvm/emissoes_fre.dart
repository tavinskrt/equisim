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
// ([byCapitalChange]).
import 'dart:io';
import 'dart:math' as math;

import 'package:equisim_core/equisim_core.dart';

import 'csv.dart';

class _Record {
  _Record({
    required this.document,
    required this.date,
    required this.value,
    required this.shares,
  });
  final String document;
  final DateTime date;
  final double value;
  final double shares;
}

/// Uma versão do quadro de capital social: o capital integralizado e a
/// contagem, com a aprovação que a produziu.
class _Capital {
  _Capital(this.received, this.approval, this.value, this.shares, this.document);
  final DateTime received;
  final DateTime approval;
  final double value;
  final double shares;
  final String document;
}

/// As emissões por valor do FRE, por CNPJ.
class FreIssuances {
  FreIssuances._(this._byCnpj, this._documents, this._capital);

  /// Desde quando vale a variação do capital: o quadro de aumentos cobre até
  /// aqui, e somar as duas fontes antes disso contaria a emissão duas vezes.
  static final DateTime capitalStart = DateTime.utc(2023, 7, 1);

  /// Versões do quadro de capital integralizado, por CNPJ.
  final Map<String, List<_Capital>> _capital;

  /// Emissões com valor, por CNPJ, de todas as versões.
  final Map<String, List<_Record>> _byCnpj;

  /// Toda versão com o quadro preenchido — inclusive só com capitalização sem
  /// ação nova —, por CNPJ, com o recebimento.
  final Map<String, Map<String, DateTime>> _documents;

  /// Forma de integralização que é bonificação ou capitalização de reserva.
  static final RegExp _noValue = RegExp(
      r'bonific|reserva|lucros? acumulad|lucros? retid',
      caseSensitive: false);

  /// Lê os formulários de [folder], ou devolve `null` sem eles.
  static FreIssuances? read({String folder = 'data/cvm/fre'}) {
    final dir = Directory(folder);
    if (!dir.existsSync()) return null;
    final files = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final receivedInputs = <String, DateTime>{};
    for (final f in files) {
      if (!RegExp(r'^fre_cia_aberta_\d{4}\.csv$')
          .hasMatch(f.uri.pathSegments.last)) {
        continue;
      }
      for (final r in readCvmCsv(f)) {
        final id = r['ID_DOC'];
        final day = DateTime.tryParse('${r['DT_RECEB']}T00:00:00Z');
        if (id != null && day != null) receivedInputs[id] = day;
      }
    }
    final capital = <String, List<_Capital>>{};
    for (final f in files) {
      if (!RegExp(r'^fre_cia_aberta_capital_social_\d{4}\.csv$')
          .hasMatch(f.uri.pathSegments.last)) {
        continue;
      }
      for (final r in readCvmCsv(f)) {
        if (r['Tipo_Capital'] != 'Capital Integralizado') continue;
        final cnpj = r['CNPJ_Companhia'];
        final document = r['ID_Documento'];
        final received = receivedInputs[document ?? ''];
        final approval =
            DateTime.tryParse('${r['Data_Autorizacao_Aprovacao']}T00:00:00Z');
        final value = double.tryParse(r['Valor_Capital'] ?? '');
        final shares = double.tryParse(r['Quantidade_Total_Acoes'] ?? '');
        if (cnpj == null || document == null || received == null) continue;
        if (approval == null || value == null || shares == null) continue;
        if (!(value > 0) || !(shares > 0)) continue;
        (capital[cnpj] ??= [])
            .add(_Capital(received, approval, value, shares, document));
      }
    }
    for (final v in capital.values) {
      v.sort((a, b) {
        final c = a.received.compareTo(b.received);
        return c != 0 ? c : a.document.compareTo(b.document);
      });
    }
    final byCnpj = <String, List<_Record>>{};
    final documents = <String, Map<String, DateTime>>{};
    for (final f in files) {
      if (!RegExp(r'^fre_cia_aberta_capital_social_aumento_\d{4}\.csv$')
          .hasMatch(f.uri.pathSegments.last)) {
        continue;
      }
      for (final r in readCvmCsv(f)) {
        final cnpj = r['CNPJ_Companhia'];
        final document = r['ID_Documento'];
        final received = receivedInputs[document ?? ''];
        if (cnpj == null || document == null || received == null) continue;
        (documents[cnpj] ??= {})[document] = received;
        if ((r['Tipo_Subscricao'] ?? '').toLowerCase().contains('sem emiss')) {
          continue;
        }
        if (_noValue.hasMatch(r['Forma_Integralizacao'] ?? '') ||
            _noValue.hasMatch(r['Tipo_Subscricao'] ?? '')) {
          continue;
        }
        final value = double.tryParse(r['Valor_Total_Emissao'] ?? '');
        final shares = double.tryParse(r['Quantidade_Total_Acoes'] ?? '');
        final price = double.tryParse(r['Preco_Emissao'] ?? '');
        if (value == null || shares == null || !(value > 0) || !(shares > 0)) {
          continue;
        }
        if (price == null || !(price > 0)) continue;
        final date = DateTime.tryParse('${r['Data_Emissao']}T00:00:00Z') ??
            DateTime.tryParse('${r['Data_Deliberacao']}T00:00:00Z');
        if (date == null) continue;
        (byCnpj[cnpj] ??= []).add(_Record(
          document: document,
          date: date,
          value: value,
          shares: shares,
        ));
      }
    }
    return FreIssuances._(byCnpj, documents, capital);
  }

  /// As emissões de [cnpj] no formulário mais recente recebido até [t] que
  /// tem o quadro de aumentos preenchido.
  ///
  /// Dentro do mesmo formulário, a mesma emissão repetida — mesma data, mesma
  /// quantidade — entra uma vez.
  List<ShareIssue> known(String cnpj, DateTime t) {
    final day = DateTime.utc(t.year, t.month, t.day);
    String? last;
    DateTime? asOfDate;
    for (final e in (_documents[cnpj] ?? const <String, DateTime>{}).entries) {
      if (e.value.isAfter(day)) continue;
      if (asOfDate == null ||
          e.value.isAfter(asOfDate) ||
          (!e.value.isBefore(asOfDate) && e.key.compareTo(last!) > 0)) {
        last = e.key;
        asOfDate = e.value;
      }
    }
    if (last == null) return const [];
    final seen = <String>{};
    return [
      for (final r in (_byCnpj[cnpj] ?? const <_Record>[])
          .where((r) => r.document == last)
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date)))
        if (seen.add('${r.date.toIso8601String()}|${r.shares}'))
          ShareIssue(
              date: r.date,
              amount: Money.fromReais(r.value),
              shares: r.shares.round()),
    ];
  }

  /// As variações do capital integralizado entre versões do FRE recebidas até
  /// [t], com a aprovação a partir de [capitalStart]: cada aumento de
  /// contagem de 1% ou mais com capital maior sai como emissão pelo capital
  /// que entrou, e com a razão entre as contagens.
  ///
  /// **Quem usa descarta a que um evento de ações explica** — a bonificação
  /// também aumenta o capital —, pela razão e pela data. Ver o comentário do
  /// arquivo.
  List<({ShareIssue issuance, double ratio})> byCapitalChange(
      String cnpj, DateTime t) {
    final day = DateTime.utc(t.year, t.month, t.day);
    final versions = [
      for (final c in _capital[cnpj] ?? const <_Capital>[])
        if (!c.received.isAfter(day)) c,
    ];
    final out = <({ShareIssue issuance, double ratio})>[];
    for (var i = 1; i < versions.length; i++) {
      final a = versions[i - 1], b = versions[i];
      if (b.approval.isBefore(capitalStart)) continue;
      if (!b.approval.isAfter(a.approval)) continue;
      final ratio = b.shares / a.shares;
      final inflow = Money.fromReais(b.value) - Money.fromReais(a.value);
      if (math.log(ratio) < math.log(1.01) || !inflow.isPositive) continue;
      out.add((
        issuance: ShareIssue(
            date: b.approval,
            amount: inflow,
            shares: (b.shares - a.shares).round()),
        ratio: ratio,
      ));
    }
    return out;
  }
}

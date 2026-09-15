// Códigos de negociação e composição de unit declarados na FCA da CVM.
//
// A FCA traz, por valor mobiliário, o código de negociação **de 2018 em
// diante** (de 2010 a 2017 a coluna vem vazia, limitações §1.11) e, para a
// unit, a composição em texto livre. Serve a duas coisas no item C3:
//
// - **encadear o ticker renomeado**: a fonte de preços publica a série inteira
//   sob o código de hoje, e o COTAHIST, sob o código de cada época — a BHIA3
//   era VVAR3 até 2023, a VBBR3 era BRDT3 até 2021;
// - **conferir a razão de unidade**: a composição declarada é a verdade contra
//   a qual a razão medida na coorte se confere.
import 'dart:io';

import 'csv.dart';

/// Códigos de negociação por CNPJ, e composição de unit por código.
class CodigosFca {
  CodigosFca._(this.porCnpj, this.acoesPorUnit);

  /// Códigos de ação declarados por cada companhia, em qualquer ano.
  final Map<String, Set<String>> porCnpj;

  /// Ações por unit, lidas da composição declarada, por código de unit.
  final Map<String, int> acoesPorUnit;

  /// Código com cara de ticker da B3: quatro letras e o número da classe.
  static final RegExp _ticker = RegExp(r'^[A-Z]{4}\d{1,2}$');

  /// Lê todas as FCAs de valor mobiliário em [dir]. Sem arquivo, devolve
  /// mapas vazios — quem chama recua para o próprio ticker.
  static CodigosFca ler({String dir = 'data/cvm'}) {
    final porCnpj = <String, Set<String>>{};
    final unit = <String, int>{};
    final pasta = Directory(dir);
    if (!pasta.existsSync()) return CodigosFca._(porCnpj, unit);
    final arquivos = pasta
        .listSync()
        .whereType<File>()
        .where((f) => RegExp(r'^fca_cia_aberta_valor_mobiliario_\d{4}\.csv$')
            .hasMatch(f.uri.pathSegments.last))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in arquivos) {
      for (final r in lerCsvCvm(f)) {
        final cnpj = r['CNPJ_Companhia'];
        final codigo = (r['Codigo_Negociacao'] ?? '').trim().toUpperCase();
        if (cnpj == null || !_ticker.hasMatch(codigo)) continue;
        (porCnpj[cnpj] ??= <String>{}).add(codigo);
        if ((r['Valor_Mobiliario'] ?? '').startsWith('Units')) {
          final n = acoesNaComposicao(r['Composicao_BDR_Unit'] ?? '');
          if (n != null) unit[codigo] = n;
        }
      }
    }
    return CodigosFca._(porCnpj, unit);
  }

  /// Ações numa unit, somando as quantidades declaradas antes de cada
  /// espécie — "1 ON e 4 PN" dá 5, "2 ações preferenciais e 1 ação ordinária"
  /// dá 3, "1 KLBN3 + 4 KLBN4" dá 5.
  ///
  /// Recibo e bônus de subscrição não são ação e não entram: a BMGB11 declara
  /// "1 PN + 3 Recibos de Subscrição" e tem uma ação. Devolve `null` quando o
  /// texto não tem quantidade de espécie reconhecível.
  static int? acoesNaComposicao(String texto) {
    // Só a quantidade seguida de espécie de ação conta; "3 Recibos" não casa.
    final termo = RegExp(
        r'(\d+)\s*(?:A[CÇ][OÕ]ES\s+|A[CÇ][AÃ]O\s+)?'
        r'(?:ON\b|PN[A-Z]?\b|ORDIN[AÁ]RIAS?|PREFERENCIA(?:IS|L)|[A-Z]{4}[3-8]\b)');
    var soma = 0;
    for (final m in termo.allMatches(texto.toUpperCase())) {
      soma += int.parse(m.group(1)!);
    }
    return soma > 0 ? soma : null;
  }
}

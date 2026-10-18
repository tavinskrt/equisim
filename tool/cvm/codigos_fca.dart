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
//
// **Desde o item B16 ela deixou de ser só conferência**: a composição
// declarada passou a ser o que o motor usa, e a razão medida no valor de
// mercado, a conferência. Por isso ela é indexada por **CNPJ** e por **ano**:
// o código de negociação da FCA vem em branco ou zerado em parte das linhas —
// a BPAC11 declara sob `000000` —, e uma avaliação datada precisa do
// formulário vigente na data dela, não do último.
import 'dart:io';

import 'package:equisim_core/equisim_core.dart';

import 'csv.dart';

/// Códigos de negociação por CNPJ, e composição de unit por CNPJ e por código.
class FcaCodes {
  FcaCodes._(this.byCnpj, this.sharesPerUnit, this.unitsByCnpj);

  /// Códigos de ação declarados por cada companhia, em qualquer ano.
  final Map<String, Set<String>> byCnpj;

  /// Ações por unit, lidas da composição declarada, por código de unit.
  ///
  /// Continua existindo para a conferência de
  /// [`ponte_por_papel.md`](../../docs/validacao/ponte_por_papel.md) §3, que
  /// compara a razão medida com a declarada sem passar pelo CNPJ. Vale a do
  /// formulário mais recente, e por isso **não** serve a uma avaliação datada
  /// — para essa, [unitsByCnpj].
  final Map<String, int> sharesPerUnit;

  /// Composição declarada de cada unit, por ano, por CNPJ da companhia.
  final Map<String, List<UnitComposition>> unitsByCnpj;

  /// Código com cara de ticker da B3: quatro letras e o número da classe.
  static final RegExp _ticker = RegExp(r'^[A-Z]{4}\d{1,2}$');

  /// Lê todas as FCAs de valor mobiliário em [dir]. Sem arquivo, devolve
  /// mapas vazios — quem chama recua para o próprio ticker.
  static FcaCodes read({String dir = 'data/cvm'}) {
    final byCnpj = <String, Set<String>>{};
    final unit = <String, int>{};
    final byCnpjUnit = <String, Map<int, UnitComposition>>{};
    final folder = Directory(dir);
    if (!folder.existsSync()) {
      return FcaCodes._(byCnpj, unit, const {});
    }
    final files = folder
        .listSync()
        .whereType<File>()
        .where((f) => RegExp(r'^fca_cia_aberta_valor_mobiliario_\d{4}\.csv$')
            .hasMatch(f.uri.pathSegments.last))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      final year = int.parse(
          f.uri.pathSegments.last.replaceAll(RegExp(r'\D'), '').substring(0, 4));
      for (final r in readCvmCsv(f)) {
        final cnpj = r['CNPJ_Companhia'];
        final code = (r['Codigo_Negociacao'] ?? '').trim().toUpperCase();
        if (cnpj != null && _ticker.hasMatch(code)) {
          (byCnpj[cnpj] ??= <String>{}).add(code);
        }
        if (!(r['Valor_Mobiliario'] ?? '').startsWith('Units')) continue;
        final text = (r['Composicao_BDR_Unit'] ?? '').trim();
        final n = UnitCompositionCodec.parse(text);
        if (n == null) continue;
        if (_ticker.hasMatch(code)) unit[code] = n;
        if (cnpj == null) continue;
        // Uma companhia pode ter mais de uma linha de unit no mesmo ano —
        // versões do formulário, ou classes distintas. Vale a **maior**
        // composição do ano: a linha residual costuma ser a que declara só uma
        // das espécies.
        final current = (byCnpjUnit[cnpj] ??= {})[year];
        if (current == null || n > current.shares) {
          byCnpjUnit[cnpj]![year] =
              UnitComposition(year: year, shares: n, declared: text);
        }
      }
    }
    return FcaCodes._(
      byCnpj,
      unit,
      {
        for (final e in byCnpjUnit.entries)
          e.key: (e.value.values.toList()
            ..sort((a, b) => a.year.compareTo(b.year))),
      },
    );
  }
}

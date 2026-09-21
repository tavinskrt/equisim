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
class CodigosFca {
  CodigosFca._(this.porCnpj, this.acoesPorUnit, this.unitsPorCnpj);

  /// Códigos de ação declarados por cada companhia, em qualquer ano.
  final Map<String, Set<String>> porCnpj;

  /// Ações por unit, lidas da composição declarada, por código de unit.
  ///
  /// Continua existindo para a conferência de
  /// [`ponte_por_papel.md`](../../docs/validacao/ponte_por_papel.md) §3, que
  /// compara a razão medida com a declarada sem passar pelo CNPJ. Vale a do
  /// formulário mais recente, e por isso **não** serve a uma avaliação datada
  /// — para essa, [unitsPorCnpj].
  final Map<String, int> acoesPorUnit;

  /// Composição declarada de cada unit, por ano, por CNPJ da companhia.
  final Map<String, List<UnitComposition>> unitsPorCnpj;

  /// Código com cara de ticker da B3: quatro letras e o número da classe.
  static final RegExp _ticker = RegExp(r'^[A-Z]{4}\d{1,2}$');

  /// Lê todas as FCAs de valor mobiliário em [dir]. Sem arquivo, devolve
  /// mapas vazios — quem chama recua para o próprio ticker.
  static CodigosFca ler({String dir = 'data/cvm'}) {
    final porCnpj = <String, Set<String>>{};
    final unit = <String, int>{};
    final porCnpjUnit = <String, Map<int, UnitComposition>>{};
    final pasta = Directory(dir);
    if (!pasta.existsSync()) {
      return CodigosFca._(porCnpj, unit, const {});
    }
    final arquivos = pasta
        .listSync()
        .whereType<File>()
        .where((f) => RegExp(r'^fca_cia_aberta_valor_mobiliario_\d{4}\.csv$')
            .hasMatch(f.uri.pathSegments.last))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in arquivos) {
      final ano = int.parse(
          f.uri.pathSegments.last.replaceAll(RegExp(r'\D'), '').substring(0, 4));
      for (final r in lerCsvCvm(f)) {
        final cnpj = r['CNPJ_Companhia'];
        final codigo = (r['Codigo_Negociacao'] ?? '').trim().toUpperCase();
        if (cnpj != null && _ticker.hasMatch(codigo)) {
          (porCnpj[cnpj] ??= <String>{}).add(codigo);
        }
        if (!(r['Valor_Mobiliario'] ?? '').startsWith('Units')) continue;
        final texto = (r['Composicao_BDR_Unit'] ?? '').trim();
        final n = UnitCompositionCodec.parse(texto);
        if (n == null) continue;
        if (_ticker.hasMatch(codigo)) unit[codigo] = n;
        if (cnpj == null) continue;
        // Uma companhia pode ter mais de uma linha de unit no mesmo ano —
        // versões do formulário, ou classes distintas. Vale a **maior**
        // composição do ano: a linha residual costuma ser a que declara só uma
        // das espécies.
        final atual = (porCnpjUnit[cnpj] ??= {})[ano];
        if (atual == null || n > atual.shares) {
          porCnpjUnit[cnpj]![ano] =
              UnitComposition(year: ano, shares: n, declared: texto);
        }
      }
    }
    return CodigosFca._(
      porCnpj,
      unit,
      {
        for (final e in porCnpjUnit.entries)
          e.key: (e.value.values.toList()
            ..sort((a, b) => a.year.compareTo(b.year))),
      },
    );
  }
}

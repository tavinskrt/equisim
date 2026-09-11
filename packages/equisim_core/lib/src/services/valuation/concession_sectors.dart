/// Quais negócios operam sob contrato de prazo determinado.
library;

import 'cyclical_sectors.dart';

/// Setores cujo direito de operar tem data para acabar.
///
/// **Por que existe.** O valor terminal do motor é perpétuo para todo ativo.
/// Numa concessão — transmissão, distribuição, saneamento, rodovia, ferrovia,
/// aeroporto — o direito de operar acaba em data marcada, e o ativo reverte ao
/// poder concedente ou vai a nova licitação.
///
/// **O que isto NÃO faz.** Não trunca a perpetuidade, porque **o prazo não é
/// publicado**. Medido em 10/09/2026: a razão
/// `(imobilizado + intangível) ÷ D&A` parecia servir de estimador do prazo
/// remanescente e não serve — ela dá 6,3 anos para a TAEE11, cujas concessões
/// vão a 2042, e 14,3 anos para a WEGE3, que não tem concessão alguma. O que
/// ela mede é giro da base de ativos. Ver
/// [`concessao.md`](../../../../../docs/validacao/concessao.md).
///
/// **O que isto faz.** Bloqueia a afirmação que o contrato nega diretamente: a
/// de que o **retorno excedente sobrevive para sempre**. Uma concessão é
/// relicitada, e a tarifa é fixada para remunerar o capital ao custo dele —
/// não acima. O terminal neutro da decisão 25, `ROIC_∞ = WACC`, é exatamente o
/// modelo certo para esse negócio, e a exceção de vantagem competitiva é
/// exatamente o errado.
///
/// A lista é **declarada, não inferida**, pela mesma razão que a de
/// [CyclicalSectors]: quem tem concessão é fato do contrato, não do dado.
abstract final class ConcessionSectors {
  /// Chaves de setor cujo conteúdo inteiro opera sob concessão.
  static const List<String> sectorKeys = ['saneamento', 'infraestrutura'];

  /// Termos de subsetor que denunciam contrato de prazo determinado.
  ///
  /// A comparação é sobre o subsetor **normalizado**, sem acento e sem
  /// pontuação, pela mesma razão que em [CyclicalSectors]: a fonte publica
  /// variantes do mesmo rótulo.
  ///
  /// `energia eletrica` cobre geração, transmissão, distribuição e
  /// comercialização, e as quatro dependem de outorga — a comercializadora
  /// pura seria a exceção, e o universo não tem nenhuma isolada.
  static const List<String> industryTerms = [
    'energia eletrica',
    'agua e saneamento',
    'exploracao de rodovias',
    'transporte ferroviario',
    'aeroportu',
    'concessao',
  ];

  /// `true` quando o direito de operar tem prazo.
  ///
  /// - [sectorKey]: chave setorial da fonte, já em minúsculas.
  /// - [industry]: subsetor da fonte, com acentuação e pontuação originais.
  static bool hasFiniteTerm({String? sectorKey, String? industry}) {
    final chave = CyclicalSectors.normalize(sectorKey);
    for (final k in sectorKeys) {
      if (chave == CyclicalSectors.normalize(k)) return true;
    }
    final sub = CyclicalSectors.normalize(industry);
    if (sub.isEmpty) return false;
    for (final termo in industryTerms) {
      if (sub.contains(termo)) return true;
    }
    return false;
  }
}

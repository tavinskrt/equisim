/// A composição declarada de uma unit, do Formulário Cadastral da CVM (item
/// B16).
library;

/// Quantas ações a unit reúne, **segundo a companhia**, num ano do formulário.
///
/// **Por que existe.** A razão de unidade era inferida do valor de mercado —
/// `contagem × preço da unit ÷ valor de mercado` —, e essa razão só devolve o
/// número de ações da unit quando ordinária e preferencial valem o mesmo.
/// Medida nas coortes contra esta composição, ela erra 79 de 220 observações:
/// em 49 cai em 1, e a unit é avaliada como ação; em 12 cai no inteiro errado
/// dentro da folga de 5% — a ENGI11 com 4 em vez de 5 —, sem aviso; em 18 a
/// espécie não negocia e o valor de mercado volta a ser a contagem vezes o
/// preço da unit, o que devolve 1 por construção. Ver
/// [`ponte_por_papel.md`](../../../../../docs/validacao/ponte_por_papel.md) §3.
///
/// **A fonte é primária e datada.** O quadro de valores mobiliários da FCA
/// (`fca_cia_aberta_valor_mobiliario_<ano>.csv`) traz, para cada unit, a coluna
/// `Composicao_BDR_Unit` em texto livre — "1 ON e 4 PN", "1 KLBN3 + 4 KLBN4",
/// "2 ações preferenciais e 1 ação ordinária". Um formulário por ano, de modo
/// que a composição de uma avaliação datada é a do formulário mais recente
/// **até** a data dela.
class UnitComposition {
  /// Ano do formulário de onde a composição foi lida.
  final int year;

  /// Ações reunidas na unit. Sempre ≥ 1.
  final int shares;

  /// O texto como a companhia o declarou. Viaja junto para que o rastro de
  /// auditoria mostre a fonte, e não só o número.
  final String declared;

  const UnitComposition({
    required this.year,
    required this.shares,
    required this.declared,
  });
}

/// Leitura do texto livre e serialização do pacote.
abstract final class UnitCompositionCodec {
  /// Versão do formato do pacote.
  static const int versao = 1;

  /// Teto de ações por unit, o mesmo de `ValuationCascade.maxSharesPerUnit`.
  ///
  /// As units da B3 vão até 5 — 1 ON e 4 PN. O teto existe para que um texto
  /// mal lido não vire divisor absurdo.
  static const int maxShares = 10;

  /// Quantidade seguida de espécie de ação. Recibo e bônus de subscrição não
  /// são ação e não casam.
  ///
  /// O código de negociação entra com **três ou quatro letras**: a ENGI11 de
  /// 2018 declara "1 ENG3 e 4 ENGI4", e exigir quatro letras somava só o 4.
  static final RegExp _termo = RegExp(
      r'(\d+)\s*(?:A[CÇ][OÕ]ES\s+|A[CÇ][AÃ]O\s+)?'
      r'(?:ON\b|PN[A-Z]?\b|ORDIN[AÁ]RIAS?|PREFERENCIA(?:IS|L)|[A-Z]{3,4}[3-8]\b)');

  /// Ações numa unit, somando as quantidades declaradas antes de cada espécie.
  ///
  /// "1 ON e 4 PN" dá 5, "2 ações preferenciais e 1 ação ordinária" dá 3,
  /// "1 KLBN3 + 4 KLBN4" dá 5, "1 ENG3 e 4 ENGI4" dá 5.
  ///
  /// **Recibo de subscrição não é ação**: a BMGB11 declara "1 PN + 3 Recibos de
  /// Subscrição" e tem uma ação. Devolve `null` quando o texto não tem
  /// quantidade de espécie reconhecível, e quando a soma passa de [maxShares] —
  /// nos dois casos quem chama recua para a razão medida, declarando.
  static int? parse(String texto) {
    var soma = 0;
    for (final m in _termo.allMatches(texto.toUpperCase())) {
      soma += int.parse(m.group(1)!);
    }
    if (soma < 1 || soma > maxShares) return null;
    return soma;
  }

  /// A composição declarada mais recente **até** [asOf], ou `null`.
  ///
  /// Formulário posterior à data da avaliação não entra: numa coorte de 2019 a
  /// composição de 2024 seria conhecimento futuro. Ano do formulário contra ano
  /// da avaliação, e não data contra data, porque a FCA é anual e a entrega
  /// varia de mês.
  static UnitComposition? at(List<UnitComposition> declaradas, DateTime asOf) {
    UnitComposition? melhor;
    for (final c in declaradas) {
      if (c.year > asOf.year) continue;
      if (melhor == null || c.year > melhor.year) melhor = c;
    }
    return melhor;
  }

  /// Grava o pacote: composições por código de unit, por ano.
  static Map<String, Object> encodePackage(
    Map<String, List<UnitComposition>> porTicker, {
    required DateTime geradoEm,
  }) =>
      {
        'versao': versao,
        'geradoEm': geradoEm.toIso8601String().substring(0, 10),
        'units': {
          for (final e in porTicker.entries)
            e.key: [
              for (final c in (e.value.toList()
                    ..sort((a, b) => a.year.compareTo(b.year))))
                {'ano': c.year, 'acoes': c.shares, 'texto': c.declared},
            ],
        },
      };

  /// Lê o pacote. Entrada malformada é **pulada**, e não derruba a leitura: uma
  /// unit sem composição recua para a razão medida, que é o comportamento
  /// anterior.
  static Map<String, List<UnitComposition>> decodePackage(
    Map<String, dynamic> pacote,
  ) {
    final out = <String, List<UnitComposition>>{};
    final units = pacote['units'];
    if (units is! Map) return out;
    for (final e in units.entries) {
      final lista = e.value;
      if (lista is! List) continue;
      final composicoes = <UnitComposition>[];
      for (final x in lista) {
        if (x is! Map) continue;
        final ano = (x['ano'] as num?)?.toInt();
        final acoes = (x['acoes'] as num?)?.toInt();
        if (ano == null || acoes == null || acoes < 1 || acoes > maxShares) {
          continue;
        }
        composicoes.add(UnitComposition(
          year: ano,
          shares: acoes,
          declared: (x['texto'] as String?) ?? '',
        ));
      }
      if (composicoes.isNotEmpty) out['${e.key}'] = composicoes;
    }
    return out;
  }
}

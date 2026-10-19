/// Leitura do plano de contas padronizado da CVM.
///
/// **Por que este arquivo existe.** A CVM publica DFP e ITR com um plano de
/// contas que parece padronizado — `1 = Ativo Total`, `3.01 = Receita` — e
/// **não é um só**. A conferência de 11/09/2026 encontrou quatro layouts no
/// universo, e o lucro líquido mora em código diferente em cada um:
///
/// | layout | consolidado | individual |
/// |---|---|---|
/// | Não financeira (513 cias) | 3.11 | 3.11 |
/// | Banco "**de** Intermediação" (18) | 3.11 | 3.11 |
/// | Banco "**da** Intermediação" (7) | **3.09** | **3.13** |
/// | Seguradora (4) | 3.13 | 3.13 |
///
/// Os dois de banco se distinguem por **uma preposição** num rótulo em
/// português. Ler `3.11` como lucro no individual do Itaú devolve *"Reversão
/// dos Juros sobre Capital Próprio"*; ler `3.05` como EBIT num banco devolve
/// "Resultado Antes dos Tributos" — R$ 47,6 bi contra R$ 42,1 bi de lucro.
///
/// **Por isso a resolução é por evidência, não por tabela de códigos.** Cada
/// conta semântica é procurada por padrão de descrição entre as linhas de
/// nível raso, e o código serve de desempate e de conferência. Onde o layout
/// não tem o conceito — EBIT de banco não existe —, a resposta é `null`, nunca
/// um número plausível.
///
/// Ver `docs/validacao/cvm_conferencia.md`.
library;

import '../../audit/wire_keyed.dart';

/// Uma linha de demonstração, como a CVM a publica.
///
/// **O valor é guardado em centavos inteiros**, e não em `double`. O CSV traz
/// `VL_CONTA` como texto — `265438605.0000000000` — e uma escala em
/// `ESCALA_MOEDA`, quase sempre MIL. Converter o texto para `double` e depois
/// de volta para centavos presume que o `double` esteja limpo, o que é
/// presunção desnecessária quando a origem é texto. [CvmAccountLine.fromText]
/// vai do texto ao inteiro sem passar por ponto flutuante.
class CvmAccountLine {
  /// `CD_CONTA` — o código do plano, com níveis separados por ponto.
  final String code;

  /// `DS_CONTA` — a descrição. Padronizada no nível raso, texto livre abaixo.
  final String label;

  /// Valor em **centavos**, já com a escala aplicada. É a forma canônica.
  final int cents;

  /// Declara a linha a partir dos centavos.
  const CvmAccountLine.inCents({
    required this.code,
    required this.label,
    required this.cents,
  });

  /// Declara a linha a partir de um valor em reais, **arredondando**.
  ///
  /// O nome diz o que ela é: `double` não representa exatamente toda quantia
  /// decimal, e converter de volta para centavos arredonda. Serve para teste
  /// e para quem já tem o número pronto de outra fonte.
  ///
  /// **A ingestão da CVM não usa isto** — usa [CvmAccountLine.fromText], que
  /// vai do texto do CSV ao inteiro sem ponto flutuante no caminho.
  CvmAccountLine.approximate({
    required this.code,
    required this.label,
    required double value,
  }) : cents = (value * 100).round();

  /// Declara a linha a partir do texto do CSV, **sem ponto flutuante**.
  ///
  /// - [value]: `VL_CONTA` como veio, com ou sem sinal e casas decimais.
  /// - [scale]: 1000 para `ESCALA_MOEDA` igual a MIL, 1 caso contrário.
  ///
  /// Devolve `null` para texto que não seja número — o que é resposta, e não
  /// falha: linha ilegível não entra na demonstração.
  static CvmAccountLine? fromText({
    required String code,
    required String label,
    required String value,
    int scale = 1,
  }) {
    final c = _cents(value, scale);
    return c == null
        ? null
        : CvmAccountLine.inCents(code: code, label: label, cents: c);
  }

  /// Texto decimal para centavos, com a escala aplicada, em aritmética
  /// inteira.
  ///
  /// **A escala entra antes do arredondamento**, e a ordem importa: com
  /// `ESCALA_MOEDA` igual a MIL, um valor de `1.0005` são R$ 1.000,50 —
  /// 100.050 centavos exatos. Arredondar para centavos primeiro daria R$ 1,00
  /// e depois R$ 1.000,00, perdendo cinquenta centavos por multiplicar o
  /// resíduo descartado.
  ///
  /// Usa [BigInt] no caminho: o ativo total de uma companhia grande em
  /// centavos passa de 1e14, e a escala MIL o multiplica de novo. O resultado
  /// é recusado se não couber em `int`, em vez de estourar em silêncio.
  static int? _cents(String raw, int scale) {
    var s = raw.trim();
    if (s.isEmpty || scale <= 0) return null;
    var negative = false;
    if (s.startsWith('-')) {
      negative = true;
      s = s.substring(1);
    } else if (s.startsWith('+')) {
      s = s.substring(1);
    }
    final parts = s.split('.');
    if (parts.length > 2) return null;
    final whole = parts[0].isEmpty ? '0' : parts[0];
    final decimals = parts.length == 2 ? parts[1] : '';
    if (!RegExp(r'^\d+$').hasMatch(whole)) return null;
    if (decimals.isNotEmpty && !RegExp(r'^\d+$').hasMatch(decimals)) {
      return null;
    }

    // `bruto` = mantissa / 10^casas. Os centavos são
    // `mantissa × escala × 100 / 10^casas`, arredondados meio para cima —
    // tudo em inteiro, sem passar por ponto flutuante.
    final mantissa = BigInt.parse('$whole$decimals');
    final divisor = BigInt.from(10).pow(decimals.length);
    final numerator = mantissa * BigInt.from(scale) * BigInt.from(100);
    var v = numerator ~/ divisor;
    final remainder = numerator.remainder(divisor);
    if (remainder * BigInt.two >= divisor) v += BigInt.one;
    if (negative) v = -v;

    final cap = BigInt.parse('9223372036854775807');
    if (v > cap || v < -cap) return null;
    return v.toInt();
  }

  /// Valor em reais. **Vista derivada** — a fonte da verdade é [cents].
  double get value => cents / 100.0;

  /// Profundidade do código: `3` é 1, `3.01` é 2, `3.01.01` é 3.
  int get depth => code.split('.').length;
}

/// Qual dos planos de contas a companhia usa.
///
/// **Não é setor** — é a forma da demonstração que a companhia entregou. Uma
/// mesma empresa pode mudar de layout entre exercícios, e por isso a detecção
/// é feita por documento e não guardada por CNPJ.
enum CvmLayout implements WireKeyed {
  /// Plano padrão: `3.01 = Receita de Venda de Bens e/ou Serviços`.
  corporate('corporativo'),

  /// Intermediação financeira. **Não tem EBIT** — a estrutura não separa
  /// resultado operacional de resultado financeiro, porque o financeiro *é* a
  /// operação.
  financialIntermediation('intermediacaoFinanceira'),

  /// Atividades seguradoras e resseguradoras. Também sem EBIT.
  insurer('seguradora'),

  /// Nenhum padrão reconhecido. Tudo que dependa de layout devolve `null`.
  unknown('desconhecido');

  const CvmLayout(this.key);

  /// Chave gravada nas saídas — pacote de dados, rastro de auditoria,
  /// relatório. É dado, e não nome de código: renomear o valor não a muda.
  @override
  final String key;

  /// `true` quando a estrutura separa resultado operacional do financeiro.
  ///
  /// É a condição para que exista EBIT. Banco e seguradora não a satisfazem, e
  /// [CvmChart.ebit] devolve `null` para eles — o que é o certo: a via da
  /// firma já os recusa pela Porta 1.
  bool get hasOperatingResult => this == CvmLayout.corporate;
}

/// Um documento de demonstração já lido, com as contas resolvidas por
/// significado.
///
/// Construa por [CvmChart.of], que detecta o layout a partir das próprias
/// linhas.
class CvmChart {
  /// Linhas do documento, como vieram.
  final List<CvmAccountLine> lines;

  /// Layout detectado.
  final CvmLayout layout;

  const CvmChart._(this.lines, this.layout);

  /// Lê um documento e detecta o layout.
  ///
  /// - [lines]: linhas de **uma** demonstração de **um** exercício, já
  ///   filtradas por `ORDEM_EXERC`. Misturar exercícios aqui produz resolução
  ///   silenciosamente errada, porque a busca é por descrição.
  factory CvmChart.of(List<CvmAccountLine> lines) =>
      CvmChart._(List.unmodifiable(lines), _detect(lines));

  // ----------------------------------------------------------- normalização

  /// Minúsculas sem acento, para comparar descrição da fonte.
  ///
  /// Os CSVs da CVM vêm em `latin-1` e as descrições carregam acentuação
  /// inconsistente entre companhias. Comparar sem normalizar faz o mesmo
  /// rótulo casar num documento e não casar no seguinte.
  static String normalize(String s) {
    const accented = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const plain = 'aaaaaeeeeiiiiooooouuuucn';
    final b = StringBuffer();
    for (final c in s.toLowerCase().runes) {
      final ch = String.fromCharCode(c);
      final i = accented.indexOf(ch);
      b.write(i >= 0 ? plain[i] : ch);
    }
    return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static CvmLayout _detect(List<CvmAccountLine> lines) {
    for (final l in lines) {
      if (l.code != '3.01') continue;
      final d = normalize(l.label);
      if (d.contains('intermediacao financeira')) {
        return CvmLayout.financialIntermediation;
      }
      if (d.contains('segurador') || d.contains('ressegurador')) {
        return CvmLayout.insurer;
      }
      if (d.contains('receita')) return CvmLayout.corporate;
    }
    // Sem DRE no documento — é balanço puro. O ativo e o passivo não dependem
    // de layout, então isto não impede a leitura deles.
    final hasBalanceSheet = lines.any((l) => l.code == '1' || l.code == '2');
    return hasBalanceSheet ? CvmLayout.corporate : CvmLayout.unknown;
  }

  // -------------------------------------------------------------- resolução

  /// Linhas de nível até [upToLevel], que é onde o plano é padronizado.
  ///
  /// Abaixo do nível 2 a descrição é texto livre da companhia — a conferência
  /// encontrou 26 grafias distintas de "Caixa e Equivalentes" no nível 4 — e
  /// nada aqui deve descer até lá.
  Iterable<CvmAccountLine> shallow([int upToLevel = 2]) =>
      lines.where((l) => l.depth <= upToLevel);

  /// A linha de código exatamente [code], se existir.
  CvmAccountLine? byCode(String code) {
    for (final l in lines) {
      if (l.code == code) return l;
    }
    return null;
  }

  /// Procura entre as linhas rasas a que casa [pattern], preferindo o **maior**
  /// código.
  ///
  /// O maior código é o mais abaixo na demonstração, e a linha de resultado
  /// que interessa é sempre a última — no layout de banco "de Intermediação",
  /// tanto `3.07` ("Operações Continuadas") quanto `3.11` ("Líquido
  /// Consolidado do Período") casam com "lucro", e o certo é o segundo.
  CvmAccountLine? _find(
    RegExp pattern, {
    RegExp? excluding,
    int upToLevel = 2,
  }) {
    CvmAccountLine? best;
    for (final l in shallow(upToLevel)) {
      final d = normalize(l.label);
      if (!pattern.hasMatch(d)) continue;
      if (excluding != null && excluding.hasMatch(d)) continue;
      if (best == null || _isGreater(l.code, best.code)) best = l;
    }
    return best;
  }

  /// `true` quando [a] vem depois de [b] na ordem do plano de contas.
  ///
  /// Comparação **segmento a segmento como número**, e não como texto: `3.9`
  /// contra `3.11` daria a resposta errada em ordem lexicográfica, e o plano
  /// da CVM chega a dois dígitos por nível.
  static bool _isGreater(String a, String b) {
    final partsA = a.split('.');
    final partsB = b.split('.');
    for (var i = 0; i < partsA.length && i < partsB.length; i++) {
      final numA = int.tryParse(partsA[i]) ?? -1;
      final numB = int.tryParse(partsB[i]) ?? -1;
      if (numA != numB) return numA > numB;
    }
    return partsA.length > partsB.length;
  }

  // ------------------------------------------------------ contas semânticas

  static final _reProfit = RegExp(r'(lucro|prejuizo)');
  static final _rePerShare = RegExp(r'por acao');
  static final _reContinued = RegExp(r'(des)?continuada');
  static final _reBeforeTaxes = RegExp(r'antes.*(tributa|tributos|imposto)');
  static final _reTaxes =
      RegExp(r'(imposto de renda|provisao para ir|tributos sobre o lucro)');
  static final _reEbit = RegExp(
    r'antes do resultado financeiro',
  );

  /// Receita do período. `3.01` em todos os layouts conferidos.
  double? get revenue => byCode('3.01')?.value;

  /// Resultado antes do resultado financeiro e dos tributos — o **EBIT**.
  ///
  /// **`null` fora do layout corporativo, por decisão.** Banco e seguradora
  /// não separam operação de financeiro, e o `3.05` deles é "Resultado Antes
  /// dos Tributos" — devolvê-lo como EBIT erraria 13% no Itaú e daria à via da
  /// firma um número que ela não deve receber.
  double? get ebit {
    if (!layout.hasOperatingResult) return null;
    final byDescription = _find(_reEbit);
    if (byDescription != null) return byDescription.value;
    // Recuo pelo código, conferindo que a descrição não desminta.
    final l = byCode('3.05');
    if (l == null) return null;
    final d = normalize(l.label);
    if (_reBeforeTaxes.hasMatch(d) && !_reEbit.hasMatch(d)) return null;
    return l.value;
  }

  /// Resultado antes dos tributos sobre o lucro.
  double? get incomeBeforeTaxes =>
      _find(_reBeforeTaxes, excluding: _rePerShare)?.value;

  /// Imposto de renda e contribuição social.
  ///
  /// O sinal é o que a CVM publica — despesa vem **negativa** —, e quem
  /// consome deve preservá-lo. A `effectiveTaxRate` do motor já nega em vez de
  /// modular, pela correção de 10/09/2026 registrada na §2.1-b.
  double? get taxes => _find(_reTaxes, excluding: _rePerShare)?.value;

  /// Lucro líquido do período.
  ///
  /// Procurado por descrição e não por código, e **excluindo** as linhas de
  /// operações continuadas e descontinuadas, que casam com "lucro" e não são o
  /// resultado final. Entre as que sobram vence o maior código, que é o fundo
  /// da demonstração.
  double? get netIncome =>
      _find(_reProfit, excluding: RegExp('${_rePerShare.pattern}|'
              '${_reContinued.pattern}|reversao|juros sobre'))
          ?.value;

  /// Lucro por ação, quando publicado. `3.99` nos quatro layouts.
  double? get earningsPerShare {
    final l = byCode('3.99');
    if (l == null) return null;
    return _rePerShare.hasMatch(normalize(l.label)) ? l.value : null;
  }

  // --- Balanço: não depende de layout, os códigos de topo são universais ---

  /// Ativo total — `1`. **Existe em 100% do universo conferido**, e é o que
  /// torna possível a conferência analítica que a §2.17 dizia não haver.
  double? get totalAssets => byCode('1')?.value;

  /// Ativo circulante — `1.01`.
  double? get currentAssets => byCode('1.01')?.value;

  /// Passivo total — `2`.
  double? get totalLiabilities => byCode('2')?.value;

  /// Passivo circulante — `2.01`.
  double? get currentLiabilities => byCode('2.01')?.value;

  /// Patrimônio líquido consolidado.
  ///
  /// `2.03` no layout corporativo e `2.07` ou `2.08` no de banco — por isso a
  /// busca é por descrição entre os três.
  double? get equity =>
      _find(RegExp(r'patrimonio liquido'), excluding: RegExp(r'controlador'))
          ?.value;

  /// Participação dos não controladores no patrimônio.
  ///
  /// `2.03.09` no layout corporativo, `2.07.02` no de banco — nível 3, que é a
  /// única exceção ao limite de nível 2, e ela é segura porque a descrição
  /// "não controladores" é padronizada.
  double? get nonControllingInterests {
    final l = _find(RegExp(r'nao controlador'), upToLevel: 3);
    if (l == null) return null;
    // "Patrimônio Líquido Atribuído aos Não Controladores" e "Participação dos
    // Acionistas Não Controladores" descrevem a mesma coisa; ambas servem.
    return l.value;
  }

  // --- Nível 3 do balanço: padronizado, e conferido ------------------------
  //
  // Abaixo do nível 2 a regra geral é texto livre, e o nível 3 é a exceção
  // **medida**: sobre os 293 CNPJs do universo em 2023, cada código abaixo
  // aparece em 246 a 260 companhias com **duas ou três grafias apenas**. As
  // que faltam são banco e seguradora, cujo balanço tem outra estrutura — e
  // para elas estes campos devolvem `null`, que é o certo.

  /// Caixa e equivalentes — `1.01.01`.
  double? get cash => _level3('1.01.01', RegExp(r'caixa'));

  /// Aplicações financeiras de curto prazo — `1.01.02`.
  double? get financialInvestments =>
      _level3('1.01.02', RegExp(r'aplicaco(es|ns) financeira'));

  /// Imobilizado — `1.02.03`.
  double? get propertyPlantEquipment => _level3('1.02.03', RegExp(r'imobilizado'));

  /// Intangível — `1.02.04`.
  double? get intangibleAssets => _level3('1.02.04', RegExp(r'intangivel'));

  /// Empréstimos e financiamentos no circulante — `2.01.04`.
  double? get shortTermDebt =>
      _level3('2.01.04', RegExp(r'emprestimos e financiamentos'));

  /// Empréstimos e financiamentos no não circulante — `2.02.01`.
  double? get longTermDebt =>
      _level3('2.02.01', RegExp(r'emprestimos e financiamentos'));

  /// Lê um código de nível 3 **conferindo a descrição**.
  ///
  /// O código sozinho não basta: `2.01.04` é "Empréstimos e Financiamentos" na
  /// estrutura corporativa e outra coisa na de banco. Discordando o rótulo, a
  /// resposta é `null` — a mesma disciplina do [ebit].
  double? _level3(String code, RegExp expected) {
    final l = byCode(code);
    if (l == null) return null;
    return expected.hasMatch(normalize(l.label)) ? l.value : null;
  }

  // --- Fluxo de caixa: códigos de topo universais no método indireto ---

  /// Caixa líquido das atividades operacionais — `6.01`.
  double? get operatingCashFlow => byCode('6.01')?.value;

  /// Caixa líquido das atividades de investimento — `6.02`.
  double? get investingCashFlow => byCode('6.02')?.value;

  /// Depreciação e amortização, da reconciliação do fluxo operacional.
  ///
  /// `6.01.01.*` traz os ajustes que reconciliam lucro e caixa, e a
  /// depreciação está entre eles — em texto livre, como o CapEx. Soma todas as
  /// linhas que a mencionem, em centavos inteiros.
  ///
  /// Devolve `null` quando nenhuma casa: o motor deriva D&A de
  /// `EBITDA − EBIT` quando isto falta, e um zero aqui apagaria essa rota.
  double? get depreciationAndAmortization {
    var cents = 0;
    var found = false;
    for (final l in lines) {
      if (!l.code.startsWith('6.01.')) continue;
      final d = normalize(l.label);
      if (!d.contains('deprecia') && !d.contains('amortiza')) continue;
      cents += l.cents;
      found = true;
    }
    // A reconciliação soma a despesa de volta ao lucro, então ela vem
    // **positiva**. O domínio a quer positiva também.
    return found ? (cents.abs()) / 100.0 : null;
  }

  /// Aquisição de imobilizado e intangível, somada — o **CapEx**.
  ///
  /// **Aproximação declarada, e é a única parte desta classe que depende de
  /// texto livre.** A conferência achou a linha em 86% das companhias, com
  /// mais de oito grafias ("Aquisição de intangível", "Adições ao imobilizado
  /// e intangível", "Aquisição de ativo imobilizado"...). Soma todas as linhas
  /// de nível 3 sob `6.02` que mencionem imobilizado ou intangível.
  ///
  /// Devolve `null` — e não zero — quando nenhuma linha casa: ausência de
  /// linha não é ausência de investimento, é ausência de dado.
  double? get capex {
    // **Soma os centavos inteiros da própria linha**, sem passar por reais:
    // acumular ponto flutuante deixaria resíduo que reaparece na taxa de
    // reinvestimento, e a linha já guarda o inteiro exato vindo do texto.
    var cents = 0;
    var found = false;
    for (final l in lines) {
      if (!l.code.startsWith('6.02.') || l.depth != 3) continue;
      final d = normalize(l.label);
      if (!d.contains('imobiliz') && !d.contains('intangivel')) continue;
      cents += l.cents;
      found = true;
    }
    return found ? cents / 100.0 : null;
  }
}

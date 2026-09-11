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

/// Uma linha de demonstração, como a CVM a publica.
///
/// **O valor é guardado em centavos inteiros**, e não em `double`. O CSV traz
/// `VL_CONTA` como texto — `265438605.0000000000` — e uma escala em
/// `ESCALA_MOEDA`, quase sempre MIL. Converter o texto para `double` e depois
/// de volta para centavos presume que o `double` esteja limpo, o que é
/// presunção desnecessária quando a origem é texto. [CvmAccountLine.doTexto]
/// vai do texto ao inteiro sem passar por ponto flutuante.
class CvmAccountLine {
  /// `CD_CONTA` — o código do plano, com níveis separados por ponto.
  final String code;

  /// `DS_CONTA` — a descrição. Padronizada no nível raso, texto livre abaixo.
  final String label;

  /// Valor em **centavos**, já com a escala aplicada. É a forma canônica.
  final int cents;

  /// Declara a linha a partir dos centavos.
  const CvmAccountLine.emCentavos({
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
  /// **A ingestão da CVM não usa isto** — usa [CvmAccountLine.doTexto], que
  /// vai do texto do CSV ao inteiro sem ponto flutuante no caminho.
  CvmAccountLine.aproximada({
    required this.code,
    required this.label,
    required double value,
  }) : cents = (value * 100).round();

  /// Declara a linha a partir do texto do CSV, **sem ponto flutuante**.
  ///
  /// - [valor]: `VL_CONTA` como veio, com ou sem sinal e casas decimais.
  /// - [escala]: 1000 para `ESCALA_MOEDA` igual a MIL, 1 caso contrário.
  ///
  /// Devolve `null` para texto que não seja número — o que é resposta, e não
  /// falha: linha ilegível não entra na demonstração.
  static CvmAccountLine? doTexto({
    required String code,
    required String label,
    required String valor,
    int escala = 1,
  }) {
    final c = _centavos(valor, escala);
    return c == null
        ? null
        : CvmAccountLine.emCentavos(code: code, label: label, cents: c);
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
  static int? _centavos(String bruto, int escala) {
    var s = bruto.trim();
    if (s.isEmpty || escala <= 0) return null;
    var negativo = false;
    if (s.startsWith('-')) {
      negativo = true;
      s = s.substring(1);
    } else if (s.startsWith('+')) {
      s = s.substring(1);
    }
    final partes = s.split('.');
    if (partes.length > 2) return null;
    final inteira = partes[0].isEmpty ? '0' : partes[0];
    final decimais = partes.length == 2 ? partes[1] : '';
    if (!RegExp(r'^\d+$').hasMatch(inteira)) return null;
    if (decimais.isNotEmpty && !RegExp(r'^\d+$').hasMatch(decimais)) {
      return null;
    }

    // `bruto` = mantissa / 10^casas. Os centavos são
    // `mantissa × escala × 100 / 10^casas`, arredondados meio para cima —
    // tudo em inteiro, sem passar por ponto flutuante.
    final mantissa = BigInt.parse('$inteira$decimais');
    final divisor = BigInt.from(10).pow(decimais.length);
    final numerador = mantissa * BigInt.from(escala) * BigInt.from(100);
    var v = numerador ~/ divisor;
    final resto = numerador.remainder(divisor);
    if (resto * BigInt.two >= divisor) v += BigInt.one;
    if (negativo) v = -v;

    final teto = BigInt.parse('9223372036854775807');
    if (v > teto || v < -teto) return null;
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
enum CvmLayout {
  /// Plano padrão: `3.01 = Receita de Venda de Bens e/ou Serviços`.
  corporativo('não financeira'),

  /// Intermediação financeira. **Não tem EBIT** — a estrutura não separa
  /// resultado operacional de resultado financeiro, porque o financeiro *é* a
  /// operação.
  intermediacaoFinanceira('intermediação financeira'),

  /// Atividades seguradoras e resseguradoras. Também sem EBIT.
  seguradora('seguradora'),

  /// Nenhum padrão reconhecido. Tudo que dependa de layout devolve `null`.
  desconhecido('desconhecido');

  /// Rótulo para mensagem e diagnóstico.
  final String label;

  const CvmLayout(this.label);

  /// `true` quando a estrutura separa resultado operacional do financeiro.
  ///
  /// É a condição para que exista EBIT. Banco e seguradora não a satisfazem, e
  /// [CvmChart.ebit] devolve `null` para eles — o que é o certo: a via da
  /// firma já os recusa pela Porta 1.
  bool get temResultadoOperacional => this == CvmLayout.corporativo;
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
      CvmChart._(List.unmodifiable(lines), _detectar(lines));

  // ----------------------------------------------------------- normalização

  /// Minúsculas sem acento, para comparar descrição da fonte.
  ///
  /// Os CSVs da CVM vêm em `latin-1` e as descrições carregam acentuação
  /// inconsistente entre companhias. Comparar sem normalizar faz o mesmo
  /// rótulo casar num documento e não casar no seguinte.
  static String normalizar(String s) {
    const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const para = 'aaaaaeeeeiiiiooooouuuucn';
    final b = StringBuffer();
    for (final c in s.toLowerCase().runes) {
      final ch = String.fromCharCode(c);
      final i = de.indexOf(ch);
      b.write(i >= 0 ? para[i] : ch);
    }
    return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static CvmLayout _detectar(List<CvmAccountLine> lines) {
    for (final l in lines) {
      if (l.code != '3.01') continue;
      final d = normalizar(l.label);
      if (d.contains('intermediacao financeira')) {
        return CvmLayout.intermediacaoFinanceira;
      }
      if (d.contains('segurador') || d.contains('ressegurador')) {
        return CvmLayout.seguradora;
      }
      if (d.contains('receita')) return CvmLayout.corporativo;
    }
    // Sem DRE no documento — é balanço puro. O ativo e o passivo não dependem
    // de layout, então isto não impede a leitura deles.
    final temBalanco = lines.any((l) => l.code == '1' || l.code == '2');
    return temBalanco ? CvmLayout.corporativo : CvmLayout.desconhecido;
  }

  // -------------------------------------------------------------- resolução

  /// Linhas de nível até [ateNivel], que é onde o plano é padronizado.
  ///
  /// Abaixo do nível 2 a descrição é texto livre da companhia — a conferência
  /// encontrou 26 grafias distintas de "Caixa e Equivalentes" no nível 4 — e
  /// nada aqui deve descer até lá.
  Iterable<CvmAccountLine> rasas([int ateNivel = 2]) =>
      lines.where((l) => l.depth <= ateNivel);

  /// A linha de código exatamente [code], se existir.
  CvmAccountLine? porCodigo(String code) {
    for (final l in lines) {
      if (l.code == code) return l;
    }
    return null;
  }

  /// Procura entre as linhas rasas a que casa [padrao], preferindo o **maior**
  /// código.
  ///
  /// O maior código é o mais abaixo na demonstração, e a linha de resultado
  /// que interessa é sempre a última — no layout de banco "de Intermediação",
  /// tanto `3.07` ("Operações Continuadas") quanto `3.11` ("Líquido
  /// Consolidado do Período") casam com "lucro", e o certo é o segundo.
  CvmAccountLine? _buscar(
    RegExp padrao, {
    RegExp? excluindo,
    int ateNivel = 2,
  }) {
    CvmAccountLine? melhor;
    for (final l in rasas(ateNivel)) {
      final d = normalizar(l.label);
      if (!padrao.hasMatch(d)) continue;
      if (excluindo != null && excluindo.hasMatch(d)) continue;
      if (melhor == null || _maior(l.code, melhor.code)) melhor = l;
    }
    return melhor;
  }

  /// `true` quando [a] vem depois de [b] na ordem do plano de contas.
  ///
  /// Comparação **segmento a segmento como número**, e não como texto: `3.9`
  /// contra `3.11` daria a resposta errada em ordem lexicográfica, e o plano
  /// da CVM chega a dois dígitos por nível.
  static bool _maior(String a, String b) {
    final pa = a.split('.');
    final pb = b.split('.');
    for (var i = 0; i < pa.length && i < pb.length; i++) {
      final na = int.tryParse(pa[i]) ?? -1;
      final nb = int.tryParse(pb[i]) ?? -1;
      if (na != nb) return na > nb;
    }
    return pa.length > pb.length;
  }

  // ------------------------------------------------------ contas semânticas

  static final _reLucro = RegExp(r'(lucro|prejuizo)');
  static final _rePorAcao = RegExp(r'por acao');
  static final _reContinuadas = RegExp(r'(des)?continuada');
  static final _reAntesTributos = RegExp(r'antes.*(tributa|tributos|imposto)');
  static final _reTributos =
      RegExp(r'(imposto de renda|provisao para ir|tributos sobre o lucro)');
  static final _reEbit = RegExp(
    r'antes do resultado financeiro',
  );

  /// Receita do período. `3.01` em todos os layouts conferidos.
  double? get receita => porCodigo('3.01')?.value;

  /// Resultado antes do resultado financeiro e dos tributos — o **EBIT**.
  ///
  /// **`null` fora do layout corporativo, por decisão.** Banco e seguradora
  /// não separam operação de financeiro, e o `3.05` deles é "Resultado Antes
  /// dos Tributos" — devolvê-lo como EBIT erraria 13% no Itaú e daria à via da
  /// firma um número que ela não deve receber.
  double? get ebit {
    if (!layout.temResultadoOperacional) return null;
    final porDescricao = _buscar(_reEbit);
    if (porDescricao != null) return porDescricao.value;
    // Recuo pelo código, conferindo que a descrição não desminta.
    final l = porCodigo('3.05');
    if (l == null) return null;
    final d = normalizar(l.label);
    if (_reAntesTributos.hasMatch(d) && !_reEbit.hasMatch(d)) return null;
    return l.value;
  }

  /// Resultado antes dos tributos sobre o lucro.
  double? get resultadoAntesDosTributos =>
      _buscar(_reAntesTributos, excluindo: _rePorAcao)?.value;

  /// Imposto de renda e contribuição social.
  ///
  /// O sinal é o que a CVM publica — despesa vem **negativa** —, e quem
  /// consome deve preservá-lo. A `effectiveTaxRate` do motor já nega em vez de
  /// modular, pela correção de 10/09/2026 registrada na §2.1-b.
  double? get tributos => _buscar(_reTributos, excluindo: _rePorAcao)?.value;

  /// Lucro líquido do período.
  ///
  /// Procurado por descrição e não por código, e **excluindo** as linhas de
  /// operações continuadas e descontinuadas, que casam com "lucro" e não são o
  /// resultado final. Entre as que sobram vence o maior código, que é o fundo
  /// da demonstração.
  double? get lucroLiquido =>
      _buscar(_reLucro, excluindo: RegExp('${_rePorAcao.pattern}|'
              '${_reContinuadas.pattern}|reversao|juros sobre'))
          ?.value;

  /// Lucro por ação, quando publicado. `3.99` nos quatro layouts.
  double? get lucroPorAcao {
    final l = porCodigo('3.99');
    if (l == null) return null;
    return _rePorAcao.hasMatch(normalizar(l.label)) ? l.value : null;
  }

  // --- Balanço: não depende de layout, os códigos de topo são universais ---

  /// Ativo total — `1`. **Existe em 100% do universo conferido**, e é o que
  /// torna possível a conferência analítica que a §2.17 dizia não haver.
  double? get ativoTotal => porCodigo('1')?.value;

  /// Ativo circulante — `1.01`.
  double? get ativoCirculante => porCodigo('1.01')?.value;

  /// Ativo não circulante — `1.02`.
  double? get ativoNaoCirculante => porCodigo('1.02')?.value;

  /// Passivo total — `2`.
  double? get passivoTotal => porCodigo('2')?.value;

  /// Passivo circulante — `2.01`.
  double? get passivoCirculante => porCodigo('2.01')?.value;

  /// Passivo não circulante — `2.02`.
  double? get passivoNaoCirculante => porCodigo('2.02')?.value;

  /// Patrimônio líquido consolidado.
  ///
  /// `2.03` no layout corporativo e `2.07` ou `2.08` no de banco — por isso a
  /// busca é por descrição entre os três.
  double? get patrimonioLiquido =>
      _buscar(RegExp(r'patrimonio liquido'), excluindo: RegExp(r'controlador'))
          ?.value;

  /// Participação dos não controladores no patrimônio.
  ///
  /// `2.03.09` no layout corporativo, `2.07.02` no de banco — nível 3, que é a
  /// única exceção ao limite de nível 2, e ela é segura porque a descrição
  /// "não controladores" é padronizada.
  double? get participacaoNaoControladores {
    final l = _buscar(RegExp(r'nao controlador'), ateNivel: 3);
    if (l == null) return null;
    // "Patrimônio Líquido Atribuído aos Não Controladores" e "Participação dos
    // Acionistas Não Controladores" descrevem a mesma coisa; ambas servem.
    return l.value;
  }

  // --- Fluxo de caixa: códigos de topo universais no método indireto ---

  /// Caixa líquido das atividades operacionais — `6.01`.
  double? get caixaOperacional => porCodigo('6.01')?.value;

  /// Caixa líquido das atividades de investimento — `6.02`.
  double? get caixaDeInvestimento => porCodigo('6.02')?.value;

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
    var centavos = 0;
    var achou = false;
    for (final l in lines) {
      if (!l.code.startsWith('6.02.') || l.depth != 3) continue;
      final d = normalizar(l.label);
      if (!d.contains('imobiliz') && !d.contains('intangivel')) continue;
      centavos += l.cents;
      achou = true;
    }
    return achou ? centavos / 100.0 : null;
  }
}

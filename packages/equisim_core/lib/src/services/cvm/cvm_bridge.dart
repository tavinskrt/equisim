/// A ponte entre o ticker negociado e o CNPJ que arquiva na CVM.
///
/// **Por que ela não é trivial.** A CVM identifica companhia por CNPJ; a bolsa,
/// por ticker. O FCA publica `Codigo_Negociacao`, que **parece** ser a ponte e
/// não é: conferido em 11/09/2026 sobre 1.023 linhas do FCA 2024, **44% vêm em
/// branco**, e o resto traz código CVM (`25585` na CSN Mineração), zeros
/// (`000000` no BTG) ou a string `ADR` (Marfrig).
///
/// A resolução usa quatro regras, em ordem, e **para na primeira que
/// responde**:
///
/// 1. `Codigo_Negociacao` com **formato de ticker**, sobre todos os anos de
///    FCA disponíveis. Sete anos dão 644 códigos e **zero ambiguidade**.
/// 2. Propagação pela **raiz de quatro letras**, quando ela aponta para um
///    CNPJ único — é o que resolve a classe que a companhia não declarou.
/// 3. Nome **idêntico** após normalização.
/// 4. [overrides], a tabela declarada abaixo.
///
/// **Casamento aproximado de nome está proibido, e a razão está medida.** Com
/// corte de similaridade em 0,62, `CSNA3` — cujo nome na fonte de preços é só
/// "CSN" — casa com **COSAN S.A.** a 0,75: confiante e errado. Uma ponte errada
/// não falha, ela avalia a empresa trocada.
///
/// Ver `docs/validacao/cvm_conferencia.md §2`.
library;

/// Resolve ticker para CNPJ.
abstract final class CvmBridge {
  /// Um código só é candidato a ticker se tiver a forma da B3.
  ///
  /// É este filtro que descarta `25585`, `000000` e `ADR` sem precisar
  /// enumerá-los.
  ///
  /// **A raiz admite dígito depois da primeira posição**, e não admiti-lo foi
  /// defeito: `B3SA3` — a própria B3 — tem raiz `B3SA`. A primeira versão
  /// exigia `[A-Z]{4}` e descartava a bolsa como se fosse lixo de
  /// preenchimento. O que separa ticker de código CVM é **começar por letra**,
  /// não ser todo de letras.
  static final RegExp tickerFormat = RegExp(r'^[A-Z][A-Z0-9]{3}[0-9]{1,2}$');

  /// `true` quando [codigo] tem forma de ticker negociável.
  static bool pareceTicker(String codigo) =>
      tickerFormat.hasMatch(codigo.trim().toUpperCase());

  /// Raiz de quatro letras — as classes de uma mesma companhia a compartilham.
  ///
  /// Devolve `null` para código que não tenha a forma esperada, em vez de
  /// recortar às cegas: `substring(0, 4)` sobre uma entrada curta lança, e
  /// sobre uma entrada estranha inventa uma raiz que casaria com outra coisa.
  static String? raiz(String ticker) {
    final t = ticker.trim().toUpperCase();
    return tickerFormat.hasMatch(t) ? t.substring(0, 4) : null;
  }

  /// Nome em minúsculas, sem acento e sem os sufixos societários que a CVM e a
  /// fonte de preços grafam de formas diferentes.
  ///
  /// Serve **apenas** para igualdade exata. Não use para similaridade.
  static String normalizarNome(String nome) {
    const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const para = 'aaaaaeeeeiiiiooooouuuucn';
    final b = StringBuffer();
    for (final c in nome.toLowerCase().runes) {
      final ch = String.fromCharCode(c);
      final i = de.indexOf(ch);
      b.write(i >= 0 ? para[i] : ch);
    }
    // Cerca com espaço antes de remover os termos: sem isso ` cia ` não casa
    // em "CIA SIDERURGICA NACIONAL", que começa por ele, e o nome sai
    // diferente do mesmo nome escrito com prefixo.
    var s = ' ${b.toString()} ';
    for (final p in const ['.', ',', '-', '/']) {
      s = s.replaceAll(p, ' ');
    }
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    for (final termo in const [
      ' s a ', ' sa ', ' participacoes ', ' part ', ' holding ',
      ' cia ', ' companhia ', ' bco ', ' banco ',
    ]) {
      while (s.contains(termo)) {
        s = s.replaceAll(termo, ' ');
      }
    }
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Tabela declarada, para o que as três regras automáticas não alcançam.
  ///
  /// **Cada entrada é uma afirmação verificada contra o `DENOM_CIA` da CVM**,
  /// não um palpite. Companhias grandes caem aqui porque nunca preencheram o
  /// `Codigo_Negociacao` com o ticker — o BTG grafa `000000` e a B3 não grafa
  /// nada.
  static const Map<String, String> overrides = {
    // Nunca declararam o código no FCA.
    'B3SA3': '09.346.601/0001-25', // B3 S.A. - BRASIL, BOLSA, BALCÃO
    'CSNA3': '33.042.730/0001-04', // CIA SIDERURGICA NACIONAL
    'BPAC3': '30.306.294/0001-45', // BCO BTG PACTUAL S.A.
    'BPAC5': '30.306.294/0001-45',
    'BPAC11': '30.306.294/0001-45',
    'B1003': '52.270.350/0001-71', // B100 S.A.
    'CTAX3': '04.032.433/0001-80', // CONTAX PARTICIPAÇÕES — em recuperação
    'NORD3': '60.884.319/0001-59', // NORDON INDUSTRIAS METALURGICAS
    'HAGA3': '30.540.991/0001-66', // HAGA S.A. INDUSTRIA E COMERCIO
    'HAGA4': '30.540.991/0001-66',
  };

  /// Tickers cuja companhia **não foi encontrada** nos arquivos de 2024, e que
  /// por isso ficam sem ponte até que a carga histórica os alcance.
  ///
  /// Estão aqui **nomeados** em vez de silenciosamente ausentes, porque uma
  /// lacuna declarada é dívida e uma lacuna silenciosa é defeito.
  ///
  /// - `FASA3`, `LUXM4`, `OBTC3`: sem companhia correspondente em 2024;
  ///   provável deslistagem ou mudança de razão social. A carga de todos os
  ///   anos (A1.6) deve alcançá-los.
  /// - `MAPT3`: o nome na fonte de preços é "CIA MARCOPOLO", que casa com
  ///   `MARCOPOLO S.A.` — **mas a Marcopolo negocia como POMO3 e POMO4**. É o
  ///   mesmo formato de engano do `CSNA3`/`COSAN`, e por isso fica sem ponte
  ///   em vez de receber a errada.
  static const Set<String> semPonte = {'FASA3', 'LUXM4', 'OBTC3', 'MAPT3'};

  /// Resolve o CNPJ de [ticker].
  ///
  /// - [porCodigo]: mapa ticker → CNPJ construído do FCA, já filtrado por
  ///   [pareceTicker] e já conferido como não ambíguo.
  /// - [porNome]: mapa nome normalizado → CNPJ, do `DENOM_CIA` da CVM.
  /// - [nomeDoAtivo]: nome do ativo na fonte de preços, para a regra 3.
  ///
  /// Devolve `null` quando nenhuma regra responde — e isso é resposta, não
  /// falha.
  static String? resolver(
    String ticker, {
    required Map<String, String> porCodigo,
    Map<String, String> porNome = const {},
    String? nomeDoAtivo,
  }) {
    final t = ticker.trim().toUpperCase();

    // O veto vem **antes** de tudo, e é o que [semPonte] significa. Deixá-lo
    // como comentário não bastou: o `MAPT3` foi resolvido para a Marcopolo
    // pela regra de nome, ao lado de `POMO3` e `POMO4`, que é o engano que a
    // própria lista existia para impedir.
    if (semPonte.contains(t)) return null;

    final direto = porCodigo[t];
    if (direto != null) return direto;

    final r = raiz(t);
    if (r != null) {
      final daRaiz = <String>{
        for (final e in porCodigo.entries)
          if (e.key.startsWith(r) && raiz(e.key) == r) e.value,
      };
      if (daRaiz.length == 1) return daRaiz.first;
    }

    if (nomeDoAtivo != null) {
      final porExato = porNome[normalizarNome(nomeDoAtivo)];
      if (porExato != null) return porExato;
    }

    return overrides[t];
  }

  /// Resolve o universo inteiro, **propagando a raiz depois** de todas as
  /// outras regras.
  ///
  /// A propagação tardia é o que resolve `AXIA7` e `EQPA5`: nenhum dos dois é
  /// alcançado pelas regras diretas, mas `AXIA3` e `EQPA3` são — pelo nome —, e
  /// classes da mesma raiz são a mesma companhia. Propagar **antes** não
  /// funcionaria, porque na primeira passada a raiz ainda não tem nenhum
  /// membro resolvido.
  ///
  /// - [tickers]: universo a resolver.
  /// - [nomes]: nome de cada ativo na fonte de preços, quando houver.
  static Map<String, String> resolverUniverso(
    Iterable<String> tickers, {
    required Map<String, String> porCodigo,
    Map<String, String> porNome = const {},
    Map<String, String> nomes = const {},
  }) {
    final out = <String, String>{};
    for (final t in tickers) {
      final c = resolver(t,
          porCodigo: porCodigo, porNome: porNome, nomeDoAtivo: nomes[t]);
      if (c != null) out[t.trim().toUpperCase()] = c;
    }

    // Segunda passada: quem ficou de fora herda o CNPJ da própria raiz, se ela
    // for unânime entre os já resolvidos.
    final porRaiz = <String, Set<String>>{};
    for (final e in out.entries) {
      final r = raiz(e.key);
      if (r != null) porRaiz.putIfAbsent(r, () => {}).add(e.value);
    }
    for (final t in tickers) {
      final k = t.trim().toUpperCase();
      if (out.containsKey(k)) continue;
      if (semPonte.contains(k)) continue;
      final r = raiz(k);
      if (r == null) continue;
      final c = porRaiz[r];
      if (c != null && c.length == 1) out[k] = c.first;
    }
    return out;
  }

  /// Companhias alcançadas por tickers de **raízes diferentes**.
  ///
  /// **É a regra geral que o veto de [semPonte] resolve caso a caso.** As
  /// classes de uma companhia compartilham a raiz — `POMO3` e `POMO4` são a
  /// Marcopolo. Quando um CNPJ recebe `POMO` **e** `MAPT`, uma das duas pontes
  /// está errada, e nenhuma medição interna diz qual.
  ///
  /// Não remove nada por conta própria: uma companhia pode legitimamente ter
  /// mudado de raiz — a Natura virou `NTCO` — e apagar o histórico seria pior.
  /// Devolve o conflito para quem carrega decidir, e para o relatório mostrar.
  ///
  /// Devolve CNPJ → conjunto de raízes, apenas onde há mais de uma.
  static Map<String, Set<String>> conflitosDeRaiz(Map<String, String> ponte) {
    final porCnpj = <String, Set<String>>{};
    for (final e in ponte.entries) {
      final r = raiz(e.key);
      if (r != null) porCnpj.putIfAbsent(e.value, () => {}).add(r);
    }
    return {
      for (final e in porCnpj.entries)
        if (e.value.length > 1) e.key: e.value,
    };
  }
}

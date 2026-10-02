// A contagem de ações por data conferida contra o salto do preço (item B43).
//
// **Por que conferir.** A contagem do Formulário de Referência erra de escala
// nos dois sentidos. A correção reenviada às vezes repete a contagem de antes
// de um grupamento: a Ampla agrupou 40.000 para 1 em dezembro de 2015, e a
// correção de maio de 2016 volta aos 3,9 trilhões de ações — vezes o preço de
// depois, R$ 142 trilhões de valor de mercado; a Hapvida (2025) e o IRB (2024)
// fazem o mesmo. E às vezes a correção é o **único** registro de um grupamento
// de verdade: a Magazine Luiza agrupou 10 para 1 em maio de 2024, e a contagem
// só cai de 7,39 bilhões para 739 milhões na correção de maio de 2025 — a coorte
// de 31/03/2025 foi avaliada com dez vezes as ações que a companhia tinha. A
// fonte da entrada não separa os dois casos; o preço separa: num grupamento de
// dez para um, o preço fica dez vezes maior de um pregão para o outro.
//
// **A regra.** Parte da contagem mais recente até a data de corte e anda para
// trás. Cada entrada é comparada com a última aceita depois dela: a diferença de
// até [mudancaGrandeDaContagem] vezes vale como veio (emissão, recompra,
// conversão). Na maior, o preço decide:
//
// - com o salto correspondente no preço bruto de algum papel da companhia,
//   entre a data da entrada e [prazoDoSaltoDoPreco] dias depois da aceita, a
//   mudança é grupamento ou desdobramento, e a aceita passa a valer **no dia do
//   salto**, para que ação e preço mudem de base juntos;
// - sem o salto, a mudança não é evento de ações: é emissão ou incorporação
//   grande — a Dasa e a Light se capitalizaram, a Azul reestruturou — e vale
//   como veio, **a menos que a entrada seja uma correção de formulário**
//   (`filingCorrection`). A correção sem salto é a que repete a contagem de
//   antes do evento, e é descartada; o trecho dela fica com a contagem anterior
//   a ela. (Descartar toda mudança grande sem salto tirava das coortes, antes da
//   emissão, justamente as companhias que se capitalizaram em crise: viés de
//   seleção na validação.)
//
// A âncora é a contagem mais recente porque é a que o formulário de hoje
// confirma.
//
// **O que a regra não pega:** a entrada primária errada. A da TIM começa em
// julho de 2020 com 423 milhões — a contagem da TIM S.A. antes da incorporação
// da controladora —, contra os 2,42 bilhões que a ação tem desde então; é um
// evento de ações registrado, sem salto no preço, e fica como veio.
import 'dart:math' as math;

import '../b3/proventos.dart' show Pregao;

/// Mudança, em vezes, a partir da qual o preço tem de confirmar a contagem.
const mudancaGrandeDaContagem = 3.0;

/// Dias depois da contagem nova em que o salto do preço ainda a confirma: a
/// aprovação do desdobramento vem meses antes da data ex (a da PRIO, de
/// 28/01/2021, para a data ex de 06/05/2021). É o prazo do item B30.
const prazoDoSaltoDoPreco = 400;

/// Folga, em vezes, entre o salto do preço e o inverso da mudança da contagem.
const toleranciaDoSaltoDoPreco = 1.4;

/// Pregões consecutivos mais distantes que isto não formam um salto.
const _maiorIntervaloDoSalto = 30;

/// Uma entrada da contagem. [fonte] é a do arquivo, quando ele a traz.
typedef EntradaDaContagem = ({DateTime desde, double acoes, String? fonte});

/// Uma entrada que o preço não confirmou, e a contagem aceita depois dela.
typedef ContagemDescartada = ({
  DateTime desde,
  double acoes,
  double posterior,
  String? fonte,
});

/// O primeiro pregão entre [de] e [ate] em que o preço bruto de alguma das
/// [series] saltou [fator] vezes, com folga de [toleranciaDoSaltoDoPreco].
DateTime? saltoDoPreco(
  Iterable<List<Pregao>> series,
  double fator,
  DateTime de,
  DateTime ate,
) {
  final alvo = math.log(fator);
  final folga = math.log(toleranciaDoSaltoDoPreco);
  DateTime? primeiro;
  for (final s in series) {
    for (var i = 1; i < s.length; i++) {
      final a = s[i - 1], b = s[i];
      if (b.date.isBefore(de) || b.date.isAfter(ate)) continue;
      if (b.date.difference(a.date).inDays > _maiorIntervaloDoSalto) continue;
      if (!(a.close > 0) || !(b.close > 0)) continue;
      if ((math.log(b.close / a.close) - alvo).abs() >= folga) continue;
      if (primeiro == null || b.date.isBefore(primeiro)) primeiro = b.date;
      break;
    }
  }
  return primeiro;
}

/// A contagem conferida contra o preço, em ordem de data, e as entradas
/// descartadas.
///
/// - [contagem]: as entradas do formulário, em qualquer ordem;
/// - [series]: os pregões brutos de cada papel de espécie da companhia;
/// - [ate]: a data de corte — entrada posterior a ela não entra, nem como
///   âncora (o arquivo traz datas no futuro, de digitação).
({
  List<({DateTime desde, double acoes})> aceitas,
  List<ContagemDescartada> descartadas,
})
conferirContagem(
  List<EntradaDaContagem> contagem,
  Iterable<List<Pregao>> series, {
  required DateTime ate,
}) {
  final entradas = [
    for (final p in contagem)
      if (p.acoes > 0 && !p.desde.isAfter(ate)) p,
  ]..sort((a, b) => a.desde.compareTo(b.desde));
  final descartadas = <ContagemDescartada>[];
  // Da mais recente para a mais antiga; o `desde` da aceita pode recuar ao dia
  // do salto do preço.
  final aceitas = <({DateTime desde, double acoes})>[];
  DateTime? dataDaAceita;
  for (final p in entradas.reversed) {
    if (aceitas.isEmpty || dataDaAceita == null) {
      aceitas.add((desde: p.desde, acoes: p.acoes));
      dataDaAceita = p.desde;
      continue;
    }
    final posterior = aceitas.last;
    final mudanca = posterior.acoes / p.acoes;
    if (mudanca <= mudancaGrandeDaContagem &&
        mudanca >= 1 / mudancaGrandeDaContagem) {
      aceitas.add((desde: p.desde, acoes: p.acoes));
      dataDaAceita = p.desde;
      continue;
    }
    final salto = saltoDoPreco(
      series,
      1 / mudanca,
      p.desde,
      dataDaAceita.add(const Duration(days: prazoDoSaltoDoPreco)),
    );
    if (salto == null && p.fonte != 'filingCorrection') {
      aceitas.add((desde: p.desde, acoes: p.acoes));
      dataDaAceita = p.desde;
      continue;
    }
    if (salto == null) {
      descartadas.add((
        desde: p.desde,
        acoes: p.acoes,
        posterior: posterior.acoes,
        fonte: p.fonte,
      ));
      continue;
    }
    // As entradas da contagem nova anteriores ao salto — a aprovação costuma
    // vir antes da data ex — passam a valer no dia dele.
    var daNova = posterior.acoes;
    while (aceitas.isNotEmpty && aceitas.last.desde.isBefore(salto)) {
      daNova = aceitas.removeLast().acoes;
    }
    aceitas
      ..add((desde: salto, acoes: daNova))
      ..add((desde: p.desde, acoes: p.acoes));
    dataDaAceita = p.desde;
  }
  return (aceitas: aceitas.reversed.toList(), descartadas: descartadas);
}

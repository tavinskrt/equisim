import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

/// A volta entre o veredito do moat e a taxa de equilíbrio (item D3).
///
/// O veredito aqui é um `double?` — o retorno terminal que ele concede — e as
/// taxas são a taxa terminal. As funções sintéticas reproduzem os três
/// desfechos que a cascata trata: estabiliza, alterna até o teto, e trava no
/// solucionador.
void main() {
  // A "taxa" que cada retorno terminal produz: alta com moat, baixa sem.
  double taxaDe(double? moat) => moat == null ? 0.10 : 0.12;

  test('estabiliza quando o veredito refeito repete o anterior', () {
    final r = MoatFixedPoint.iterate<double?, double>(
      verdict: 0.15,
      moat: 0.15,
      rates: taxaDe(0.15),
      reassess: (_) => 0.15,
      moatOf: (v) => v,
      solve: taxaDe,
    );
    expect(r.stable, isTrue);
    expect(r.passes, 1);
    expect(r.moat, 0.15);
  });

  test('converge em alguns passes e devolve o par do último', () {
    // O veredito sobe até 0,15 e para: 0,12 → 0,14 → 0,15 → 0,15. A escada
    // é indexada pelo passe, e não pelo valor: `double` não serve de chave
    // (regra R6).
    const escada = [0.14, 0.15, 0.15];
    var passe = 0;
    final r = MoatFixedPoint.iterate<double?, double>(
      verdict: 0.12,
      moat: 0.12,
      rates: taxaDe(0.12),
      reassess: (_) => escada[passe],
      moatOf: (v) => v,
      solve: (m) {
        passe++;
        return taxaDe(m);
      },
    );
    expect(r.stable, isTrue);
    expect(r.passes, 3);
    expect(r.moat, 0.15);
    expect(r.verdict, 0.15);
  });

  test('alterna até o teto, e o par devolvido é consistente entre si', () {
    // O ativo na fronteira: com a taxa do moat (0,12) o excedente some e o
    // veredito recusa; sem moat a taxa cai (0,10), o excedente volta e o
    // veredito concede. Para sempre.
    final r = MoatFixedPoint.iterate<double?, double>(
      verdict: 0.15,
      moat: 0.15,
      rates: taxaDe(0.15),
      reassess: (taxa) => taxa > 0.11 ? null : 0.15,
      moatOf: (v) => v,
      solve: taxaDe,
      maxPasses: 5,
    );
    expect(r.stable, isFalse);
    expect(r.solverFailed, isFalse);
    expect(r.passes, 5);
    // Consistência: a taxa devolvida é a do moat devolvido, e não a do passe
    // seguinte — que nunca foi adotado.
    expect(r.rates, taxaDe(r.moat));
    expect(r.verdict, r.moat);
  });

  test('o teto padrão é o da cascata', () {
    var chamadas = 0;
    final r = MoatFixedPoint.iterate<double?, double>(
      verdict: 0.15,
      moat: 0.15,
      rates: taxaDe(0.15),
      reassess: (taxa) {
        chamadas++;
        return taxa > 0.11 ? null : 0.15;
      },
      moatOf: (v) => v,
      solve: taxaDe,
    );
    expect(r.passes, ValuationParameters.moatMaxPasses);
    expect(chamadas, ValuationParameters.moatMaxPasses - 1);
  });

  test('o solucionador que não fecha para a volta no último par válido', () {
    final r = MoatFixedPoint.iterate<double?, double>(
      verdict: 0.15,
      moat: 0.15,
      rates: taxaDe(0.15),
      reassess: (_) => null,
      moatOf: (v) => v,
      solve: (_) => null,
    );
    expect(r.solverFailed, isTrue);
    expect(r.stable, isFalse);
    expect(r.passes, 1);
    // O veredito que pedia a taxa inexistente não foi adotado.
    expect(r.moat, 0.15);
    expect(r.verdict, 0.15);
    expect(r.rates, taxaDe(0.15));
  });

  test('a imposição externa vale sobre o veredito refeito', () {
    // `moatOf` é onde `terminalReturnOverride` entra: com ela, o veredito
    // pode mudar à vontade que o retorno terminal não muda.
    final r = MoatFixedPoint.iterate<double?, double>(
      verdict: 0.15,
      moat: 0.20,
      rates: taxaDe(0.20),
      reassess: (taxa) => taxa > 0.11 ? null : 0.15,
      moatOf: (_) => 0.20,
      solve: taxaDe,
    );
    expect(r.stable, isTrue);
    expect(r.moat, 0.20);
  });
}

// O poder do teste do R3 (item C6): a simulação tem de estar calibrada antes de
// dizer qualquer coisa sobre o motor.
import 'package:flutter_test/flutter_test.dart';

import '../../tool/poder_r3.dart';
import '../../tool/validation/regression.dart';

void main() {
  // A amostra do R3: 22 coortes trimestrais de 36 meses, 11 sobreposições.
  const k = 22, overlap = 11;
  final critico = Regression.overlapCritical(k, overlap);

  test('sem efeito, o poder é o nível do critério', () {
    // `t > 2` unilateral sob a normal é 2,28%; o Newey-West acima de 2 só pode
    // tirar, e 4.000 sorteios têm erro-padrão de 0,24 p.p.
    final nivel =
        poder(mu: 0, desvio: 1, k: k, overlap: overlap, critico: critico);
    expect(nivel, lessThan(Regression.r3Tail + 0.01));
    expect(nivel, greaterThan(0.005));
  });

  test('o poder cresce com o efeito e chega a quase 1', () {
    double p(double mu) =>
        poder(mu: mu, desvio: 1, k: k, overlap: overlap, critico: critico);
    expect(p(0.5), greaterThan(p(0)));
    expect(p(1.5), greaterThan(p(0.5)));
    expect(p(6), greaterThan(0.99));
  });

  test('o efeito mínimo detectável tem 80% de poder, e não mais que isso', () {
    final mde = efeitoMinimo(
        desvio: 1, k: k, overlap: overlap, critico: critico);
    expect(
        poder(mu: mde, desvio: 1, k: k, overlap: overlap, critico: critico),
        greaterThanOrEqualTo(0.8));
    expect(
        poder(
            mu: mde * 0.9, desvio: 1, k: k, overlap: overlap, critico: critico),
        lessThan(0.8));
  });

  test('a data de disponibilidade confere com a amostra que existe', () {
    // A 22ª coorte é a de 30/06/2023, e o retorno de 36 meses dela fecha em
    // 30/06/2026 — o último que o backtest de 22/09/2026 tinha.
    expect(disponivelEm(22, 36), DateTime.utc(2026, 6, 30));
    expect(disponivelEm(1, 12), DateTime.utc(2019, 3, 31));
  });
}

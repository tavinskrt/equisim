import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

bool _fin(String? chave, [String? sub]) =>
    FinancialSectors.isFinancial(sectorKey: chave, industry: sub);

void main() {
  group('Porta 1 pela taxonomia oficial — item A5', () {
    test('os três bancos que chegavam sem setor passam a ser financeiros', () {
      // BRSR6, PINE4 e SANB4: a B3 os classifica pelo emissor.
      expect(_fin('financeiro', 'Intermediários Financeiros / Bancos'), isTrue);
    });

    test('seguradora, resseguradora e bolsa entram', () {
      expect(_fin('financeiro', 'Previdência e Seguros / Seguradoras'), isTrue);
      expect(_fin('financeiro', 'Previdência e Seguros / Resseguradoras'), isTrue);
      expect(
          _fin('financeiro',
              'Serviços Financeiros Diversos / Serviços Financeiros Diversos'),
          isTrue);
    });

    test('shopping e holding, que a B3 também põe em Financeiro, não entram',
        () {
      expect(_fin('financeiro', 'Exploração de Imóveis / Exploração de Imóveis'),
          isFalse);
      expect(
          _fin('financeiro', 'Holdings Diversificadas / Holdings Diversificadas'),
          isFalse);
      expect(_fin('financeiro'), isFalse, reason: 'setor sem subsetor não basta');
    });

    test('a chave da fonte de preços continua valendo no recuo', () {
      expect(_fin('servicos-financeiros'), isTrue);
      expect(_fin('Servicos-Financeiros'), isTrue);
      expect(_fin('Finance'), isFalse,
          reason: 'a taxonomia da listagem nunca foi a do perfil');
      expect(_fin(null), isFalse);
      expect(_fin('utilidade-publica', 'Energia Elétrica / Energia Elétrica'),
          isFalse);
    });
  });
}

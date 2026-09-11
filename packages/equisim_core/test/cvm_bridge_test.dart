import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

void main() {
  group('Filtro de formato', () {
    test('descarta o que a fonte grafa no lugar do ticker', () {
      // Medidos no FCA 2024: codigo CVM, zeros e a string ADR.
      for (final lixo in ['25585', '000000', 'ADR', '022055', '', '   ']) {
        expect(CvmBridge.pareceTicker(lixo), isFalse, reason: lixo);
      }
      for (final bom in ['PETR4', 'BPAC11', 'ITUB3', 'b3sa3']) {
        expect(CvmBridge.pareceTicker(bom), isTrue, reason: bom);
      }
    });

    test('a raiz recusa entrada malformada em vez de recortar', () {
      expect(CvmBridge.raiz('PETR4'), 'PETR');
      expect(CvmBridge.raiz('BPAC11'), 'BPAC');
      expect(CvmBridge.raiz('ADR'), isNull);
      expect(CvmBridge.raiz('25585'), isNull);
      expect(CvmBridge.raiz('AB'), isNull);
    });
  });

  group('Resolução', () {
    test('o código direto vence', () {
      expect(
        CvmBridge.resolver('PETR4', porCodigo: {'PETR4': 'CNPJ-PETRO'}),
        'CNPJ-PETRO',
      );
    });

    test('a raiz resolve a classe que a companhia não declarou', () {
      expect(
        CvmBridge.resolver('KLBN3', porCodigo: {'KLBN11': 'CNPJ-KLABIN'}),
        'CNPJ-KLABIN',
      );
    });

    test('raiz ambígua não resolve', () {
      expect(
        CvmBridge.resolver('XXXX3',
            porCodigo: {'XXXX4': 'CNPJ-A', 'XXXX11': 'CNPJ-B'}),
        isNull,
      );
    });

    test('nome idêntico resolve; parecido não', () {
      const porNome = {'siderurgica nacional': 'CNPJ-CSN', 'cosan': 'CNPJ-COSAN'};
      expect(
        CvmBridge.resolver('QQQQ3',
            porCodigo: const {}, porNome: porNome,
            nomeDoAtivo: 'CIA SIDERURGICA NACIONAL'),
        'CNPJ-CSN',
      );
      // "CSN" nao e "COSAN". Com similaridade de 0,62 o casamento aproximado
      // dava COSAN a 0,75 — confiante e errado. Aqui simplesmente nao casa.
      expect(
        CvmBridge.resolver('CSNA9',
            porCodigo: const {}, porNome: porNome, nomeDoAtivo: 'CSN'),
        isNull,
      );
    });

    test('a tabela declarada é o último recurso, e alcança o que falta', () {
      expect(CvmBridge.resolver('B3SA3', porCodigo: const {}),
          '09.346.601/0001-25');
      expect(CvmBridge.resolver('CSNA3', porCodigo: const {}),
          '33.042.730/0001-04');
      // As tres classes do BTG apontam para a mesma companhia.
      final btg = {
        for (final t in ['BPAC3', 'BPAC5', 'BPAC11'])
          CvmBridge.resolver(t, porCodigo: const {})
      };
      expect(btg.length, 1);
    });

    test('o veto de semPonte vence TODAS as regras', () {
      // Nao basta declarar: o MAPT3 foi resolvido para a Marcopolo pela regra
      // de nome, ao lado de POMO3 e POMO4, enquanto semPonte era so comentario.
      expect(
        CvmBridge.resolver('MAPT3',
            porCodigo: const {'MAPT3': 'CNPJ-QUALQUER'},
            porNome: const {'marcopolo': 'CNPJ-MARCOPOLO'},
            nomeDoAtivo: 'CIA MARCOPOLO'),
        isNull,
      );
      for (final t in CvmBridge.semPonte) {
        expect(CvmBridge.resolver(t, porCodigo: const {}), isNull, reason: t);
      }
    });

    test('o veto sobrevive a propagacao de raiz', () {
      final out = CvmBridge.resolverUniverso(
        const ['MAPT3', 'MAPT4'],
        porCodigo: const {'MAPT4': 'CNPJ-X'},
      );
      expect(out['MAPT4'], 'CNPJ-X');
      expect(out.containsKey('MAPT3'), isFalse);
    });
  });

  group('Conflito de raiz', () {
    test('denuncia companhia alcancada por duas raizes', () {
      final c = CvmBridge.conflitosDeRaiz(const {
        'POMO3': 'CNPJ-MARCO',
        'POMO4': 'CNPJ-MARCO',
        'MAPT3': 'CNPJ-MARCO',
        'PETR4': 'CNPJ-PETRO',
      });
      expect(c.keys, ['CNPJ-MARCO']);
      expect(c['CNPJ-MARCO'], {'POMO', 'MAPT'});
    });

    test('nao denuncia companhia de raiz unica', () {
      expect(
        CvmBridge.conflitosDeRaiz(
            const {'PETR3': 'CNPJ-P', 'PETR4': 'CNPJ-P'}),
        isEmpty,
      );
    });
  });

  group('Universo', () {
    test('a propagação de raiz acontece DEPOIS das outras regras', () {
      // AXIA7 nao e alcancado por regra nenhuma; AXIA3 e, pelo nome. Propagar
      // antes nao resolveria, porque na primeira passada a raiz AXIA ainda
      // nao tem membro resolvido.
      final out = CvmBridge.resolverUniverso(
        const ['AXIA3', 'AXIA7'],
        porCodigo: const {},
        porNome: const {'axia energia': 'CNPJ-AXIA'},
        nomes: const {'AXIA3': 'AXIA ENERGIA S.A.'},
      );
      expect(out['AXIA3'], 'CNPJ-AXIA');
      expect(out['AXIA7'], 'CNPJ-AXIA');
    });

    test('não propaga quando a raiz discorda', () {
      final out = CvmBridge.resolverUniverso(
        const ['YYYY3', 'YYYY4', 'YYYY11'],
        porCodigo: const {'YYYY3': 'CNPJ-A', 'YYYY4': 'CNPJ-B'},
      );
      expect(out['YYYY11'], isNull);
    });

    test('normaliza a chave de saída', () {
      final out = CvmBridge.resolverUniverso(const ['  petr4 '],
          porCodigo: const {'PETR4': 'CNPJ-P'});
      expect(out['PETR4'], 'CNPJ-P');
    });
  });
}

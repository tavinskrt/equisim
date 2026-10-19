import 'package:equisim_core/equisim_core.dart';
import 'package:test/test.dart';

void main() {
  group('Filtro de formato', () {
    test('descarta o que a fonte grafa no lugar do ticker', () {
      // Medidos no FCA 2024: codigo CVM, zeros e a string ADR.
      for (final garbage in ['25585', '000000', 'ADR', '022055', '', '   ']) {
        expect(CvmBridge.looksLikeTicker(garbage), isFalse, reason: garbage);
      }
      for (final valid in ['PETR4', 'BPAC11', 'ITUB3', 'b3sa3']) {
        expect(CvmBridge.looksLikeTicker(valid), isTrue, reason: valid);
      }
    });

    test('a raiz recusa entrada malformada em vez de recortar', () {
      expect(CvmBridge.root('PETR4'), 'PETR');
      expect(CvmBridge.root('BPAC11'), 'BPAC');
      expect(CvmBridge.root('ADR'), isNull);
      expect(CvmBridge.root('25585'), isNull);
      expect(CvmBridge.root('AB'), isNull);
    });
  });

  group('Resolução', () {
    test('o código direto vence', () {
      expect(
        CvmBridge.resolver('PETR4', byCode: {'PETR4': 'CNPJ-PETRO'}),
        'CNPJ-PETRO',
      );
    });

    test('a raiz resolve a classe que a companhia não declarou', () {
      expect(
        CvmBridge.resolver('KLBN3', byCode: {'KLBN11': 'CNPJ-KLABIN'}),
        'CNPJ-KLABIN',
      );
    });

    test('raiz ambígua não resolve', () {
      expect(
        CvmBridge.resolver('XXXX3',
            byCode: {'XXXX4': 'CNPJ-A', 'XXXX11': 'CNPJ-B'}),
        isNull,
      );
    });

    test('nome idêntico resolve; parecido não', () {
      const byName = {'siderurgica nacional': 'CNPJ-CSN', 'cosan': 'CNPJ-COSAN'};
      expect(
        CvmBridge.resolver('QQQQ3',
            byCode: const {}, byName: byName,
            assetName: 'CIA SIDERURGICA NACIONAL'),
        'CNPJ-CSN',
      );
      // "CSN" nao e "COSAN". Com similaridade de 0,62 o casamento aproximado
      // dava COSAN a 0,75 — confiante e errado. Aqui simplesmente nao casa.
      expect(
        CvmBridge.resolver('CSNA9',
            byCode: const {}, byName: byName, assetName: 'CSN'),
        isNull,
      );
    });

    test('a tabela declarada é o último recurso, e alcança o que falta', () {
      expect(CvmBridge.resolver('B3SA3', byCode: const {}),
          '09.346.601/0001-25');
      expect(CvmBridge.resolver('CSNA3', byCode: const {}),
          '33.042.730/0001-04');
      // As tres classes do BTG apontam para a mesma companhia.
      final btg = {
        for (final t in ['BPAC3', 'BPAC5', 'BPAC11'])
          CvmBridge.resolver(t, byCode: const {})
      };
      expect(btg.length, 1);
    });

    test('o veto de semPonte vence TODAS as regras', () {
      // Nao basta declarar: o MAPT3 foi resolvido para a Marcopolo pela regra
      // de nome, ao lado de POMO3 e POMO4, enquanto semPonte era so comentario.
      expect(
        CvmBridge.resolver('MAPT3',
            byCode: const {'MAPT3': 'CNPJ-QUALQUER'},
            byName: const {'marcopolo': 'CNPJ-MARCOPOLO'},
            assetName: 'CIA MARCOPOLO'),
        isNull,
      );
      for (final t in CvmBridge.withoutBridge) {
        expect(CvmBridge.resolver(t, byCode: const {}), isNull, reason: t);
      }
    });

    test('o veto sobrevive a propagacao de raiz', () {
      final out = CvmBridge.resolveUniverse(
        const ['MAPT3', 'MAPT4'],
        byCode: const {'MAPT4': 'CNPJ-X'},
      );
      expect(out['MAPT4'], 'CNPJ-X');
      expect(out.containsKey('MAPT3'), isFalse);
    });
  });

  group('Conflito de raiz', () {
    test('denuncia companhia alcancada por duas raizes', () {
      final c = CvmBridge.rootConflicts(const {
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
        CvmBridge.rootConflicts(
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
      final out = CvmBridge.resolveUniverse(
        const ['AXIA3', 'AXIA7'],
        byCode: const {},
        byName: const {'axia energia': 'CNPJ-AXIA'},
        names: const {'AXIA3': 'AXIA ENERGIA S.A.'},
      );
      expect(out['AXIA3'], 'CNPJ-AXIA');
      expect(out['AXIA7'], 'CNPJ-AXIA');
    });

    test('não propaga quando a raiz discorda', () {
      final out = CvmBridge.resolveUniverse(
        const ['YYYY3', 'YYYY4', 'YYYY11'],
        byCode: const {'YYYY3': 'CNPJ-A', 'YYYY4': 'CNPJ-B'},
      );
      expect(out['YYYY11'], isNull);
    });

    test('normaliza a chave de saída', () {
      final out = CvmBridge.resolveUniverse(const ['  petr4 '],
          byCode: const {'PETR4': 'CNPJ-P'});
      expect(out['PETR4'], 'CNPJ-P');
    });
  });

  group('Regra 0: registro oficial da B3 — decisão 82', () {
    test('vence o nome que a fonte de preços deixou com a empresa absorvida', () {
      // MBRF3: a fonte de preços chama de "BRF S.A." e a regra de nome casava
      // com a BRF; o emissor MBRF, no registro da B3, é a Marfrig.
      final c = CvmBridge.resolver(
        'MBRF3',
        byCode: const {},
        byName: {CvmBridge.normalizeName('BRF S.A.'): 'CNPJ-BRF'},
        assetName: 'BRF S.A.',
        byOfficialRegistry: const {'MBRF': 'CNPJ-MARFRIG'},
      );
      expect(c, 'CNPJ-MARFRIG');
    });

    test('o veto de semPonte continua vindo antes', () {
      expect(
        CvmBridge.resolver('MAPT3',
            byCode: const {},
            byOfficialRegistry: const {'MAPT': 'CNPJ-QUALQUER'}),
        isNull,
      );
    });

    test('sem registro, as regras de antes seguem', () {
      expect(
        CvmBridge.resolver('PETR4',
            byCode: const {'PETR4': 'CNPJ-PETRO'},
            byOfficialRegistry: const {'VALE': 'CNPJ-VALE'}),
        'CNPJ-PETRO',
      );
    });
  });
}

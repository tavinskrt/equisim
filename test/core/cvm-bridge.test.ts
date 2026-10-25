import { describe, expect, it } from 'vitest';

import { CvmBridge } from '../../src/core';

const m = (entries: Record<string, string> = {}): Map<string, string> => new Map(Object.entries(entries));

describe('Filtro de formato', () => {
  it('descarta o que a fonte grafa no lugar do ticker', () => {
    // Medidos no FCA 2024: código CVM, zeros e a string ADR.
    for (const garbage of ['25585', '000000', 'ADR', '022055', '', '   ']) {
      expect(CvmBridge.looksLikeTicker(garbage), garbage).toBe(false);
    }
    for (const valid of ['PETR4', 'BPAC11', 'ITUB3', 'b3sa3']) {
      expect(CvmBridge.looksLikeTicker(valid), valid).toBe(true);
    }
  });

  it('a raiz recusa entrada malformada em vez de recortar', () => {
    expect(CvmBridge.root('PETR4')).toBe('PETR');
    expect(CvmBridge.root('BPAC11')).toBe('BPAC');
    expect(CvmBridge.root('ADR')).toBeNull();
    expect(CvmBridge.root('25585')).toBeNull();
    expect(CvmBridge.root('AB')).toBeNull();
  });
});

describe('Resolução', () => {
  it('o código direto vence', () => {
    expect(CvmBridge.resolver('PETR4', { byCode: m({ PETR4: 'CNPJ-PETRO' }) })).toBe('CNPJ-PETRO');
  });

  it('a raiz resolve a classe que a companhia não declarou', () => {
    expect(CvmBridge.resolver('KLBN3', { byCode: m({ KLBN11: 'CNPJ-KLABIN' }) })).toBe('CNPJ-KLABIN');
  });

  it('raiz ambígua não resolve', () => {
    expect(CvmBridge.resolver('XXXX3', { byCode: m({ XXXX4: 'CNPJ-A', XXXX11: 'CNPJ-B' }) })).toBeNull();
  });

  it('nome idêntico resolve; parecido não', () => {
    const byName = m({ 'siderurgica nacional': 'CNPJ-CSN', cosan: 'CNPJ-COSAN' });
    expect(CvmBridge.resolver('QQQQ3', { byCode: m(), byName, assetName: 'CIA SIDERURGICA NACIONAL' })).toBe(
      'CNPJ-CSN',
    );
    // "CSN" não é "COSAN". Com similaridade de 0,62 o casamento aproximado
    // dava COSAN a 0,75 — confiante e errado. Aqui simplesmente não casa.
    expect(CvmBridge.resolver('CSNA9', { byCode: m(), byName, assetName: 'CSN' })).toBeNull();
  });

  it('a tabela declarada é o último recurso, e alcança o que falta', () => {
    expect(CvmBridge.resolver('B3SA3', { byCode: m() })).toBe('09.346.601/0001-25');
    expect(CvmBridge.resolver('CSNA3', { byCode: m() })).toBe('33.042.730/0001-04');
    // As três classes do BTG apontam para a mesma companhia.
    const btg = new Set(['BPAC3', 'BPAC5', 'BPAC11'].map((t) => CvmBridge.resolver(t, { byCode: m() })));
    expect(btg.size).toBe(1);
  });

  it('o veto de semPonte vence TODAS as regras', () => {
    // Não basta declarar: o MAPT3 foi resolvido para a Marcopolo pela regra
    // de nome, ao lado de POMO3 e POMO4, enquanto semPonte era só comentário.
    expect(
      CvmBridge.resolver('MAPT3', {
        byCode: m({ MAPT3: 'CNPJ-QUALQUER' }),
        byName: m({ marcopolo: 'CNPJ-MARCOPOLO' }),
        assetName: 'CIA MARCOPOLO',
      }),
    ).toBeNull();
    for (const t of CvmBridge.withoutBridge) {
      expect(CvmBridge.resolver(t, { byCode: m() }), t).toBeNull();
    }
  });

  it('o veto sobrevive à propagação de raiz', () => {
    const out = CvmBridge.resolveUniverse(['MAPT3', 'MAPT4'], { byCode: m({ MAPT4: 'CNPJ-X' }) });
    expect(out.get('MAPT4')).toBe('CNPJ-X');
    expect(out.has('MAPT3')).toBe(false);
  });
});

describe('Conflito de raiz', () => {
  it('denuncia companhia alcançada por duas raízes', () => {
    const c = CvmBridge.rootConflicts(
      m({ POMO3: 'CNPJ-MARCO', POMO4: 'CNPJ-MARCO', MAPT3: 'CNPJ-MARCO', PETR4: 'CNPJ-PETRO' }),
    );
    expect([...c.keys()]).toEqual(['CNPJ-MARCO']);
    expect(c.get('CNPJ-MARCO')).toEqual(new Set(['POMO', 'MAPT']));
  });

  it('não denuncia companhia de raiz única', () => {
    expect(CvmBridge.rootConflicts(m({ PETR3: 'CNPJ-P', PETR4: 'CNPJ-P' })).size).toBe(0);
  });
});

describe('Universo', () => {
  it('a propagação de raiz acontece DEPOIS das outras regras', () => {
    // AXIA7 não é alcançado por regra nenhuma; AXIA3 é, pelo nome. Propagar
    // antes não resolveria, porque na primeira passada a raiz AXIA ainda
    // não tem membro resolvido.
    const out = CvmBridge.resolveUniverse(['AXIA3', 'AXIA7'], {
      byCode: m(),
      byName: m({ 'axia energia': 'CNPJ-AXIA' }),
      names: m({ AXIA3: 'AXIA ENERGIA S.A.' }),
    });
    expect(out.get('AXIA3')).toBe('CNPJ-AXIA');
    expect(out.get('AXIA7')).toBe('CNPJ-AXIA');
  });

  it('não propaga quando a raiz discorda', () => {
    const out = CvmBridge.resolveUniverse(['YYYY3', 'YYYY4', 'YYYY11'], {
      byCode: m({ YYYY3: 'CNPJ-A', YYYY4: 'CNPJ-B' }),
    });
    expect(out.get('YYYY11')).toBeUndefined();
  });

  it('normaliza a chave de saída', () => {
    const out = CvmBridge.resolveUniverse(['  petr4 '], { byCode: m({ PETR4: 'CNPJ-P' }) });
    expect(out.get('PETR4')).toBe('CNPJ-P');
  });
});

describe('Regra 0: registro oficial da B3 — decisão 82', () => {
  it('vence o nome que a fonte de preços deixou com a empresa absorvida', () => {
    // MBRF3: a fonte de preços chama de "BRF S.A." e a regra de nome casava
    // com a BRF; o emissor MBRF, no registro da B3, é a Marfrig.
    const c = CvmBridge.resolver('MBRF3', {
      byCode: m(),
      byName: new Map([[CvmBridge.normalizeName('BRF S.A.'), 'CNPJ-BRF']]),
      assetName: 'BRF S.A.',
      byOfficialRegistry: m({ MBRF: 'CNPJ-MARFRIG' }),
    });
    expect(c).toBe('CNPJ-MARFRIG');
  });

  it('o veto de semPonte continua vindo antes', () => {
    expect(CvmBridge.resolver('MAPT3', { byCode: m(), byOfficialRegistry: m({ MAPT: 'CNPJ-QUALQUER' }) })).toBeNull();
  });

  it('sem registro, as regras de antes seguem', () => {
    expect(
      CvmBridge.resolver('PETR4', {
        byCode: m({ PETR4: 'CNPJ-PETRO' }),
        byOfficialRegistry: m({ VALE: 'CNPJ-VALE' }),
      }),
    ).toBe('CNPJ-PETRO');
  });
});

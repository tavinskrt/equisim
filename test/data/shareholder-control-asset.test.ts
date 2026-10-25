import { expect, it } from 'vitest';

import {
  DateTime,
  ShareholderControl,
  ShareholderControlHistory,
  ShareholderControlPeriod,
  Ticker,
} from '../../src/core';
import { AssetPaths } from '../../src/data/config/asset-paths';
import { ShareholderControlRepository } from '../../src/data/repositories/shareholder-control-repository';
import { isServed, readPublicJson } from './public-assets';

/**
 * O controle acionário versionado é o que o build leva (item B46).
 *
 * Ele só acrescenta a ressalva de controle estatal, e por isso a ausência não
 * muda preço; mas um build sem ele deixaria de declarar o que a medição
 * mandou declarar, e isso reprova a suíte.
 */

it('o pacote existe em public/, de onde o build o serve', () => {
  expect(isServed(AssetPaths.shareholderControl), 'gerar com `npm run tool -- control-package` e versionar').toBe(true);
});

it('o pacote é legível, e as estatais conhecidas estão onde devem', () => {
  const parsed = ShareholderControlHistory.decode(readPublicJson(AssetPaths.shareholderControl));
  expect(parsed, 'o codec mudou de versão e o pacote não foi regerado').not.toBeNull();
  const at = (root: string, d: DateTime) => ShareholderControlHistory.at(parsed!.byIssuer.get(root)!, d);
  const today = DateTime.local(2026, 9, 14);
  expect(at('PETR', today)).toBe(ShareholderControl.state);
  expect(at('BBAS', today)).toBe(ShareholderControl.state);
  expect(at('ITUB', today)).toBe(ShareholderControl.private);
  // A Sabesp foi privatizada em 22/07/2024: estatal antes, privada depois.
  expect(at('SBSP', DateTime.local(2024, 6, 30))).toBe(ShareholderControl.state);
  expect(at('SBSP', today)).toBe(ShareholderControl.private);
});

it('o repositório responde pela raiz do código, e sem pacote diz que não', async () => {
  const pkg = JSON.stringify(
    ShareholderControlHistory.encode(
      new Map([
        [
          'SBSP',
          [
            new ShareholderControlPeriod({ since: DateTime.local(2010), control: ShareholderControl.state }),
            new ShareholderControlPeriod({ since: DateTime.local(2024, 7, 22), control: ShareholderControl.private }),
          ],
        ],
      ]),
      { generatedAt: DateTime.local(2026, 9, 14) },
    ),
  );
  const repo = new ShareholderControlRepository({ loadPackage: async () => pkg, today: () => DateTime.local(2026, 9, 14) });
  expect(await repo.isStateControlled(Ticker.parse('SBSP3'))).toBe(false);
  expect(await repo.isStateControlled(Ticker.parse('SBSP3'), { asOf: DateTime.local(2023, 12, 31) })).toBe(true);
  expect(await repo.isStateControlled(Ticker.parse('PETR4'))).toBe(false);

  const noPackage = new ShareholderControlRepository({
    loadPackage: async () => {
      throw new Error('ausente');
    },
  });
  expect(await noPackage.isStateControlled(Ticker.parse('PETR4'))).toBe(false);
});

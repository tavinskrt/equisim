import { Asset, type Ticker } from '../../core';
import { fetchProfile } from '../../app/hooks';
import { StudyActions } from '../../app/state/study-store';

/**
 * Inclui um ativo no estudo **com o perfil**: sem a classificação setorial, o
 * alerta de concentração — requisito funcional — não teria como operar. Sem
 * perfil, entra com o ticker por nome e setor não classificado.
 */
export async function addToStudy(ticker: Ticker, toPrincipal: boolean): Promise<boolean> {
  let asset: Asset | null = null;
  try {
    asset = await fetchProfile(ticker);
  } catch {
    asset = null;
  }
  return StudyActions.addAsset(asset ?? new Asset({ ticker, name: ticker.value }), toPrincipal);
}

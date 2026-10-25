import { FeasibilityLevel } from '../../core';
import type { Tone } from '../../ui/tone';

/** O papel de cor de cada nível de viabilidade — o mesmo do aplicativo Flutter. */
export function feasibilityTone(level: FeasibilityLevel): Tone {
  switch (level) {
    case FeasibilityLevel.riskFreeSufficient:
      return 'pending';
    case FeasibilityLevel.plausible:
      return 'positive';
    case FeasibilityLevel.demanding:
      return 'caution';
    default:
      return 'negative';
  }
}

/** O título do veredito. */
export function feasibilityTitle(level: FeasibilityLevel): string {
  switch (level) {
    case FeasibilityLevel.riskFreeSufficient:
      return 'Meta sem necessidade de risco';
    case FeasibilityLevel.plausible:
      return 'Meta plausível';
    case FeasibilityLevel.demanding:
      return 'Meta exigente';
    default:
      return 'Meta inviável';
  }
}

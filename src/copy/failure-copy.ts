import { type Failure, QuantityUnit } from '../core';
import { Fmt } from './fmt';

/**
 * Compõe, para a tela, o texto de uma `Failure` do domínio.
 *
 * `Failure.message` é diagnóstico técnico — diz quais tickers ficaram sem
 * cotação, quantos pregões sobraram, quanto os pesos somaram. Aqui a
 * apresentação decide o **rótulo** a partir do tipo e dos campos
 * estruturados, e usa o diagnóstico como detalhe (decisão 122).
 */
export const FailureCopy = {
  /** Rótulo curto da natureza da falha, para cabeçalho de aviso. */
  titleOf(failure: Failure): string {
    switch (failure.kind) {
      case 'InsufficientData':
        return 'Dados insuficientes';
      case 'InvalidInput':
        return 'Entrada inválida';
      case 'ComputationFailure':
        return 'Cálculo não concluído';
      case 'DataQualityFailure':
        return 'Dado sob ressalva';
    }
  },

  /**
   * Frase completa: rótulo, o assunto quando ele existe, e o diagnóstico.
   *
   * O assunto de `InsufficientData` entra no rótulo — «Dados insuficientes ·
   * PETR4» —, o que permite agrupar falhas por ativo sem ler a frase inteira.
   */
  of(failure: Failure): string {
    let detail = failure.message;
    const f = failure as Failure & {
      observedDeviation?: number | null;
      actual?: number | null;
      limit?: number | null;
      unit?: QuantityUnit | null;
      subject?: string | null;
    };
    if (failure.kind === 'DataQualityFailure' && f.observedDeviation != null) {
      detail = `${failure.message} Desvio medido: ${Fmt.percent(f.observedDeviation, { decimals: 1 })}.`;
    } else if (failure.kind === 'InvalidInput' && f.actual != null && f.unit != null) {
      // A grandeza vem do domínio, e a frase é montada aqui (decisão 122).
      detail = `${failure.message} ${quantity(f.actual, f.limit ?? null, f.unit)}`;
    }
    const subject = failure.kind === 'InsufficientData' ? (f.subject ?? null) : null;
    const head = subject === null ? FailureCopy.titleOf(failure) : `${FailureCopy.titleOf(failure)} · ${subject}`;
    return `${head} — ${detail}`;
  },
};

/** «Informado: X. Limite: Y.» na unidade que o domínio declarou. */
function quantity(actual: number, limit: number | null, unit: QuantityUnit): string {
  const write = (v: number): string => {
    switch (unit) {
      case QuantityUnit.fraction:
        return Fmt.percent(v, { decimals: 1 });
      // Contagem é grandeza inteira: escrevê-la com casa decimal seria
      // sugerir meio ativo.
      case QuantityUnit.count:
        return String(Math.round(v));
      case QuantityUnit.currency:
        return Fmt.money(v);
    }
  };
  const reported = `Informado: ${write(actual)}.`;
  return limit === null ? reported : `${reported} Limite: ${write(limit)}.`;
}

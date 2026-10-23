import { Slider } from '../../ui/slider';
import { NumberField } from '../../ui/field';

/**
 * Valor em reais com **controle deslizante e campo**: o controle dá a noção
 * de escala, o campo dá o número exato. A escala do controle é quadrática —
 * entre R$ 0 e R$ 10 milhões, uma régua linear deixaria os valores comuns
 * espremidos no primeiro centímetro.
 */
export function MoneySlider(props: {
  label: string;
  value: number;
  onChange: (value: number) => void;
  max: number;
  step: number;
  min?: number;
  hint?: string;
}) {
  const min = props.min ?? 0;
  const toPosition = (v: number) => Math.sqrt(Math.max(v - min, 0) / (props.max - min)) * 1000;
  const fromPosition = (p: number) => {
    const raw = min + (p / 1000) ** 2 * (props.max - min);
    return Math.round(raw / props.step) * props.step;
  };
  const money = (v: number) => `R$ ${new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 0 }).format(v)}`;
  return (
    <div className="space-y-1">
      <NumberField
        label={props.label}
        value={props.value}
        decimals={0}
        prefix="R$"
        inputMode="numeric"
        hint={props.hint}
        onChange={(v) => {
          if (v !== null && v >= 0) props.onChange(Math.round(v));
        }}
      />
      <Slider
        label={<span className="sr-only">{props.label}, controle deslizante</span>}
        value={Math.min(toPosition(props.value), 1000)}
        min={0}
        max={1000}
        step={1}
        format={(p) => money(fromPosition(p))}
        onChange={(p) => props.onChange(fromPosition(p))}
        className="[&_output]:hidden"
      />
    </div>
  );
}

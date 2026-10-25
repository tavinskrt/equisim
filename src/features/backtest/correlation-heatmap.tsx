import type { CorrelationMatrix } from '../../app/backtest';
import { Fmt } from '../../copy';
import { ChartFrame, DataTable } from '../../ui/charts/chart-frame';

/**
 * A cor de uma célula na escala **divergente**: dois polos e o meio neutro,
 * nunca matiz no meio. A intensidade para em 60% do polo — medido nos dois
 * temas, é o teto em que o número em tinta de texto ainda passa de 4,5:1 sobre
 * a célula (WCAG 1.4.3).
 */
export function cellColor(rho: number): string {
  const r = Math.max(-1, Math.min(1, rho));
  const pole = r < 0 ? 'var(--div-low)' : 'var(--div-high)';
  const strength = Math.round(Math.abs(r) * 60);
  return `color-mix(in srgb, ${pole} ${strength}%, var(--div-mid))`;
}

/**
 * **Correlação entre os ativos** da Principal. Correlação baixa ou negativa é
 * diversificação: os ativos não caem juntos. A tabela é a matriz inteira; o
 * mapa mostra só o triângulo de baixo, porque o de cima é o espelho dele.
 */
export function CorrelationHeatmap({ data }: { data: CorrelationMatrix }) {
  const names = data.tickers.map((t) => t.value);
  const n = names.length;
  const label = (rho: number) => Fmt.ratio(rho, 2);

  return (
    <ChartFrame
      title="Correlação entre os ativos"
      subtitle="Azul: andam em sentidos opostos · cinza: independentes · vermelho: andam juntos. Menos co-movimento, mais diversificação."
      chart={
        <div className="overflow-x-auto scrollbar-thin pb-1">
          <div
            className="grid gap-0.5"
            style={{ gridTemplateColumns: `max-content repeat(${n}, minmax(52px, 1fr))`, minWidth: 64 + n * 54 }}
            role="img"
            aria-label="Mapa de correlação; os valores exatos estão na vista de tabela."
          >
            {names.map((row, i) => (
              <Row key={row} name={row} cells={data.matrix[i]!.slice(0, i + 1)} total={n} label={label} />
            ))}
            <span />
            {names.map((c) => (
              <span key={c} className="truncate px-1 pt-1 text-center text-caption text-fg-2">
                {c}
              </span>
            ))}
          </div>
          <ScaleLegend />
        </div>
      }
      table={
        <DataTable
          caption="Matriz de correlação dos retornos diários"
          columns={['', ...names]}
          rows={names.map((row, i) => [row, ...data.matrix[i]!.map((v) => label(v))])}
        />
      }
      footer="Correlação de Pearson dos retornos diários de fechamento, no calendário comum aos ativos — datas desencontradas mediriam ruído de calendário, e não co-movimento."
    />
  );
}

function Row({ name, cells, total, label }: { name: string; cells: readonly number[]; total: number; label: (v: number) => string }) {
  return (
    <>
      <span className="flex items-center pr-2 text-caption text-fg-2">{name}</span>
      {cells.map((rho, j) =>
        j === cells.length - 1 ? (
          // A diagonal é o ativo contra ele mesmo: 1 por definição, e pintá-la
          // de vermelho pleno roubaria a atenção das células que informam.
          <span key={j} className="num flex h-10 items-center justify-center rounded-sm bg-sunken text-caption text-fg-3">
            1
          </span>
        ) : (
          <span
            key={j}
            title={label(rho)}
            className="num flex h-10 items-center justify-center rounded-sm text-caption font-semibold text-fg"
            style={{ background: cellColor(rho) }}
          >
            {label(rho)}
          </span>
        ),
      )}
      {Array.from({ length: total - cells.length }, (_, k) => (
        <span key={`v${k}`} />
      ))}
    </>
  );
}

function ScaleLegend() {
  return (
    <div className="mt-3 max-w-xs" aria-hidden>
      <div className="h-2 rounded-full" style={{ background: `linear-gradient(to right, ${cellColor(-1)}, ${cellColor(0)}, ${cellColor(1)})` }} />
      <div className="mt-1 flex justify-between text-caption text-fg-3">
        <span>−1 opostos</span>
        <span>0</span>
        <span>+1 juntos</span>
      </div>
    </div>
  );
}

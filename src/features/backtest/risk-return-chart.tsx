import { CartesianGrid, LabelList, ReferenceLine, ResponsiveContainer, Scatter, ScatterChart, Tooltip, XAxis, YAxis } from 'recharts';

import type { PortfolioComparison, RiskReturnKind, RiskReturnPoint } from '../../app/backtest';
import { Fmt } from '../../copy';
import { axisProps, ChartFrame, DataTable, type LegendItem, TooltipBox } from '../../ui/charts/chart-frame';

type Shape = 'circle' | 'square' | 'diamond';

/**
 * Cada papel com cor **e** forma: a carteira é losango grande, o ativo detido é
 * círculo, o candidato da Reserva é quadrado. A forma carrega a identidade
 * sozinha quando a cor não chega (daltonismo, impressão).
 */
const kinds: readonly { kind: RiskReturnKind; label: string; color: string; shape: Shape; size: number }[] = [
  { kind: 'principalAsset', label: 'Ativos da Principal', color: 'var(--fg-2)', shape: 'circle', size: 5 },
  { kind: 'reserveAsset', label: 'Ativos da Reserva', color: 'var(--reserve-muted)', shape: 'square', size: 5 },
  { kind: 'principal', label: 'Principal', color: 'var(--brand)', shape: 'diamond', size: 8 },
  { kind: 'reserve', label: 'Reserva', color: 'var(--reserve)', shape: 'diamond', size: 8 },
];

function Mark({ cx, cy, color, shape, size }: { cx?: number; cy?: number; color: string; shape: Shape; size: number }) {
  if (cx === undefined || cy === undefined) return null;
  // Anel de 2 px na cor da superfície: marcas sobrepostas continuam separáveis.
  const ring = { stroke: 'var(--surface)', strokeWidth: 2 };
  if (shape === 'circle') return <circle cx={cx} cy={cy} r={size} fill={color} {...ring} />;
  if (shape === 'square') return <rect x={cx - size} y={cy - size} width={size * 2} height={size * 2} rx={1.5} fill={color} {...ring} />;
  return <path d={`M${cx} ${cy - size}L${cx + size} ${cy}L${cx} ${cy + size}L${cx - size} ${cy}Z`} fill={color} {...ring} />;
}

/**
 * **Risco × retorno**: cada ativo das duas carteiras e as próprias carteiras,
 * anualizados na janela. A carteira costuma cair à esquerda da nuvem dos
 * ativos — é a diversificação, visível.
 */
export function RiskReturnChart({ result }: { result: PortfolioComparison }) {
  const present = kinds.filter((k) => result.riskReturn.some((p) => p.kind === k.kind));
  const legend: LegendItem[] = present.map((k) => ({ key: k.kind, label: k.label, color: k.color, shape: k.shape }));
  const pctAxis = (v: number) => `${Fmt.ratio(v, 0)}%`;
  const kindLabel = (k: RiskReturnKind) => kinds.find((x) => x.kind === k)!.label;
  // Folga vertical de 12% da amplitude: sem ela o ponto mais baixo encosta no
  // eixo, e o rótulo da carteira — embaixo da marca — cai sobre as marcas do X.
  const returns = result.riskReturn.map((p) => p.ret);
  const span = Math.max(Math.max(...returns) - Math.min(...returns), 2);
  const yDomain: [number, number] = [Math.floor(Math.min(...returns) - span * 0.12), Math.ceil(Math.max(...returns) + span * 0.12)];

  return (
    <ChartFrame
      title="Risco × retorno"
      subtitle={`Cada ativo das duas carteiras e as próprias carteiras, anualizados em ${result.window.toString()}`}
      legend={legend}
      height={320}
      chart={
        <ResponsiveContainer width="100%" height="100%">
          <ScatterChart margin={{ top: 16, right: 16, bottom: 16, left: 0 }}>
            <CartesianGrid stroke="var(--grid)" />
            <XAxis
              type="number"
              dataKey="risk"
              name="Volatilidade"
              tickFormatter={pctAxis}
              domain={[0, 'auto']}
              label={{ value: 'Volatilidade anualizada', position: 'insideBottom', offset: -8, fill: 'var(--fg-3)', fontSize: 11 }}
              {...axisProps}
            />
            <YAxis
              type="number"
              dataKey="ret"
              name="Retorno"
              width={52}
              tickFormatter={pctAxis}
              domain={yDomain}
              label={{ value: 'Retorno ao ano', angle: -90, position: 'insideLeft', offset: 12, fill: 'var(--fg-3)', fontSize: 11 }}
              {...axisProps}
            />
            <ReferenceLine y={0} stroke="var(--border-strong)" />
            <Tooltip
              cursor={{ strokeDasharray: '3 3', stroke: 'var(--border-strong)' }}
              content={({ active, payload }) => {
                if (!active || payload === undefined || payload.length === 0) return null;
                const p = payload[0]!.payload as RiskReturnPoint;
                return (
                  <TooltipBox
                    title={`${p.label} · ${kindLabel(p.kind)}`}
                    rows={[
                      { key: 'ret', label: 'Retorno ao ano', value: Fmt.percent(p.ret / 100, { decimals: 1, signed: true }) },
                      { key: 'risk', label: 'Volatilidade', value: Fmt.percent(p.risk / 100, { decimals: 1 }) },
                    ]}
                  />
                );
              }}
            />
            {present.map((k) => (
              <Scatter
                key={k.kind}
                name={k.label}
                data={result.riskReturn.filter((p) => p.kind === k.kind)}
                isAnimationActive={false}
                shape={(props: { cx?: number; cy?: number }) => <Mark cx={props.cx} cy={props.cy} color={k.color} shape={k.shape} size={k.size} />}
              >
                <LabelList
                  dataKey="label"
                  // Carteira embaixo, ativo em cima: uma Reserva de um ativo só cai no
                  // mesmo ponto dele, e os dois rótulos no alto se sobrepunham.
                  position={k.kind === 'principal' || k.kind === 'reserve' ? 'bottom' : 'top'}
                  offset={k.size + 4}
                  fill={k.kind === 'principal' || k.kind === 'reserve' ? 'var(--fg)' : 'var(--fg-2)'}
                  fontSize={11}
                  fontWeight={k.kind === 'principal' || k.kind === 'reserve' ? 600 : 400}
                />
              </Scatter>
            ))}
          </ScatterChart>
        </ResponsiveContainer>
      }
      table={
        <DataTable
          caption="Risco e retorno anualizados por ativo e por carteira"
          columns={['Ativo ou carteira', 'Papel', 'Retorno ao ano', 'Volatilidade']}
          rows={[...result.riskReturn]
            .sort((a, b) => b.ret - a.ret)
            .map((p) => [p.label, kindLabel(p.kind), Fmt.percent(p.ret / 100, { decimals: 1, signed: true }), Fmt.percent(p.risk / 100, { decimals: 1 })])}
        />
      }
      footer="Cada ativo entra com a volatilidade e o CAGR da própria série de fechamentos, só de preço; as carteiras, com as métricas da simulação."
    />
  );
}

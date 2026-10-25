import { cn } from '../../ui/cn';

/**
 * O nome da carteira sob o ponto colorido dela — o mesmo selo no cabeçalho da
 * tabela comparativa, nos grupos por ativo e na ponte do patrimônio. O texto
 * fica em tinta de texto: a cor da série mora no ponto, e o nome é legível em
 * qualquer tema.
 */
export function PortfolioBadge(props: { name: string; color: string; className?: string }) {
  return (
    <span className={cn('inline-flex items-center gap-1.5 text-caption font-bold tracking-[0.06em] text-fg-2 uppercase', props.className)}>
      <span aria-hidden className="size-2 shrink-0 rounded-full" style={{ background: props.color }} />
      {props.name}
    </span>
  );
}

/** As cores das duas carteiras: as mesmas em todo gráfico da tela. */
export const PortfolioColors = {
  principal: 'var(--brand)',
  reserve: 'var(--reserve)',
} as const;

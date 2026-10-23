import { BadgeCheck, FlaskConical, LayoutGrid, type LucideIcon, Target } from 'lucide-react';

/**
 * As quatro áreas do aplicativo. **Não há aba de Valuation**: a avaliação de
 * um ativo abre no Raio-X, por cima de qualquer área, e a edição manual tem
 * rota própria a partir dele.
 */
export interface NavItem {
  readonly to: string;
  readonly label: string;
  /** Rótulo curto da barra inferior do celular. */
  readonly short: string;
  readonly icon: LucideIcon;
  readonly description: string;
}

export const navItems: readonly NavItem[] = [
  { to: '/estudo', label: 'Estudo', short: 'Estudo', icon: LayoutGrid, description: 'Montar a Principal e a Reserva' },
  { to: '/meta', label: 'Meta', short: 'Meta', icon: Target, description: 'Planejar o patrimônio e a rentabilidade exigida' },
  { to: '/backtest', label: 'Backtest', short: 'Backtest', icon: FlaskConical, description: 'Simular as duas carteiras no histórico' },
  { to: '/valuations', label: 'Meus valuations', short: 'Valuations', icon: BadgeCheck, description: 'Os valuations que você confirmou' },
];

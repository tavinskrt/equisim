import { create } from 'zustand';

/**
 * Se o histórico de versões está aberto. Mora fora dos componentes porque três
 * lugares o abrem — o menu do perfil, a busca global e a tela Meu perfil — e
 * a folha é uma só, montada na casca.
 */
export const useChangelog = create<{ readonly open: boolean }>(() => ({ open: false }));

export const ChangelogActions = {
  /**
   * Abre no tique seguinte. Quem chama costuma ser um menu ou a busca, que se
   * fecham no mesmo clique e devolvem o foco a quem os abriu; abrir depois
   * deixa o foco na folha, e não no botão do menu.
   */
  open(): void {
    setTimeout(() => useChangelog.setState({ open: true }), 0);
  },
  setOpen(open: boolean): void {
    useChangelog.setState({ open });
  },
};

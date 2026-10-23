import { create } from 'zustand';

import {
  type Asset,
  type ConcentrationReport,
  type FinancialGoal,
  Portfolio,
  PortfolioKind,
  SectorConcentration,
  SwapAssetBetweenPortfolios,
  type Ticker,
} from '../../core';
import { FailureCopy } from '../../copy';
import { PortfolioStudyCodec } from '../../data/persistence/portfolio-codec';
import { PortfolioStudy } from '../../data/persistence/portfolio-study';
import { getRuntime, hasRuntime } from '../runtime';
import { activeStores, currentUserId } from './session-store';

/** A lista de estudos gravados, como a tela a lê. */
export type SavedStudies =
  | { readonly status: 'idle' | 'loading'; readonly studies: readonly PortfolioStudy[]; readonly error: null }
  | { readonly status: 'ready'; readonly studies: readonly PortfolioStudy[]; readonly error: null }
  | { readonly status: 'error'; readonly studies: readonly PortfolioStudy[]; readonly error: string };

export interface StudyState {
  /** O estudo em edição. */
  readonly study: PortfolioStudy;
  /** `true` enquanto uma gravação está em curso — a interface bloqueia o botão. */
  readonly isSaving: boolean;
  /** Mensagem da última operação recusada, para exibição transitória. */
  readonly lastError: string | null;
  /**
   * Estudos gravados. A falha é **propagada**, e não convertida em lista
   * vazia: "nenhum estudo" e "não consegui ler" são situações diferentes.
   */
  readonly saved: SavedStudies;
}

/** O estudo vazio: as duas carteiras sem ativo, e sem meta. */
export function emptyStudy(goal: FinancialGoal | null = null): PortfolioStudy {
  return new PortfolioStudy({
    name: 'Novo estudo',
    principal: new Portfolio({ id: 'principal', name: 'Principal', kind: PortfolioKind.principal, entries: new Map() }),
    reserve: new Portfolio({ id: 'reserva', name: 'Reserva', kind: PortfolioKind.reserve, entries: new Map() }),
    goal,
  });
}

const draftKey = 'equisim:rascunho';

/**
 * O rascunho do estudo, guardado no navegador a cada mudança. É conveniência
 * por pessoa — recarregar a página não perde o que estava na tela —, e não
 * gravação: o estudo só é do usuário depois de "Salvar".
 */
function saveDraft(study: PortfolioStudy): void {
  if (!hasRuntime()) return;
  getRuntime().preferences.set(
    draftKey,
    JSON.stringify({
      id: study.id,
      name: study.name,
      principal: PortfolioStudyCodec.encodePortfolio(study.principal),
      reserve: PortfolioStudyCodec.encodePortfolio(study.reserve),
      goal: study.goal === null ? null : PortfolioStudyCodec.encodeGoal(study.goal),
    }),
  );
}

/** O rascunho guardado, ou `null` quando não há ou está ilegível. */
export function readDraft(): PortfolioStudy | null {
  if (!hasRuntime()) return null;
  const raw = getRuntime().preferences.get(draftKey);
  if (raw === null) return null;
  try {
    const d = JSON.parse(raw) as Record<string, unknown>;
    return new PortfolioStudy({
      id: typeof d['id'] === 'string' ? d['id'] : null,
      name: typeof d['name'] === 'string' ? d['name'] : 'Novo estudo',
      principal: PortfolioStudyCodec.decodePortfolio(d['principal'], {
        id: 'principal',
        name: 'Principal',
        kind: PortfolioKind.principal,
      }),
      reserve: PortfolioStudyCodec.decodePortfolio(d['reserve'], {
        id: 'reserva',
        name: 'Reserva',
        kind: PortfolioKind.reserve,
      }),
      goal: PortfolioStudyCodec.decodeGoal(d['goal']),
    });
  } catch {
    return null;
  }
}

/**
 * Estado das duas carteiras e da meta.
 *
 * Todas as edições são **síncronas**: o recálculo de pesos e concentração
 * custa microssegundos, o que dispensa espera no arrastar-e-soltar.
 */
export const useStudy = create<StudyState>(() => ({
  study: emptyStudy(),
  isSaving: false,
  lastError: null,
  saved: { status: 'idle', studies: [], error: null },
}));

function setStudy(study: PortfolioStudy, extra: Partial<StudyState> = {}): void {
  useStudy.setState({ study, lastError: null, ...extra });
  saveDraft(study);
}

function refuse(message: string): void {
  useStudy.setState({ lastError: message });
}

/** As operações do estudo — a porta de [StudyNotifier] do aplicativo Flutter. */
export const StudyActions = {
  /** Substitui o estudo em edição, descartando alterações e erro pendente. */
  load(study: PortfolioStudy): void {
    setStudy(study, { isSaving: false });
  },

  /** Renomeia. Nome vazio é aceito. */
  rename(name: string): void {
    setStudy(useStudy.getState().study.copyWith({ name }));
  },

  /** Define a meta, substituindo a anterior. */
  setGoal(goal: FinancialGoal): void {
    setStudy(useStudy.getState().study.copyWith({ goal }));
  },

  /**
   * Move um ativo entre as carteiras — o gesto central. As **duas** carteiras
   * são reequiponderadas. Recusa quando o ativo não está na origem, já está no
   * destino, ou o destino chegou ao teto de 15.
   */
  swap(ticker: Ticker, toPrincipal: boolean): boolean {
    const { study } = useStudy.getState();
    const result = SwapAssetBetweenPortfolios.call({
      principal: study.principal,
      reserve: study.reserve,
      ticker,
      toPrincipal,
    });
    if (result.isErr) {
      refuse(FailureCopy.of(result.failureOrNull!));
      return false;
    }
    const outcome = result.unwrap();
    setStudy(study.copyWith({ principal: outcome.principal, reserve: outcome.reserve }));
    return true;
  },

  /** Inclui um ativo na carteira indicada e reequipondera. */
  addAsset(asset: Asset, toPrincipal: boolean): boolean {
    const { study } = useStudy.getState();
    const target = toPrincipal ? study.principal : study.reserve;
    const result = target.add(asset);
    if (result.isErr) {
      refuse(FailureCopy.of(result.failureOrNull!));
      return false;
    }
    setStudy(toPrincipal ? study.copyWith({ principal: result.unwrap() }) : study.copyWith({ reserve: result.unwrap() }));
    return true;
  },

  /** Remove um ativo e reequipondera o restante. Esvaziar a carteira não é erro. */
  removeAsset(ticker: Ticker, fromPrincipal: boolean): boolean {
    const { study } = useStudy.getState();
    const target = fromPrincipal ? study.principal : study.reserve;
    const result = target.remove(ticker);
    if (result.isErr) {
      refuse(FailureCopy.of(result.failureOrNull!));
      return false;
    }
    setStudy(
      fromPrincipal ? study.copyWith({ principal: result.unwrap() }) : study.copyWith({ reserve: result.unwrap() }),
    );
    return true;
  },

  /** Pesos iguais na carteira indicada. Nunca falha. */
  equalize(onPrincipal: boolean): void {
    const { study } = useStudy.getState();
    setStudy(
      onPrincipal
        ? study.copyWith({ principal: study.principal.equalize() })
        : study.copyWith({ reserve: study.reserve.equalize() }),
    );
  },

  /**
   * Grava o estudo. Em falha, devolve `false` e publica a mensagem — **não
   * lança**. O `id` devolvido converte a próxima gravação em atualização.
   */
  async save(): Promise<boolean> {
    const userId = currentUserId();
    const stores = activeStores();
    if (userId === null || stores === null) {
      refuse('Sessão não identificada. Saia e entre novamente para salvar o estudo.');
      return false;
    }
    useStudy.setState({ isSaving: true, lastError: null });
    const result = await stores.portfolios.save(userId, useStudy.getState().study);
    if (result.isErr) {
      useStudy.setState({ isSaving: false, lastError: FailureCopy.of(result.failureOrNull!) });
      return false;
    }
    setStudy(useStudy.getState().study.copyWith({ id: result.unwrap() }), { isSaving: false });
    // Sem recarregar, o recém-gravado só apareceria na próxima sessão.
    void StudyActions.refreshSaved();
    return true;
  },

  /** Estudo novo, **preservando a meta**: o mesmo plano torna dois estudos comparáveis. */
  startNew(): void {
    setStudy(emptyStudy(useStudy.getState().study.goal), { isSaving: false });
  },

  /**
   * Remove um estudo gravado. **Apagar o aberto não limpa a tela**: só desfaz
   * o vínculo, e o próximo "Salvar" cria um documento novo.
   */
  async deleteSaved(id: string): Promise<boolean> {
    const userId = currentUserId();
    const stores = activeStores();
    if (userId === null || stores === null) return false;
    const result = await stores.portfolios.delete(userId, id);
    if (result.isErr) {
      refuse(FailureCopy.of(result.failureOrNull!));
      return false;
    }
    const { study } = useStudy.getState();
    if (study.id === id) {
      setStudy(
        new PortfolioStudy({ name: study.name, principal: study.principal, reserve: study.reserve, goal: study.goal }),
      );
    }
    void StudyActions.refreshSaved();
    return true;
  },

  /** Recarrega a lista de estudos gravados do usuário da sessão. */
  async refreshSaved(): Promise<void> {
    const userId = currentUserId();
    const stores = activeStores();
    const previous = useStudy.getState().saved.studies;
    if (userId === null || stores === null) {
      useStudy.setState({ saved: { status: 'ready', studies: [], error: null } });
      return;
    }
    useStudy.setState({ saved: { status: 'loading', studies: previous, error: null } });
    const result = await stores.portfolios.listFor(userId);
    useStudy.setState({
      saved: result.isOk
        ? { status: 'ready', studies: result.unwrap(), error: null }
        : { status: 'error', studies: previous, error: FailureCopy.of(result.failureOrNull!) },
    });
  },

  /** Apaga a mensagem de erro pendente, depois que a interface a exibiu. */
  clearError(): void {
    useStudy.setState({ lastError: null });
  },
};

/**
 * Concentração setorial da Principal, derivada de forma síncrona: o alerta
 * acompanha cada arraste sem atraso. Memorizada pela identidade da carteira.
 */
let lastConcentration: { principal: Portfolio; report: ConcentrationReport } | null = null;

export function concentrationOf(principal: Portfolio): ConcentrationReport {
  if (lastConcentration?.principal !== principal) {
    lastConcentration = { principal, report: SectorConcentration.analyze(principal) };
  }
  return lastConcentration.report;
}

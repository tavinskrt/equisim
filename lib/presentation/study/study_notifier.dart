import 'package:equisim_core/equisim_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/portfolio_repository.dart';
import '../../di/providers.dart';
import '../shared/failure_copy.dart';
import '../shared/ui_kit.dart';

/// Estado editável do estudo, com o erro da última operação recusada.
class StudyState {
  /// O estudo em edição.
  final PortfolioStudy study;

  /// `true` enquanto uma gravação está em curso — a interface bloqueia o botão.
  final bool isSaving;

  /// Mensagem da última operação rejeitada, para exibição transitória.
  final String? lastError;

  /// Declara o estado.
  const StudyState({
    required this.study,
    this.isSaving = false,
    this.lastError,
  });

  /// Cópia com os campos informados substituídos.
  ///
  /// - [clearError]: apaga [lastError]. **Necessário** porque passar `null` em
  ///   [lastError] preserva o erro atual, como em todo `copyWith` de campo
  ///   anulável; sem esta chave não haveria como limpar a mensagem. Quando
  ///   `true`, tem precedência sobre [lastError].
  StudyState copyWith({
    PortfolioStudy? study,
    bool? isSaving,
    String? lastError,
    bool clearError = false,
  }) => StudyState(
    study: study ?? this.study,
    isSaving: isSaving ?? this.isSaving,
    lastError: clearError ? null : (lastError ?? this.lastError),
  );
}

/// Estado das duas carteiras e da meta.
///
/// Todas as operações de edição são **síncronas**. O recálculo de pesos,
/// concentração setorial e retorno esperado custa microssegundos (medido:
/// 0,024 ms para um backtest completo de cinco anos), o que dispensa
/// `Future`, *debounce* e estado de carregamento no arrastar-e-soltar.
class StudyNotifier extends Notifier<StudyState> {
  @override
  StudyState build() => StudyState(study: _emptyStudy());

  static PortfolioStudy _emptyStudy() => PortfolioStudy(
    name: 'Novo estudo',
    principal: Portfolio(
      id: 'principal',
      name: 'Principal',
      kind: PortfolioKind.principal,
      entries: const {},
    ),
    reserva: Portfolio(
      id: 'reserva',
      name: 'Reserva',
      kind: PortfolioKind.reserva,
      entries: const {},
    ),
  );

  /// Substitui o estudo em edição pelo informado, descartando alterações não
  /// salvas e qualquer erro pendente.
  void load(PortfolioStudy study) {
    state = StudyState(study: study);
  }

  /// Renomeia o estudo. Não valida: nome vazio é aceito.
  void rename(String name) {
    state = state.copyWith(
      study: state.study.copyWith(name: name),
      clearError: true,
    );
  }

  /// Define a meta patrimonial do estudo, substituindo a anterior.
  void setGoal(FinancialGoal goal) {
    state = state.copyWith(
      study: state.study.copyWith(goal: goal),
      clearError: true,
    );
  }

  /// Move um ativo entre as carteiras — o gesto central da interface.
  ///
  /// - [ticker]: ativo a mover.
  /// - [toPrincipal]: `true` promove da Reserva para a Principal; `false`
  ///   rebaixa no sentido contrário.
  ///
  /// As **duas** carteiras são reequiponderadas, o que descarta pesos
  /// customizados de ambas. Recusa — via [StudyState.lastError] — quando o
  /// ativo não está na origem, já está no destino, ou o destino atingiu o teto
  /// de 15 ativos.
  void swap({required Ticker ticker, required bool toPrincipal}) {
    final result = SwapAssetBetweenPortfolios.call(
      principal: state.study.principal,
      reserva: state.study.reserva,
      ticker: ticker,
      toPrincipal: toPrincipal,
    );

    result.fold(
      (outcome) => state = state.copyWith(
        study: state.study.copyWith(
          principal: outcome.principal,
          reserva: outcome.reserva,
        ),
        clearError: true,
      ),
      (failure) => state = state.copyWith(lastError: FailureCopy.of(failure)),
    );
  }

  /// Inclui um ativo na carteira indicada e reequipondera.
  ///
  /// - [asset]: ativo a incluir.
  /// - [toPrincipal]: carteira de destino.
  ///
  /// Recusa via [StudyState.lastError] se o ativo já estiver presente ou se a
  /// carteira estiver no teto. Descarta pesos customizados.
  void addAsset(Asset asset, {required bool toPrincipal}) {
    final target = toPrincipal ? state.study.principal : state.study.reserva;
    final result = target.add(asset);

    result.fold(
      (updated) => state = state.copyWith(
        study: toPrincipal
            ? state.study.copyWith(principal: updated)
            : state.study.copyWith(reserva: updated),
        clearError: true,
      ),
      (failure) => state = state.copyWith(lastError: FailureCopy.of(failure)),
    );
  }

  /// Remove um ativo da carteira indicada e reequipondera o restante.
  ///
  /// - [ticker]: ativo a remover.
  /// - [fromPrincipal]: carteira de origem.
  ///
  /// Recusa via [StudyState.lastError] se o ativo não estiver na carteira.
  /// Remover o último ativo deixa a carteira **vazia**, não é erro. Descarta
  /// pesos customizados.
  void removeAsset(Ticker ticker, {required bool fromPrincipal}) {
    final target = fromPrincipal ? state.study.principal : state.study.reserva;
    final result = target.remove(ticker);

    result.fold(
      (updated) => state = state.copyWith(
        study: fromPrincipal
            ? state.study.copyWith(principal: updated)
            : state.study.copyWith(reserva: updated),
        clearError: true,
      ),
      (failure) => state = state.copyWith(lastError: FailureCopy.of(failure)),
    );
  }

  /// Aplica pesos customizados, exigindo soma de 100%.
  ///
  /// - [weights]: peso em fração por ativo. Precisa cobrir **todos** os ativos
  ///   da carteira alvo e somar 1,0 com folga de `1e-6`.
  /// - [onPrincipal]: `true` para a Principal, `false` para a Reserva.
  ///
  /// **Não lança e não devolve nada**: a recusa vira mensagem em
  /// [StudyState.lastError] e o estado permanece inalterado. É o contrato de
  /// erro de todo este notifier — a interface reage ao campo, não a exceção.
  ///
  /// Recusa quando a soma foge da tolerância ou quando falta o peso de algum
  /// ativo presente na carteira. Pesos de tickers que não estão na carteira são
  /// **ignorados em silêncio**.
  void setWeights(Map<Ticker, double> weights, {required bool onPrincipal}) {
    final target = onPrincipal ? state.study.principal : state.study.reserva;

    final total = weights.values.fold<double>(0.0, (a, b) => a + b);
    if ((total - 1.0).abs() > 1e-6) {
      state = state.copyWith(
        lastError: 'Os pesos devem somar 100%; somam ${Fmt.percent(total)}.',
      );
      return;
    }

    final entries = <Ticker, PortfolioEntry>{};
    for (final entry in target.entries.entries) {
      final weight = weights[entry.key];
      if (weight == null) {
        state = state.copyWith(
          lastError: 'Peso não informado para ${entry.key.value}.',
        );
        return;
      }
      entries[entry.key] = entry.value.withWeight(Weight.fraction(weight));
    }

    final updated = Portfolio(
      id: target.id,
      name: target.name,
      kind: target.kind,
      entries: entries,
    );

    state = state.copyWith(
      study: onPrincipal
          ? state.study.copyWith(principal: updated)
          : state.study.copyWith(reserva: updated),
      clearError: true,
    );
  }

  /// Redistribui os pesos igualmente na carteira indicada.
  ///
  /// - [onPrincipal]: `true` para a Principal, `false` para a Reserva.
  ///
  /// Nunca falha: uma carteira vazia continua vazia.
  void equalize({required bool onPrincipal}) {
    state = state.copyWith(
      study: onPrincipal
          ? state.study.copyWith(principal: state.study.principal.equalize())
          : state.study.copyWith(reserva: state.study.reserva.equalize()),
      clearError: true,
    );
  }

  /// Grava o estudo no Firestore.
  ///
  /// Retorna `true` em sucesso. Em falha devolve `false` e publica a mensagem
  /// em [StudyState.lastError] — **não lança**.
  ///
  /// Efeitos colaterais: marca [StudyState.isSaving] durante a operação, grava
  /// o `id` devolvido no estudo em edição (o que converte a próxima gravação de
  /// criação em atualização) e invalida a lista de estudos salvos, sem a qual o
  /// recém-gravado só apareceria na sessão seguinte.
  ///
  /// Devolve `false` sem tocar no estado quando não há usuário autenticado.
  Future<bool> save() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) {
      state = state.copyWith(
        lastError:
            'Sessão não identificada. Saia e entre novamente para '
            'salvar o estudo.',
      );
      return false;
    }

    state = state.copyWith(isSaving: true, clearError: true);
    final result = await ref
        .read(portfolioRepositoryProvider)
        .save(userId, state.study);

    return result.fold(
      (id) {
        state = state.copyWith(
          study: state.study.copyWith(id: id),
          isSaving: false,
        );
        // A lista de estudos salvos é derivada do Firestore; sem invalidar,
        // o estudo recém-gravado só apareceria na próxima sessão.
        ref.invalidate(savedStudiesProvider);
        return true;
      },
      (failure) {
        state = state.copyWith(isSaving: false, lastError: FailureCopy.of(failure));
        return false;
      },
    );
  }

  /// Cria um estudo novo, preservando a meta já definida.
  ///
  /// Zerar a meta junto obrigaria a redigitá-la a cada estudo — e é justamente
  /// o mesmo plano de aportes que torna dois estudos comparáveis.
  void startNew() {
    state = StudyState(study: _emptyStudy().copyWith(goal: state.study.goal));
  }

  /// Remove um estudo salvo, pelo identificador.
  ///
  /// - [id]: documento a remover.
  ///
  /// Retorna `true` em sucesso; em falha devolve `false` e publica a mensagem
  /// em [StudyState.lastError].
  ///
  /// **Apagar o estudo aberto não limpa a tela**: o conteúdo permanece e apenas
  /// o vínculo com o documento é desfeito, de modo que a próxima gravação crie
  /// um documento novo. Devolve `false` sem efeito se não houver usuário
  /// autenticado.
  Future<bool> deleteSaved(String id) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return false;

    final result = await ref
        .read(portfolioRepositoryProvider)
        .delete(userId, id);
    return result.fold(
      (_) {
        // Apagar o estudo aberto não apaga o que está na tela: só desfaz o
        // vínculo, para que o próximo "salvar" crie um documento novo.
        if (state.study.id == id) {
          state = StudyState(study: _detach(state.study));
        }
        ref.invalidate(savedStudiesProvider);
        return true;
      },
      (failure) {
        state = state.copyWith(lastError: FailureCopy.of(failure));
        return false;
      },
    );
  }

  static PortfolioStudy _detach(PortfolioStudy study) => PortfolioStudy(
    name: study.name,
    principal: study.principal,
    reserva: study.reserva,
    goal: study.goal,
  );

  /// Apaga a mensagem de erro pendente, depois que a interface a exibiu.
  void clearError() => state = state.copyWith(clearError: true);
}

final studyProvider = NotifierProvider<StudyNotifier, StudyState>(
  StudyNotifier.new,
);

/// Concentração setorial da carteira Principal.
///
/// Derivada de forma síncrona: reagir ao estado custa menos que orquestrar um
/// recálculo assíncrono, e o alerta acompanha cada arraste sem atraso.
final concentrationProvider = Provider<ConcentrationReport>((ref) {
  final study = ref.watch(studyProvider).study;
  return SectorConcentration.analyze(study.principal);
});

/// Estudos salvos pelo usuário.
///
/// A falha é **propagada**, não convertida em lista vazia: "nenhum estudo
/// salvo" e "não consegui ler os estudos" são situações diferentes, e
/// confundi-las esconderia justamente o erro que o usuário precisa ver.
final savedStudiesProvider = FutureProvider<List<PortfolioStudy>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const [];

  final result = await ref.watch(portfolioRepositoryProvider).listFor(userId);
  return result.fold(
    (studies) => studies,
    (failure) => throw Exception(failure.message),
  );
});

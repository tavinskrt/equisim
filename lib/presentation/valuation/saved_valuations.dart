import 'package:equisim_core/equisim_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';

/// Os valuations que o usuário confirmou, do mais recente para o mais antigo
/// (decisão 150).
///
/// **É daqui que eles chegam ao painel de logs.** Cada registro vira um evento
/// de auditoria em dois momentos: na confirmação, e ao carregar o histórico
/// gravado. O segundo é o que faz o painel refletir o que está **persistido**,
/// e não só o que aconteceu nesta sessão — o histórico do painel vive em
/// memória e começa vazio a cada abertura do aplicativo. O evento leva o
/// identificador do registro, e o barramento descarta identificador repetido:
/// o mesmo valuation nunca aparece duas vezes.
///
/// Sem painel ligado, `AuditRecorder.emit` não faz nada — o custo em produção
/// é zero, como o do resto da instrumentação.
class SavedValuationsNotifier extends AsyncNotifier<List<ManualValuationRecord>> {
  @override
  Future<List<ManualValuationRecord>> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return const [];

    final result = await ref.watch(manualValuationStoreProvider).listFor(userId);
    final records = result.fold(
      (records) => records,
      (failure) => throw Exception(failure.message),
    );
    // Do mais antigo ao mais recente: o painel lista na ordem de chegada, e
    // assim a ordem dele é a das confirmações.
    for (final record in records.reversed) {
      AuditRecorder.emit(record.toAuditEvent());
    }
    return records;
  }

  /// Grava o valuation confirmado e o registra no painel de logs.
  ///
  /// O evento só vai ao painel como **confirmado** depois que o armazenamento
  /// aceitou o registro. Se a gravação falha, vai ao painel uma tentativa
  /// recusada, com o motivo — e com outro identificador, para que a nova
  /// tentativa, com o mesmo registro, apareça quando der certo.
  Future<Result<void>> confirm(ManualValuationRecord record) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) {
      const failure = InvalidInput(
        'Entre na sua conta para salvar o valuation: ele é guardado junto dos '
        'seus estudos.',
      );
      _emitRefused(record, failure);
      return const Err(failure);
    }

    final saved = await ref.read(manualValuationStoreProvider).save(userId, record);
    final failure = saved.failureOrNull;
    if (failure != null) {
      _emitRefused(record, failure);
      return Err(failure);
    }

    AuditRecorder.emit(record.toAuditEvent());
    final current = state.value ?? const <ManualValuationRecord>[];
    state = AsyncData([
      record,
      for (final r in current)
        if (r.id != record.id) r,
    ]);
    return const Ok(null);
  }

  /// Apaga um valuation salvo. **Irreversível.**
  ///
  /// O evento que ele deixou no painel desta sessão fica: o painel é o
  /// registro do que aconteceu, e o valuation foi confirmado.
  Future<Result<void>> remove(String id) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) {
      return const Err(InvalidInput('Usuário não identificado.'));
    }
    final removed = await ref.read(manualValuationStoreProvider).delete(userId, id);
    if (removed.isOk) {
      final current = state.value ?? const <ManualValuationRecord>[];
      state = AsyncData([
        for (final r in current)
          if (r.id != id) r,
      ]);
    }
    return removed;
  }

  void _emitRefused(ManualValuationRecord record, Failure failure) {
    final event = record.toAuditEvent();
    AuditRecorder.emit(AuditEvent(
      transactionId: AuditIds.uuidV4(),
      timestamp: event.timestamp,
      endpoint: event.endpoint,
      inputPayload: event.inputPayload,
      outputPayload: {
        'status': 'falha',
        'motivo': 'O valuation não foi salvo: ${failure.message}',
        'registro': record.id,
      },
      executionTimeMs: 0,
      calculations: event.calculations,
    ));
  }
}

/// Os valuations confirmados do usuário autenticado.
///
/// **Sem nova tentativa automática**: a falha comum aqui é de permissão ou de
/// Firebase não inicializado, que repetir não conserta, e cada repetição
/// voltaria a emitir para o painel. A tela mostra a falha e segue.
final savedValuationsProvider =
    AsyncNotifierProvider<SavedValuationsNotifier, List<ManualValuationRecord>>(
  SavedValuationsNotifier.new,
  retry: (_, _) => null,
);

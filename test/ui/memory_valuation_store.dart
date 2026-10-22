import 'package:equisim/data/repositories/manual_valuation_repository.dart';
import 'package:equisim_core/equisim_core.dart';

/// Os valuations confirmados em memória, para os testes de tela (decisão 150).
///
/// **Passa cada registro por [ManualValuationRecord.toJson] e
/// [ManualValuationRecord.fromJson]**, como o Firestore obriga: um campo que
/// não sobrevivesse à gravação apareceria aqui, e não só no aparelho.
///
/// Não é teste — é apoio dos testes, por isso o nome sem `_test`.
class MemoryValuationStore implements ManualValuationStore {
  /// Documentos gravados, por identificador: o dono e o registro serializado.
  final Map<String, ({String userId, Map<String, dynamic> json})> documents =
      {};

  /// Quando não nulo, toda gravação devolve esta falha.
  Failure? failOnSave;

  /// Declara o armazenamento, já com [seed] gravado em nome de [owner].
  MemoryValuationStore({
    List<ManualValuationRecord> seed = const [],
    String owner = 'usuario-1',
  }) {
    for (final r in seed) {
      documents[r.id] = (userId: owner, json: r.toJson());
    }
  }

  /// Os registros relidos, do mais recente ao mais antigo.
  List<ManualValuationRecord> recordsOf(String userId) => [
        for (final d in documents.values)
          if (d.userId == userId) ManualValuationRecord.fromJson(d.json)!,
      ]..sort((a, b) => b.savedAt.compareTo(a.savedAt));

  @override
  Future<Result<List<ManualValuationRecord>>> listFor(String userId) async =>
      Ok(recordsOf(userId));

  @override
  Future<Result<void>> save(String userId, ManualValuationRecord record) async {
    final failure = failOnSave;
    if (failure != null) return Err(failure);
    documents[record.id] = (userId: userId, json: record.toJson());
    return const Ok(null);
  }

  @override
  Future<Result<void>> delete(String userId, String id) async {
    final doc = documents[id];
    if (doc == null) return const Err(InsufficientData('Valuation não encontrado.'));
    if (doc.userId != userId) {
      return const Err(InvalidInput('Este valuation pertence a outro usuário.'));
    }
    documents.remove(id);
    return const Ok(null);
  }
}

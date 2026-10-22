import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equisim_core/equisim_core.dart';
import 'package:flutter/foundation.dart';

/// Onde moram os valuations que o usuário confirmou (decisão 150).
///
/// **Contrato, e não classe concreta**, porque a tela e o painel de logs são
/// testados sem Firebase: o teste monta a mesma lógica sobre um armazenamento
/// em memória, e o aplicativo, sobre o Firestore.
abstract interface class ManualValuationStore {
  /// Os valuations do usuário, do mais recente para o mais antigo.
  ///
  /// Lista vazia é **sucesso**. Um documento ilegível é descartado, e não
  /// derruba a lista.
  Future<Result<List<ManualValuationRecord>>> listFor(String userId);

  /// Grava [record] em nome de [userId].
  ///
  /// **Idempotente**: o documento leva o identificador do registro, então
  /// repetir a gravação depois de uma falha de rede não cria duplicata.
  Future<Result<void>> save(String userId, ManualValuationRecord record);

  /// Apaga o valuation [id], conferindo que ele é de [userId]. Irreversível.
  Future<Result<void>> delete(String userId, String id);
}

/// Os valuations confirmados no Firestore, na coleção [collection].
///
/// O desenho segue o de `PortfolioRepository`: o dono vai no documento, a
/// regra de segurança confere que é quem está autenticado, e a ordenação é
/// local para não exigir índice composto publicado.
class FirestoreManualValuationStore implements ManualValuationStore {
  /// Instância do Firestore. Injetada para permitir teste com um duplo.
  final FirebaseFirestore firestore;

  /// Quanto esperar a confirmação do servidor antes de desistir.
  ///
  /// Sem teto, a gravação feita sem rede no navegador fica pendurada para
  /// sempre — o Firestore da web só resolve o `set` quando o servidor
  /// confirma —, e o botão de confirmar ficaria girando sem dizer nada.
  final Duration timeout;

  /// Declara o armazenamento sobre uma instância do Firestore.
  FirestoreManualValuationStore(
    this.firestore, {
    this.timeout = const Duration(seconds: 20),
  });

  /// Nome da coleção. Ver `firestore.rules`.
  static const String collection = 'valuations';

  CollectionReference<Map<String, dynamic>> get _collection =>
      firestore.collection(collection);

  @override
  Future<Result<List<ManualValuationRecord>>> listFor(String userId) async {
    if (userId.trim().isEmpty) {
      return const Err(InvalidInput('Usuário não identificado.'));
    }
    try {
      final snapshot =
          await _collection.where('userId', isEqualTo: userId).get();
      final records = <ManualValuationRecord>[];
      for (final doc in snapshot.docs) {
        final raw = doc.data()['registro'];
        final record = raw is Map
            ? ManualValuationRecord.fromJson(
                raw.map((k, v) => MapEntry('$k', v)),
              )
            : null;
        if (record == null) {
          debugPrint('⚠️  Valuation salvo ilegível, descartado: ${doc.id}');
          continue;
        }
        records.add(record);
      }
      records.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return Ok(records);
    } on FirebaseException catch (e) {
      return Err(ComputationFailure(
        'Falha ao carregar os valuations salvos: ${e.message ?? e.code}',
      ));
    }
  }

  @override
  Future<Result<void>> save(String userId, ManualValuationRecord record) async {
    if (userId.trim().isEmpty) {
      return const Err(InvalidInput('Usuário não identificado.'));
    }
    try {
      await _collection.doc(record.id).set({
        'userId': userId,
        // Campos de topo só para consulta e leitura no console; a verdade é o
        // `registro`, que o núcleo relê.
        'ticker': record.ticker.value,
        'salvoEm': Timestamp.fromDate(record.savedAt),
        'registro': record.toJson(),
        'gravadoEm': FieldValue.serverTimestamp(),
      }).timeout(timeout);
      return const Ok(null);
    } on TimeoutException {
      return const Err(ComputationFailure(
        'O servidor não confirmou a gravação a tempo. Confira a conexão e '
        'confirme de novo: a nova tentativa não duplica o valuation.',
      ));
    } on FirebaseException catch (e) {
      return Err(ComputationFailure(
        'Falha ao salvar o valuation: ${e.message ?? e.code}',
      ));
    }
  }

  @override
  Future<Result<void>> delete(String userId, String id) async {
    try {
      final doc = await _collection.doc(id).get();
      if (!doc.exists) {
        return const Err(InsufficientData('Valuation não encontrado.'));
      }
      // Dupla checagem local, além da regra de segurança do Firestore: a regra
      // é a barreira, esta produz a frase que o usuário entende.
      if (doc.data()?['userId'] != userId) {
        return const Err(InvalidInput('Este valuation pertence a outro usuário.'));
      }
      await _collection.doc(id).delete();
      return const Ok(null);
    } on FirebaseException catch (e) {
      return Err(ComputationFailure(
        'Falha ao apagar o valuation: ${e.message ?? e.code}',
      ));
    }
  }
}

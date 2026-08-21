import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equisim_core/equisim_core.dart';

import 'portfolio_codec.dart';

/// Um estudo: as duas carteiras e a meta que as motiva.
///
/// Principal e Reserva vivem no **mesmo documento** porque só fazem sentido
/// juntas — a Reserva existe para alimentar a Principal. Guardá-las separadas
/// exigiria uma chave de ligação e abriria a possibilidade de estado
/// inconsistente entre as duas metades.
class PortfolioStudy {
  final String? id;
  final String name;
  final Portfolio principal;
  final Portfolio reserva;
  final FinancialGoal? goal;
  final DateTime? updatedAt;

  const PortfolioStudy({
    this.id,
    required this.name,
    required this.principal,
    required this.reserva,
    this.goal,
    this.updatedAt,
  });

  PortfolioStudy copyWith({
    String? id,
    String? name,
    Portfolio? principal,
    Portfolio? reserva,
    FinancialGoal? goal,
  }) =>
      PortfolioStudy(
        id: id ?? this.id,
        name: name ?? this.name,
        principal: principal ?? this.principal,
        reserva: reserva ?? this.reserva,
        goal: goal ?? this.goal,
        updatedAt: updatedAt,
      );
}

/// Persistência dos estudos no Firestore.
///
/// Substitui a coleção `backtests`, do escopo anterior. Os documentos antigos
/// permanecem no banco com suas regras de segurança: apagá-los agora deixaria
/// dados de usuário órfãos. A migração é uma decisão do usuário, não um efeito
/// colateral da troca de escopo.
class PortfolioRepository {
  final FirebaseFirestore firestore;

  PortfolioRepository(this.firestore);

  static const String collection = 'portfolios';

  CollectionReference<Map<String, dynamic>> get _collection =>
      firestore.collection(collection);

  Future<Result<List<PortfolioStudy>>> listFor(String userId) async {
    if (userId.trim().isEmpty) {
      return const Err(InvalidInput('Usuário não identificado.'));
    }
    try {
      // Só o filtro por dono vai ao servidor. `orderBy` combinado com `where`
      // exigiria um índice composto publicado — e, sem ele, a consulta falha
      // inteira. A ordenação acontece aqui: são poucos estudos por usuário, e
      // a lista deixa de depender de um passo de infraestrutura.
      final snapshot =
          await _collection.where('userId', isEqualTo: userId).get();

      final studies = snapshot.docs.map(_fromDoc).toList()
        ..sort((a, b) {
          final left = a.updatedAt;
          final right = b.updatedAt;
          if (left == null && right == null) return 0;
          if (left == null) return 1; // sem data vai para o fim
          if (right == null) return -1;
          return right.compareTo(left);
        });
      return Ok(studies);
    } on FirebaseException catch (e) {
      return Err(ComputationFailure(
        'Falha ao carregar os estudos salvos: ${e.message ?? e.code}',
      ));
    }
  }

  Future<Result<String>> save(String userId, PortfolioStudy study) async {
    if (userId.trim().isEmpty) {
      return const Err(InvalidInput('Usuário não identificado.'));
    }
    try {
      final data = <String, dynamic>{
        'userId': userId,
        'name': study.name,
        'principal': PortfolioStudyCodec.encodePortfolio(study.principal),
        'reserva': PortfolioStudyCodec.encodePortfolio(study.reserva),
        if (study.goal != null) 'goal': PortfolioStudyCodec.encodeGoal(study.goal!),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (study.id == null) {
        data['createdAt'] = FieldValue.serverTimestamp();
        final ref = await _collection.add(data);
        return Ok(ref.id);
      }
      await _collection.doc(study.id).update(data);
      return Ok(study.id!);
    } on FirebaseException catch (e) {
      return Err(ComputationFailure(
        'Falha ao salvar o estudo: ${e.message ?? e.code}',
      ));
    }
  }

  Future<Result<void>> delete(String userId, String id) async {
    try {
      final doc = await _collection.doc(id).get();
      if (!doc.exists) {
        return const Err(InsufficientData('Estudo não encontrado.'));
      }
      // Dupla checagem local, além da regra de segurança do Firestore.
      if (doc.data()?['userId'] != userId) {
        return const Err(InvalidInput(
          'Este estudo pertence a outro usuário.',
        ));
      }
      await _collection.doc(id).delete();
      return const Ok(null);
    } on FirebaseException catch (e) {
      return Err(ComputationFailure(
        'Falha ao remover o estudo: ${e.message ?? e.code}',
      ));
    }
  }

  static PortfolioStudy _fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return PortfolioStudy(
      id: doc.id,
      name: (data['name'] as String?) ?? 'Estudo sem nome',
      principal: PortfolioStudyCodec.decodePortfolio(
        data['principal'],
        id: '${doc.id}-principal',
        name: 'Principal',
        kind: PortfolioKind.principal,
      ),
      reserva: PortfolioStudyCodec.decodePortfolio(
        data['reserva'],
        id: '${doc.id}-reserva',
        name: 'Reserva',
        kind: PortfolioKind.reserva,
      ),
      goal: PortfolioStudyCodec.decodeGoal(data['goal']),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}

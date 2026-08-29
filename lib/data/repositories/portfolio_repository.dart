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
  /// Identificador do documento. `null` enquanto o estudo não foi gravado —
  /// é o que distingue criação de atualização.
  final String? id;

  /// Nome do estudo, editável pelo usuário.
  final String name;

  /// Carteira vigente.
  final Portfolio principal;

  /// Candidatos a substituição.
  final Portfolio reserva;

  /// Meta patrimonial. `null` enquanto o usuário não a declarou.
  final FinancialGoal? goal;

  /// Instante da última gravação, vindo do servidor. `null` num estudo ainda
  /// não persistido.
  final DateTime? updatedAt;

  /// Declara o estudo.
  const PortfolioStudy({
    this.id,
    required this.name,
    required this.principal,
    required this.reserva,
    this.goal,
    this.updatedAt,
  });

  /// Cópia com os campos informados substituídos.
  ///
  /// **[updatedAt] é sempre preservado**, nunca sobrescrito: quem o define é o
  /// servidor na gravação, não o cliente. E, como em todo `copyWith` de campo
  /// anulável, passar `null` em [goal] preserva a meta atual em vez de apagá-la
  /// — remover a meta exige construir o estudo diretamente.
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
  /// Instância do Firestore. Injetada para permitir teste com um duplo.
  final FirebaseFirestore firestore;

  /// Declara o repositório sobre uma instância do Firestore.
  PortfolioRepository(this.firestore);

  /// Nome da coleção. A anterior, `backtests`, permanece intocada no banco.
  static const String collection = 'portfolios';

  CollectionReference<Map<String, dynamic>> get _collection =>
      firestore.collection(collection);

  /// Lista os estudos de um usuário, do mais recente para o mais antigo.
  ///
  /// - [userId]: dono dos estudos.
  ///
  /// Devolve [InvalidInput] para identificador vazio e [ComputationFailure]
  /// para falha do Firestore. Lista vazia é **sucesso**, não falha.
  ///
  /// Estudos sem `updatedAt` — gravação ainda não confirmada pelo servidor —
  /// vão para o fim da lista. A ordenação é local de propósito: combinar
  /// `where` com `orderBy` exigiria índice composto publicado, e sem ele a
  /// consulta falharia inteira.
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

  /// Grava o estudo, criando ou atualizando conforme `study.id`.
  ///
  /// - [userId]: dono do estudo, gravado no documento.
  /// - [study]: estudo a persistir. `id` nulo cria; `id` presente atualiza.
  ///
  /// Retorna o identificador do documento — o novo, na criação.
  ///
  /// Devolve [InvalidInput] para identificador de usuário vazio e
  /// [ComputationFailure] para falha do Firestore.
  ///
  /// `updatedAt` é sempre carimbado pelo **servidor**; `createdAt` só na
  /// criação. Uma meta nula é **omitida** do payload em vez de gravada como
  /// nulo — o que, numa atualização, deixa a meta anterior intacta no
  /// documento em vez de removê-la.
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

  /// Remove um estudo, conferindo a propriedade antes.
  ///
  /// - [userId]: quem está pedindo a remoção.
  /// - [id]: documento a remover.
  ///
  /// Devolve [InsufficientData] se o documento não existe e [InvalidInput] se
  /// pertence a outro usuário; [ComputationFailure] para falha do Firestore.
  ///
  /// A conferência de dono é **redundante** com a regra de segurança do
  /// Firestore, e deliberadamente: a regra é a barreira que vale, esta produz a
  /// mensagem que o usuário entende em vez de um erro de permissão cru.
  ///
  /// **Irreversível** — não há lixeira.
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

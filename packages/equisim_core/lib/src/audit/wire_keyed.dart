/// Valor que se grava pela própria chave, e não pelo nome do identificador.
///
/// Os enums cujo texto sai do código — no pacote de dados, no rastro de
/// auditoria, num relatório — implementam esta interface, para que o nome do
/// valor possa mudar sem mudar o que se grava. `AuditJson.safe` lê [key] antes
/// de `name`.
abstract interface class WireKeyed {
  /// O texto gravado.
  String get key;
}

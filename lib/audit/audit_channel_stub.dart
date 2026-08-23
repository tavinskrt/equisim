import 'audit_channel.dart';

/// Canal fora do navegador: não há segunda janela para alcançar.
///
/// Não é um erro nem uma pendência — em Android, iOS e desktop o painel de
/// auditoria vive na mesma aplicação, e o barramento entrega os eventos
/// localmente. Este canal apenas declara que não há travessia a fazer.
class PlatformAuditChannel implements AuditChannel {
  PlatformAuditChannel(this.name);

  final String name;

  @override
  bool get supportsCrossWindow => false;

  @override
  void post(String json) {}

  @override
  Stream<String> get incoming => const Stream<String>.empty();

  @override
  void close() {}
}

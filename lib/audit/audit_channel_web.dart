import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'audit_channel.dart';

/// Canal sobre a `BroadcastChannel` do navegador.
///
/// O tráfego é **texto JSON**, não objeto estruturado. A alternativa seria
/// converter os mapas Dart para objetos JS e de volta a cada mensagem; JSON
/// resolve isso numa linha, tem custo desprezível para payloads desta ordem
/// (poucos kilobytes) e — o que decide a questão — é exatamente o formato que
/// a exportação da auditoria precisa produzir no fim.
class PlatformAuditChannel implements AuditChannel {
  PlatformAuditChannel(this.name) : _channel = web.BroadcastChannel(name) {
    _channel.addEventListener('message', _onMessage.toJS);
  }

  final String name;
  final web.BroadcastChannel _channel;
  final StreamController<String> _incoming = StreamController<String>.broadcast();
  bool _closed = false;

  void _onMessage(web.Event event) {
    if (_closed) return;
    final data = (event as web.MessageEvent).data;
    if (data.isA<JSString>()) {
      _incoming.add((data as JSString).toDart);
    }
  }

  @override
  bool get supportsCrossWindow => true;

  @override
  void post(String json) {
    if (_closed) return;
    _channel.postMessage(json.toJS);
  }

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _channel.close();
    _incoming.close();
  }
}

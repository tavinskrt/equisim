import 'audio_helper_stub.dart'
    if (dart.library.html) 'audio_helper_web.dart'
    if (dart.library.io) 'audio_helper_native.dart';

/// Helper para acionar feedback de áudio leve baseado em hardware e feedback tátil.
class AudioHelper {
  /// Toca um som leve de sucesso (Web Audio API) ou som de clique e feedback tátil (nativo).
  static void playSuccessSound() {
    playSuccessSoundImpl();
  }
}

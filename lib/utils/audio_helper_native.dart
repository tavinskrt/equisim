import 'package:flutter/services.dart';

/// Implementação nativa do player de áudio usando sons do sistema Flutter e feedback tátil.
void playSuccessSoundImpl() {
  try {
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.mediumImpact();
  } catch (e) {
    // Falha silenciosamente caso os sons do sistema/plataforma não estejam disponíveis
  }
}

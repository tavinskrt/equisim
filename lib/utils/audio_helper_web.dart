import 'dart:js' as js;

/// Implementação Web do player de áudio usando a Web Audio API do navegador.
void playSuccessSoundImpl() {
  try {
    js.context.callMethod('eval', [
      """
      (function() {
        try {
          const AudioContext = window.AudioContext || window.webkitAudioContext;
          if (!AudioContext) return;
          const ctx = new AudioContext();
          const playTone = (freq, start, duration) => {
            const osc = ctx.createOscillator();
            const gain = ctx.createGain();
            osc.type = 'sine';
            osc.frequency.setValueAtTime(freq, ctx.currentTime + start);
            gain.gain.setValueAtTime(0.08, ctx.currentTime + start);
            gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + start + duration);
            osc.connect(gain);
            gain.connect(ctx.destination);
            osc.start(ctx.currentTime + start);
            osc.stop(ctx.currentTime + start + duration);
          };
          playTone(523.25, 0, 0.08); // C5 (Do)
          playTone(659.25, 0.08, 0.15); // E5 (Mi)
        } catch (e) {
          console.warn('Audio feedback failed:', e);
        }
      })();
      """
    ]);
  } catch (e) {
    // Falha silenciosamente em caso de bloqueios de contexto de segurança ou outros problemas
  }
}

import 'package:flutter/services.dart';

const _channel = MethodChannel('com.example.equisim/audio');

/// Native implementation of the audio player using platform channels for mobile.
void playSuccessSoundImpl() async {
  try {
    // Tries to play custom native audio on Android/iOS via MethodChannel
    await _channel.invokeMethod('playSuccessSound');
    // Provides tactile feedback
    await HapticFeedback.mediumImpact();
  } catch (e) {
    // Fallback: plays the system basic click if channel fails
    try {
      await SystemSound.play(SystemSoundType.click);
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }
}

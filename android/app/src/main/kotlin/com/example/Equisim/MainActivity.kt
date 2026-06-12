package com.example.equisim

import android.media.AudioManager
import android.media.ToneGenerator
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.equisim/audio"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "playSuccessSound") {
                try {
                    val toneGen = ToneGenerator(AudioManager.STREAM_MUSIC, 85)
                    // TONE_PROP_ACK plays a pleasant double beep
                    toneGen.startTone(ToneGenerator.TONE_PROP_ACK, 220)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("AUDIO_ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}

import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VektorVoice {
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool sttReady = false;
  bool listening = false;

  Future<void> init() async {
    await Permission.microphone.request();
    sttReady = await _stt.initialize(
      onError: (e) => listening = false,
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') listening = false;
      },
    );
    await _tts.setLanguage('ru-RU');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  Future<String?> listenOnce({Duration timeout = const Duration(seconds: 8)}) async {
    if (!sttReady) {
      await init();
      if (!sttReady) return null;
    }
    if (listening) {
      await _stt.stop();
      listening = false;
    }
    listening = true;
    var text = '';
    await _stt.listen(
      localeId: 'ru_RU',
      listenMode: ListenMode.confirmation,
      partialResults: true,
      onResult: (r) {
        text = r.recognizedWords;
      },
    );
    await Future.delayed(timeout);
    await _stt.stop();
    listening = false;
    final t = text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> stopListen() async {
    await _stt.stop();
    listening = false;
  }

  Future<void> speak(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    // strip heavy markdown for speech
    final clean = t
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' блок кода ')
        .replaceAll(RegExp(r'[*_#>`]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (clean.isEmpty) return;
    await _tts.stop();
    await _tts.speak(clean.length > 800 ? '${clean.substring(0, 800)}…' : clean);
  }

  Future<void> stopSpeak() => _tts.stop();
}

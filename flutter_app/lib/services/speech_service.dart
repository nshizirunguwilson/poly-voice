import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Handles both Speech-to-Text (STT) and Text-to-Speech (TTS).
///
/// STT: For Blind/Normal users speaking → text for Deaf user.
/// TTS: For Deaf user's sign → text → voice for Blind/Normal user.
class SpeechService extends ChangeNotifier {
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _sttAvailable = false;
  bool _isListening = false;
  String _currentTranscript = '';
  String _lastFinalResult = '';
  List<String> _transcriptHistory = [];

  // ── Getters ──
  bool get isListening => _isListening;
  bool get sttAvailable => _sttAvailable;
  String get currentTranscript => _currentTranscript;
  String get lastFinalResult => _lastFinalResult;
  List<String> get transcriptHistory => _transcriptHistory;

  // ── Callbacks ──
  Function(String text)? onFinalResult;
  Function(String text)? onPartialResult;

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // INITIALIZATION
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Future<void> init() async {
    // Initialize STT
    _sttAvailable = await _stt.initialize(
      onStatus: (status) {
        debugPrint('STT Status: $status');
        if (status == 'done' || status == 'notListening') {
          _isListening = false;
          notifyListeners();
          // Auto-restart for continuous listening during calls
          if (_shouldAutoRestart) {
            Future.delayed(const Duration(milliseconds: 300), startListening);
          }
        }
      },
      onError: (error) {
        debugPrint('STT Error: $error');
        _isListening = false;
        notifyListeners();
      },
    );

    // Initialize TTS
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    // Use system's best voice
    final voices = await _tts.getVoices;
    if (voices is List && voices.isNotEmpty) {
      // Prefer a natural-sounding English voice
      final englishVoices = voices.where(
        (v) => v['locale']?.toString().startsWith('en') ?? false,
      );
      if (englishVoices.isNotEmpty) {
        await _tts.setVoice({
          'name': englishVoices.first['name'],
          'locale': englishVoices.first['locale'],
        });
      }
    }

    debugPrint('Speech service initialized. STT available: $_sttAvailable');
  }

  bool _shouldAutoRestart = false;

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // SPEECH TO TEXT
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Future<void> startListening({bool continuous = true}) async {
    if (!_sttAvailable || _isListening) return;

    _shouldAutoRestart = continuous;
    _isListening = true;
    notifyListeners();

    await _stt.listen(
      onResult: _onSpeechResult,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      listenMode: ListenMode.dictation,
    );
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    _currentTranscript = result.recognizedWords;

    if (result.finalResult) {
      _lastFinalResult = result.recognizedWords;
      if (_lastFinalResult.isNotEmpty) {
        _transcriptHistory.add(_lastFinalResult);
        onFinalResult?.call(_lastFinalResult);
      }
    } else {
      onPartialResult?.call(_currentTranscript);
    }

    notifyListeners();
  }

  Future<void> stopListening() async {
    _shouldAutoRestart = false;
    _isListening = false;
    await _stt.stop();
    notifyListeners();
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // TEXT TO SPEECH
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    await _tts.speak(text);
  }

  Future<void> stopSpeaking() async {
    await _tts.stop();
  }

  // ── Utility ──
  void clearHistory() {
    _transcriptHistory.clear();
    _currentTranscript = '';
    _lastFinalResult = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _shouldAutoRestart = false;
    _stt.stop();
    _tts.stop();
    super.dispose();
  }
}

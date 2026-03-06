import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Speech-to-Text + Text-to-Speech service.
///
/// STT auto-restarts for continuous listening during calls with
/// exponential backoff and a retry limit to avoid infinite error loops.
class SpeechService extends ChangeNotifier {
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _sttAvailable = false;
  bool _isListening = false;
  String _currentTranscript = '';
  String _lastFinalResult = '';
  final List<String> _transcriptHistory = [];

  // Public getters
  bool get sttAvailable => _sttAvailable;
  bool get isListening => _isListening;
  String get currentTranscript => _currentTranscript;
  String get lastFinalResult => _lastFinalResult;
  List<String> get transcriptHistory => List.unmodifiable(_transcriptHistory);

  // Callbacks
  Function(String text)? onFinalResult;
  Function(String text)? onPartialResult;

  bool _shouldAutoRestart = false;
  int _consecutiveErrors = 0;
  static const int _maxConsecutiveErrors = 3;

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // INITIALIZATION
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Future<void> init() async {
    _sttAvailable = await _stt.initialize(
      onStatus: (status) {
        debugPrint('STT Status: $status');
        if (status == 'done' || status == 'notListening') {
          _isListening = false;
          notifyListeners();
          // Auto-restart for continuous listening during calls
          if (_shouldAutoRestart &&
              _consecutiveErrors < _maxConsecutiveErrors) {
            final delay = Duration(
              milliseconds: 500 * (_consecutiveErrors + 1),
            );
            Future.delayed(delay, () {
              if (_shouldAutoRestart) startListening();
            });
          }
        }
      },
      onError: (error) {
        debugPrint('STT Error: $error');
        _isListening = false;
        _consecutiveErrors++;
        notifyListeners();

        // Only retry if below the error limit and set to auto-restart
        if (_shouldAutoRestart && _consecutiveErrors < _maxConsecutiveErrors) {
          final delay = Duration(seconds: _consecutiveErrors * 2);
          debugPrint(
              'STT will retry in ${delay.inSeconds}s (attempt $_consecutiveErrors/$_maxConsecutiveErrors)');
          Future.delayed(delay, () {
            if (_shouldAutoRestart) startListening();
          });
        } else if (_consecutiveErrors >= _maxConsecutiveErrors) {
          debugPrint('STT max retries reached, stopping auto-restart');
          _shouldAutoRestart = false;
        }
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
    // Reset error counter on successful result
    _consecutiveErrors = 0;

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
    _consecutiveErrors = 0;
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

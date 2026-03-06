import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:audioplayers/audioplayers.dart';
import '../config/app_config.dart';

/// Speech-to-Text + Text-to-Speech service using Deepgram.
class SpeechService extends ChangeNotifier {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  WebSocketChannel? _channel;
  StreamSubscription? _audioStreamSub;

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

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // INITIALIZATION
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Future<void> init() async {
    _sttAvailable = await _audioRecorder.hasPermission();
    debugPrint('Speech service initialized. STT available: $_sttAvailable');
    notifyListeners();
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // SPEECH TO TEXT (Deepgram Streaming)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Future<void> startListening({bool continuous = true}) async {
    if (!_sttAvailable || _isListening) return;

    _isListening = true;
    notifyListeners();

    try {
      final uri = Uri.parse(
          'wss://api.deepgram.com/v1/listen?encoding=linear16&sample_rate=16000&channels=1&interim_results=true');

      _channel = WebSocketChannel.connect(
        uri,
        protocols: ['token', AppConfig.deepgramApiKey],
      );

      _channel!.stream.listen((message) {
        final data = jsonDecode(message);
        if (data['channel'] != null &&
            data['channel']['alternatives'] != null) {
          final alt = data['channel']['alternatives'][0];
          final text = alt['transcript'] as String;

          if (text.isNotEmpty) {
            _currentTranscript = text;

            if (data['is_final'] == true) {
              _lastFinalResult = text;
              _transcriptHistory.add(text);
              onFinalResult?.call(text);
              _currentTranscript = ''; // reset for next sentence
            } else {
              onPartialResult?.call(text);
            }
            notifyListeners();
          }
        }
      }, onError: (error) {
        debugPrint('Deepgram STT Socket Error: $error');
        stopListening();
      }, onDone: () {
        debugPrint('Deepgram STT Socket Closed');
        stopListening();
      });

      final stream = await _audioRecorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ));

      _audioStreamSub = stream.listen((Uint8List data) {
        if (_channel != null) {
          _channel!.sink.add(data);
        }
      });
    } catch (e) {
      debugPrint('Error starting STT: $e');
      stopListening();
    }
  }

  Future<void> stopListening() async {
    _isListening = false;
    await _audioStreamSub?.cancel();
    _audioStreamSub = null;

    await _audioRecorder.stop();

    // Close websocket gently
    _channel?.sink.close();
    _channel = null;

    notifyListeners();
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // TEXT TO SPEECH (Deepgram REST)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Future<void> speak(String text) async {
    if (text.isEmpty) return;

    try {
      final url =
          Uri.parse('https://api.deepgram.com/v1/speak?model=aura-asteria-en');
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Token ${AppConfig.deepgramApiKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'text': text}),
      );

      if (response.statusCode == 200) {
        await _audioPlayer.play(BytesSource(response.bodyBytes));
      } else {
        debugPrint('TTS Error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('TTS Network Error: $e');
    }
  }

  Future<void> stopSpeaking() async {
    await _audioPlayer.stop();
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
    stopListening();
    _audioPlayer.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }
}

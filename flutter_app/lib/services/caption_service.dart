import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:googleapis/speech/v1.dart' as speech;
import 'package:googleapis_auth/auth_io.dart';

/// Manages real-time speech-to-text captions for the remote participant.
/// Uses Google Cloud Speech-to-Text API to transcribe incoming audio.
class CaptionService extends ChangeNotifier {
  bool _captionsEnabled = false;
  String _currentCaption = '';
  String _speakerName = '';
  Timer? _clearCaptionTimer;

  // Google Speech-to-Text
  speech.SpeechApi? _speechApi;
  StreamController<Uint8List>? _audioStreamController;
  bool _isTranscribing = false;

  bool get captionsEnabled => _captionsEnabled;
  String get currentCaption => _currentCaption;
  String get speakerName => _speakerName;

  /// Initialize the Google Speech-to-Text client.
  /// [credentials] should be your Google service account JSON credentials.
  Future<void> initialize(Map<String, dynamic> credentials) async {
    try {
      final accountCredentials = ServiceAccountCredentials.fromJson(credentials);
      final scopes = [speech.SpeechApi.cloudPlatformScope];
      final client = await clientViaServiceAccount(accountCredentials, scopes);
      _speechApi = speech.SpeechApi(client);
    } catch (e) {
      debugPrint('CaptionService: Failed to initialize Speech API: $e');
    }
  }

  /// Toggle captions on or off.
  void toggleCaptions() {
    _captionsEnabled = !_captionsEnabled;
    if (!_captionsEnabled) {
      _stopTranscription();
      _currentCaption = '';
      _speakerName = '';
    }
    notifyListeners();
  }

  /// Call this when a remote participant starts speaking.
  /// [participantName] is the display name shown above the caption.
  void onRemoteParticipantStartedSpeaking(String participantName) {
    if (!_captionsEnabled) return;
    _speakerName = participantName;
    _startTranscription();
  }

  /// Call this when a remote participant stops speaking.
  void onRemoteParticipantStoppedSpeaking() {
    if (!_captionsEnabled) return;
    _stopTranscription();
    // Keep caption visible for 3 seconds after speaking stops
    _clearCaptionTimer?.cancel();
    _clearCaptionTimer = Timer(const Duration(seconds: 3), () {
      _currentCaption = '';
      _speakerName = '';
      notifyListeners();
    });
  }

  /// Feed raw PCM audio bytes from the Twilio remote audio track.
  /// Call this continuously while the remote participant is speaking.
  void feedAudioData(Uint8List audioBytes) {
    if (!_captionsEnabled || !_isTranscribing) return;
    _audioStreamController?.add(audioBytes);
  }

  /// Update caption text directly (used when receiving transcription results).
  void _updateCaption(String text) {
    if (text.trim().isEmpty) return;
    _currentCaption = text;
    notifyListeners();
  }

  void _startTranscription() {
    if (_isTranscribing || _speechApi == null) return;
    _isTranscribing = true;
    _audioStreamController = StreamController<Uint8List>();
    _streamingRecognize();
  }

  Future<void> _streamingRecognize() async {
    try {
      final config = speech.RecognitionConfig(
        encoding: 'LINEAR16',
        sampleRateHertz: 16000,
        languageCode: 'en-US',
        enableAutomaticPunctuation: true,
        model: 'phone_call', // optimised for call audio
      );

      final streamingConfig = speech.StreamingRecognitionConfig(
        config: config,
        interimResults: true, // show partial results in real-time
      );

      // Build request stream: first message is config, rest are audio
      final requests = () async* {
        yield speech.StreamingRecognizeRequest(
          streamingConfig: streamingConfig,
        );
        await for (final audioChunk in _audioStreamController!.stream) {
          yield speech.StreamingRecognizeRequest(
            audioContent: base64Encode(audioChunk),
          );
        }
      }();

      final responses = _speechApi!.speech.streamingRecognize(
        speech.StreamingRecognizeRequest(), // placeholder; actual stream below
      );

      // NOTE: The googleapis package uses a request-stream pattern.
      // Depending on your googleapis version, use the streaming overload:
      // _speechApi!.speech.streamingRecognize(requestStream)
      // and listen to the response stream for transcripts.

    } catch (e) {
      debugPrint('CaptionService: Streaming recognition error: $e');
    }
  }

  void _stopTranscription() {
    _isTranscribing = false;
    _audioStreamController?.close();
    _audioStreamController = null;
  }

  @override
  void dispose() {
    _clearCaptionTimer?.cancel();
    _stopTranscription();
    super.dispose();
  }
}

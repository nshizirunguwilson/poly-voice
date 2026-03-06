import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'dart:convert';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../config/app_config.dart';

// ─────────────────────────────────────────────
// RESULT TYPE
// ─────────────────────────────────────────────

class SignDetectionResult {
  final String letter;
  final double confidence;
  final bool isStable;
  final String? wordPrediction;
  final double? wordConfidence;
  final DateTime timestamp;

  const SignDetectionResult({
    required this.letter,
    required this.confidence,
    this.isStable = false,
    this.wordPrediction,
    this.wordConfidence,
    required this.timestamp,
  });
}

// ─────────────────────────────────────────────
// IMAGE CONVERSION (run in compute isolate)
// ─────────────────────────────────────────────

Future<Uint8List?> _convertCameraImageToJpeg(CameraImage cameraImage) async {
  return compute(_convertIsolate, cameraImage);
}

Uint8List? _convertIsolate(CameraImage cameraImage) {
  try {
    img.Image? image;

    if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
      final plane = cameraImage.planes[0];
      image = img.Image.fromBytes(
        width: cameraImage.width,
        height: cameraImage.height,
        bytes: plane.bytes.buffer,
        format: img.Format.uint8,
        numChannels: 4,
        order: img.ChannelOrder.bgra,
      );
    } else if (cameraImage.format.group == ImageFormatGroup.yuv420) {
      image = _yuv420ToImage(cameraImage);
    } else {
      return null;
    }

    if (image == null) return null;

    final size = image.width < image.height ? image.width : image.height;
    final x = (image.width - size) ~/ 2;
    final y = (image.height - size) ~/ 2;
    final cropped = img.copyCrop(image, x: x, y: y, width: size, height: size);
    final resized = img.copyResize(cropped,
        width: 256, height: 256, interpolation: img.Interpolation.linear);

    return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
  } catch (e) {
    return null;
  }
}

img.Image? _yuv420ToImage(CameraImage cameraImage) {
  final width = cameraImage.width;
  final height = cameraImage.height;
  final yPlane = cameraImage.planes[0];
  final uPlane = cameraImage.planes[1];
  final vPlane = cameraImage.planes[2];

  final yBytes = yPlane.bytes;
  final uBytes = uPlane.bytes;
  final vBytes = vPlane.bytes;

  final uvRowStride = uPlane.bytesPerRow;
  final uvPixelStride = uPlane.bytesPerPixel ?? 1;

  final image = img.Image(width: width, height: height);

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final yIndex = y * yPlane.bytesPerRow + x;
      final uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;

      final yVal = yBytes[yIndex];
      final uVal = uBytes[uvIndex] - 128;
      final vVal = vBytes[uvIndex] - 128;

      int r = (yVal + 1.402 * vVal).round().clamp(0, 255);
      int g = (yVal - 0.344136 * uVal - 0.714136 * vVal).round().clamp(0, 255);
      int b = (yVal + 1.772 * uVal).round().clamp(0, 255);

      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return image;
}

// ─────────────────────────────────────────────
// SIGN LANGUAGE SERVICE (SocketIO-based)
// ─────────────────────────────────────────────

class SignLanguageService extends ChangeNotifier {
  // Detection state
  SignDetectionResult? _lastResult;
  final Queue<String> _stabilityBuffer = Queue();
  DateTime _lastAddedTime = DateTime.now();
  final List<String> _detectedWord = [];

  // Frame throttling
  bool _isProcessing = false;
  int _frameCount = 0;
  static const int _frameSkip = 8;

  // Connection state
  bool _backendReachable = false;
  bool _isInitialized = false;

  // SocketIO
  IO.Socket? _socket;

  // Callbacks
  Function(String letter, double confidence)? onLetterDetected;
  Function(String word)? onWordUpdated;

  // Getters
  SignDetectionResult? get lastResult => _lastResult;
  List<String> get detectedWord => List.unmodifiable(_detectedWord);
  String get detectedWordString => _detectedWord.join();
  bool get isInitialized => _isInitialized;
  bool get backendReachable => _backendReachable;

  // Quick phrases for demo
  static const List<String> quickPhrases = [
    'Hello',
    'Thank you',
    'Yes',
    'No',
    'Help',
    'Please',
    'How are you?',
    'Goodbye',
    'I understand',
    'Repeat please',
    'Nice to meet you',
    'My name is...',
  ];

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // INITIALIZATION
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Future<void> init() async {
    _connectSocket();
    _isInitialized = true;
    debugPrint('SignLanguageService initialized. Backend: $_backendReachable');
  }

  void _connectSocket() {
    _socket?.dispose();
    _socket = IO.io(
      AppConfig.aslBackendUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('[ASL] SocketIO connected to ${AppConfig.aslBackendUrl}');
      _backendReachable = true;
      notifyListeners();
    });

    _socket!.onDisconnect((_) {
      debugPrint('[ASL] SocketIO disconnected');
      _backendReachable = false;
      notifyListeners();
    });

    _socket!.onConnectError((err) {
      debugPrint('[ASL] SocketIO connect error: $err');
      _backendReachable = false;
      notifyListeners();
    });

    // Status event (emitted on connect by the server)
    _socket!.on('status', (data) {
      final modelLoaded = data['model_loaded'] ?? false;
      debugPrint('[ASL] Model loaded: $modelLoaded');
    });

    // Detection result from server
    _socket!.on('result', (data) {
      _handleResult(data);
    });

    _socket!.connect();
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // PROCESS CAMERA FRAME (via SocketIO)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Future<void> processFrame(CameraImage image, CameraDescription camera) async {
    _frameCount++;
    if (_frameCount % _frameSkip != 0) return;
    if (_isProcessing || !_isInitialized || !_backendReachable) return;
    if (_socket == null || !_socket!.connected) return;
    _isProcessing = true;

    try {
      final jpegBytes = await _convertCameraImageToJpeg(image);
      if (jpegBytes == null) {
        _isProcessing = false;
        return;
      }

      final b64 = base64Encode(jpegBytes);
      final dataUrl = 'data:image/jpeg;base64,$b64';

      _socket!.emit('frame', {
        'image': dataUrl,
        'mode': 'detect',
      });
    } catch (e) {
      debugPrint('[ASL] Frame processing error: $e');
      _isProcessing = false;
    }
  }

  void _handleResult(dynamic data) {
    _isProcessing = false;
    if (data == null) return;

    if (data['error'] != null) {
      debugPrint('[ASL] Backend error: ${data['error']}');
      return;
    }

    final letter = data['letter'] as String?;
    final confidence = (data['confidence'] as num?)?.toDouble() ?? 0.0;

    if (letter == null || letter.isEmpty) {
      // Hand detected but no prediction (no model or below threshold)
      _lastResult = SignDetectionResult(
        letter: '?',
        confidence: 0,
        isStable: false,
        timestamp: DateTime.now(),
      );
      notifyListeners();
      return;
    }

    final result = SignDetectionResult(
      letter: letter,
      confidence: confidence,
      timestamp: DateTime.now(),
    );

    _updateStabilityBuffer(result);
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // STABILITY BUFFER
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  void _updateStabilityBuffer(SignDetectionResult result) {
    if (result.letter == 'nothing' || result.letter == 'del') {
      _lastResult = SignDetectionResult(
        letter: result.letter,
        confidence: result.confidence,
        isStable: false,
        timestamp: DateTime.now(),
      );
      notifyListeners();
      return;
    }

    _stabilityBuffer.addLast(result.letter);
    if (_stabilityBuffer.length > AppConfig.signStabilityFrames) {
      _stabilityBuffer.removeFirst();
    }

    final counts = <String, int>{};
    for (final l in _stabilityBuffer) {
      counts[l] = (counts[l] ?? 0) + 1;
    }

    final best = counts.entries.reduce(
      (a, b) => a.value > b.value ? a : b,
    );
    final freq = best.value / _stabilityBuffer.length;
    final isStable = freq >= 0.7 &&
        _stabilityBuffer.length >= AppConfig.signStabilityFrames &&
        best.key != '?';

    _lastResult = SignDetectionResult(
      letter: best.key,
      confidence: result.confidence * freq,
      isStable: isStable,
      timestamp: DateTime.now(),
    );

    if (isStable && result.confidence >= AppConfig.signConfidenceThreshold) {
      final now = DateTime.now();
      if (now.difference(_lastAddedTime) >= AppConfig.signCooldown) {
        final letter = best.key;
        if (letter == 'space') {
          if (_detectedWord.isNotEmpty && _detectedWord.last != ' ') {
            _detectedWord.add(' ');
            _lastAddedTime = now;
            onWordUpdated?.call(detectedWordString);
          }
        } else if (_detectedWord.isEmpty || _detectedWord.last != letter) {
          _detectedWord.add(letter);
          _lastAddedTime = now;
          onLetterDetected?.call(letter, result.confidence);
          onWordUpdated?.call(detectedWordString);
        }
        _stabilityBuffer.clear();
      }
    }

    notifyListeners();
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // MANUAL WORD EDITING
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  void addQuickPhrase(String phrase) {
    _detectedWord.addAll(phrase.split(''));
    onLetterDetected?.call(phrase, 1.0);
    onWordUpdated?.call(phrase);
    notifyListeners();
  }

  void addLetter(String letter) {
    _detectedWord.add(letter);
    onWordUpdated?.call(detectedWordString);
    notifyListeners();
  }

  void addSpace() {
    _detectedWord.add(' ');
    onWordUpdated?.call(detectedWordString);
    notifyListeners();
  }

  void deleteLast() {
    if (_detectedWord.isNotEmpty) {
      _detectedWord.removeLast();
      onWordUpdated?.call(detectedWordString);
      notifyListeners();
    }
  }

  void clearWord() {
    _detectedWord.clear();
    _stabilityBuffer.clear();
    _lastResult = null;
    onWordUpdated?.call('');
    notifyListeners();
  }

  String consumeWord() {
    final word = detectedWordString;
    clearWord();
    return word;
  }

  @override
  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    super.dispose();
  }
}

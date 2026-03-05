import 'dart:async';
import 'dart:collection';
import 'dart:ui' show Size;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../config/app_config.dart';

/// 21 hand landmark indices (MediaPipe convention)
class HandLandmark {
  static const int wrist = 0;
  static const int thumbCmc = 1, thumbMcp = 2, thumbIp = 3, thumbTip = 4;
  static const int indexMcp = 5, indexPip = 6, indexDip = 7, indexTip = 8;
  static const int middleMcp = 9,
      middlePip = 10,
      middleDip = 11,
      middleTip = 12;
  static const int ringMcp = 13, ringPip = 14, ringDip = 15, ringTip = 16;
  static const int pinkyMcp = 17, pinkyPip = 18, pinkyDip = 19, pinkyTip = 20;
}

/// A single 3D landmark point
class LandmarkPoint {
  final double x, y, z;
  const LandmarkPoint(this.x, this.y, this.z);

  double distanceTo(LandmarkPoint other) {
    final dx = x - other.x;
    final dy = y - other.y;
    final dz = z - other.z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }
}

/// Result of ASL classification
class SignDetectionResult {
  final String letter;
  final double confidence;
  final bool isStable;
  final DateTime timestamp;

  const SignDetectionResult({
    required this.letter,
    required this.confidence,
    this.isStable = false,
    required this.timestamp,
  });
}

/// Core sign language detection service.
///
/// Uses Google ML Kit's Pose Detection for hand landmark estimation,
/// then applies rule-based geometric analysis to classify ASL letters.
///
/// For hackathon: If ML Kit pose detection doesn't provide hand landmarks
/// directly, we fall back to a simpler approach using the camera feed
/// with predefined gesture buttons + limited ML detection.
class SignLanguageService extends ChangeNotifier {
  // ML Kit
  PoseDetector? _poseDetector;
  bool _isProcessing = false;
  bool _isInitialized = false;

  // Detection state
  SignDetectionResult? _lastResult;
  final Queue<String> _stabilityBuffer = Queue();
  DateTime _lastAddedTime = DateTime.now();
  final List<String> _detectedWord = [];

  // Callbacks
  Function(String letter, double confidence)? onLetterDetected;
  Function(String word)? onWordUpdated;

  // ── Getters ──
  SignDetectionResult? get lastResult => _lastResult;
  List<String> get detectedWord => List.unmodifiable(_detectedWord);
  String get detectedWordString => _detectedWord.join();
  bool get isInitialized => _isInitialized;

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // INITIALIZATION
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Future<void> init() async {
    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.stream,
        model: PoseDetectionModel.accurate,
      ),
    );
    _isInitialized = true;
    debugPrint('Sign language service initialized');
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // PROCESS CAMERA FRAME
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// Process a camera image frame for hand detection.
  ///
  /// This extracts pose landmarks from ML Kit. For hand-specific
  /// landmarks, we use the wrist + arm positions as anchors and
  /// combine with the hand region analysis.
  Future<void> processFrame(CameraImage image, CameraDescription camera) async {
    if (_isProcessing || !_isInitialized) return;
    _isProcessing = true;

    try {
      final inputImage = _convertCameraImage(image, camera);
      if (inputImage == null) return;

      final poses = await _poseDetector?.processImage(inputImage);

      if (poses != null && poses.isNotEmpty) {
        final pose = poses.first;

        // Extract hand-relevant landmarks from pose
        final landmarks = _extractHandLandmarks(pose);

        if (landmarks != null) {
          final result = _classifyASLLetter(landmarks);
          _updateStabilityBuffer(result);
        }
      }
    } catch (e) {
      debugPrint('Frame processing error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// Convert CameraImage to ML Kit InputImage
  InputImage? _convertCameraImage(CameraImage image, CameraDescription camera) {
    try {
      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (format == null) return null;

      final rotation =
          InputImageRotationValue.fromRawValue(camera.sensorOrientation);
      if (rotation == null) return null;

      return InputImage.fromBytes(
        bytes: image.planes.first.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    } catch (e) {
      return null;
    }
  }

  /// Extract hand landmarks from pose detection.
  /// ML Kit Pose gives us wrist, elbow, shoulder — we use these
  /// plus hand region estimation for basic gesture recognition.
  List<LandmarkPoint>? _extractHandLandmarks(Pose pose) {
    // Get right wrist and hand-area landmarks
    final rightWrist = pose.landmarks[PoseLandmarkType.rightWrist];
    final rightElbow = pose.landmarks[PoseLandmarkType.rightElbow];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final rightIndex = pose.landmarks[PoseLandmarkType.rightIndex];
    final rightThumb = pose.landmarks[PoseLandmarkType.rightThumb];
    final rightPinky = pose.landmarks[PoseLandmarkType.rightPinky];

    if (rightWrist == null || rightIndex == null || rightThumb == null) {
      return null;
    }

    // Build a simplified landmark set from available pose data
    // For full 21-point hand landmarks, use MediaPipe Hands native plugin
    return [
      LandmarkPoint(rightWrist.x, rightWrist.y, rightWrist.z),
      LandmarkPoint(rightThumb.x, rightThumb.y, rightThumb.z),
      LandmarkPoint(rightIndex.x, rightIndex.y, rightIndex.z),
      if (rightPinky != null)
        LandmarkPoint(rightPinky.x, rightPinky.y, rightPinky.z),
      if (rightElbow != null)
        LandmarkPoint(rightElbow.x, rightElbow.y, rightElbow.z),
      if (rightShoulder != null)
        LandmarkPoint(rightShoulder.x, rightShoulder.y, rightShoulder.z),
    ];
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // ASL CLASSIFICATION (Rule-Based Geometric)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// Classify ASL letter from simplified landmarks.
  ///
  /// With full 21-point MediaPipe hand landmarks, this uses the
  /// same geometric rules as the Python detector. With pose-only
  /// landmarks (wrist, thumb, index, pinky), we classify a subset.
  SignDetectionResult _classifyASLLetter(List<LandmarkPoint> pts) {
    if (pts.length < 3) {
      return SignDetectionResult(
        letter: '?',
        confidence: 0,
        timestamp: DateTime.now(),
      );
    }

    final wrist = pts[0];
    final thumb = pts[1];
    final index = pts[2];
    final pinky = pts.length > 3 ? pts[3] : null;

    // Distances
    final thumbIndexDist = thumb.distanceTo(index);
    final wristIndexDist = wrist.distanceTo(index);
    final wristThumbDist = wrist.distanceTo(thumb);

    // Direction vectors
    final indexUp = index.y < wrist.y;
    final thumbOut = (thumb.x - wrist.x).abs() > (thumb.y - wrist.y).abs();

    String letter = '?';
    double confidence = 0.0;

    // ── L: Thumb out + Index up (L-shape) ──
    if (indexUp && thumbOut && thumbIndexDist > wristIndexDist * 0.6) {
      letter = 'L';
      confidence = 0.82;
    }
    // ── Y: Thumb out + Pinky out, index down ──
    else if (pinky != null && thumbOut && pinky.y < wrist.y && !indexUp) {
      letter = 'Y';
      confidence = 0.80;
    }
    // ── I: Only pinky up ──
    else if (pinky != null && pinky.y < wrist.y && !indexUp && !thumbOut) {
      letter = 'I';
      confidence = 0.78;
    }
    // ── D / 1: Index up, others down ──
    else if (indexUp && !thumbOut && thumbIndexDist > wristThumbDist * 0.5) {
      letter = 'D';
      confidence = 0.75;
    }
    // ── A: Fist with thumb beside ──
    else if (!indexUp && thumbOut && thumbIndexDist < wristIndexDist * 0.3) {
      letter = 'A';
      confidence = 0.70;
    }
    // ── B: Fingers up, thumb across ──
    else if (indexUp && !thumbOut && pinky != null && pinky.y < wrist.y) {
      letter = 'B';
      confidence = 0.72;
    }
    // ── V: Index and middle spread (approximate) ──
    else if (indexUp && pinky != null && pinky.y > wrist.y) {
      letter = 'V';
      confidence = 0.65;
    }
    // ── S/E: Closed fist variants ──
    else if (!indexUp && !thumbOut) {
      letter = 'S';
      confidence = 0.55;
    }

    return SignDetectionResult(
      letter: letter,
      confidence: confidence,
      timestamp: DateTime.now(),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // STABILITY BUFFER (Smoothing)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  void _updateStabilityBuffer(SignDetectionResult result) {
    _stabilityBuffer.addLast(result.letter);
    if (_stabilityBuffer.length > AppConfig.signStabilityFrames) {
      _stabilityBuffer.removeFirst();
    }

    // Count most frequent letter
    final counts = <String, int>{};
    for (final l in _stabilityBuffer) {
      counts[l] = (counts[l] ?? 0) + 1;
    }

    final best = counts.entries.reduce(
      (a, b) => a.value > b.value ? a : b,
    );

    final freq = best.value / _stabilityBuffer.length;
    final isStable = freq >= 0.6 && best.key != '?';

    _lastResult = SignDetectionResult(
      letter: best.key,
      confidence: result.confidence * freq,
      isStable: isStable,
      timestamp: DateTime.now(),
    );

    // Auto-add to word if stable and cooldown passed
    if (isStable && result.confidence >= AppConfig.signConfidenceThreshold) {
      final now = DateTime.now();
      if (now.difference(_lastAddedTime) >= AppConfig.signCooldown) {
        if (_detectedWord.isEmpty || _detectedWord.last != best.key) {
          _detectedWord.add(best.key);
          _lastAddedTime = now;
          onLetterDetected?.call(best.key, result.confidence);
          onWordUpdated?.call(detectedWordString);
        }
      }
    }

    notifyListeners();
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // MANUAL INPUT (Quick phrases for MVP)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// Quick phrase buttons for reliable communication during demo
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

  void addQuickPhrase(String phrase) {
    // Add as detected text
    for (final char in phrase.split('')) {
      _detectedWord.add(char);
    }
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
    _poseDetector?.close();
    super.dispose();
  }
}

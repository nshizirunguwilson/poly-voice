import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

/// Connects to the backend WebSocket (/captions/:roomName)
/// and surfaces live captions to the UI via ChangeNotifier.
///
/// Replace [CaptionService] in your existing code with this class.
class CaptionWebSocketService extends ChangeNotifier {
  // ── Config ────────────────────────────────────────────────────
  /// Base WebSocket URL of your Railway/Render backend.
  /// Set via --dart-define or your app config.
  static const String _wsBaseUrl =
      String.fromEnvironment('WS_URL', defaultValue: 'wss://your-app.railway.app');

  // ── State ─────────────────────────────────────────────────────
  bool _captionsEnabled = false;
  String _currentCaption = '';
  String _speakerName = '';
  bool _isConnected = false;

  bool get captionsEnabled => _captionsEnabled;
  String get currentCaption => _currentCaption;
  String get speakerName => _speakerName;
  bool get isConnected => _isConnected;

  // ── WebSocket internals ───────────────────────────────────────
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _clearTimer;
  Timer? _reconnectTimer;
  String? _currentRoomName;

  /// Call this when the user joins a call.
  /// [roomName] must match the Twilio room name.
  void joinRoom(String roomName) {
    _currentRoomName = roomName;
    if (_captionsEnabled) {
      _connect(roomName);
    }
  }

  /// Toggle captions on or off.
  void toggleCaptions() {
    _captionsEnabled = !_captionsEnabled;

    if (_captionsEnabled) {
      if (_currentRoomName != null) _connect(_currentRoomName!);
    } else {
      _disconnect();
      _currentCaption = '';
      _speakerName = '';
    }
    notifyListeners();
  }

  // ── WebSocket connection ──────────────────────────────────────

  void _connect(String roomName) {
    _disconnect(); // close any existing connection first

    final uri = Uri.parse('$_wsBaseUrl/captions/${Uri.encodeComponent(roomName)}');
    debugPrint('[CaptionWS] Connecting to $uri');

    try {
      _channel = WebSocketChannel.connect(uri);
      _isConnected = false;

      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );
    } catch (e) {
      debugPrint('[CaptionWS] Connection failed: $e');
      _scheduleReconnect(roomName);
    }
  }

  void _onMessage(dynamic raw) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    switch (msg['type']) {
      case 'connected':
        _isConnected = true;
        debugPrint('[CaptionWS] Connected to room: ${msg['roomName']}');
        notifyListeners();
        break;

      case 'caption':
        _clearTimer?.cancel();
        _speakerName = msg['speaker'] as String? ?? '';
        _currentCaption = msg['text'] as String? ?? '';

        // Clear caption 3 seconds after a final result
        if (msg['isFinal'] == true) {
          _clearTimer = Timer(const Duration(seconds: 3), () {
            _currentCaption = '';
            _speakerName = '';
            notifyListeners();
          });
        }
        notifyListeners();
        break;

      case 'speakingStop':
        _clearTimer?.cancel();
        _clearTimer = Timer(const Duration(seconds: 2), () {
          _currentCaption = '';
          _speakerName = '';
          notifyListeners();
        });
        break;
    }
  }

  void _onError(Object error) {
    debugPrint('[CaptionWS] Error: $error');
    _isConnected = false;
    notifyListeners();
    if (_captionsEnabled && _currentRoomName != null) {
      _scheduleReconnect(_currentRoomName!);
    }
  }

  void _onDone() {
    debugPrint('[CaptionWS] Connection closed');
    _isConnected = false;
    notifyListeners();
    if (_captionsEnabled && _currentRoomName != null) {
      _scheduleReconnect(_currentRoomName!);
    }
  }

  void _scheduleReconnect(String roomName) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      debugPrint('[CaptionWS] Reconnecting...');
      _connect(roomName);
    });
  }

  void _disconnect() {
    _subscription?.cancel();
    _channel?.sink.close(ws_status.normalClosure);
    _channel = null;
    _subscription = null;
    _isConnected = false;
    _reconnectTimer?.cancel();
  }

  /// Call this when the call ends.
  void leaveRoom() {
    _disconnect();
    _currentCaption = '';
    _speakerName = '';
    _currentRoomName = null;
    _captionsEnabled = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _clearTimer?.cancel();
    _disconnect();
    super.dispose();
  }
}

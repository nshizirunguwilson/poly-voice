import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/user_model.dart';

enum CallState { idle, ringing, connecting, connected, ended }

/// Call service with Twilio Video removed (package was sunset Dec 2024).
///
/// Video room connection is stubbed out. The REST API calls for
/// call signaling (initiate, accept, end, poll) still work against
/// the Node.js backend. To restore real WebRTC, integrate
/// `flutter_webrtc` or `livekit_client` and implement _connectToRoom.
class CallService extends ChangeNotifier {
  CallState _state = CallState.idle;
  String? _currentCallId;
  String? _currentRoomName;
  Timer? _pollTimer;
  String? _authToken;

  // Audio / video toggle state (UI only until WebRTC is wired)
  bool _audioEnabled = true;
  bool _videoEnabled = true;

  // ── Getters ──
  CallState get state => _state;
  bool get isConnected => _state == CallState.connected;
  String? get currentCallId => _currentCallId;
  bool get audioEnabled => _audioEnabled;
  bool get videoEnabled => _videoEnabled;

  // ── Auth headers ──
  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_authToken != null) 'Authorization': 'Bearer $_authToken',
      };

  void setAuthToken(String? token) => _authToken = token;

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // INITIATE A CALL
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Future<Map<String, dynamic>> initiateCall(String calleeId) async {
    try {
      _state = CallState.ringing;
      notifyListeners();

      final res = await http.post(
        Uri.parse(AppConfig.callsInitiate),
        headers: _headers,
        body: jsonEncode({'calleeId': calleeId}),
      );

      if (res.statusCode != 200) {
        _state = CallState.idle;
        notifyListeners();
        final data = jsonDecode(res.body);
        return {'success': false, 'error': data['error']};
      }

      final data = jsonDecode(res.body);
      _currentCallId = data['callId'];
      _currentRoomName = data['roomName'];

      // Stub: simulate connection (no real WebRTC)
      _state = CallState.connected;
      notifyListeners();

      return {
        'success': true,
        'callId': _currentCallId,
        'callee': data['callee'],
      };
    } catch (e) {
      _state = CallState.idle;
      notifyListeners();
      return {'success': false, 'error': e.toString()};
    }
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // ACCEPT A CALL
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Future<Map<String, dynamic>> acceptCall(String callId) async {
    try {
      _state = CallState.connecting;
      notifyListeners();

      final res = await http.post(
        Uri.parse(AppConfig.callAccept(callId)),
        headers: _headers,
      );

      if (res.statusCode != 200) {
        _state = CallState.idle;
        notifyListeners();
        return {'success': false, 'error': 'Failed to accept call'};
      }

      final data = jsonDecode(res.body);
      _currentCallId = callId;
      _currentRoomName = data['roomName'];

      // Stub: simulate connection
      _state = CallState.connected;
      notifyListeners();

      return {'success': true};
    } catch (e) {
      _state = CallState.idle;
      notifyListeners();
      return {'success': false, 'error': e.toString()};
    }
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // END CALL
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Future<void> endCall() async {
    try {
      if (_currentCallId != null) {
        await http.post(
          Uri.parse(AppConfig.callEnd(_currentCallId!)),
          headers: _headers,
        );
      }
    } catch (_) {}

    _state = CallState.ended;
    _currentCallId = null;
    _currentRoomName = null;
    notifyListeners();

    // Reset after brief delay
    Future.delayed(const Duration(seconds: 2), () {
      _state = CallState.idle;
      notifyListeners();
    });
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // POLL FOR INCOMING CALLS
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  void startPollingForCalls(Function(CallModel) onIncomingCall) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(AppConfig.callPollInterval, (_) async {
      if (_state != CallState.idle) return;

      try {
        final res = await http.get(
          Uri.parse(AppConfig.callsPending),
          headers: _headers,
        );

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final calls = data['calls'] as List;
          if (calls.isNotEmpty) {
            onIncomingCall(CallModel.fromJson(calls.first));
          }
        }
      } catch (_) {}
    });
  }

  void stopPolling() => _pollTimer?.cancel();

  // ── Toggle Audio/Video (UI state only — no WebRTC) ──
  void toggleAudio(bool enabled) {
    _audioEnabled = enabled;
    notifyListeners();
  }

  void toggleVideo(bool enabled) {
    _videoEnabled = enabled;
    notifyListeners();
  }

  Future<void> switchCamera() async {
    // No-op without WebRTC
    debugPrint('switchCamera: no WebRTC backend connected');
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

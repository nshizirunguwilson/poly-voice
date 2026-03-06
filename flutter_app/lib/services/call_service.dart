import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../config/app_config.dart';
import '../models/user_model.dart';

enum CallState { idle, ringing, connecting, connected, ended }

/// Real-time call service using flutter_webrtc + socket.io.
class CallService extends ChangeNotifier {
  CallState _state = CallState.idle;
  String? _currentCallId;
  String? _currentRoomName;
  Timer? _pollTimer;
  String? _authToken;

  // WebRTC
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  // Socket.IO
  IO.Socket? _socket;
  bool _socketReady = false;

  // Pending join-room data (set before connecting socket)
  Map<String, dynamic>? _pendingJoinData;

  // Audio / video toggle state
  bool _audioEnabled = true;
  bool _videoEnabled = true;

  // ── Getters ──
  CallState get state => _state;
  bool get isConnected => _state == CallState.connected;
  String? get currentCallId => _currentCallId;
  bool get audioEnabled => _audioEnabled;
  bool get videoEnabled => _videoEnabled;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  // ── Text message stream (incoming from remote peer) ──
  final _textMessageController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onRemoteTextMessage =>
      _textMessageController.stream;

  final _partialSpeechController = StreamController<String>.broadcast();
  Stream<String> get onRemotePartialSpeech => _partialSpeechController.stream;

  // ── Auth headers ──
  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_authToken != null) 'Authorization': 'Bearer $_authToken',
      };

  void setAuthToken(String? token) => _authToken = token;

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // SOCKET.IO CONNECTION
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Future<void> _connectAndJoinRoom(Map<String, dynamic> joinData) async {
    _pendingJoinData = joinData;

    if (_socket != null && _socket!.connected) {
      // Already connected — just join
      _socket!.emit('join-room', joinData);
      return;
    }

    // Create fresh socket
    _socket?.dispose();
    _socket = IO.io(
      AppConfig.socketUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );

    // On connect → join the room immediately
    _socket!.onConnect((_) {
      debugPrint('[CallService] Socket.IO connected');
      _socketReady = true;
      if (_pendingJoinData != null) {
        _socket!.emit('join-room', _pendingJoinData!);
        debugPrint(
            '[CallService] Emitted join-room: ${_pendingJoinData!['roomName']}');
      }
    });

    _socket!.onDisconnect((_) {
      debugPrint('[CallService] Socket.IO disconnected');
      _socketReady = false;
    });

    // ── Signaling events ──
    _socket!.on('user-joined', (data) {
      debugPrint('[CallService] Remote user joined: ${data['username']}');
      _createOffer();
    });

    _socket!.on('offer', (data) async {
      debugPrint('[CallService] Received offer');
      await _handleOffer(data);
    });

    _socket!.on('answer', (data) async {
      debugPrint('[CallService] Received answer');
      await _handleAnswer(data);
    });

    _socket!.on('ice-candidate', (data) async {
      await _handleIceCandidate(data);
    });

    _socket!.on('text-message', (data) {
      _textMessageController.add(Map<String, dynamic>.from(data));
    });

    _socket!.on('partial-speech', (data) {
      final text = data['text'] as String? ?? '';
      _partialSpeechController.add(text);
    });

    _socket!.on('user-left', (_) {
      debugPrint('[CallService] Remote user left');
      endCall();
    });

    _socket!.on('call-connected', (_) {
      debugPrint('[CallService] Remote peer confirmed connected');
      if (_state != CallState.connected) {
        _state = CallState.connected;
        notifyListeners();
      }
    });

    _socket!.connect();
  }

  void _disconnectSocket() {
    _socket?.emit('leave-room');
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _socketReady = false;
    _pendingJoinData = null;
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // WEBRTC PEER CONNECTION
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  static const Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection(_iceConfig);

    // Add local tracks — audio only (video handled by camera plugin for deaf users)
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {
        'facingMode': 'user',
        'width': 640,
        'height': 480,
      },
    });

    for (final track in _localStream!.getTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }

    // Handle remote tracks
    _peerConnection!.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        debugPrint('[CallService] Remote stream received');
        notifyListeners();
      }
    };

    // ICE candidates
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (_socket != null && _socketReady) {
        _socket!.emit('ice-candidate', {
          'candidate': {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
          'roomName': _currentRoomName,
        });
      }
    };

    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('[CallService] Connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _state = CallState.connected;
        notifyListeners();
        // Notify remote peer so they can start their timer too
        if (_socket != null && _socketReady) {
          _socket!.emit('call-connected', {'roomName': _currentRoomName});
        }
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        endCall();
      }
    };
  }

  Future<void> _createOffer() async {
    if (_peerConnection == null) await _createPeerConnection();

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    _socket?.emit('offer', {
      'offer': {'sdp': offer.sdp, 'type': offer.type},
      'roomName': _currentRoomName,
    });
    debugPrint('[CallService] Sent offer');
  }

  Future<void> _handleOffer(dynamic data) async {
    if (_peerConnection == null) await _createPeerConnection();

    final offer = data['offer'];
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(offer['sdp'], offer['type']),
    );

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    _socket?.emit('answer', {
      'answer': {'sdp': answer.sdp, 'type': answer.type},
      'roomName': _currentRoomName,
    });
    debugPrint('[CallService] Sent answer');
  }

  Future<void> _handleAnswer(dynamic data) async {
    final answer = data['answer'];
    await _peerConnection?.setRemoteDescription(
      RTCSessionDescription(answer['sdp'], answer['type']),
    );
  }

  Future<void> _handleIceCandidate(dynamic data) async {
    final candidate = data['candidate'];
    if (candidate != null) {
      await _peerConnection?.addCandidate(
        RTCIceCandidate(
          candidate['candidate'],
          candidate['sdpMid'],
          candidate['sdpMLineIndex'],
        ),
      );
    }
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // INITIATE A CALL
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Future<Map<String, dynamic>> initiateCall(String calleeId,
      {String? myUserId, String? myUsername, String? myRole}) async {
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

      _state = CallState.connecting;
      notifyListeners();

      // Create peer connection first, then connect socket and join room
      await _createPeerConnection();
      await _connectAndJoinRoom({
        'roomName': _currentRoomName,
        'userId': myUserId ?? '',
        'username': myUsername ?? '',
        'role': myRole ?? '',
      });

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

  Future<Map<String, dynamic>> acceptCall(String callId,
      {String? myUserId, String? myUsername, String? myRole}) async {
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

      // Create peer connection first, then connect socket and join room
      await _createPeerConnection();
      await _connectAndJoinRoom({
        'roomName': _currentRoomName,
        'userId': myUserId ?? '',
        'username': myUsername ?? '',
        'role': myRole ?? '',
      });

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

    // Clean up WebRTC
    _localStream?.getTracks().forEach((track) => track.stop());
    await _localStream?.dispose();
    _localStream = null;

    _remoteStream?.getTracks().forEach((track) => track.stop());
    await _remoteStream?.dispose();
    _remoteStream = null;

    await _peerConnection?.close();
    _peerConnection = null;

    // Clean up Socket
    _disconnectSocket();

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
  // TEXT MESSAGE (via Socket.IO)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  void sendTextMessage(String text, String type, {String? senderName}) {
    if (_currentRoomName == null || _socket == null || !_socketReady) return;
    _socket!.emit('text-message', {
      'roomName': _currentRoomName,
      'text': text,
      'type': type,
      'senderName': senderName ?? '',
    });
  }

  void sendPartialSpeech(String text) {
    if (_currentRoomName == null || _socket == null || !_socketReady) return;
    _socket!.emit('partial-speech', {
      'roomName': _currentRoomName,
      'text': text,
    });
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // POLL FOR INCOMING CALLS
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  // Track seen call IDs to avoid showing the same incoming call twice
  final Set<String> _seenCallIds = {};

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
            final call = CallModel.fromJson(calls.first);
            // Only show if we haven't already shown this call
            if (!_seenCallIds.contains(call.id)) {
              _seenCallIds.add(call.id);
              onIncomingCall(call);
            }
          }
        }
      } catch (_) {}
    });
  }

  void stopPolling() => _pollTimer?.cancel();

  // ── Toggle Audio/Video ──
  void toggleAudio(bool enabled) {
    _audioEnabled = enabled;
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = enabled;
    });
    notifyListeners();
  }

  void toggleVideo(bool enabled) {
    _videoEnabled = enabled;
    _localStream?.getVideoTracks().forEach((track) {
      track.enabled = enabled;
    });
    notifyListeners();
  }

  Future<void> switchCamera() async {
    final videoTrack = _localStream?.getVideoTracks().firstOrNull;
    if (videoTrack != null) {
      await Helper.switchCamera(videoTrack);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _textMessageController.close();
    _localStream?.dispose();
    _remoteStream?.dispose();
    _peerConnection?.close();
    _disconnectSocket();
    super.dispose();
  }
}

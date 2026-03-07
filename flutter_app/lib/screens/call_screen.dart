import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:camera/camera.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;

import '../config/app_config.dart';
import '../config/theme.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/call_service.dart';
import '../services/speech_service.dart';
import '../services/sign_language_service.dart';

class CallScreen extends StatefulWidget {
  final UserModel remoteUser;
  const CallScreen({super.key, required this.remoteUser});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with TickerProviderStateMixin {
  bool _audioEnabled = true;
  final List<_ChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  late AnimationController _pulseController;

  // Camera (deaf users only)
  CameraController? _cameraController;
  bool _cameraActive = false;

  // Avatar (Three.js WebView)
  WebViewController? _webViewController;
  bool _isWebViewReady = false;

  Timer? _callTimer;
  int _callDuration = 0;

  // We need to keep a renderer alive purely for audio playback of the remote stream,
  // even if it is visually hidden from the UI.
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  StreamSubscription? _textMessageSub;
  StreamSubscription? _partialSpeechSub;
  String _remotePartialSpeech = '';

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _initRenderers();
    _setupTranslationBridge();
    // Timer starts when call connects — see _listenForConnection()
    _listenForConnection();

    _initAvatar();

    // Init camera for deaf users (sign language detection)
    final auth = context.read<AuthService>();
    if (auth.currentUser?.role == AppConfig.roleDeaf) {
      _initCamera();
    }
  }

  Future<void> _initRenderers() async {
    await _remoteRenderer.initialize();
  }

  /// The core translation bridge:
  /// - For speaking users: STT → text → display to deaf user (via socket)
  /// - For deaf users: sign/phrase → text → TTS → voice to hearing user (via socket)
  void _setupTranslationBridge() {
    final auth = context.read<AuthService>();
    final callService = context.read<CallService>();
    final speechService = context.read<SpeechService>();
    final signService = context.read<SignLanguageService>();
    final myRole = auth.currentUser?.role ?? 'normal';

    // ── VOICE PATH (Blind/Normal → Deaf) ──
    // When my speech is recognized, show it locally AND send to remote
    if (myRole != 'deaf') {
      speechService.onFinalResult = (text) {
        _addMessage(text, isMe: true, type: MessageType.speech);
        callService.sendTextMessage(text, 'speech',
            senderName: auth.currentUser?.displayName);
      };
      speechService.onPartialResult = (text) {
        callService.sendPartialSpeech(text);
        setState(() {});
      };
      speechService.startListening(continuous: true);
    }

    // ── SIGN PATH (Deaf → Blind/Normal) ──
    if (myRole == 'deaf') {
      signService.onLetterDetected = (letter, confidence) {
        setState(() {});
      };
      signService.onWordUpdated = (word) {
        setState(() {});
      };
      signService.onSentenceCompleted = (sentence) {
        // Only run if mounted to avoid errors if call ended
        if (mounted) {
          _sendAndSpeakSignWord();
        }
      };
    }

    // ── INCOMING TEXT FROM REMOTE USER (via Socket.IO) ──
    _textMessageSub = callService.onRemoteTextMessage.listen((msg) {
      final text = msg['text'] as String? ?? '';
      final type = msg['type'] as String? ?? 'speech';
      if (text.isEmpty) return;

      MessageType msgType;
      switch (type) {
        case 'sign':
          msgType = MessageType.sign;
          break;
        case 'quickPhrase':
          msgType = MessageType.quickPhrase;
          break;
        default:
          msgType = MessageType.speech;
      }
      _addMessage(text, isMe: false, type: msgType);

      // Trigger Avatar Animation
      if (_isWebViewReady) {
        _webViewController
            ?.runJavaScript("window.AvatarAPI?.playWord('$text');");
      }

      // Clear the partial transcript once the final message arrives
      if (mounted) {
        setState(() => _remotePartialSpeech = '');
      }
    });

    _partialSpeechSub = callService.onRemotePartialSpeech.listen((text) {
      if (mounted) {
        setState(() => _remotePartialSpeech = text);
      }
    });
  }

  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _callDuration++);
    });
  }

  /// Listen for call state to become connected, then start the timer.
  void _listenForConnection() {
    final callService = context.read<CallService>();
    if (callService.state == CallState.connected) {
      _startCallTimer();
      return;
    }
    // Listen for changes
    void listener() {
      if (callService.state == CallState.connected) {
        _startCallTimer();
        callService.removeListener(listener);
      }
    }

    callService.addListener(listener);
  }

  Future<void> _initAvatar() async {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) async {
            try {
              ByteData glbData =
                  await rootBundle.load('assets/avatar/avatar.glb');
              String base64Glb = base64Encode(glbData.buffer.asUint8List());
              await _webViewController?.runJavaScript(
                  "if (window.loadAvatarGLB) window.loadAvatarGLB('data:model/gltf-binary;base64,$base64Glb');");
            } catch (e) {
              debugPrint("Error pushing GLB: $e");
            }
          },
        ),
      )
      ..addJavaScriptChannel(
        'Print',
        onMessageReceived: (JavaScriptMessage message) {
          debugPrint("WebView: ${message.message}");
          if (message.message == 'AvatarReady') {
            if (mounted) {
              setState(() => _isWebViewReady = true);
            }
          }
        },
      )
      ..loadFlutterAsset('assets/avatar/index.html');
  }

  // ── Camera (deaf users only) ──────────────

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      // Prefer front camera for signing
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _cameraActive = true;
      });
      _startSignDetection();
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  void _startSignDetection() {
    final signService = context.read<SignLanguageService>();
    final camera = _cameraController;
    if (camera == null || !camera.value.isInitialized) return;
    camera.startImageStream((image) {
      signService.processFrame(image, camera.description);
    });
  }

  Future<void> _stopCamera() async {
    try {
      await _cameraController?.stopImageStream();
      await _cameraController?.dispose();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _cameraController = null;
        _cameraActive = false;
      });
    }
  }

  /// Send sign word as chat message, speak it, and relay to remote
  void _sendAndSpeakSignWord() {
    final signService = context.read<SignLanguageService>();
    final auth = context.read<AuthService>();
    final callService = context.read<CallService>();
    final word = signService.consumeWord();
    if (word.isEmpty) return;
    _addMessage(word, isMe: true, type: MessageType.sign);
    context.read<SpeechService>().speak(word);
    callService.sendTextMessage(word, 'sign',
        senderName: auth.currentUser?.displayName);
  }

  String get _formattedDuration {
    final m = (_callDuration ~/ 60).toString().padLeft(2, '0');
    final s = (_callDuration % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _addMessage(String text,
      {required bool isMe, required MessageType type}) {
    if (text.isEmpty) return;

    setState(() {
      _messages.add(_ChatMessage(
        text: text,
        isMe: isMe,
        type: type,
        timestamp: DateTime.now(),
      ));
    });

    // Auto-scroll
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    // If I'm NOT deaf and the message is from the remote deaf user, speak it
    final myRole = context.read<AuthService>().currentUser?.role;
    if (!isMe && (myRole == 'blind' || myRole == 'normal')) {
      context.read<SpeechService>().speak(text);
    }
  }

  Future<void> _endCall() async {
    final callService = context.read<CallService>();
    final speechService = context.read<SpeechService>();

    speechService.stopListening();
    await _stopCamera();
    await callService.endCall();

    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _callTimer?.cancel();
    _scrollController.dispose();
    _textMessageSub?.cancel();
    _partialSpeechSub?.cancel();
    _remoteRenderer.dispose();
    context.read<SpeechService>().stopListening();
    _cameraController?.stopImageStream().catchError((_) {});
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    // callService is accessed via context.watch in sub-methods
    // callService is accessed via context.watch in sub-methods
    final callService = context.watch<CallService>();
    final speechService = context.watch<SpeechService>();
    final signService = context.watch<SignLanguageService>();
    final myRole = auth.currentUser?.role ?? 'normal';
    final isDeaf = myRole == 'deaf';

    // Ensure audio works by attaching remote stream
    if (_remoteRenderer.srcObject != callService.remoteStream) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _remoteRenderer.srcObject = callService.remoteStream;
        }
      });
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Call Header ──
            _buildCallHeader(),

            // ── Main Content ──
            Expanded(
              child: Stack(
                children: [
                  // Background gradient
                  Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.topCenter,
                        radius: 1.5,
                        colors: [
                          AppTheme.roleColor(widget.remoteUser.role)
                              .withOpacity(0.08),
                          AppTheme.background,
                        ],
                      ),
                    ),
                  ),

                  // Main content area
                  isDeaf
                      ? _buildDeafLayout(speechService, signService)
                      : _buildHearingLayout(speechService, signService),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // DEAF LAYOUT
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildDeafLayout(
      SpeechService speech, SignLanguageService signService) {
    return Column(
      children: [
        // Top: Large camera preview for signing
        Expanded(
          flex: 3,
          child: Container(
            margin: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppTheme.surfaceLight,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.primary.withOpacity(0.4)),
            ),
            child: _cameraController != null &&
                    _cameraController!.value.isInitialized
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      // Wrap with FittedBox to crop without stretching
                      FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          // swap width & height because portrait cameras are rotated
                          width:
                              _cameraController!.value.previewSize?.height ?? 1,
                          height:
                              _cameraController!.value.previewSize?.width ?? 1,
                          child: CameraPreview(_cameraController!),
                        ),
                      ),
                      // ROI overlay
                      Center(
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: Colors.white.withOpacity(0.6),
                                width: 1.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  )
                : const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: AppTheme.primary),
                        SizedBox(height: 12),
                        Text(
                          'Starting camera...',
                          style:
                              TextStyle(color: AppTheme.textDim, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
          ),
        ),

        // Middle: Large remote avatar (WebView)
        Container(
          width: 180,
          height: 180,
          margin: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.surface,
            border: Border.all(color: AppTheme.border, width: 1),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withOpacity(0.1),
                blurRadius: 20,
                spreadRadius: 2,
              )
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              if (_webViewController != null)
                WebViewWidget(controller: _webViewController!),
              if (!_isWebViewReady)
                const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                ),
            ],
          ),
        ),

        // Bottom: Transcripts / Captions
        Expanded(
          flex: 2,
          child: _buildTranscriptArea(speech, signService, true),
        ),
      ],
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // HEARING / NORMAL LAYOUT
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildHearingLayout(
      SpeechService speech, SignLanguageService signService) {
    return Column(
      children: [
        // Top: Large remote avatar (WebView)
        Container(
          width: 200,
          height: 200,
          margin: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.surface,
            border: Border.all(color: AppTheme.border, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withOpacity(0.15),
                blurRadius: 30,
                spreadRadius: 5,
              )
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              if (_webViewController != null)
                WebViewWidget(controller: _webViewController!),
              if (!_isWebViewReady)
                const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Bottom: Large transcript area (Live captions of what the deaf person signs)
        Expanded(
          child: _buildTranscriptArea(speech, signService, false),
        ),
      ],
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // HEADER
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildCallHeader() {
    final myRole = context.read<AuthService>().currentUser?.role ?? 'normal';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color:
                  AppTheme.roleColor(widget.remoteUser.role).withOpacity(0.12),
            ),
            child: Center(
              child: Text(
                AppTheme.roleEmoji(widget.remoteUser.role),
                style: const TextStyle(fontSize: 22),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.remoteUser.displayName,
                  style: GoogleFonts.syne(
                      fontSize: 17, fontWeight: FontWeight.w700),
                ),
                Row(
                  children: [
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (_, __) => Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.accent.withOpacity(
                            0.5 + 0.5 * _pulseController.value,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Consumer<CallService>(
                      builder: (_, cs, __) {
                        if (cs.state == CallState.connected) {
                          return Text(
                            'Connected • $_formattedDuration',
                            style: const TextStyle(
                                color: AppTheme.accent, fontSize: 12),
                          );
                        }
                        return const Text(
                          'Ringing...',
                          style:
                              TextStyle(color: AppTheme.warning, fontSize: 12),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() => _audioEnabled = !_audioEnabled);
              context.read<CallService>().toggleAudio(_audioEnabled);
              if (_audioEnabled && myRole != 'deaf') {
                context.read<SpeechService>().startListening();
              } else {
                context.read<SpeechService>().stopListening();
              }
            },
            style: IconButton.styleFrom(
              backgroundColor: _audioEnabled
                  ? AppTheme.primary.withOpacity(0.12)
                  : AppTheme.danger.withOpacity(0.12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: Icon(
                _audioEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
                color: _audioEnabled ? AppTheme.primary : AppTheme.danger,
                size: 22),
          ),
          const SizedBox(width: 8),
          // End call button (compact)
          IconButton(
            onPressed: _endCall,
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.danger.withOpacity(0.12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.call_end_rounded,
                color: AppTheme.danger, size: 22),
          ),
        ],
      ),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // TRANSCRIPT / CAPTION AREA
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildTranscriptArea(
    SpeechService speech,
    SignLanguageService sign,
    bool isDeaf,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: AppTheme.border, width: 0.5)),
            ),
            child: Row(
              children: [
                Icon(
                  isDeaf ? Icons.closed_caption : Icons.record_voice_over,
                  size: 18,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  isDeaf ? 'Live Captions' : 'Conversation',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const Spacer(),
                if (speech.isListening)
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.danger,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text('REC',
                          style: TextStyle(
                              color: AppTheme.danger,
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
              ],
            ),
          ),

          // Messages
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isDeaf ? '💬' : '🎙️',
                          style: const TextStyle(fontSize: 32),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isDeaf
                              ? 'Captions will appear here\nwhen the other person speaks'
                              : 'Start speaking...\nYour words will be captioned',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: AppTheme.textDim,
                              fontSize: 13,
                              height: 1.5),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) =>
                        _MessageBubble(message: _messages[i]),
                  ),
          ),

          // Live partial transcript
          if ((!isDeaf && speech.currentTranscript.isNotEmpty) ||
              (isDeaf && _remotePartialSpeech.isNotEmpty))
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.05),
                border: const Border(
                    top: BorderSide(color: AppTheme.border, width: 0.5)),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isDeaf ? _remotePartialSpeech : speech.currentTranscript,
                      style: TextStyle(
                        color: AppTheme.textPrimary.withOpacity(0.6),
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HELPER WIDGETS
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

enum MessageType { speech, sign, quickPhrase }

class _ChatMessage {
  final String text;
  final bool isMe;
  final MessageType type;
  final DateTime timestamp;

  const _ChatMessage({
    required this.text,
    required this.isMe,
    required this.type,
    required this.timestamp,
  });
}

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;

    IconData typeIcon;
    String typeLabel;
    switch (message.type) {
      case MessageType.speech:
        typeIcon = Icons.mic;
        typeLabel = 'Voice';
        break;
      case MessageType.sign:
        typeIcon = Icons.back_hand;
        typeLabel = 'Sign';
        break;
      case MessageType.quickPhrase:
        typeIcon = Icons.chat_bubble;
        typeLabel = 'Quick';
        break;
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
        decoration: BoxDecoration(
          color:
              isMe ? AppTheme.primary.withOpacity(0.15) : AppTheme.surfaceLight,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          border: Border.all(
            color: isMe ? AppTheme.primary.withOpacity(0.2) : AppTheme.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Type indicator
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(typeIcon, size: 12, color: AppTheme.textDim),
                const SizedBox(width: 4),
                Text(
                  typeLabel,
                  style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.textDim,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              message.text,
              style: TextStyle(
                fontSize: isMe ? 15 : 17,
                color: AppTheme.textPrimary,
                fontWeight: isMe ? FontWeight.w400 : FontWeight.w500,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

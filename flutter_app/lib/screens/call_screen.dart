import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
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
  bool _videoEnabled = true;
  bool _showQuickPhrases = false;
  final List<_ChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  late AnimationController _pulseController;

  Timer? _callTimer;
  int _callDuration = 0;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _setupTranslationBridge();
    _startCallTimer();
  }

  /// The core translation bridge:
  /// - For speaking users: STT → text → display to deaf user
  /// - For deaf users: sign/phrase → text → TTS → voice to hearing user
  void _setupTranslationBridge() {
    final auth = context.read<AuthService>();
    final speechService = context.read<SpeechService>();
    final signService = context.read<SignLanguageService>();
    final myRole = auth.currentUser?.role ?? 'normal';

    // ── VOICE PATH (Blind/Normal → Deaf) ──
    // When my speech is recognized, show it as a caption
    if (myRole != 'deaf') {
      speechService.onFinalResult = (text) {
        _addMessage(text, isMe: true, type: MessageType.speech);
      };
      speechService.onPartialResult = (text) {
        // Update live partial transcript
        setState(() {});
      };
      // Start listening automatically
      speechService.startListening(continuous: true);
    }

    // ── SIGN PATH (Deaf → Blind/Normal) ──
    // When sign is detected, convert to text and speak it
    if (myRole == 'deaf') {
      signService.onLetterDetected = (letter, confidence) {
        setState(() {});
      };
      signService.onWordUpdated = (word) {
        setState(() {});
      };
    }
  }

  void _startCallTimer() {
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _callDuration++);
    });
  }

  String get _formattedDuration {
    final m = (_callDuration ~/ 60).toString().padLeft(2, '0');
    final s = (_callDuration % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _addMessage(String text, {required bool isMe, required MessageType type}) {
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

  /// Send the composed sign word as a message
  void _sendSignWord() {
    final signService = context.read<SignLanguageService>();
    final word = signService.consumeWord();
    if (word.isNotEmpty) {
      _addMessage(word, isMe: true, type: MessageType.sign);
      // The other side will receive this via Twilio data track
      // For demo: we also TTS it locally so they can hear
    }
  }

  /// Send a quick phrase
  void _sendQuickPhrase(String phrase) {
    _addMessage(phrase, isMe: true, type: MessageType.quickPhrase);
    setState(() => _showQuickPhrases = false);
  }

  Future<void> _endCall() async {
    final callService = context.read<CallService>();
    final speechService = context.read<SpeechService>();

    speechService.stopListening();
    await callService.endCall();

    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _callTimer?.cancel();
    _scrollController.dispose();
    context.read<SpeechService>().stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final callService = context.watch<CallService>();
    final speechService = context.watch<SpeechService>();
    final signService = context.watch<SignLanguageService>();
    final myRole = auth.currentUser?.role ?? 'normal';
    final isDeaf = myRole == 'deaf';

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
                          AppTheme.roleColor(widget.remoteUser.role).withOpacity(0.08),
                          AppTheme.background,
                        ],
                      ),
                    ),
                  ),

                  // Main content area
                  Column(
                    children: [
                      // ── Remote User Display ──
                      _buildRemoteUserArea(),

                      const SizedBox(height: 8),

                      // ── Live Caption / Transcript Area ──
                      Expanded(
                        child: _buildTranscriptArea(speechService, signService, isDeaf),
                      ),

                      // ── Sign Detection Status (deaf users) ──
                      if (isDeaf) _buildSignStatus(signService),

                      // ── Quick Phrases Panel ──
                      if (_showQuickPhrases && isDeaf) _buildQuickPhrases(),
                    ],
                  ),
                ],
              ),
            ),

            // ── Bottom Controls ──
            _buildControls(isDeaf),
          ],
        ),
      ),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // HEADER
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildCallHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: AppTheme.roleColor(widget.remoteUser.role).withOpacity(0.12),
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
                  style: GoogleFonts.syne(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                Row(
                  children: [
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (_, __) => Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.accent.withOpacity(
                            0.5 + 0.5 * _pulseController.value,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Connected • $_formattedDuration',
                      style: const TextStyle(color: AppTheme.accent, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // End call button (compact)
          IconButton(
            onPressed: _endCall,
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.danger.withOpacity(0.12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.call_end_rounded, color: AppTheme.danger, size: 22),
          ),
        ],
      ),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // REMOTE USER AREA (mini video / avatar)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildRemoteUserArea() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      height: 180,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppTheme.roleColor(widget.remoteUser.role),
                    AppTheme.roleColor(widget.remoteUser.role).withOpacity(0.5),
                  ],
                ),
              ),
              child: Center(
                child: Text(
                  AppTheme.roleEmoji(widget.remoteUser.role),
                  style: const TextStyle(fontSize: 36),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.remoteUser.displayName,
              style: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Text(
              AppTheme.roleLabel(widget.remoteUser.role),
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.roleColor(widget.remoteUser.role),
              ),
            ),
          ],
        ),
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
              border: Border(bottom: BorderSide(color: AppTheme.border, width: 0.5)),
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
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const Spacer(),
                if (speech.isListening)
                  Row(
                    children: [
                      Container(
                        width: 6, height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.danger,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text('REC', style: TextStyle(color: AppTheme.danger, fontSize: 10, fontWeight: FontWeight.w700)),
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
                          style: const TextStyle(color: AppTheme.textDim, fontSize: 13, height: 1.5),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => _MessageBubble(message: _messages[i]),
                  ),
          ),

          // Live partial transcript
          if (speech.currentTranscript.isNotEmpty && !isDeaf)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.05),
                border: const Border(top: BorderSide(color: AppTheme.border, width: 0.5)),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      speech.currentTranscript,
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

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // SIGN DETECTION STATUS BAR
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildSignStatus(SignLanguageService signService) {
    final result = signService.lastResult;
    final word = signService.detectedWordString;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          // Detected letter
          Container(
            width: 50, height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: result != null && result.isStable
                  ? const LinearGradient(colors: [AppTheme.primary, AppTheme.primaryLight])
                  : null,
              color: result == null ? AppTheme.surfaceLight : null,
            ),
            child: Center(
              child: Text(
                result?.letter ?? '?',
                style: GoogleFonts.syne(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Word being built
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Composing:', style: TextStyle(color: AppTheme.textDim, fontSize: 11)),
                const SizedBox(height: 2),
                Text(
                  word.isEmpty ? '...' : word,
                  style: GoogleFonts.syne(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),

          // Send button
          IconButton(
            onPressed: word.isEmpty ? null : _sendSignWord,
            style: IconButton.styleFrom(
              backgroundColor: word.isEmpty
                  ? AppTheme.surfaceLight
                  : AppTheme.accent.withOpacity(0.15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: Icon(
              Icons.send_rounded,
              color: word.isEmpty ? AppTheme.textDim : AppTheme.accent,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // QUICK PHRASES
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildQuickPhrases() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Phrases',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: SignLanguageService.quickPhrases.map((phrase) {
              return GestureDetector(
                onTap: () => _sendQuickPhrase(phrase),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Text(
                    phrase,
                    style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // BOTTOM CONTROLS
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Widget _buildControls(bool isDeaf) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Mic toggle
          _ControlButton(
            icon: _audioEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
            label: 'Mic',
            active: _audioEnabled,
            onTap: () {
              setState(() => _audioEnabled = !_audioEnabled);
              context.read<CallService>().toggleAudio(_audioEnabled);
              if (_audioEnabled && !isDeaf) {
                context.read<SpeechService>().startListening();
              } else {
                context.read<SpeechService>().stopListening();
              }
            },
          ),

          // Video toggle
          _ControlButton(
            icon: _videoEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded,
            label: 'Video',
            active: _videoEnabled,
            onTap: () {
              setState(() => _videoEnabled = !_videoEnabled);
              context.read<CallService>().toggleVideo(_videoEnabled);
            },
          ),

          // Quick phrases (deaf only)
          if (isDeaf)
            _ControlButton(
              icon: Icons.chat_bubble_rounded,
              label: 'Phrases',
              active: _showQuickPhrases,
              color: AppTheme.warning,
              onTap: () => setState(() => _showQuickPhrases = !_showQuickPhrases),
            ),

          // Flip camera
          _ControlButton(
            icon: Icons.flip_camera_ios_rounded,
            label: 'Flip',
            onTap: () => context.read<CallService>().switchCamera(),
          ),

          // End call
          _ControlButton(
            icon: Icons.call_end_rounded,
            label: 'End',
            color: AppTheme.danger,
            active: true,
            onTap: _endCall,
          ),
        ],
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// HELPER WIDGETS
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color? color;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    this.active = false,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? c.withOpacity(0.15) : AppTheme.surfaceLight,
              border: Border.all(
                color: active ? c.withOpacity(0.4) : AppTheme.border,
              ),
            ),
            child: Icon(icon, color: active ? c : AppTheme.textSecondary, size: 24),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: active ? c : AppTheme.textDim,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

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
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
        decoration: BoxDecoration(
          color: isMe ? AppTheme.primary.withOpacity(0.15) : AppTheme.surfaceLight,
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
                  style: const TextStyle(fontSize: 10, color: AppTheme.textDim, fontWeight: FontWeight.w600),
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

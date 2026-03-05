import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:twilio_programmable_video/twilio_programmable_video.dart';
import 'package:polyvoice/services/caption_service.dart';
import 'package:polyvoice/widgets/caption_overlay.dart';

/// Example video call screen demonstrating how to wire up captions
/// with the Twilio Programmable Video SDK.
class CallScreen extends StatefulWidget {
  final String roomName;
  final String twilioToken;
  final String participantName;

  const CallScreen({
    super.key,
    required this.roomName,
    required this.twilioToken,
    required this.participantName,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  Room? _room;
  late CaptionService _captionService;

  // Track widgets for local + remote video
  Widget? _localVideoWidget;
  Widget? _remoteVideoWidget;

  @override
  void initState() {
    super.initState();
    _captionService = CaptionService();
    _initializeCaptionService();
    _connectToRoom();
  }

  /// Initialize Google Speech-to-Text.
  /// Replace the map below with your actual Google service account credentials,
  /// ideally loaded from a secure source (e.g. environment variable or backend).
  Future<void> _initializeCaptionService() async {
    const googleCredentials = <String, dynamic>{
      // "type": "service_account",
      // "project_id": "YOUR_PROJECT_ID",
      // "private_key_id": "...",
      // "private_key": "-----BEGIN RSA PRIVATE KEY-----\n...",
      // "client_email": "...",
      // ... other fields from your service account JSON
    };

    await _captionService.initialize(googleCredentials);
  }

  Future<void> _connectToRoom() async {
    // Configure Twilio connection
    final connectOptions = ConnectOptions(
      widget.twilioToken,
      roomName: widget.roomName,
      audioTracks: [LocalAudioTrack(true, 'mic')],
      videoTracks: [
        LocalVideoTrack(true, CameraCapturer(CameraSource.FRONT_CAMERA))
      ],
    );

    _room = await TwilioProgrammableVideo.connect(connectOptions);

    // ── Local video ──────────────────────────────────────────────
    _room!.localParticipant?.videoTracks.first.localVideoTrack?.widget().then(
      (widget) => setState(() => _localVideoWidget = widget),
    );

    // ── Remote participant events ────────────────────────────────
    _room!.onParticipantConnected.listen((event) {
      _subscribeToRemoteParticipant(event.remoteParticipant);
    });

    // Handle participants already in the room
    for (final participant in _room!.remoteParticipants) {
      _subscribeToRemoteParticipant(participant);
    }
  }

  void _subscribeToRemoteParticipant(RemoteParticipant participant) {
    final displayName = participant.identity ?? 'Remote User';

    // Remote video
    for (final publication in participant.remoteVideoTrackPublications) {
      publication.remoteVideoTrack?.widget().then(
        (w) => setState(() => _remoteVideoWidget = w),
      );
    }

    // ── Audio events → feed into caption service ─────────────────
    participant.onAudioTrackEnabled.listen((_) {
      _captionService.onRemoteParticipantStartedSpeaking(displayName);
    });

    participant.onAudioTrackDisabled.listen((_) {
      _captionService.onRemoteParticipantStoppedSpeaking();
    });

    // If Twilio exposes raw audio bytes, feed them like this:
    // participant.remoteAudioTrackPublications.first
    //     .remoteAudioTrack
    //     .onAudioData  // (hypothetical callback — wrap in your audio sink)
    //     .listen((Uint8List bytes) => _captionService.feedAudioData(bytes));
    //
    // NOTE: twilio_programmable_video does not natively expose raw PCM bytes.
    // For full production use, stream audio to your backend via a WebSocket
    // and return transcription results back to the app. See README comments.
  }

  @override
  void dispose() {
    _room?.disconnect();
    _captionService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _captionService,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              // ── Remote video (full screen) with caption overlay ──
              if (_remoteVideoWidget != null)
                CaptionOverlay(
                  child: SizedBox.expand(child: _remoteVideoWidget!),
                )
              else
                const Center(
                  child: Text(
                    'Waiting for the other person to join...',
                    style: TextStyle(color: Colors.white60),
                  ),
                ),

              // ── Local video (picture-in-picture, bottom-right) ───
              if (_localVideoWidget != null)
                Positioned(
                  bottom: 100,
                  right: 16,
                  width: 100,
                  height: 140,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: _localVideoWidget!,
                  ),
                ),

              // ── End call button ──────────────────────────────────
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: FloatingActionButton(
                    backgroundColor: Colors.red,
                    onPressed: () {
                      _room?.disconnect();
                      Navigator.of(context).pop();
                    },
                    child: const Icon(Icons.call_end, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PRODUCTION NOTE: Raw audio access
//
// The twilio_programmable_video Flutter package does not expose raw PCM audio
// bytes from remote participants directly. For full production transcription:
//
// Option A — Twilio Media Streams (recommended):
//   1. Create a TwiML <Stream> on your Twilio backend to pipe audio to a
//      WebSocket server.
//   2. On your server, forward audio to Google Speech-to-Text streaming API.
//   3. Push transcription results back to the Flutter app via your WebSocket
//      or a Firestore/Supabase realtime channel.
//   4. Call _captionService.updateCaption(text) when results arrive.
//
// Option B — On-device via native plugin:
//   Record the audio output (speaker) using a native Flutter plugin such as
//   `flutter_sound` and pipe PCM chunks to _captionService.feedAudioData().
//
// ─────────────────────────────────────────────────────────────────────────────

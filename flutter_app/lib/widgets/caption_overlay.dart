import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'caption_service.dart';

/// Wraps any video widget and overlays live captions at the bottom.
///
/// Usage:
/// ```dart
/// CaptionOverlay(
///   child: TwilioVideoWidget(...),
/// )
/// ```
class CaptionOverlay extends StatelessWidget {
  final Widget child;

  const CaptionOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Consumer<CaptionService>(
      builder: (context, captionService, _) {
        return Stack(
          children: [
            // The video feed sits underneath
            child,

            // Caption text — only shown when captions are enabled and there's text
            if (captionService.captionsEnabled &&
                captionService.currentCaption.isNotEmpty)
              Positioned(
                bottom: 80, // sits above any control buttons
                left: 16,
                right: 16,
                child: _CaptionBubble(
                  speakerName: captionService.speakerName,
                  caption: captionService.currentCaption,
                ),
              ),

            // Toggle button — always visible in the top-right corner
            Positioned(
              top: 16,
              right: 16,
              child: _CaptionToggleButton(captionService: captionService),
            ),
          ],
        );
      },
    );
  }
}

/// The styled caption bubble shown over the video.
class _CaptionBubble extends StatelessWidget {
  final String speakerName;
  final String caption;

  const _CaptionBubble({required this.speakerName, required this.caption});

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: caption.isNotEmpty ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.75),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Speaker name label
            if (speakerName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  speakerName,
                  style: const TextStyle(
                    color: Color(0xFF4FC3F7), // light blue accent
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            // Caption text
            Text(
              caption,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                height: 1.4,
                shadows: [
                  Shadow(
                    blurRadius: 4,
                    color: Colors.black54,
                    offset: Offset(1, 1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact toggle button to enable/disable captions.
class _CaptionToggleButton extends StatelessWidget {
  final CaptionService captionService;

  const _CaptionToggleButton({required this.captionService});

  @override
  Widget build(BuildContext context) {
    final isEnabled = captionService.captionsEnabled;

    return GestureDetector(
      onTap: captionService.toggleCaptions,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isEnabled
              ? const Color(0xFF4FC3F7).withOpacity(0.9) // active: blue
              : Colors.black.withOpacity(0.55),          // inactive: dark
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isEnabled ? const Color(0xFF4FC3F7) : Colors.white38,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isEnabled ? Icons.closed_caption : Icons.closed_caption_off,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              isEnabled ? 'CC On' : 'CC Off',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

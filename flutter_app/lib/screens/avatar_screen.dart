import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';

class AvatarScreen extends StatefulWidget {
  const AvatarScreen({super.key});

  @override
  State<AvatarScreen> createState() => _AvatarScreenState();
}

class _AvatarScreenState extends State<AvatarScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();

  String _currentWord = '';
  int _currentLetterIndex = 0;
  bool _isPlaying = false;
  double _speed = 1.0;
  Timer? _animationTimer;

  late AnimationController _pulseController;

  final List<String> _recentTranslations = [
    'HELLO',
    'THANK YOU',
    'GOODBYE',
    'PLEASE',
    'YES',
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _animationTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _translateText() {
    final text = _textController.text.trim().toUpperCase();
    if (text.isEmpty) return;

    final cleaned = text.replaceAll(RegExp(r'[^A-Z ]'), '');
    if (cleaned.isEmpty) return;

    setState(() {
      _currentWord = cleaned;
      _currentLetterIndex = 0;
    });

    // Add to recent if not already present
    if (!_recentTranslations.contains(cleaned)) {
      setState(() {
        _recentTranslations.insert(0, cleaned);
        if (_recentTranslations.length > 20) {
          _recentTranslations.removeLast();
        }
      });
    }

    _startAnimation();
    _textController.clear();
  }

  void _showLetter(String letter) {
    _pauseAnimation();
    setState(() {
      _currentWord = letter;
      _currentLetterIndex = 0;
    });
  }

  void _loadWord(String word) {
    _pauseAnimation();
    setState(() {
      _currentWord = word;
      _currentLetterIndex = 0;
    });
    _startAnimation();
  }

  void _startAnimation() {
    if (_currentWord.isEmpty) return;

    _animationTimer?.cancel();
    setState(() => _isPlaying = true);
    _pulseController.repeat(reverse: true);

    _animationTimer = Timer.periodic(
      Duration(milliseconds: (800 / _speed).round()),
      (_) {
        if (_currentLetterIndex < _currentWord.length - 1) {
          setState(() => _currentLetterIndex++);
        } else {
          _pauseAnimation();
        }
      },
    );
  }

  void _pauseAnimation() {
    _animationTimer?.cancel();
    _pulseController.stop();
    setState(() => _isPlaying = false);
  }

  void _togglePlayPause() {
    if (_currentWord.isEmpty) return;
    if (_isPlaying) {
      _pauseAnimation();
    } else {
      if (_currentLetterIndex >= _currentWord.length - 1) {
        setState(() => _currentLetterIndex = 0);
      }
      _startAnimation();
    }
  }

  void _prevLetter() {
    if (_currentWord.isEmpty) return;
    _pauseAnimation();
    setState(() {
      _currentLetterIndex =
          (_currentLetterIndex - 1).clamp(0, _currentWord.length - 1);
    });
  }

  void _nextLetter() {
    if (_currentWord.isEmpty) return;
    _pauseAnimation();
    setState(() {
      _currentLetterIndex =
          (_currentLetterIndex + 1).clamp(0, _currentWord.length - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentLetter = _currentWord.isNotEmpty
        ? _currentWord[_currentLetterIndex]
        : '?';

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Sign Language Avatar',
                    style: GoogleFonts.syne(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Avatar Display ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  children: [
                    // Avatar circle
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (_, child) {
                        final scale = 1.0 + (_pulseController.value * 0.05);
                        return Transform.scale(
                          scale: _isPlaying ? scale : 1.0,
                          child: child,
                        );
                      },
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppTheme.primary, AppTheme.primaryLight],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary.withOpacity(0.3),
                              blurRadius: 40,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            transitionBuilder: (child, animation) =>
                                ScaleTransition(scale: animation, child: child),
                            child: Text(
                              currentLetter,
                              key: ValueKey(currentLetter + _currentLetterIndex.toString()),
                              style: GoogleFonts.syne(
                                fontSize: 72,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Word progress
                    if (_currentWord.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            children: _currentWord
                                .split('')
                                .asMap()
                                .entries
                                .map((entry) {
                              final isActive =
                                  entry.key == _currentLetterIndex;
                              final isPast = entry.key < _currentLetterIndex;
                              return TextSpan(
                                text: entry.value == ' '
                                    ? '  '
                                    : entry.value,
                                style: GoogleFonts.syne(
                                  fontSize: 22,
                                  fontWeight: isActive
                                      ? FontWeight.w800
                                      : FontWeight.w400,
                                  color: isActive
                                      ? AppTheme.primary
                                      : isPast
                                          ? AppTheme.textPrimary
                                          : AppTheme.textDim,
                                  letterSpacing: 3,
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      )
                    else
                      Text(
                        'Type a word to see it signed',
                        style: TextStyle(
                          color: AppTheme.textDim,
                          fontSize: 14,
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // ── Controls ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ControlButton(
                    icon: Icons.skip_previous_rounded,
                    onTap: _prevLetter,
                  ),
                  const SizedBox(width: 16),
                  _ControlButton(
                    icon: _isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    onTap: _togglePlayPause,
                    isPrimary: true,
                  ),
                  const SizedBox(width: 16),
                  _ControlButton(
                    icon: Icons.skip_next_rounded,
                    onTap: _nextLetter,
                  ),
                  const SizedBox(width: 24),

                  // Speed selector
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<double>(
                        value: _speed,
                        isDense: true,
                        dropdownColor: AppTheme.surface,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 0.5, child: Text('0.5x')),
                          DropdownMenuItem(
                              value: 1.0, child: Text('1x')),
                          DropdownMenuItem(
                              value: 1.5, child: Text('1.5x')),
                          DropdownMenuItem(
                              value: 2.0, child: Text('2x')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _speed = v);
                          if (_isPlaying) {
                            _pauseAnimation();
                            _startAnimation();
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── Text Input ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: const InputDecoration(
                        hintText: 'Type text to translate...',
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _translateText(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: IconButton(
                      onPressed: _translateText,
                      style: IconButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.send_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── Tabs: Recent & Alphabet ──
            Expanded(
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: TabBar(
                          indicator: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          indicatorSize: TabBarIndicatorSize.tab,
                          labelColor: Colors.white,
                          unselectedLabelColor: AppTheme.textSecondary,
                          labelStyle: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          dividerColor: Colors.transparent,
                          tabs: const [
                            Tab(text: 'Recent'),
                            Tab(text: 'Alphabet'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: TabBarView(
                        children: [
                          // Recent tab
                          _recentTranslations.isEmpty
                              ? Center(
                                  child: Text(
                                    'No recent translations',
                                    style: TextStyle(
                                        color: AppTheme.textDim,
                                        fontSize: 14),
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20),
                                  itemCount: _recentTranslations.length,
                                  itemBuilder: (_, i) {
                                    final word = _recentTranslations[i];
                                    return GestureDetector(
                                      onTap: () => _loadWord(word),
                                      child: Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 14),
                                        decoration: BoxDecoration(
                                          color: AppTheme.surface,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color: AppTheme.border),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.sign_language_rounded,
                                              color: AppTheme.primary
                                                  .withOpacity(0.6),
                                              size: 20,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                word,
                                                style: GoogleFonts.syne(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                  letterSpacing: 1,
                                                ),
                                              ),
                                            ),
                                            const Icon(
                                              Icons.play_circle_outline_rounded,
                                              color: AppTheme.textDim,
                                              size: 20,
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),

                          // Alphabet tab
                          GridView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 5,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                            ),
                            itemCount: 26,
                            itemBuilder: (_, i) {
                              final letter =
                                  String.fromCharCode(65 + i);
                              final isActive =
                                  _currentWord.isNotEmpty &&
                                      _currentWord[_currentLetterIndex] ==
                                          letter;
                              return GestureDetector(
                                onTap: () => _showLetter(letter),
                                child: AnimatedContainer(
                                  duration:
                                      const Duration(milliseconds: 200),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? AppTheme.primary
                                            .withOpacity(0.2)
                                        : AppTheme.surfaceLight,
                                    borderRadius:
                                        BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isActive
                                          ? AppTheme.primary
                                          : AppTheme.border,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      letter,
                                      style: GoogleFonts.syne(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        color: isActive
                                            ? AppTheme.primary
                                            : AppTheme.textPrimary,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SUB-WIDGETS
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isPrimary;

  const _ControlButton({
    required this.icon,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: isPrimary ? 52 : 44,
        height: isPrimary ? 52 : 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isPrimary ? AppTheme.primary : AppTheme.surfaceLight,
          border: isPrimary
              ? null
              : Border.all(color: AppTheme.border),
          boxShadow: isPrimary
              ? [
                  BoxShadow(
                    color: AppTheme.primary.withOpacity(0.3),
                    blurRadius: 12,
                  ),
                ]
              : null,
        ),
        child: Icon(
          icon,
          color: isPrimary ? Colors.white : AppTheme.textSecondary,
          size: isPrimary ? 28 : 22,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/app_config.dart';
import '../config/theme.dart';
import '../services/auth_service.dart';
import 'auth_screen.dart';
import 'subscription_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // ── Accessibility ──
  double _textScaleFactor = 1.0;
  bool _highContrast = false;

  // ── Communication ──
  double _ttsSpeed = 0.5;
  bool _autoListen = true;

  // ── Sign Language ──
  double _signConfidence = 0.70;
  double _stabilityFrames = 8;

  // ── Notifications ──
  bool _callNotifications = true;
  bool _vibration = true;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;

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
                    'Settings',
                    style: GoogleFonts.syne(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),

            // ── Content ──
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  // ── Profile Section ──
                  _SettingsSection(
                    title: 'Profile',
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: LinearGradient(
                                  colors: [
                                    AppTheme.roleColor(
                                        user?.role ?? 'normal'),
                                    AppTheme.roleColor(
                                            user?.role ?? 'normal')
                                        .withOpacity(0.6),
                                  ],
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  AppTheme.roleEmoji(
                                      user?.role ?? 'normal'),
                                  style: const TextStyle(fontSize: 28),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    user?.displayName ?? 'User',
                                    style: GoogleFonts.syne(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    user?.email ?? '',
                                    style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppTheme.roleColor(
                                              user?.role ?? 'normal')
                                          .withOpacity(0.15),
                                      borderRadius:
                                          BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      AppTheme.roleLabel(
                                          user?.role ?? 'normal'),
                                      style: TextStyle(
                                        color: AppTheme.roleColor(
                                            user?.role ?? 'normal'),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // ── Accessibility Section ──
                  _SettingsSection(
                    title: 'Accessibility',
                    children: [
                      _SliderTile(
                        icon: Icons.format_size_rounded,
                        label: 'Text Size',
                        value: _textScaleFactor,
                        min: 0.8,
                        max: 1.5,
                        divisions: 7,
                        valueLabel:
                            '${(_textScaleFactor * 100).round()}%',
                        onChanged: (v) =>
                            setState(() => _textScaleFactor = v),
                      ),
                      const _Divider(),
                      _SwitchTile(
                        icon: Icons.contrast_rounded,
                        label: 'High Contrast',
                        subtitle: 'Increase text and UI contrast',
                        value: _highContrast,
                        onChanged: (v) =>
                            setState(() => _highContrast = v),
                      ),
                    ],
                  ),

                  // ── Communication Section ──
                  _SettingsSection(
                    title: 'Communication',
                    children: [
                      _SliderTile(
                        icon: Icons.speed_rounded,
                        label: 'TTS Voice Speed',
                        value: _ttsSpeed,
                        min: 0.25,
                        max: 1.0,
                        divisions: 3,
                        valueLabel: _ttsSpeedLabel(_ttsSpeed),
                        onChanged: (v) =>
                            setState(() => _ttsSpeed = v),
                      ),
                      const _Divider(),
                      _SwitchTile(
                        icon: Icons.mic_rounded,
                        label: 'Auto-listen on Call',
                        subtitle:
                            'Start speech recognition when call connects',
                        value: _autoListen,
                        onChanged: (v) =>
                            setState(() => _autoListen = v),
                      ),
                    ],
                  ),

                  // ── Sign Language Section ──
                  _SettingsSection(
                    title: 'Sign Language',
                    children: [
                      _SliderTile(
                        icon: Icons.tune_rounded,
                        label: 'Detection Sensitivity',
                        value: _signConfidence,
                        min: 0.5,
                        max: 0.95,
                        divisions: 9,
                        valueLabel:
                            '${(_signConfidence * 100).round()}%',
                        onChanged: (v) =>
                            setState(() => _signConfidence = v),
                      ),
                      const _Divider(),
                      _SliderTile(
                        icon: Icons.filter_frames_rounded,
                        label: 'Stability Frames',
                        value: _stabilityFrames,
                        min: 3,
                        max: 15,
                        divisions: 12,
                        valueLabel: '${_stabilityFrames.round()}',
                        onChanged: (v) =>
                            setState(() => _stabilityFrames = v),
                      ),
                    ],
                  ),

                  // ── Notifications Section ──
                  _SettingsSection(
                    title: 'Notifications',
                    children: [
                      _SwitchTile(
                        icon: Icons.notifications_rounded,
                        label: 'Call Notifications',
                        subtitle: 'Get notified of incoming calls',
                        value: _callNotifications,
                        onChanged: (v) =>
                            setState(() => _callNotifications = v),
                      ),
                      const _Divider(),
                      _SwitchTile(
                        icon: Icons.vibration_rounded,
                        label: 'Vibration',
                        subtitle: 'Vibrate on incoming calls',
                        value: _vibration,
                        onChanged: (v) =>
                            setState(() => _vibration = v),
                      ),
                    ],
                  ),

                  // ── About Section ──
                  _SettingsSection(
                    title: 'About',
                    children: [
                      _InfoTile(
                        icon: Icons.info_outline_rounded,
                        label: 'App Version',
                        value: AppConfig.appVersion,
                      ),
                      const _Divider(),
                      _InfoTile(
                        icon: Icons.cloud_outlined,
                        label: 'Backend',
                        value: AppConfig.baseUrl,
                      ),
                      const _Divider(),
                      _TapTile(
                        icon: Icons.workspace_premium_rounded,
                        label: 'Current Plan',
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Free',
                            style: TextStyle(
                              color: AppTheme.accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    const SubscriptionScreen()),
                          );
                        },
                      ),
                    ],
                  ),

                  // ── Sign Out ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _handleSignOut(auth),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.danger,
                          side: BorderSide(
                              color: AppTheme.danger.withOpacity(0.4)),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('Sign Out'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _ttsSpeedLabel(double v) {
    if (v <= 0.25) return 'Slow';
    if (v <= 0.5) return 'Normal';
    if (v <= 0.75) return 'Fast';
    return 'Very Fast';
  }

  Future<void> _handleSignOut(AuthService auth) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Sign Out',
          style: GoogleFonts.syne(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Are you sure you want to sign out?',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await auth.logout();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AuthScreen()),
          (route) => false,
        );
      }
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SUB-WIDGETS
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.syne(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: AppTheme.border,
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.textSecondary, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: AppTheme.textDim,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppTheme.primary,
          ),
        ],
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  const _SliderTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.valueLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.textSecondary, size: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  valueLabel,
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AppTheme.primary,
              inactiveTrackColor: AppTheme.surfaceLight,
              thumbColor: AppTheme.primary,
              overlayColor: AppTheme.primary.withOpacity(0.12),
              trackHeight: 4,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.textSecondary, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _TapTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;
  final VoidCallback onTap;

  const _TapTile({
    required this.icon,
    required this.label,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.textSecondary, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (trailing != null) ...[
              trailing!,
              const SizedBox(width: 8),
            ],
            const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.textDim,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

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
import 'avatar_screen.dart';
import 'call_screen.dart';
import 'settings_screen.dart';
import 'subscription_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<UserModel> _users = [];
  bool _loadingUsers = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initServices();
    _loadUsers();

    // Refresh users every 10 seconds
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _loadUsers(),
    );
  }

  Future<void> _initServices() async {
    final auth = context.read<AuthService>();
    final callService = context.read<CallService>();
    final speechService = context.read<SpeechService>();
    final signService = context.read<SignLanguageService>();

    callService.setAuthToken(auth.token);

    // Init speech & sign services
    await speechService.init();
    await signService.init();

    // Start polling for incoming calls
    callService.startPollingForCalls(_handleIncomingCall);
  }

  Future<void> _loadUsers() async {
    final auth = context.read<AuthService>();
    final users = await auth.fetchUsers();
    if (mounted) {
      setState(() {
        _users = users;
        _loadingUsers = false;
      });
    }
  }

  void _handleIncomingCall(CallModel call) {
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _IncomingCallSheet(
        call: call,
        onAccept: () async {
          Navigator.pop(ctx);
          final callService = context.read<CallService>();
          final result = await callService.acceptCall(call.id);
          if (result['success'] == true && mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CallScreen(
                  remoteUser: UserModel(
                    id: call.callerId,
                    username: call.callerUsername,
                    displayName: call.callerName,
                    role: call.callerRole,
                  ),
                ),
              ),
            );
          }
        },
        onReject: () {
          Navigator.pop(ctx);
        },
      ),
    );
  }

  Future<void> _callUser(UserModel user) async {
    final callService = context.read<CallService>();
    final result = await callService.initiateCall(user.id);

    if (result['success'] == true && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CallScreen(remoteUser: user),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['error'] ?? 'Failed to start call'),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    context.read<CallService>().stopPolling();
    super.dispose();
  }

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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  // Profile avatar
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.roleColor(user?.role ?? 'normal'),
                          AppTheme.roleColor(user?.role ?? 'normal').withOpacity(0.6),
                        ],
                      ),
                    ),
                    child: Center(
                      child: Text(
                        AppTheme.roleEmoji(user?.role ?? 'normal'),
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName ?? 'User',
                          style: GoogleFonts.syne(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          AppTheme.roleLabel(user?.role ?? 'normal'),
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.roleColor(user?.role ?? 'normal'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_rounded, color: AppTheme.textSecondary),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SettingsScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Role Info Card ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _RoleInfoCard(role: user?.role ?? 'normal'),
            ),

            const SizedBox(height: 16),

            // ── Action Tiles ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: _ActionTile(
                      icon: Icons.sign_language_rounded,
                      label: 'Avatar',
                      color: AppTheme.primary,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AvatarScreen()),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionTile(
                      icon: Icons.workspace_premium_rounded,
                      label: 'Plans',
                      color: AppTheme.warning,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionTile(
                      icon: Icons.settings_rounded,
                      label: 'Settings',
                      color: AppTheme.textSecondary,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SettingsScreen()),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Contacts Header ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    'Contacts',
                    style: GoogleFonts.syne(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_users.length}',
                      style: const TextStyle(color: AppTheme.primary, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary, size: 22),
                    onPressed: _loadUsers,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── User List ──
            Expanded(
              child: _loadingUsers
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : _users.isEmpty
                      ? _emptyState()
                      : RefreshIndicator(
                          onRefresh: _loadUsers,
                          color: AppTheme.primary,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: _users.length,
                            itemBuilder: (_, i) => _UserCard(
                              user: _users[i],
                              onCall: () => _callUser(_users[i]),
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🫥', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          const Text('No contacts yet', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            'Register more users to start calling',
            style: TextStyle(color: AppTheme.textDim, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SUB-WIDGETS
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _RoleInfoCard extends StatelessWidget {
  final String role;
  const _RoleInfoCard({required this.role});

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.roleColor(role);
    String title, subtitle;

    switch (role) {
      case 'deaf':
        title = 'You will see live captions';
        subtitle = 'Use camera for sign language or quick phrases to respond. Your signs will be converted to voice for the other person.';
        break;
      case 'blind':
        title = 'You will hear voice output';
        subtitle = 'Speak normally — your voice converts to text for Deaf users. Their sign responses will be read aloud to you.';
        break;
      default:
        title = 'Full accessibility bridge';
        subtitle = 'Speak normally. Deaf users will see your words as text and can respond with signs converted to voice.';
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: Text(AppTheme.roleEmoji(role), style: const TextStyle(fontSize: 22))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final UserModel user;
  final VoidCallback onCall;
  const _UserCard({required this.user, required this.onCall});

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.roleColor(user.role);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 50, height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: color.withOpacity(0.12),
          ),
          child: Center(
            child: Text(AppTheme.roleEmoji(user.role), style: const TextStyle(fontSize: 24)),
          ),
        ),
        title: Text(
          user.displayName,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        subtitle: Row(
          children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: user.isOnline ? AppTheme.accent : AppTheme.textDim,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${AppTheme.roleLabel(user.role)} • ${user.isOnline ? "Online" : "Offline"}',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ],
        ),
        trailing: SizedBox(
          width: 48, height: 48,
          child: IconButton(
            onPressed: onCall,
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.accent.withOpacity(0.12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.call_rounded, color: AppTheme.accent, size: 22),
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IncomingCallSheet extends StatelessWidget {
  final CallModel call;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _IncomingCallSheet({
    required this.call,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.primaryLight]),
            ),
            child: Center(
              child: Text(AppTheme.roleEmoji(call.callerRole), style: const TextStyle(fontSize: 40)),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Incoming Call',
            style: GoogleFonts.syne(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            call.callerName,
            style: const TextStyle(fontSize: 18, color: AppTheme.textSecondary),
          ),
          Text(
            AppTheme.roleLabel(call.callerRole),
            style: TextStyle(fontSize: 13, color: AppTheme.roleColor(call.callerRole)),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Reject
              GestureDetector(
                onTap: onReject,
                child: Container(
                  width: 70, height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.danger.withOpacity(0.15),
                    border: Border.all(color: AppTheme.danger.withOpacity(0.4)),
                  ),
                  child: const Icon(Icons.call_end_rounded, color: AppTheme.danger, size: 32),
                ),
              ),
              // Accept
              GestureDetector(
                onTap: onAccept,
                child: Container(
                  width: 70, height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.accent.withOpacity(0.15),
                    border: Border.all(color: AppTheme.accent.withOpacity(0.4)),
                  ),
                  child: const Icon(Icons.call_rounded, color: AppTheme.accent, size: 32),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// PolyVoice App Configuration
///
/// Change [baseUrl] to your deployed backend URL.
/// For local dev with Android emulator, use 10.0.2.2.
/// For physical device, use your machine's local IP.
class AppConfig {
  static const String appName = 'PolyVoice';
  static const String appVersion = '1.0.0';

  // ── Backend URL ──
  // Android emulator → 10.0.2.2
  // iOS simulator   → localhost
  // Physical device  → your local IP (e.g., 192.168.1.x)
  static const String baseUrl = 'http://172.17.10.254:3000';
  static const String socketUrl = 'http://172.17.10.254:3000';

  // ── API Endpoints ──
  static const String apiBase = '$baseUrl/api';
  static const String authRegister = '$apiBase/auth/register';
  static const String authLogin = '$apiBase/auth/login';
  static const String authMe = '$apiBase/auth/me';
  static const String usersList = '$apiBase/users';
  static const String usersStatus = '$apiBase/users/status';
  static const String twilioToken = '$apiBase/twilio/token';
  static const String callsInitiate = '$apiBase/calls/initiate';
  static const String callsPending = '$apiBase/calls/pending';

  static String callAccept(String id) => '$apiBase/calls/$id/accept';
  static String callEnd(String id) => '$apiBase/calls/$id/end';

  // ── Call Polling Interval ──
  static const Duration callPollInterval = Duration(seconds: 3);

  // ── ASL Python Backend ──
  // iOS simulator   → localhost
  // Android emulator → 10.0.2.2
  // Physical device  → your local IP (e.g., 192.168.1.x)
  static const String aslBackendUrl = 'http://172.17.10.254:8000';

  // ── ASL Detection ──
  static const double signConfidenceThreshold = 0.70;
  static const int signStabilityFrames = 8;
  static const Duration signCooldown = Duration(milliseconds: 1200);

  // ── Deepgram API Key ──
  static const String deepgramApiKey =
      'ae84d96beeb1763742ae7ce2e29637fc2b711a37';

  // ── User Roles ──
  static const String roleDeaf = 'deaf';
  static const String roleBlind = 'blind';
  static const String roleNormal = 'normal';
}

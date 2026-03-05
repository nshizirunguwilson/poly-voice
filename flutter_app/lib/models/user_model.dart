class UserModel {
  final String id;
  final String username;
  final String email;
  final String role; // 'deaf', 'blind', 'normal'
  final String displayName;
  final bool isOnline;

  const UserModel({
    required this.id,
    required this.username,
    this.email = '',
    required this.role,
    required this.displayName,
    this.isOnline = false,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? 'normal',
      displayName: json['display_name'] ?? json['displayName'] ?? '',
      isOnline: json['is_online'] == 1 || json['is_online'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'email': email,
        'role': role,
        'displayName': displayName,
        'is_online': isOnline,
      };

  bool get isDeaf => role == 'deaf';
  bool get isBlind => role == 'blind';
  bool get isNormal => role == 'normal';
}

class CallModel {
  final String id;
  final String roomName;
  final String callerId;
  final String callerUsername;
  final String callerName;
  final String callerRole;
  final String status;

  const CallModel({
    required this.id,
    required this.roomName,
    required this.callerId,
    required this.callerUsername,
    required this.callerName,
    required this.callerRole,
    this.status = 'pending',
  });

  factory CallModel.fromJson(Map<String, dynamic> json) {
    return CallModel(
      id: json['id'] ?? '',
      roomName: json['room_name'] ?? json['roomName'] ?? '',
      callerId: json['caller_id'] ?? json['callerId'] ?? '',
      callerUsername: json['caller_username'] ?? json['callerUsername'] ?? '',
      callerName: json['caller_name'] ?? json['callerName'] ?? '',
      callerRole: json['caller_role'] ?? json['callerRole'] ?? '',
      status: json['status'] ?? 'pending',
    );
  }
}

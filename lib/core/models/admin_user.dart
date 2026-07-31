class AdminUser {
  const AdminUser({
    required this.id,
    required this.nickname,
    this.email = '',
    this.isAdmin = false,
    this.isMe = false,
    this.accountStatus = 'active',
    this.createdAt = '',
  });

  final String id;
  final String nickname;
  final String email;
  final bool isAdmin;
  final bool isMe;
  final String accountStatus;
  final String createdAt;

  bool get isSuspended => accountStatus == 'suspended';

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    return AdminUser(
      id: json['id'].toString(),
      nickname: json['nickname']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      isAdmin: json['isAdmin'] == true || json['isAdmin'] == 1,
      isMe: json['isMe'] == true || json['isMe'] == 1,
      accountStatus: json['accountStatus']?.toString() ?? 'active',
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }
}

class AdminUser {
  const AdminUser({
    required this.id,
    required this.nickname,
    this.email = '',
    this.isAdmin = false,
    this.createdAt = '',
  });

  final String id;
  final String nickname;
  final String email;
  final bool isAdmin;
  final String createdAt;

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    return AdminUser(
      id: json['id'].toString(),
      nickname: json['nickname']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      isAdmin: json['isAdmin'] == true || json['isAdmin'] == 1,
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }
}

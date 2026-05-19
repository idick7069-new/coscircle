class CircleGroup {
  const CircleGroup({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.inviteUrl,
    required this.memberCount,
    required this.isOwner,
  });

  final String id;
  final String name;
  final String inviteCode;
  final String inviteUrl;
  final int memberCount;
  final bool isOwner;

  factory CircleGroup.fromJson(Map<String, dynamic> json) {
    return CircleGroup(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      inviteCode: json['inviteCode']?.toString() ?? '',
      inviteUrl: json['inviteUrl']?.toString() ?? '',
      memberCount: _asInt(json['memberCount']),
      isOwner: json['isOwner'] == true || json['isOwner'] == 1,
    );
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  return int.parse(value.toString());
}

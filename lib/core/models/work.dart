class WorkTag {
  const WorkTag({required this.id, required this.name});

  final String id;
  final String name;

  factory WorkTag.fromJson(Map<String, dynamic> json) {
    return WorkTag(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WorkTag && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

enum PartnerWorkScope { mine, all }

typedef PartnerWorkQuery = ({PartnerWorkScope scope, String q});

class PartnerWork {
  const PartnerWork({
    required this.id,
    required this.name,
    required this.partnerCount,
    required this.isMine,
  });

  final String id;
  final String name;
  final int partnerCount;
  final bool isMine;

  factory PartnerWork.fromJson(Map<String, dynamic> json) => PartnerWork(
    id: json['id'].toString(),
    name: json['name'] as String,
    partnerCount: (json['partnerCount'] as num).toInt(),
    isMine: json['isMine'] == true,
  );
}

class PartnerWorkPage {
  const PartnerWorkPage({required this.items, this.nextOffset});

  final List<PartnerWork> items;
  final int? nextOffset;

  factory PartnerWorkPage.fromJson(Map<String, dynamic> json) =>
      PartnerWorkPage(
        items: (json['items'] as List<dynamic>)
            .map((item) => PartnerWork.fromJson(item as Map<String, dynamic>))
            .toList(),
        nextOffset: json['hasMore'] == true
            ? (json['nextOffset'] as num?)?.toInt()
            : null,
      );
}

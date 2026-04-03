import 'dart:convert';

class DietGoal {
  const DietGoal({
    required this.mission,
    required this.aiBrief,
    required this.updatedAt,
  });

  final String mission;
  final String aiBrief;
  final DateTime updatedAt;

  bool get isEmpty => mission.trim().isEmpty;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'mission': mission,
      'aiBrief': aiBrief,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory DietGoal.fromMap(Map<String, dynamic> map) {
    return DietGoal(
      mission: map['mission'] as String? ?? '',
      aiBrief: map['aiBrief'] as String? ?? '',
      updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  factory DietGoal.fromRaw(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return DietGoal.fromMap(decoded);
  }

  String encode() => jsonEncode(toMap());
}

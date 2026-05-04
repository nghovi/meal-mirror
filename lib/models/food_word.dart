import 'dart:convert';

class FoodWord {
  const FoodWord({
    required this.id,
    required this.term,
    required this.category,
    required this.definition,
    required this.examples,
    this.pronunciation,
    this.pronunciationAudioUrl,
    required this.imageHint,
    required this.sourceImagePath,
    required this.sourceSummary,
    required this.createdAt,
    this.sourceMealId,
  });

  final String id;
  final String term;
  final String category;
  final String definition;
  final List<String> examples;
  final String? pronunciation;
  final String? pronunciationAudioUrl;
  final String imageHint;
  final String sourceImagePath;
  final String sourceSummary;
  final DateTime createdAt;
  final String? sourceMealId;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'term': term,
      'category': category,
      'definition': definition,
      'examples': examples,
      'pronunciation': pronunciation,
      'pronunciationAudioUrl': pronunciationAudioUrl,
      'imageHint': imageHint,
      'sourceImagePath': sourceImagePath,
      'sourceSummary': sourceSummary,
      'createdAt': createdAt.toIso8601String(),
      'sourceMealId': sourceMealId,
    };
  }

  factory FoodWord.fromMap(Map<String, dynamic> map) {
    return FoodWord(
      id: map['id'] as String,
      term: map['term'] as String? ?? '',
      category: map['category'] as String? ?? 'Food',
      definition: map['definition'] as String? ?? map['note'] as String? ?? '',
      examples:
          List<String>.from(map['examples'] as List<dynamic>? ?? const []),
      pronunciation: map['pronunciation'] as String?,
      pronunciationAudioUrl: map['pronunciationAudioUrl'] as String?,
      imageHint: map['imageHint'] as String? ?? '',
      sourceImagePath: map['sourceImagePath'] as String? ?? '',
      sourceSummary: map['sourceSummary'] as String? ?? '',
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      sourceMealId: map['sourceMealId'] as String?,
    );
  }

  static String encodeList(List<FoodWord> words) {
    return jsonEncode(words.map((word) => word.toMap()).toList());
  }

  static List<FoodWord> decodeList(String raw) {
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => FoodWord.fromMap(Map<String, dynamic>.from(item as Map)))
        .toList();
  }
}

import 'dart:convert';

class WeeklyMealPlan {
  const WeeklyMealPlan({
    required this.location,
    this.latitude,
    this.longitude,
    required this.goalSummary,
    required this.startDate,
    required this.generatedAt,
    required this.days,
  });

  final String location;
  final double? latitude;
  final double? longitude;
  final String goalSummary;
  final DateTime startDate;
  final DateTime generatedAt;
  final List<WeeklyMealPlanDay> days;

  bool get isEmpty => location.trim().isEmpty || days.isEmpty;

  WeeklyMealPlanDay? dayFor(DateTime date) {
    final target = DateTime(date.year, date.month, date.day);
    for (final day in days) {
      final current = DateTime(
        day.date.year,
        day.date.month,
        day.date.day,
      );
      if (current == target) {
        return day;
      }
    }
    return null;
  }

  Map<String, dynamic> toMap() {
    return {
      'location': location,
      'latitude': latitude,
      'longitude': longitude,
      'goalSummary': goalSummary,
      'startDate': startDate.toIso8601String(),
      'generatedAt': generatedAt.toIso8601String(),
      'days': days.map((day) => day.toMap()).toList(),
    };
  }

  factory WeeklyMealPlan.fromMap(Map<String, dynamic> map) {
    final rawDays = map['days'] as List<dynamic>? ?? const [];
    return WeeklyMealPlan(
      location: map['location'] as String? ?? '',
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      goalSummary: map['goalSummary'] as String? ?? '',
      startDate: DateTime.tryParse(map['startDate'] as String? ?? '') ??
          DateTime.now(),
      generatedAt:
          DateTime.tryParse(map['generatedAt'] as String? ?? '') ??
              DateTime.now(),
      days: rawDays
          .map((item) =>
              WeeklyMealPlanDay.fromMap(Map<String, dynamic>.from(item as Map)))
          .toList(),
    );
  }

  factory WeeklyMealPlan.fromRaw(String raw) {
    return WeeklyMealPlan.fromMap(jsonDecode(raw) as Map<String, dynamic>);
  }

  WeeklyMealPlan copyWith({
    String? location,
    double? latitude,
    double? longitude,
    String? goalSummary,
    DateTime? startDate,
    DateTime? generatedAt,
    List<WeeklyMealPlanDay>? days,
  }) {
    return WeeklyMealPlan(
      location: location ?? this.location,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      goalSummary: goalSummary ?? this.goalSummary,
      startDate: startDate ?? this.startDate,
      generatedAt: generatedAt ?? this.generatedAt,
      days: days ?? this.days,
    );
  }

  String encode() => jsonEncode(toMap());
}

class WeeklyMealPlanDay {
  const WeeklyMealPlanDay({
    required this.date,
    required this.label,
    required this.focus,
    required this.breakfast,
    required this.lunch,
    required this.dinner,
    this.snack,
  });

  final DateTime date;
  final String label;
  final String focus;
  final String breakfast;
  final String lunch;
  final String dinner;
  final String? snack;

  Map<String, dynamic> toMap() {
    return {
      'date': date.toIso8601String(),
      'label': label,
      'focus': focus,
      'breakfast': breakfast,
      'lunch': lunch,
      'dinner': dinner,
      'snack': snack,
    };
  }

  factory WeeklyMealPlanDay.fromMap(Map<String, dynamic> map) {
    return WeeklyMealPlanDay(
      date: DateTime.tryParse(map['date'] as String? ?? '') ?? DateTime.now(),
      label: map['label'] as String? ?? '',
      focus: map['focus'] as String? ?? '',
      breakfast: map['breakfast'] as String? ?? '',
      lunch: map['lunch'] as String? ?? '',
      dinner: map['dinner'] as String? ?? '',
      snack: map['snack'] as String?,
    );
  }
}

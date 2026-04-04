import 'dart:convert';

import 'package:flutter/material.dart';

enum MealType { breakfast, lunch, dinner, snack, drink }

extension MealTypeX on MealType {
  String get label {
    switch (this) {
      case MealType.breakfast:
        return 'Breakfast';
      case MealType.lunch:
        return 'Lunch';
      case MealType.dinner:
        return 'Dinner';
      case MealType.snack:
        return 'Snack';
      case MealType.drink:
        return 'Drink';
    }
  }

  static MealType fromName(String value) {
    return MealType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => MealType.snack,
    );
  }

  IconData get icon {
    switch (this) {
      case MealType.breakfast:
        return Icons.wb_sunny_outlined;
      case MealType.lunch:
        return Icons.ramen_dining_outlined;
      case MealType.dinner:
        return Icons.nightlight_round;
      case MealType.snack:
        return Icons.cookie_outlined;
      case MealType.drink:
        return Icons.local_drink_outlined;
    }
  }
}

class MealEntry {
  MealEntry({
    required this.id,
    required this.mealType,
    required this.capturedAt,
    required this.feelingRating,
    required this.feelingNote,
    required this.drinkVolumeMl,
    required this.aiSuggestedSummary,
    required this.aiSuggestedCalories,
    required this.aiReview,
    required this.isSharedMeal,
    required this.sharedMealPeopleCount,
    required this.userPortionPercent,
    required this.tags,
    required this.imagePaths,
    this.userEditedSummary,
    this.userEditedCalories,
  });

  final String id;
  final MealType mealType;
  final DateTime capturedAt;
  final int feelingRating;
  final String feelingNote;
  final int drinkVolumeMl;
  final String aiSuggestedSummary;
  final int aiSuggestedCalories;
  final String aiReview;
  final bool isSharedMeal;
  final int sharedMealPeopleCount;
  final int userPortionPercent;
  final List<String> tags;
  final List<String> imagePaths;
  final String? userEditedSummary;
  final int? userEditedCalories;

  String get displaySummary => userEditedSummary?.trim().isNotEmpty == true
      ? userEditedSummary!
      : aiSuggestedSummary;

  int get displayCalories => userEditedCalories ?? aiSuggestedCalories;
  int get totalEstimatedCalories => aiSuggestedCalories;
  bool get isDrink => mealType == MealType.drink;
  int get userEstimatedCalories {
    final baseCalories = userEditedCalories ?? aiSuggestedCalories;
    if (!isSharedMeal) {
      return baseCalories;
    }
    return ((baseCalories * userPortionPercent) / 100).round();
  }

  bool get isSummaryOverridden => userEditedSummary?.trim().isNotEmpty == true;
  bool get isCaloriesOverridden => userEditedCalories != null;

  String get feelingLabel {
    switch (feelingRating) {
      case 1:
        return 'Very rough';
      case 2:
        return 'Not great';
      case 3:
        return 'Okay';
      case 4:
        return 'Pretty good';
      case 5:
        return 'Excellent';
      default:
        return 'Unrated';
    }
  }

  MealEntry copyWith({
    String? id,
    MealType? mealType,
    DateTime? capturedAt,
    int? feelingRating,
    String? feelingNote,
    int? drinkVolumeMl,
    String? aiSuggestedSummary,
    int? aiSuggestedCalories,
    String? aiReview,
    bool? isSharedMeal,
    int? sharedMealPeopleCount,
    int? userPortionPercent,
    List<String>? tags,
    List<String>? imagePaths,
    Object? userEditedSummary = _sentinel,
    Object? userEditedCalories = _sentinel,
  }) {
    return MealEntry(
      id: id ?? this.id,
      mealType: mealType ?? this.mealType,
      capturedAt: capturedAt ?? this.capturedAt,
      feelingRating: feelingRating ?? this.feelingRating,
      feelingNote: feelingNote ?? this.feelingNote,
      drinkVolumeMl: drinkVolumeMl ?? this.drinkVolumeMl,
      aiSuggestedSummary: aiSuggestedSummary ?? this.aiSuggestedSummary,
      aiSuggestedCalories: aiSuggestedCalories ?? this.aiSuggestedCalories,
      aiReview: aiReview ?? this.aiReview,
      isSharedMeal: isSharedMeal ?? this.isSharedMeal,
      sharedMealPeopleCount: sharedMealPeopleCount ?? this.sharedMealPeopleCount,
      userPortionPercent: userPortionPercent ?? this.userPortionPercent,
      tags: tags ?? this.tags,
      imagePaths: imagePaths ?? this.imagePaths,
      userEditedSummary: userEditedSummary == _sentinel
          ? this.userEditedSummary
          : userEditedSummary as String?,
      userEditedCalories: userEditedCalories == _sentinel
          ? this.userEditedCalories
          : userEditedCalories as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'mealType': mealType.name,
      'capturedAt': capturedAt.toIso8601String(),
      'feelingRating': feelingRating,
      'feelingNote': feelingNote,
      'drinkVolumeMl': drinkVolumeMl,
      'aiSuggestedSummary': aiSuggestedSummary,
      'aiSuggestedCalories': aiSuggestedCalories,
      'aiReview': aiReview,
      'isSharedMeal': isSharedMeal,
      'sharedMealPeopleCount': sharedMealPeopleCount,
      'userPortionPercent': userPortionPercent,
      'tags': tags,
      'imagePaths': imagePaths,
      'userEditedSummary': userEditedSummary,
      'userEditedCalories': userEditedCalories,
    };
  }

  factory MealEntry.fromMap(Map<String, dynamic> map) {
    return MealEntry(
      id: map['id'] as String,
      mealType: MealTypeX.fromName(map['mealType'] as String),
      capturedAt: DateTime.parse(map['capturedAt'] as String),
      feelingRating: map['feelingRating'] as int? ?? 3,
      feelingNote: map['feelingNote'] as String? ?? '',
      drinkVolumeMl: map['drinkVolumeMl'] as int? ?? 0,
      aiSuggestedSummary:
          map['aiSuggestedSummary'] as String? ?? map['foodSummary'] as String? ?? '',
      aiSuggestedCalories:
          map['aiSuggestedCalories'] as int? ?? map['estimatedCalories'] as int? ?? 0,
      aiReview: map['aiReview'] as String? ?? '',
      isSharedMeal: map['isSharedMeal'] as bool? ?? false,
      sharedMealPeopleCount: map['sharedMealPeopleCount'] as int? ?? 1,
      userPortionPercent: map['userPortionPercent'] as int? ?? 100,
      tags: List<String>.from(map['tags'] as List<dynamic>? ?? const []),
      imagePaths: List<String>.from(
        map['imagePaths'] as List<dynamic>? ??
            ((map['imagePath'] as String?) == null ? const [] : [map['imagePath']]),
      ),
      userEditedSummary: map['userEditedSummary'] as String?,
      userEditedCalories: map['userEditedCalories'] as int?,
    );
  }

  static String encodeList(List<MealEntry> entries) {
    return jsonEncode(entries.map((entry) => entry.toMap()).toList());
  }

  static List<MealEntry> decodeList(String raw) {
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => MealEntry.fromMap(item as Map<String, dynamic>))
        .toList();
  }
}

const _sentinel = Object();

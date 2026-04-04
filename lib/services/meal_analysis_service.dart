import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../models/meal_entry.dart';

class MealAnalysisSuggestion {
  const MealAnalysisSuggestion({
    required this.summary,
    required this.estimatedCalories,
    required this.review,
    this.detectedMealType,
    this.estimatedDrinkVolumeMl,
    this.debug,
  });

  final String summary;
  final int estimatedCalories;
  final String review;
  final MealType? detectedMealType;
  final int? estimatedDrinkVolumeMl;
  final MealAnalysisDebug? debug;
}

class MealAnalysisDebug {
  const MealAnalysisDebug({
    required this.imageCount,
    required this.responseTimeMs,
    this.inputTokens,
    this.outputTokens,
    this.totalTokens,
  });

  final int imageCount;
  final int responseTimeMs;
  final int? inputTokens;
  final int? outputTokens;
  final int? totalTokens;
}

class MealAnalysisService {
  static const _aiUploadMaxDimension = 1024;
  static const _aiUploadJpegQuality = 82;

  MealAnalysisService({
    http.Client? client,
    String? apiBaseUrl,
    String? apiKey,
    String? model,
  })  : _client = client ?? http.Client(),
        _apiBaseUrl = apiBaseUrl ??
            const String.fromEnvironment('MEAL_MIRROR_API_BASE_URL'),
        _apiKey = apiKey ?? const String.fromEnvironment('OPENAI_API_KEY'),
        _model = model ?? const String.fromEnvironment('OPENAI_MODEL', defaultValue: 'gpt-4.1-mini');

  final http.Client _client;
  final String _apiBaseUrl;
  final String _apiKey;
  final String _model;

  static const coachName = 'Mira';

  Map<String, dynamic> _decodeJsonResponse(http.Response response) {
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  Future<MealAnalysisSuggestion> analyzeMeal({
    required List<XFile> images,
    required MealType mealType,
    required DateTime capturedAt,
    String? userEditedSummary,
    String? dietGoalBrief,
  }) async {
    final imagePayloads = <Map<String, String>>[];
    for (final image in images) {
      imagePayloads.add(await _prepareImagePayload(image));
    }

    if (_apiBaseUrl.isNotEmpty) {
      return _analyzeWithBackend(
        images: imagePayloads,
        mealType: mealType,
        capturedAt: capturedAt,
        userEditedSummary: userEditedSummary,
        dietGoalBrief: dietGoalBrief,
      );
    }

    if (_apiKey.isNotEmpty) {
      return _analyzeWithOpenAi(
        images: imagePayloads,
        mealType: mealType,
        capturedAt: capturedAt,
        userEditedSummary: userEditedSummary,
        dietGoalBrief: dietGoalBrief,
      );
    }

    return _fallbackSuggestion(images: images, mealType: mealType);
  }

  Future<Map<String, String>> _prepareImagePayload(XFile image) async {
    final originalBytes = await image.readAsBytes();
    final decoded = img.decodeImage(originalBytes);
    if (decoded == null) {
      return {
        'mimeType': _guessMimeType(image.path),
        'base64': base64Encode(originalBytes),
      };
    }

    final longestSide = decoded.width > decoded.height ? decoded.width : decoded.height;
    final needsResize = longestSide > _aiUploadMaxDimension;
    final outputImage = needsResize
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? _aiUploadMaxDimension : null,
            height: decoded.height > decoded.width ? _aiUploadMaxDimension : null,
            interpolation: img.Interpolation.average,
          )
        : decoded;

    final jpegBytes = img.encodeJpg(outputImage, quality: _aiUploadJpegQuality);
    return {
      'mimeType': 'image/jpeg',
      'base64': base64Encode(jpegBytes),
    };
  }

  Future<String> createDietGoalBrief(String mission) async {
    final normalized = mission.trim();
    if (normalized.isEmpty) {
      return '';
    }

    if (_apiBaseUrl.isNotEmpty) {
      return _createGoalBriefWithBackend(normalized);
    }

    if (_apiKey.isEmpty) {
      return _fallbackGoalBrief(normalized);
    }

    try {
      final response = await _client.post(
        Uri.parse('https://api.openai.com/v1/responses'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': _model,
          'input': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'input_text',
                  'text':
                      'Condense this diet mission into a very short reusable AI context brief. '
                      'Keep the user intent, preferred outcome, and important guardrails. '
                      'Do not repeat filler words. Keep it under 35 words. '
                      'Return strict JSON only with key: brief.\n\nMission: $normalized',
                },
              ],
            }
          ],
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _fallbackGoalBrief(normalized);
      }

      final json = _decodeJsonResponse(response);
      final outputText = _extractOpenAiOutputText(json);
      if (outputText.isEmpty) {
        return _fallbackGoalBrief(normalized);
      }

      try {
        final parsed = _extractSuggestionJson(outputText);
        final brief = (parsed['brief'] as String? ?? '').trim();
        return brief.isEmpty ? _fallbackGoalBrief(normalized) : brief;
      } catch (_) {
        return _fallbackGoalBrief(normalized);
      }
    } catch (_) {
      return _fallbackGoalBrief(normalized);
    }
  }

  Future<String> chatWithCoach({
    required String message,
    required List<MealEntry> recentEntries,
    String? dietGoalBrief,
    List<Map<String, dynamic>> conversationMessages = const [],
  }) async {
    final trimmedMessage = message.trim();
    if (trimmedMessage.isEmpty) {
      return 'Tell me what you want help with, and I will look at your recent meals with you.';
    }

    final goalBrief = (dietGoalBrief ?? '').trim();
    final recentSummary = recentEntries.isEmpty
        ? 'No recent meals were logged.'
        : recentEntries
            .take(12)
            .map(
              (entry) =>
                  '- ${entry.capturedAt.toIso8601String()} | ${entry.mealType.label} | ${entry.displaySummary} | ${entry.userEstimatedCalories} kcal${entry.isSharedMeal ? ' personal, ${entry.totalEstimatedCalories} kcal total' : ''} | feeling ${entry.feelingRating}/5${entry.drinkVolumeMl > 0 ? ' | ${entry.drinkVolumeMl} mL' : ''}',
            )
            .join('\n');

    if (_apiBaseUrl.isNotEmpty) {
      return _chatWithCoachBackend(
        message: trimmedMessage,
        recentEntries: recentEntries,
        dietGoalBrief: goalBrief,
        recentSummary: recentSummary,
        conversationMessages: conversationMessages,
      );
    }

    if (_apiKey.isNotEmpty) {
      final response = await _client.post(
        Uri.parse('https://api.openai.com/v1/responses'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': _model,
          'input': [
            {
              'role': 'system',
              'content': [
                {
                  'type': 'input_text',
                  'text':
                      'You are Mira, the in-app meal reflection coach for Meal Mirror. '
                      'Be warm, observant, concise, and non-judgmental. '
                      'Do not pretend to be a doctor. '
                      'Use the user mission and recent meal history to answer clearly. '
                      'Prefer practical, specific advice over generic nutrition talk. '
                      'Keep replies under 140 words unless the user asks for more detail.',
                },
              ],
            },
            {
              'role': 'user',
              'content': [
                if (goalBrief.isNotEmpty)
                  {
                    'type': 'input_text',
                    'text': 'Diet mission: $goalBrief',
                  },
                for (final item in conversationMessages.take(
                  conversationMessages.length > 8 ? 8 : conversationMessages.length,
                ))
                  {
                    'type': 'input_text',
                    'text':
                        '${item['isUser'] == true ? 'User' : 'Mira'}: ${item['text'] ?? ''}',
                  },
                {
                  'type': 'input_text',
                  'text': 'Recent meals:\n$recentSummary',
                },
                {
                  'type': 'input_text',
                  'text': 'User message: $trimmedMessage',
                },
              ],
            },
          ],
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final json = _decodeJsonResponse(response);
        final outputText = _extractOpenAiOutputText(json);
        if (outputText.isNotEmpty) {
          return outputText.trim();
        }
      }
    }

    return _fallbackCoachReply(
      message: trimmedMessage,
      recentEntries: recentEntries,
      dietGoalBrief: goalBrief,
    );
  }

  Future<String> _createGoalBriefWithBackend(String normalized) async {
    try {
      final response = await _client.post(
        Uri.parse('$_apiBaseUrl/diet-goal-brief'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'mission': normalized}),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _fallbackGoalBrief(normalized);
      }

      final json = _decodeJsonResponse(response);
      final brief = (json['brief'] as String? ?? '').trim();
      return brief.isEmpty ? _fallbackGoalBrief(normalized) : brief;
    } catch (_) {
      return _fallbackGoalBrief(normalized);
    }
  }

  Future<String> _chatWithCoachBackend({
    required String message,
    required List<MealEntry> recentEntries,
    required String dietGoalBrief,
    required String recentSummary,
    required List<Map<String, dynamic>> conversationMessages,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$_apiBaseUrl/coach-chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': message,
          'dietGoalBrief': dietGoalBrief,
          'recentSummary': recentSummary,
          'recentEntries': recentEntries.map((entry) => entry.toMap()).toList(),
          'conversationMessages': conversationMessages,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final json = _decodeJsonResponse(response);
        final reply = (json['reply'] as String? ?? '').trim();
        if (reply.isNotEmpty) {
          return reply;
        }
      }
    } catch (_) {
      // Fall back locally below.
    }

    return _fallbackCoachReply(
      message: message,
      recentEntries: recentEntries,
      dietGoalBrief: dietGoalBrief,
    );
  }

  Future<MealAnalysisSuggestion> _analyzeWithBackend({
    required List<Map<String, String>> images,
    required MealType mealType,
    required DateTime capturedAt,
    String? userEditedSummary,
    String? dietGoalBrief,
  }) async {
    final response = await _client.post(
      Uri.parse('$_apiBaseUrl/analyze-meal'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'mealType': mealType.name,
        'capturedAt': capturedAt.toIso8601String(),
        'userEditedSummary': userEditedSummary,
        'dietGoalBrief': dietGoalBrief,
        'images': images,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Meal analysis failed with status ${response.statusCode}');
    }

    final json = _decodeJsonResponse(response);
    return MealAnalysisSuggestion(
      summary: json['summary'] as String,
      estimatedCalories: json['estimatedCalories'] as int,
      review: json['review'] as String,
      detectedMealType: _parseMealTypeName(json['detectedMealType'] as String?),
      estimatedDrinkVolumeMl: (json['estimatedDrinkVolumeMl'] as num?)?.round(),
    );
  }

  Future<MealAnalysisSuggestion> _analyzeWithOpenAi({
    required List<Map<String, String>> images,
    required MealType mealType,
    required DateTime capturedAt,
    String? userEditedSummary,
    String? dietGoalBrief,
  }) async {
    final extraContext = (userEditedSummary ?? '').trim();
    final goalBrief = (dietGoalBrief ?? '').trim();
    final stopwatch = Stopwatch()..start();

    final response = await _client.post(
      Uri.parse('https://api.openai.com/v1/responses'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: jsonEncode({
        'model': _model,
        'input': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'input_text',
                'text':
                    'Analyze this ${mealType.label.toLowerCase()} captured at ${capturedAt.toIso8601String()}. '
                    'If images are provided, estimate the full meal exactly as shown now across all images, including shared dishes for the whole table when relevant. '
                    'If no images are provided, rely on the user-written meal description only and say so implicitly through your estimate. '
                    'Use the user diet goal context when it is provided, but do not force the answer to sound medical or judgmental. '
                    'If the images only show a drink, fruit, dessert, or a very small item, say that directly instead of inventing a rice or protein plate. '
                    'If the images clearly show only a beverage, set detectedMealType to "drink" and estimateDrinkVolumeMl to a reasonable integer guess for the visible liquid. '
                    'Do not reuse assumptions from earlier images beyond what is visibly present in the current set. '
                    'If the user has typed extra meal details, use them as additional context, especially counts like number of dishes, cups, glasses, bowls, portions, or water volume. '
                    'When estimating calories, count the whole meal across all visible items and the user-provided dish count or portion note when it fits the images or text description. '
                    'Do not guess how much the user personally ate unless the user explicitly gives a portion clue. '
                    'Return strict JSON only with keys: summary, estimatedCalories, review, detectedMealType, estimatedDrinkVolumeMl. '
                    'The summary should be a concise meal description. '
                    'estimatedCalories must be an integer. '
                    'review should be one short helpful note about the meal for diet tracking. '
                    'detectedMealType must be one of: breakfast, lunch, dinner, snack, drink, or null. '
                    'estimatedDrinkVolumeMl must be an integer or null.'
              },
              if (goalBrief.isNotEmpty)
                {
                  'type': 'input_text',
                  'text': 'User diet goal context: $goalBrief',
                },
              if (extraContext.isNotEmpty)
                {
                  'type': 'input_text',
                  'text':
                      'User-added meal details to consider if they match the images: $extraContext'
                },
              ...images.map(
                (image) => {
                  'type': 'input_image',
                  'image_url': 'data:${image['mimeType']};base64,${image['base64']}',
                },
              ),
            ],
          }
        ],
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Meal analysis failed with status ${response.statusCode}');
    }
    stopwatch.stop();

    final json = _decodeJsonResponse(response);
    final outputText = _extractOpenAiOutputText(json);
    if (outputText.isEmpty) {
      throw Exception('OpenAI returned no output_text');
    }

    final parsed = _extractSuggestionJson(outputText);
    return MealAnalysisSuggestion(
      summary: (parsed['summary'] as String? ?? '').trim(),
      estimatedCalories: ((parsed['estimatedCalories'] as num?) ?? 0).round(),
      review: (parsed['review'] as String? ?? '').trim(),
      detectedMealType: _parseMealTypeName(parsed['detectedMealType'] as String?),
      estimatedDrinkVolumeMl: (parsed['estimatedDrinkVolumeMl'] as num?)?.round(),
      debug: _extractDebugInfo(
        json: json,
        responseTimeMs: stopwatch.elapsedMilliseconds,
        imageCount: images.length,
      ),
    );
  }

  MealAnalysisSuggestion _fallbackSuggestion({
    required List<XFile> images,
    required MealType mealType,
  }) {
    final count = images.length;
    switch (mealType) {
      case MealType.breakfast:
        return MealAnalysisSuggestion(
          summary: count > 1
              ? 'Breakfast plate with several items'
              : 'Breakfast meal with protein and carbs',
          estimatedCalories: count > 1 ? 520 : 420,
          review:
              'Fallback analysis is active. Add your backend URL to enable real OpenAI meal review.',
          debug: MealAnalysisDebug(
            imageCount: count,
            responseTimeMs: 0,
          ),
        );
      case MealType.lunch:
        return MealAnalysisSuggestion(
          summary: count > 1
              ? 'Lunch spread with multiple dishes'
              : 'Lunch plate with protein, carbs, and vegetables',
          estimatedCalories: count > 1 ? 760 : 610,
          review:
              'Fallback analysis is active. Add your backend URL to enable real OpenAI meal review.',
          debug: MealAnalysisDebug(
            imageCount: count,
            responseTimeMs: 0,
          ),
        );
      case MealType.dinner:
        return MealAnalysisSuggestion(
          summary: count > 1
              ? 'Dinner meal with multiple components'
              : 'Dinner meal with balanced portions',
          estimatedCalories: count > 1 ? 680 : 560,
          review:
              'Fallback analysis is active. Add your backend URL to enable real OpenAI meal review.',
          debug: MealAnalysisDebug(
            imageCount: count,
            responseTimeMs: 0,
          ),
        );
      case MealType.snack:
        return MealAnalysisSuggestion(
          summary: count > 1 ? 'Multiple snack items' : 'Snack portion',
          estimatedCalories: count > 1 ? 300 : 190,
          review:
              'Fallback analysis is active. Add your backend URL to enable real OpenAI meal review.',
          debug: MealAnalysisDebug(
            imageCount: count,
            responseTimeMs: 0,
          ),
        );
      case MealType.drink:
        return MealAnalysisSuggestion(
          summary: count > 1 ? 'Multiple drinks' : 'Drink',
          estimatedCalories: count > 1 ? 120 : 0,
          review:
              'Fallback analysis is active. Add your backend URL to enable real OpenAI meal review.',
          detectedMealType: MealType.drink,
          debug: MealAnalysisDebug(
            imageCount: count,
            responseTimeMs: 0,
          ),
        );
    }
  }

  String _guessMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
      return 'image/heic';
    }
    return 'image/jpeg';
  }

  MealType? _parseMealTypeName(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    if (normalized.isEmpty || normalized == 'null') {
      return null;
    }
    for (final type in MealType.values) {
      if (type.name == normalized) {
        return type;
      }
    }
    return null;
  }

  String _fallbackGoalBrief(String mission) {
    final compact = mission.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 160) {
      return compact;
    }
    return '${compact.substring(0, 157)}...';
  }

  String _fallbackCoachReply({
    required String message,
    required List<MealEntry> recentEntries,
    required String dietGoalBrief,
  }) {
    final lower = message.toLowerCase();
    if (recentEntries.isEmpty) {
      if (dietGoalBrief.isNotEmpty) {
        return 'I do not have enough meal history yet, but I can help you work toward: $dietGoalBrief. Start with a few real logs today, and I will look for patterns with you.';
      }
      return 'I do not have enough meal history yet. Log a few meals or drinks today, and I can start spotting patterns for you.';
    }

    final averagePersonalCalories =
        (recentEntries.fold<int>(0, (sum, entry) => sum + entry.userEstimatedCalories) /
                recentEntries.length)
            .round();
    final lowFeelingCount =
        recentEntries.where((entry) => entry.feelingRating <= 2).length;
    final drinkVolume =
        recentEntries.fold<int>(0, (sum, entry) => sum + entry.drinkVolumeMl);

    if (lower.contains('drink') || lower.contains('water') || lower.contains('hydr')) {
      return 'From your recent logs, you have about $drinkVolume mL of drinks recorded. If hydration is the goal, try making one more small water log easy to repeat after your next meal.';
    }

    if (lower.contains('calorie') || lower.contains('heavy') || lower.contains('light')) {
      return 'Your recent meals average about $averagePersonalCalories kcal for your portion. If you want lighter meals, compare the ones that felt best afterward and use those as your repeat pattern.';
    }

    if (lowFeelingCount > 0) {
      return 'A few recent meals were followed by lower feeling ratings. I would compare those meals by timing, portion size, and whether drinks or fried foods showed up more often.';
    }

    if (dietGoalBrief.isNotEmpty) {
      return 'Your recent logs are starting to form a useful pattern. Keep comparing them against your mission: $dietGoalBrief';
    }

    return 'Your recent logs already give us something to work with. Ask me about calories, meal timing, drinks, or which meals felt best, and I will help you review the pattern.';
  }

  String _extractOpenAiOutputText(Map<String, dynamic> json) {
    final directText = (json['output_text'] as String? ?? '').trim();
    if (directText.isNotEmpty) {
      return directText;
    }

    final buffer = StringBuffer();
    final output = json['output'];
    if (output is List) {
      for (final item in output) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final content = item['content'];
        if (content is! List) {
          continue;
        }
        for (final block in content) {
          if (block is! Map<String, dynamic>) {
            continue;
          }
          final text = block['text'];
          if (text is String && text.trim().isNotEmpty) {
            buffer.writeln(text.trim());
            continue;
          }
          if (text is Map<String, dynamic>) {
            final value = text['value'];
            if (value is String && value.trim().isNotEmpty) {
              buffer.writeln(value.trim());
            }
          }
        }
      }
    }

    return buffer.toString().trim();
  }

  Map<String, dynamic> _extractSuggestionJson(String outputText) {
    try {
      return jsonDecode(outputText) as Map<String, dynamic>;
    } catch (_) {
      final match = RegExp(r'\{[\s\S]*\}').firstMatch(outputText);
      if (match == null) {
        rethrow;
      }
      return jsonDecode(match.group(0)!) as Map<String, dynamic>;
    }
  }

  MealAnalysisDebug _extractDebugInfo({
    required Map<String, dynamic> json,
    required int responseTimeMs,
    required int imageCount,
  }) {
    final usage = json['usage'];
    if (usage is! Map<String, dynamic>) {
      return MealAnalysisDebug(
        imageCount: imageCount,
        responseTimeMs: responseTimeMs,
      );
    }

    return MealAnalysisDebug(
      imageCount: imageCount,
      responseTimeMs: responseTimeMs,
      inputTokens: (usage['input_tokens'] as num?)?.round(),
      outputTokens: (usage['output_tokens'] as num?)?.round(),
      totalTokens: (usage['total_tokens'] as num?)?.round(),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/diet_goal.dart';
import '../models/meal_entry.dart';
import '../models/review_period.dart';
import 'mira_chat_page.dart';
import '../services/meal_analysis_service.dart';
import '../services/meal_repository.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final MealRepository _repository = MealRepository();
  final MealAnalysisService _analysisService = MealAnalysisService();
  final ImagePicker _picker = ImagePicker();

  List<MealEntry> _entries = const [];
  DietGoal? _dietGoal;
  ReviewPeriod _period = ReviewPeriod.day;
  DateTime _referenceDate = DateTime.now();
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isSavingGoal = false;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    final snapshot = await _repository.loadAppState();
    if (!mounted) {
      return;
    }

    setState(() {
      _entries = [...snapshot.entries]..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
      _dietGoal = snapshot.dietGoal;
      _isLoading = false;
    });
  }

  Future<void> _createMeal() async {
    await _openMealEditor();
  }

  Future<void> _editMeal(MealEntry entry) async {
    await _openMealEditor(existing: entry);
  }

  Future<void> _quickCameraCapture() async {
    final now = DateTime.now();
    await _openMealEditor(
      seed: _MealEditorSeed(
        mealType: _defaultMealTypeFor(now),
        capturedAt: now,
        summary: '',
        feelingRating: 3,
        feelingNote: 'Okay',
        drinkVolumeMl: 0,
      ),
      autoPickSource: ImageSource.camera,
    );
  }

  Future<void> _quickDrinkCapture({
    required String summary,
    required int volumeMl,
  }) async {
    final now = DateTime.now();
    await _openMealEditor(
      seed: _MealEditorSeed(
        mealType: MealType.drink,
        capturedAt: now,
        summary: summary,
        feelingRating: 3,
        feelingNote: 'Okay',
        drinkVolumeMl: volumeMl,
      ),
    );
  }

  Future<void> _repeatRecentEntry(MealEntry entry) async {
    final now = DateTime.now();
    await _openMealEditor(
      seed: _MealEditorSeed(
        mealType: entry.mealType,
        capturedAt: now,
        summary: entry.displaySummary,
        feelingRating: entry.feelingRating,
        feelingNote: entry.feelingNote,
        drinkVolumeMl: entry.drinkVolumeMl,
      ),
    );
  }

  Future<void> _openMealEditor({
    MealEntry? existing,
    _MealEditorSeed? seed,
    ImageSource? autoPickSource,
  }) async {
    final draft = await showModalBottomSheet<_MealDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => _MealEditorSheet(
        picker: _picker,
        analysisService: _analysisService,
        existing: existing,
        seed: seed,
        autoPickSource: autoPickSource,
        recentEntries: _recentEntries,
        dietGoalBrief: _dietGoal?.aiBrief ?? '',
      ),
    );

    if (draft == null) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final imagePaths = await _persistMealImages(draft, existing);
    final entry = MealEntry(
      id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      mealType: draft.mealType,
      capturedAt: draft.capturedAt,
      feelingRating: draft.feelingRating,
      feelingNote: draft.feelingNote,
      drinkVolumeMl: draft.drinkVolumeMl,
      aiSuggestedSummary: draft.aiSuggestedSummary,
      aiSuggestedCalories: draft.aiSuggestedCalories,
      aiReview: draft.aiReview,
      isSharedMeal: draft.isSharedMeal,
      sharedMealPeopleCount: draft.sharedMealPeopleCount,
      userPortionPercent: draft.userPortionPercent,
      tags: _deriveTags(draft),
      imagePaths: imagePaths,
      userEditedSummary: draft.summaryWasEdited ? draft.summaryInput : null,
      userEditedCalories: null,
    );

    final nextEntries = [
      for (final current in _entries)
        if (current.id != entry.id) current,
      entry,
    ]..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));

    await _repository.saveEntries(nextEntries);

    if (!mounted) {
      return;
    }

    setState(() {
      _entries = nextEntries;
      _isSaving = false;
    });
  }

  Future<List<String>> _persistMealImages(
    _MealDraft draft,
    MealEntry? existing,
  ) async {
    final persisted = <String>[];

    for (final source in draft.imageSources) {
      switch (source) {
        case _ExistingImageSource():
          persisted.add(source.path);
        case _PickedImageSource():
          final storedPath = await _repository.persistPickedImage(source.file);
          if (storedPath != null) {
            persisted.add(storedPath);
          }
      }
    }

    if (persisted.isNotEmpty) {
      return persisted;
    }

    return existing?.imagePaths ?? const [];
  }

  Future<void> _editDietGoal() async {
    final nextMission = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => _DietGoalEditorSheet(
        initialMission: _dietGoal?.mission ?? '',
      ),
    );

    if (nextMission == null || !mounted) {
      return;
    }

    final trimmedMission = nextMission.trim();
    if (trimmedMission.isEmpty) {
      setState(() {
        _dietGoal = null;
      });
      await _repository.clearDietGoal();
      return;
    }

    setState(() {
      _isSavingGoal = true;
    });

    try {
      final brief = await _analysisService.createDietGoalBrief(trimmedMission);
      final goal = DietGoal(
        mission: trimmedMission,
        aiBrief: brief,
        updatedAt: DateTime.now(),
      );
      await _repository.saveDietGoal(goal);

      if (!mounted) {
        return;
      }

      setState(() {
        _dietGoal = goal;
        _isSavingGoal = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSavingGoal = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save the diet mission right now. Please try again.'),
        ),
      );
    }
  }

  Future<void> _openMiraChat() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MiraChatPage(
          analysisService: _analysisService,
          repository: _repository,
          recentEntries: _entries.take(12).toList(),
          dietGoalBrief: _dietGoal?.aiBrief ?? '',
        ),
      ),
    );
  }

  Future<void> _openTodayDrinksRoadmap() async {
    final drinks = _todayDrinkEntries;
    await showDialog<void>(
      context: context,
      barrierColor: const Color(0x660F0B08),
      builder: (context) => _TodayDrinksSheet(
        drinks: drinks,
      ),
    );
  }

  Future<void> _pickReferenceDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _referenceDate,
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      _referenceDate = DateTime(picked.year, picked.month, picked.day);
    });
  }

  List<MealEntry> get _filteredEntries {
    final reference = _referenceDate;

    return _entries.where((entry) {
      final captured = entry.capturedAt;
      switch (_period) {
        case ReviewPeriod.day:
          return _isSameDay(captured, reference);
        case ReviewPeriod.week:
          final weekStart = DateTime(reference.year, reference.month, reference.day)
              .subtract(Duration(days: reference.weekday - 1));
          final weekEnd = weekStart.add(const Duration(days: 7));
          return !captured.isBefore(weekStart) && captured.isBefore(weekEnd);
        case ReviewPeriod.month:
          return captured.year == reference.year && captured.month == reference.month;
        case ReviewPeriod.year:
          return captured.year == reference.year;
      }
    }).toList();
  }

  int get _totalCalories => _filteredEntries.fold(
        0,
        (sum, entry) => sum + entry.userEstimatedCalories,
      );

  int get _averageCalories {
    if (_filteredEntries.isEmpty) {
      return 0;
    }

    return (_totalCalories / _filteredEntries.length).round();
  }

  int get _todayDrinkVolumeMl {
    final now = DateTime.now();
    return _entries
        .where(
          (entry) => entry.mealType == MealType.drink && _isSameDay(entry.capturedAt, now),
        )
        .fold(0, (sum, entry) => sum + entry.drinkVolumeMl);
  }

  List<MealEntry> get _todayDrinkEntries {
    final now = DateTime.now();
    final drinks = _entries
        .where(
          (entry) => entry.mealType == MealType.drink && _isSameDay(entry.capturedAt, now),
        )
        .toList()
      ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    return drinks;
  }

  List<MealEntry> get _recentEntries {
    final seen = <String>{};
    final recent = <MealEntry>[];

    for (final entry in _entries) {
      final summary = entry.displaySummary.trim();
      if (summary.isEmpty) {
        continue;
      }

      final key = '${entry.mealType.name}|${summary.toLowerCase()}|${entry.drinkVolumeMl}';
      if (!seen.add(key)) {
        continue;
      }

      recent.add(entry);
      if (recent.length == 6) {
        break;
      }
    }

    return recent;
  }

  String get _dominantMealType {
    if (_filteredEntries.isEmpty) {
      return 'No meals yet';
    }

    final counts = <MealType, int>{};
    for (final entry in _filteredEntries) {
      counts.update(entry.mealType, (value) => value + 1, ifAbsent: () => 1);
    }

    final top = counts.entries.reduce(
      (current, next) => current.value >= next.value ? current : next,
    );
    return top.key.label;
  }

  String get _coachNote {
    if (_filteredEntries.isEmpty) {
      final mission = _dietGoal?.mission.trim();
      if (mission != null && mission.isNotEmpty) {
        return 'No meals logged in this ${_period.label.toLowerCase()} yet. Start logging so Meal Mirror can review your eating pattern against your mission: $mission';
      }
      return 'No meals logged in this ${_period.label.toLowerCase()} yet. Start logging so Meal Mirror can build a meaningful review for this period.';
    }

    final meals = _filteredEntries.length;
    final averageCalories = _averageCalories;
    final topMealType = _dominantMealType.toLowerCase();
    final lowRatings =
        _filteredEntries.where((entry) => entry.feelingRating <= 2).length;
    final highRatings =
        _filteredEntries.where((entry) => entry.feelingRating >= 4).length;
    final lateMeals =
        _filteredEntries.where((entry) => entry.capturedAt.hour >= 21).length;
    final missionBrief = (_dietGoal?.aiBrief ?? '').trim();
    final periodLabel = _describeCurrentPeriod();

    final summaryParts = <String>[
      '$periodLabel includes $meals meal${meals == 1 ? '' : 's'} averaging $averageCalories kcal, with $topMealType showing up most often.',
    ];

    if (lateMeals >= 2) {
      summaryParts.add(
        'Late meals appear a few times, so timing is becoming part of the pattern.',
      );
    } else if (highRatings > lowRatings && highRatings >= 2) {
      summaryParts.add(
        'Most ratings lean positive, which suggests this period includes several meals that felt good afterward.',
      );
    } else if (lowRatings >= 2) {
      summaryParts.add(
        'Several meals were rated low, so it is worth checking which foods, portions, or times led to those dips.',
      );
    } else {
      summaryParts.add(
        'The pattern is still forming, but meal timing, calories, and feeling scores are already starting to connect.',
      );
    }

    if (missionBrief.isNotEmpty) {
      summaryParts.add(
        'For your mission, keep comparing these meals against: $missionBrief',
      );
    }

    return summaryParts.join(' ');
  }

  List<String> _deriveTags(_MealDraft draft) {
    return const [];
  }

  String _describeCurrentPeriod() {
    switch (_period) {
      case ReviewPeriod.day:
        return 'This day';
      case ReviewPeriod.week:
        return 'This week';
      case ReviewPeriod.month:
        return 'This month';
      case ReviewPeriod.year:
        return 'This year';
    }
  }

  MealType _defaultMealTypeFor(DateTime value) {
    final hour = value.hour;
    if (hour < 10) {
      return MealType.breakfast;
    }
    if (hour < 15) {
      return MealType.lunch;
    }
    if (hour < 21) {
      return MealType.dinner;
    }
    return MealType.snack;
  }

  @override
  Widget build(BuildContext context) {
    final filteredEntries = _filteredEntries;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSaving ? null : _createMeal,
        icon: _isSaving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_a_photo_outlined),
        label: Text(_isSaving ? 'Saving...' : 'Log a meal'),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _OverviewCard(
                            totalCalories: _totalCalories,
                            averageCalories: _averageCalories,
                            entryCount: filteredEntries.length,
                            todayDrinkVolumeMl: _todayDrinkVolumeMl,
                            onTapDrinksToday: _openTodayDrinksRoadmap,
                          ),
                          const SizedBox(height: 18),
                          _QuickCaptureCard(
                            recentEntries: _recentEntries,
                            onCameraTap: _quickCameraCapture,
                            onDrinkTap: _quickDrinkCapture,
                            onRecentTap: _repeatRecentEntry,
                          ),
                          const SizedBox(height: 18),
                          _DietGoalCard(
                            goal: _dietGoal,
                            isSaving: _isSavingGoal,
                            onEdit: _editDietGoal,
                          ),
                          const SizedBox(height: 18),
                          _PeriodSelector(
                            selected: _period,
                            referenceDate: _referenceDate,
                            onChanged: (period) {
                              setState(() {
                                _period = period;
                              });
                            },
                            onPickDate: _pickReferenceDate,
                          ),
                          const SizedBox(height: 18),
                          _CoachCard(
                            note: _coachNote,
                            period: _period,
                            onChat: _openMiraChat,
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Meal timeline',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                  if (filteredEntries.isEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                      sliver: SliverToBoxAdapter(
                        child: _EmptyTimelineGuide(onAddMeal: _createMeal),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                      sliver: SliverList.separated(
                        itemBuilder: (context, index) {
                          final entry = filteredEntries[index];
                          return _MealCard(
                            entry: entry,
                            onEdit: () => _editMeal(entry),
                          );
                        },
                        separatorBuilder: (context, index) => const SizedBox(height: 16),
                        itemCount: filteredEntries.length,
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  bool _isSameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.totalCalories,
    required this.averageCalories,
    required this.entryCount,
    required this.todayDrinkVolumeMl,
    required this.onTapDrinksToday,
  });

  final int totalCalories;
  final int averageCalories;
  final int entryCount;
  final int todayDrinkVolumeMl;
  final VoidCallback onTapDrinksToday;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF2F251F), Color(0xFF7A4B2F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Review dashboard',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                      child: _StatChip(label: 'Total calories', value: '$totalCalories kcal'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatChip(label: 'Average meal', value: '$averageCalories kcal'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StatChip(label: 'Meals logged', value: '$entryCount'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatChip(
                      label: 'Drinks today',
                      value: todayDrinkVolumeMl > 0 ? '$todayDrinkVolumeMl mL' : '0 mL',
                      onTap: onTapDrinksToday,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickCaptureCard extends StatelessWidget {
  const _QuickCaptureCard({
    required this.recentEntries,
    required this.onCameraTap,
    required this.onDrinkTap,
    required this.onRecentTap,
  });

  final List<MealEntry> recentEntries;
  final VoidCallback onCameraTap;
  final Future<void> Function({
    required String summary,
    required int volumeMl,
  }) onDrinkTap;
  final ValueChanged<MealEntry> onRecentTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F1E8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE9DCCD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Quick capture',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Camera, drinks, or repeat.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF6E6257),
                      ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onCameraTap,
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Camera'),
              ),
              OutlinedButton.icon(
                onPressed: () => onDrinkTap(summary: 'Tea', volumeMl: 100),
                icon: const Icon(Icons.emoji_food_beverage_outlined),
                label: const Text('Tea 100'),
              ),
              OutlinedButton.icon(
                onPressed: () => onDrinkTap(summary: 'Coffee', volumeMl: 100),
                icon: const Icon(Icons.coffee_outlined),
                label: const Text('Coffee 100'),
              ),
              OutlinedButton.icon(
                onPressed: () => onDrinkTap(summary: 'Water', volumeMl: 150),
                icon: const Icon(Icons.water_drop_outlined),
                label: const Text('Water 150'),
              ),
            ],
          ),
          if (recentEntries.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in recentEntries)
                  ActionChip(
                    onPressed: () => onRecentTap(entry),
                    avatar: Icon(
                      entry.mealType == MealType.drink
                          ? Icons.local_drink_outlined
                          : Icons.restaurant_outlined,
                      size: 16,
                      color: const Color(0xFF7A5A45),
                    ),
                    label: Text(_quickCaptureLabel(entry)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _quickCaptureLabel(MealEntry entry) {
    final summary = entry.displaySummary.trim();
    final compactSummary = summary.length > 28 ? '${summary.substring(0, 28)}...' : summary;
    if (entry.mealType == MealType.drink && entry.drinkVolumeMl > 0) {
      return '$compactSummary • ${entry.drinkVolumeMl} mL';
    }
    return compactSummary;
  }
}

class _DietGoalCard extends StatelessWidget {
  const _DietGoalCard({
    required this.goal,
    required this.isSaving,
    required this.onEdit,
  });

  final DietGoal? goal;
  final bool isSaving;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final hasGoal = goal != null && !goal!.isEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Diet mission',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                TextButton(
                  onPressed: isSaving ? null : onEdit,
                  child: Text(hasGoal ? 'Edit' : 'Add'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              hasGoal
                  ? goal!.mission
                  : 'Set your goal once so Meal Mirror can tailor meal feedback around what matters to you.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF6E6257),
                  ),
            ),
            if (isSaving) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ] else if (hasGoal && goal!.aiBrief.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F2EB),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'Mira brief: ${goal!.aiBrief}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF7A5A45),
                      ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EditorSectionLabel extends StatelessWidget {
  const _EditorSectionLabel({
    required this.label,
    required this.hint,
  });

  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF4E372D),
              ),
        ),
        const SizedBox(height: 4),
        Text(
          hint,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF7A6558),
                height: 1.35,
              ),
        ),
      ],
    );
  }
}

class _MealTypeChip extends StatelessWidget {
  const _MealTypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: selected ? const Color(0xFF7A4B2F) : const Color(0xFFFBF5EE),
          border: Border.all(
            color: selected ? const Color(0xFF7A4B2F) : const Color(0xFFE9DCCD),
          ),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x224E2D1E),
                    blurRadius: 10,
                    offset: Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? Colors.white : const Color(0xFF8A664F),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : const Color(0xFF5A4337),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StyledEditorField extends StatelessWidget {
  const _StyledEditorField({
    required this.controller,
    required this.hintText,
    this.keyboardType,
    this.minLines,
    this.maxLines,
  });

  final TextEditingController controller;
  final String hintText;
  final TextInputType? keyboardType;
  final int? minLines;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFBF6F0),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE7DBCE)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        minLines: minLines,
        maxLines: maxLines,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(
            color: Color(0xFFAA8D79),
            height: 1.45,
          ),
          border: InputBorder.none,
        ),
        style: const TextStyle(
          color: Color(0xFF3F2F28),
          height: 1.45,
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(label, style: const TextStyle(color: Colors.white70))),
                  if (onTap != null)
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: Colors.white70,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodayDrinksSheet extends StatelessWidget {
  const _TodayDrinksSheet({
    required this.drinks,
  });

  final List<MealEntry> drinks;

  @override
  Widget build(BuildContext context) {
    final dialogHeight = MediaQuery.of(context).size.height * 0.72;
    final isShortTimeline = drinks.length <= 2;
    final dialogMaxWidth = isShortTimeline ? 286.0 : 360.0;
    final dialogMinHeight = drinks.isEmpty
        ? null
        : drinks.length <= 2
            ? 140.0
            : drinks.length <= 4
                ? 220.0
                : null;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      child: ConstrainedBox(
        constraints: dialogMinHeight == null
            ? BoxConstraints(
                maxWidth: dialogMaxWidth,
                maxHeight: dialogHeight,
              )
            : BoxConstraints(
                maxWidth: dialogMaxWidth,
                maxHeight: dialogHeight,
                minHeight: dialogMinHeight,
              ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            isShortTimeline ? 12 : 16,
            18,
            isShortTimeline ? 12 : 16,
            16,
          ),
          child: drinks.isEmpty
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F2EB),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Log water, tea, coffee, or any drink today and Mira will build the timeline here.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF6E6257),
                        ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final metrics = _DrinkTimelineMetrics.forCount(drinks.length);
                    final horizontalInset = (constraints.maxWidth - metrics.rowWidth) / 2;
                    final lineLeft = horizontalInset +
                        metrics.labelWidth +
                        metrics.gap +
                        (metrics.iconSlotWidth / 2) -
                        1;
                    if (drinks.length <= 2) {
                      final lineEdgeInset = 4 + metrics.iconCenterOffset;

                      return Stack(
                        children: [
                          Positioned(
                            left: lineLeft,
                            top: lineEdgeInset,
                            bottom: lineEdgeInset,
                            child: Container(
                              width: 2,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE5D2C3),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: drinks.length,
                            separatorBuilder: (context, index) => SizedBox(
                              height: _timelineGapFor(drinks.length),
                            ),
                            itemBuilder: (context, index) => _DrinkTimelineNode(
                              entry: drinks[index],
                              drinkCount: drinks.length,
                            ),
                          ),
                        ],
                      );
                    }

                    final timelineLayout = _buildScaledTimelineLayout(
                      drinks: drinks,
                      metrics: metrics,
                      availableHeight: constraints.maxHeight,
                    );

                    return SingleChildScrollView(
                      child: SizedBox(
                        height: timelineLayout.contentHeight,
                        child: Stack(
                          children: [
                            Positioned(
                              left: lineLeft,
                              top: timelineLayout.centers.first,
                              height: timelineLayout.centers.last -
                                  timelineLayout.centers.first,
                              child: Container(
                                width: 2,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE5D2C3),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                            for (var index = 0; index < drinks.length; index++)
                              Positioned(
                                left: 0,
                                right: 0,
                                top: timelineLayout.centers[index] -
                                    metrics.iconCenterOffset,
                                child: _DrinkTimelineNode(
                                  entry: drinks[index],
                                  drinkCount: drinks.length,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  double _timelineGapFor(int count) {
    if (count <= 2) {
      return 10;
    }
    if (count <= 3) {
      return 14;
    }
    if (count <= 6) {
      return 10;
    }
    return 6;
  }

  _ScaledTimelineLayout _buildScaledTimelineLayout({
    required List<MealEntry> drinks,
    required _DrinkTimelineMetrics metrics,
    required double availableHeight,
  }) {
    final topInset = 8 + metrics.iconCenterOffset;
    final bottomInset = 16 + metrics.iconCenterOffset;
    final minCenterGap = metrics.nodeHeight + _timelineGapFor(drinks.length);
    final minContentHeight =
        topInset + bottomInset + ((drinks.length - 1) * minCenterGap);
    final firstTime = drinks.first.capturedAt;
    final lastTime = drinks.last.capturedAt;
    final totalMinutes = math.max(
      1,
      lastTime.difference(firstTime).inMinutes,
    ).toDouble();
    final desiredContentHeight = topInset + bottomInset + (totalMinutes * 0.22);
    final contentHeight = math.min(
      availableHeight,
      math.max(minContentHeight, desiredContentHeight),
    );
    final usableSpan = math.max(1.0, contentHeight - topInset - bottomInset);

    final centers = <double>[];
    for (var index = 0; index < drinks.length; index++) {
      final offsetMinutes = drinks[index].capturedAt.difference(firstTime).inMinutes.toDouble();
      final ratio = offsetMinutes / totalMinutes;
      centers.add(topInset + (ratio * usableSpan));
    }

    for (var index = 1; index < centers.length; index++) {
      final minCenter = centers[index - 1] + minCenterGap;
      if (centers[index] < minCenter) {
        centers[index] = minCenter;
      }
    }

    final maxLastCenter = contentHeight - bottomInset;
    final overflow = centers.last - maxLastCenter;
    if (overflow > 0) {
      for (var index = 0; index < centers.length; index++) {
        centers[index] -= overflow;
      }
    }

    if (centers.first < topInset) {
      final shift = topInset - centers.first;
      for (var index = 0; index < centers.length; index++) {
        centers[index] += shift;
      }
    }

    return _ScaledTimelineLayout(
      contentHeight: contentHeight,
      centers: centers,
    );
  }
}

class _DrinkTimelineNode extends StatelessWidget {
  const _DrinkTimelineNode({
    required this.entry,
    required this.drinkCount,
  });

  final MealEntry entry;
  final int drinkCount;

  @override
  Widget build(BuildContext context) {
    final accent = _accentColorFor(entry);
    final icon = _iconFor(entry);
    final metrics = _DrinkTimelineMetrics.forCount(drinkCount);

    return Center(
      child: SizedBox(
        width: metrics.rowWidth,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: metrics.labelWidth,
              child: Text(
                _formatTime(entry.capturedAt),
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF5A4337),
                      fontWeight: FontWeight.w700,
                      fontSize: metrics.fontSize,
                      letterSpacing: -0.1,
                    ),
              ),
            ),
            SizedBox(width: metrics.gap),
            SizedBox(
              width: metrics.iconSlotWidth,
              child: Center(
                child: Container(
                  padding: EdgeInsets.all(metrics.iconPadding),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Icon(
                    icon,
                    size: metrics.iconSize,
                    color: accent,
                  ),
                ),
              ),
            ),
            SizedBox(width: metrics.gap),
            SizedBox(
              width: metrics.labelWidth,
              child: Text(
                '${entry.drinkVolumeMl} mL',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                      fontSize: metrics.fontSize,
                      letterSpacing: -0.1,
                    ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime value) {
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.hour.toString().padLeft(2, '0')}:$minute';
  }

  IconData _iconFor(MealEntry entry) {
    final text = entry.displaySummary.toLowerCase();
    if (text.contains('water')) {
      return Icons.local_drink_outlined;
    }
    if (text.contains('coffee') || text.contains('espresso') || text.contains('latte')) {
      return Icons.coffee_outlined;
    }
    if (text.contains('tea') || text.contains('matcha')) {
      return Icons.emoji_food_beverage_outlined;
    }
    if (text.contains('coke') ||
        text.contains('cola') ||
        text.contains('soda') ||
        text.contains('soft drink')) {
      return Icons.wine_bar_outlined;
    }
    if (text.contains('juice') || text.contains('smoothie')) {
      return Icons.liquor_outlined;
    }
    return Icons.local_cafe_outlined;
  }

  Color _accentColorFor(MealEntry entry) {
    final text = entry.displaySummary.toLowerCase();
    if (text.contains('water')) {
      return const Color(0xFF4BA3C7);
    }
    if (text.contains('coffee') || text.contains('espresso') || text.contains('latte')) {
      return const Color(0xFF8A5A3C);
    }
    if (text.contains('tea') || text.contains('matcha')) {
      return const Color(0xFF7E6AB1);
    }
    if (text.contains('coke') ||
        text.contains('cola') ||
        text.contains('soda') ||
        text.contains('soft drink')) {
      return const Color(0xFFD24B43);
    }
    if (text.contains('juice') || text.contains('smoothie')) {
      return const Color(0xFFE0912D);
    }
    return const Color(0xFF5CA05C);
  }
}

class _DrinkTimelineMetrics {
  const _DrinkTimelineMetrics({
    required this.rowWidth,
    required this.labelWidth,
    required this.iconSlotWidth,
    required this.gap,
    required this.iconSize,
    required this.iconPadding,
    required this.fontSize,
  });

  final double rowWidth;
  final double labelWidth;
  final double iconSlotWidth;
  final double gap;
  final double iconSize;
  final double iconPadding;
  final double fontSize;

  double get iconCenterOffset => (iconSize + (iconPadding * 2)) / 2;
  double get nodeHeight => math.max(iconSize + (iconPadding * 2), fontSize + 8);

  static _DrinkTimelineMetrics forCount(int count) {
    if (count <= 2) {
      return const _DrinkTimelineMetrics(
        rowWidth: 212,
        labelWidth: 70,
        iconSlotWidth: 48,
        gap: 6,
        iconSize: 28,
        iconPadding: 6,
        fontSize: 13,
      );
    }
    if (count <= 3) {
      return const _DrinkTimelineMetrics(
        rowWidth: 236,
        labelWidth: 84,
        iconSlotWidth: 44,
        gap: 12,
        iconSize: 24,
        iconPadding: 6,
        fontSize: 13,
      );
    }
    if (count <= 6) {
      return const _DrinkTimelineMetrics(
        rowWidth: 214,
        labelWidth: 74,
        iconSlotWidth: 40,
        gap: 10,
        iconSize: 22,
        iconPadding: 5,
        fontSize: 12,
      );
    }
    return const _DrinkTimelineMetrics(
      rowWidth: 194,
      labelWidth: 66,
      iconSlotWidth: 36,
      gap: 8,
      iconSize: 20,
      iconPadding: 4,
      fontSize: 11,
    );
  }
}

class _ScaledTimelineLayout {
  const _ScaledTimelineLayout({
    required this.contentHeight,
    required this.centers,
  });

  final double contentHeight;
  final List<double> centers;
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({
    required this.selected,
    required this.referenceDate,
    required this.onChanged,
    required this.onPickDate,
  });

  final ReviewPeriod selected;
  final DateTime referenceDate;
  final ValueChanged<ReviewPeriod> onChanged;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SegmentedButton<ReviewPeriod>(
            segments: ReviewPeriod.values
                .map(
                  (period) => ButtonSegment<ReviewPeriod>(
                    value: period,
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        period.label,
                        softWrap: false,
                      ),
                    ),
                  ),
                )
                .toList(),
            selected: {selected},
            onSelectionChanged: (next) => onChanged(next.first),
          ),
        ),
        const SizedBox(width: 10),
        Tooltip(
          message: _formatReferenceDate(referenceDate),
          child: OutlinedButton(
            onPressed: onPickDate,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              minimumSize: const Size(52, 52),
            ),
            child: const Icon(Icons.calendar_month_outlined),
          ),
        ),
      ],
    );
  }

  String _formatReferenceDate(DateTime value) {
    return '${value.day}/${value.month}/${value.year}';
  }
}

class _CoachCard extends StatefulWidget {
  const _CoachCard({
    required this.note,
    required this.period,
    required this.onChat,
  });

  final String note;
  final ReviewPeriod period;
  final VoidCallback onChat;

  @override
  State<_CoachCard> createState() => _CoachCardState();
}

class _CoachCardState extends State<_CoachCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final preview = widget.note.length > 140
        ? '${widget.note.substring(0, 140).trimRight()}...'
        : widget.note;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFFF1D8C6),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.auto_awesome_rounded),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mira\'s review for this ${widget.period.label.toLowerCase()}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _expanded ? widget.note : preview,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF6E6257),
                          height: 1.5,
                        ),
                  ),
                  if (widget.note.length > 140) ...[
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _expanded = !_expanded;
                        });
                      },
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _expanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 18,
                          ),
                          const SizedBox(width: 2),
                          Text(_expanded ? 'Collapse' : 'Read more'),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: widget.onChat,
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: const Text('Chat with Mira'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyTimelineGuide extends StatelessWidget {
  const _EmptyTimelineGuide({required this.onAddMeal});

  final VoidCallback onAddMeal;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No meals yet in this period',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              'A strong first log looks like this:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF6E6257),
                  ),
            ),
            const SizedBox(height: 14),
            const _GuideRow(
              icon: Icons.photo_library_outlined,
              text: 'Add one or more meal photos from camera or gallery.',
            ),
            const _GuideRow(
              icon: Icons.auto_awesome,
              text: 'Let Mira suggest the meal summary and calories.',
            ),
            const _GuideRow(
              icon: Icons.edit_outlined,
              text: 'Keep your own edits even if you change images and re-run analysis later.',
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onAddMeal,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Log your first meal'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideRow extends StatelessWidget {
  const _GuideRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({
    required this.entry,
    required this.onEdit,
  });

  final MealEntry entry;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.mealType.label,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatDateTime(entry.capturedAt),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF6E6257),
                            ),
                      ),
                    ],
                  ),
                ),
                if (entry.aiReview.trim().isNotEmpty)
                  IconButton(
                    onPressed: () => _showAiReview(context),
                    tooltip: 'Mira review',
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    icon: const Icon(Icons.auto_awesome_outlined),
                  ),
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5E5D8),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${entry.userEstimatedCalories} kcal',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            if (entry.imagePaths.isNotEmpty) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (context, index) {
                    final path = entry.imagePaths[index];
                    return GestureDetector(
                      onTap: () => _showImageGallery(context, index),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.file(
                          MealRepository.fileFromStoredPath(path),
                          width: 140,
                          cacheWidth: 420,
                          cacheHeight: 360,
                          filterQuality: FilterQuality.low,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 140,
                              color: const Color(0xFFF1E7DE),
                              alignment: Alignment.center,
                              child: const Text('Image unavailable'),
                            );
                          },
                        ),
                      ),
                    );
                  },
                  separatorBuilder: (context, index) => const SizedBox(width: 10),
                  itemCount: entry.imagePaths.length,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              entry.displaySummary,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            if ((entry.mealType == MealType.drink && entry.drinkVolumeMl > 0) ||
                entry.isSharedMeal ||
                entry.isSummaryOverridden ||
                entry.isCaloriesOverridden) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (entry.mealType == MealType.drink && entry.drinkVolumeMl > 0)
                    _InfoChip(label: '${entry.drinkVolumeMl} mL'),
                  if (entry.isSharedMeal)
                    _InfoChip(
                      label:
                          'Shared with ${entry.sharedMealPeopleCount} • You ate ${entry.userPortionPercent}%',
                    ),
                  if (entry.isSummaryOverridden || entry.isCaloriesOverridden)
                    const _InfoChip(label: 'User edited'),
                ],
              ),
              const SizedBox(height: 12),
            ] else
              const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF3ECE5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (entry.isSharedMeal) ...[
                    Text(
                      'Whole table: ${entry.totalEstimatedCalories} kcal',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF7A5A45),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      _StarDisplay(rating: entry.feelingRating),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          entry.feelingNote.isEmpty
                              ? entry.feelingLabel
                              : entry.feelingNote,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '${value.day}/${value.month}/${value.year} at $hour:$minute $suffix';
  }

  void _showAiReview(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mira\'s meal review',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              entry.aiReview,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF4E4038),
                    height: 1.5,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  void _showImageGallery(BuildContext context, int initialIndex) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => _MealImageGallery(
        imagePaths: entry.imagePaths,
        initialIndex: initialIndex,
      ),
    );
  }
}

class _MealImageGallery extends StatefulWidget {
  const _MealImageGallery({
    required this.imagePaths,
    required this.initialIndex,
  });

  final List<String> imagePaths;
  final int initialIndex;

  @override
  State<_MealImageGallery> createState() => _MealImageGalleryState();
}

class _MealImageGalleryState extends State<_MealImageGallery> {
  late final PageController _pageController = PageController(
    initialPage: widget.initialIndex,
  );
  late int _currentIndex = widget.initialIndex;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: widget.imagePaths.length,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemBuilder: (context, index) {
                final path = widget.imagePaths[index];
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: Image.file(
                      MealRepository.fileFromStoredPath(path),
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Text(
                          'Image unavailable',
                          style: TextStyle(color: Colors.white70),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
            Positioned(
              top: 12,
              left: 12,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.of(context).pop(),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white12,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.close),
              ),
            ),
            Positioned(
              top: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_currentIndex + 1} / ${widget.imagePaths.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF3EC),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label),
    );
  }
}

class _StarDisplay extends StatelessWidget {
  const _StarDisplay({required this.rating});

  final int rating;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return Icon(
          index < rating ? Icons.star_rounded : Icons.star_border_rounded,
          size: 18,
          color: const Color(0xFFB85C38),
        );
      }),
    );
  }
}

class _DietGoalEditorSheet extends StatefulWidget {
  const _DietGoalEditorSheet({
    required this.initialMission,
  });

  final String initialMission;

  @override
  State<_DietGoalEditorSheet> createState() => _DietGoalEditorSheetState();
}

class _DietGoalEditorSheetState extends State<_DietGoalEditorSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialMission,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 8, 20, bottomInset + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Diet mission',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Write the outcome you want from this diet. Meal Mirror saves the full mission locally and only reuses a short Mira brief after you update it.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF6E6257),
                ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            minLines: 4,
            maxLines: 8,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              labelText: 'Mission / goal',
              hintText:
                  'Example: Lose body fat steadily, reduce late-night snacking, and keep meals satisfying enough to avoid overeating.',
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
              child: const Text('Save mission'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MealEditorSheet extends StatefulWidget {
  const _MealEditorSheet({
    required this.picker,
    required this.analysisService,
    required this.dietGoalBrief,
    required this.recentEntries,
    this.existing,
    this.seed,
    this.autoPickSource,
  });

  final ImagePicker picker;
  final MealAnalysisService analysisService;
  final String dietGoalBrief;
  final MealEntry? existing;
  final _MealEditorSeed? seed;
  final ImageSource? autoPickSource;
  final List<MealEntry> recentEntries;

  @override
  State<_MealEditorSheet> createState() => _MealEditorSheetState();
}

class _MealEditorSheetState extends State<_MealEditorSheet> {
  static const _maxImagesPerMeal = 5;

  late final TextEditingController _summaryController;
  late final TextEditingController _feelingController;
  late final TextEditingController _drinkVolumeController;
  late final TextEditingController _peopleCountController;
  late final bool _isEditing = widget.existing != null;
  late final _MealEditorSeed? _seed = widget.seed;
  late DateTime _capturedAt =
      widget.existing?.capturedAt ?? _seed?.capturedAt ?? DateTime.now();
  late MealType _mealType =
      widget.existing?.mealType ?? _seed?.mealType ?? _defaultMealTypeFor(_capturedAt);
  late int _feelingRating = widget.existing?.feelingRating ?? _seed?.feelingRating ?? 3;
  late List<_MealImageSource> _imageSources = [
    for (final path in widget.existing?.imagePaths ?? const <String>[])
      _ExistingImageSource(path),
  ];

  String _aiSuggestedSummary = '';
  int _aiSuggestedCalories = 0;
  String _aiReview = '';
  String _debugLastAiResult = '';
  bool _summaryWasEdited = false;
  bool _isSharedMeal = false;
  int _userPortionPercent = 100;
  bool _userPortionWasEdited = false;
  bool _isAnalyzing = false;
  bool _suppressControllerListeners = false;
  bool _didAutoPickImage = false;
  late final DateTime _initialCapturedAt = widget.existing?.capturedAt ?? _capturedAt;
  late final MealType _initialMealType = widget.existing?.mealType ?? _mealType;
  late final int _initialFeelingRating = widget.existing?.feelingRating ?? _feelingRating;
  late final int _initialDrinkVolumeMl =
      widget.existing?.drinkVolumeMl ?? _seed?.drinkVolumeMl ?? 0;
  late final bool _initialIsSharedMeal = widget.existing?.isSharedMeal ?? false;
  late final int _initialSharedMealPeopleCount =
      widget.existing?.sharedMealPeopleCount ?? 1;
  late final int _initialUserPortionPercent =
      widget.existing?.userPortionPercent ?? 100;
  late final bool _initialUserPortionWasEdited =
      widget.existing?.isSharedMeal == true;
  late final List<String> _initialImagePaths = [
    for (final path in widget.existing?.imagePaths ?? const <String>[]) path,
  ];
  late final String _initialSummary =
      widget.existing?.displaySummary.trim() ?? _seed?.summary.trim() ?? '';
  late final String _initialFeelingNote =
      widget.existing?.feelingNote.isNotEmpty == true
          ? widget.existing!.feelingNote.trim()
          : (_seed?.feelingNote.trim().isNotEmpty == true
                ? _seed!.feelingNote.trim()
                : _feelingLabel(_initialFeelingRating).trim());

  @override
  void initState() {
    super.initState();
    _aiSuggestedSummary = widget.existing?.aiSuggestedSummary ?? '';
    _aiSuggestedCalories = widget.existing?.aiSuggestedCalories ?? 0;
    _aiReview = widget.existing?.aiReview ?? '';
    _isSharedMeal = widget.existing?.isSharedMeal ?? false;
    _userPortionPercent = widget.existing?.userPortionPercent ?? 100;
    _userPortionWasEdited = widget.existing?.isSharedMeal ?? false;

    _summaryController = TextEditingController(
      text: widget.existing?.displaySummary ?? _seed?.summary ?? '',
    );
    _feelingController = TextEditingController(
      text: widget.existing?.feelingNote.isNotEmpty == true
          ? widget.existing!.feelingNote
          : (_seed?.feelingNote.isNotEmpty == true
                ? _seed!.feelingNote
                : _feelingLabel(_feelingRating)),
    );
    _drinkVolumeController = TextEditingController(
      text: (widget.existing?.drinkVolumeMl ?? 0) > 0
          ? '${widget.existing!.drinkVolumeMl}'
          : (_seed?.drinkVolumeMl ?? 0) > 0
              ? '${_seed!.drinkVolumeMl}'
          : '',
    );
    _peopleCountController = TextEditingController(
      text: '${widget.existing?.sharedMealPeopleCount ?? 2}',
    );

    _summaryWasEdited =
        widget.existing?.isSummaryOverridden ?? ((_seed?.summary.trim().isNotEmpty ?? false));

    _summaryController.addListener(() {
      if (_suppressControllerListeners) {
        return;
      }
      _summaryWasEdited = _summaryController.text.trim() != _aiSuggestedSummary.trim();
      if (mounted) {
        setState(() {});
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isEditing || _didAutoPickImage || widget.autoPickSource == null) {
        return;
      }
      _didAutoPickImage = true;
      _addImage(widget.autoPickSource!);
    });
  }

  @override
  void dispose() {
    _summaryController.dispose();
    _feelingController.dispose();
    _drinkVolumeController.dispose();
    _peopleCountController.dispose();
    super.dispose();
  }

  Future<void> _addImage(ImageSource source) async {
    if (_remainingImageSlots <= 0) {
      _showEditorSnackBar('You can add up to $_maxImagesPerMeal photos per meal.');
      return;
    }

    final pickedFiles = <XFile>[];
    if (source == ImageSource.gallery) {
      final files = await widget.picker.pickMultiImage();
      pickedFiles.addAll(files.take(_remainingImageSlots));
      if (files.length > _remainingImageSlots && mounted) {
        _showEditorSnackBar(
          'Only the first $_remainingImageSlots photos were added. Max $_maxImagesPerMeal per meal.',
        );
      }
    } else {
      final file = await widget.picker.pickImage(
        source: source,
      );
      if (file != null) {
        pickedFiles.add(file);
      }
    }

    if (pickedFiles.isEmpty || !mounted) {
      return;
    }

    setState(() {
      _imageSources = [
        ..._imageSources,
        ...pickedFiles.map(_PickedImageSource.new),
      ];
    });

    await _reanalyzeImages();
  }

  Future<void> _pickMealTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _capturedAt,
      firstDate: DateTime.now().subtract(const Duration(days: 3650)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (pickedDate == null || !mounted) {
      return;
    }

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_capturedAt),
    );

    if (pickedTime == null || !mounted) {
      return;
    }

    final nextCapturedAt = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    setState(() {
      _capturedAt = nextCapturedAt;
    });
  }

  Future<void> _reanalyzeImages() async {
    if (_imageSources.isEmpty) {
      setState(() {
        _aiSuggestedCalories = 0;
        _aiReview = '';
        _debugLastAiResult = '';
      });
      return;
    }

    final allImages = [
      for (final image in _imageSources) image.asXFile(),
    ];

    setState(() {
      _isAnalyzing = true;
    });

    try {
      final userContext = _buildAiUserContext(
        includeSummary: _summaryWasEdited,
      );
      final suggestion = await widget.analysisService.analyzeMeal(
        images: allImages,
        mealType: _mealType,
        capturedAt: _capturedAt,
        dietGoalBrief: widget.dietGoalBrief,
        userEditedSummary: userContext,
      );

      _aiSuggestedSummary = suggestion.summary;
      _aiSuggestedCalories = suggestion.estimatedCalories;
      _aiReview = suggestion.review;
      _applyDetectedDrinkDetails(suggestion);
      _debugLastAiResult = _buildDebugSummary(suggestion);
      debugPrint(
        'MEAL_MIRROR_OPENAI_RESULT summary="${suggestion.summary}" '
        'calories=${suggestion.estimatedCalories} review="${suggestion.review}"',
      );

      _suppressControllerListeners = true;
      _summaryController.text = suggestion.summary;
      _summaryWasEdited = false;
      _suppressControllerListeners = false;

      if (!mounted) {
        return;
      }

      setState(() {
        _isAnalyzing = false;
      });
    } catch (error) {
      debugPrint('MEAL_MIRROR_OPENAI_ERROR $error');
      if (!mounted) {
        return;
      }
      setState(() {
        _isAnalyzing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyAnalysisError(error)),
        ),
      );
    }
  }

  Future<void> _estimateFromSummary() async {
    final summary = _summaryController.text.trim();
    if (summary.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _mealType == MealType.drink
                ? 'Write what you drank first, then ask Mira to estimate calories.'
                : 'Write what you ate first, then ask Mira to estimate calories.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _isAnalyzing = true;
    });

    try {
      final userContext = _buildAiUserContext(includeSummary: true);
      final suggestion = await widget.analysisService.analyzeMeal(
        images: [
          for (final image in _imageSources) image.asXFile(),
        ],
        mealType: _mealType,
        capturedAt: _capturedAt,
        dietGoalBrief: widget.dietGoalBrief,
        userEditedSummary: userContext,
      );

      _aiSuggestedSummary = suggestion.summary;
      _aiSuggestedCalories = suggestion.estimatedCalories;
      _aiReview = suggestion.review;
      _applyDetectedDrinkDetails(suggestion);
      _debugLastAiResult = _buildDebugSummary(suggestion);
      debugPrint(
        'MEAL_MIRROR_OPENAI_RESULT summary="${suggestion.summary}" '
        'calories=${suggestion.estimatedCalories} review="${suggestion.review}"',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isAnalyzing = false;
      });
    } catch (error) {
      debugPrint('MEAL_MIRROR_OPENAI_ERROR $error');
      if (!mounted) {
        return;
      }
      setState(() {
        _isAnalyzing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyAnalysisError(error)),
        ),
      );
    }
  }

  void _removeImage(int index) {
    setState(() {
      _imageSources = [..._imageSources]..removeAt(index);
    });

    _reanalyzeImages();
  }

  void _applyRecentEntry(MealEntry entry) {
    _suppressControllerListeners = true;
    _summaryController.text = entry.displaySummary;
    _suppressControllerListeners = false;

    setState(() {
      _mealType = entry.mealType;
      _feelingRating = entry.feelingRating;
      _summaryWasEdited = true;
      _debugLastAiResult = '';
      if (entry.mealType == MealType.drink && entry.drinkVolumeMl > 0) {
        _drinkVolumeController.text = '${entry.drinkVolumeMl}';
      }
      if (_feelingController.text.trim().isEmpty ||
          _feelingController.text.trim() == _feelingLabel(_feelingRating)) {
        _feelingController.text = entry.feelingNote;
      }
    });
  }

  void _save() {
    final summary = _summaryController.text.trim();
    final calories = _aiSuggestedCalories;
    final drinkVolumeMl = int.tryParse(_drinkVolumeController.text.trim()) ?? 0;

    if (summary.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a meal description or wait for Mira to finish the estimate.'),
        ),
      );
      return;
    }

    if (_mealType == MealType.drink && drinkVolumeMl <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add the drink volume in mL so hydration can be tracked.'),
        ),
      );
      return;
    }

    Navigator.of(context).pop(
      _MealDraft(
        mealType: _mealType,
        capturedAt: _capturedAt,
        feelingRating: _feelingRating,
        feelingNote: _feelingController.text.trim(),
        drinkVolumeMl: drinkVolumeMl,
        imageSources: _imageSources,
        aiSuggestedSummary: _aiSuggestedSummary.isEmpty ? summary : _aiSuggestedSummary,
        aiSuggestedCalories:
            _aiSuggestedCalories == 0 ? calories : _aiSuggestedCalories,
        aiReview: _aiReview,
        isSharedMeal: _isSharedMeal,
        sharedMealPeopleCount: _sharedMealPeopleCount,
        userPortionPercent: _userPortionPercent,
        summaryInput: summary,
        caloriesInput: calories,
        summaryWasEdited: _summaryWasEdited,
      ),
    );
  }

  bool get _hasUnsavedChanges {
    final currentImagePaths = _imageSources
        .map(
          (image) => switch (image) {
            _ExistingImageSource(path: final path) => path,
            _PickedImageSource(file: final file) => file.path,
          },
        )
        .toList();

    if (!_sameItems(_initialImagePaths, currentImagePaths)) {
      return true;
    }

    return _capturedAt != _initialCapturedAt ||
        _mealType != _initialMealType ||
        _feelingRating != _initialFeelingRating ||
        (int.tryParse(_drinkVolumeController.text.trim()) ?? 0) != _initialDrinkVolumeMl ||
        _isSharedMeal != _initialIsSharedMeal ||
        _sharedMealPeopleCount != _initialSharedMealPeopleCount ||
        _userPortionPercent != _initialUserPortionPercent ||
        _userPortionWasEdited != _initialUserPortionWasEdited ||
        _summaryController.text.trim() != _initialSummary ||
        _feelingController.text.trim() != _initialFeelingNote;
  }

  int get _remainingImageSlots => _maxImagesPerMeal - _imageSources.length;

  void _showEditorSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _attemptDismiss() async {
    if (!_hasUnsavedChanges) {
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
          'You have unsaved meal changes. If you go back now, those edits will be lost.',
        ),
        actions: [
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    if (discard == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final canEstimateFromCurrentInput =
        _summaryController.text.trim().isNotEmpty && !_isAnalyzing && _summaryWasEdited;
    final estimationStatusText = _imageSources.isNotEmpty
        ? 'Analyzing meal details...'
        : 'Estimating calories...';
    final displayedCalories = _displayedCalories;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        await _attemptDismiss();
      },
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, bottomInset + 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
            Row(
              children: [
                IconButton(
                  onPressed: _attemptDismiss,
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  tooltip: 'Back',
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _isEditing ? 'Edit meal' : 'Log a meal',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                TextButton(
                  onPressed: _attemptDismiss,
                  child: const Text('Close'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _mealType == MealType.drink
                  ? 'Add a drink photo or log it manually.'
                  : 'Add a meal photo or log it manually.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF6E6257),
                  ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed:
                      _isAnalyzing || _remainingImageSlots <= 0
                          ? null
                          : () => _addImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Camera'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _isAnalyzing || _remainingImageSlots <= 0
                          ? null
                          : () => _addImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Gallery'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${_imageSources.length}/$_maxImagesPerMeal photos',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF8A7468),
                  ),
            ),
            if (!_isEditing && widget.recentEntries.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                _mealType == MealType.drink ? 'Recent drinks' : 'Recent meals',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: const Color(0xFF7A5A45),
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in widget.recentEntries.where(
                    (entry) => entry.mealType == _mealType,
                  ))
                    ActionChip(
                      onPressed: _isAnalyzing ? null : () => _applyRecentEntry(entry),
                      label: Text(_quickEntryLabel(entry)),
                    ),
                ],
              ),
            ],
            if (_imageSources.isNotEmpty) ...[
              const SizedBox(height: 14),
              SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (context, index) {
                    final image = _imageSources[index];
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: image.buildPreview(),
                        ),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: GestureDetector(
                            onTap: () => _removeImage(index),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                  separatorBuilder: (context, index) => const SizedBox(width: 10),
                  itemCount: _imageSources.length,
                ),
              ),
            ],
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _isAnalyzing ? null : _pickMealTime,
              icon: const Icon(Icons.schedule),
              label: Text('Meal time: ${_formatMealTime(_capturedAt)}'),
            ),
            const SizedBox(height: 14),
            _EditorSectionLabel(
              label: 'Meal type',
              hint: 'Pick the moment that fits this log best.',
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in MealType.values)
                  _MealTypeChip(
                    label: type.label,
                    icon: switch (type) {
                      MealType.breakfast => Icons.wb_sunny_outlined,
                      MealType.lunch => Icons.ramen_dining_outlined,
                      MealType.dinner => Icons.nightlight_round,
                      MealType.snack => Icons.cookie_outlined,
                      MealType.drink => Icons.local_drink_outlined,
                    },
                    selected: _mealType == type,
                    onTap: _isAnalyzing
                        ? null
                        : () {
                            setState(() {
                              _mealType = type;
                            });
                          },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _EditorSectionLabel(
              label: _mealType == MealType.drink ? 'What did you drink?' : 'What did you eat?',
              hint: 'Mira can suggest this for you, but you can shape it in your own words.',
            ),
            const SizedBox(height: 10),
            _StyledEditorField(
              controller: _summaryController,
              keyboardType: TextInputType.multiline,
              minLines: 4,
              maxLines: null,
              hintText: _mealType == MealType.drink
                  ? 'Cold water, half-full glass, after lunch...'
                  : 'Rice, grilled chicken, greens, small soup...'
            ),
            if (_mealType != MealType.drink) ...[
              const SizedBox(height: 14),
              SwitchListTile.adaptive(
                value: _isSharedMeal,
                onChanged: _isAnalyzing
                    ? null
                    : (value) {
                        setState(() {
                          _isSharedMeal = value;
                          if (!_isSharedMeal) {
                            _peopleCountController.text = '1';
                            _userPortionPercent = 100;
                            _userPortionWasEdited = false;
                          } else if (_peopleCountController.text.trim().isEmpty ||
                              _peopleCountController.text.trim() == '1') {
                            _peopleCountController.text = '2';
                            _syncUserPortionWithPeopleCount();
                          } else {
                            _syncUserPortionWithPeopleCount();
                          }
                        });
                      },
                contentPadding: EdgeInsets.zero,
                title: const Text('Shared meal'),
                subtitle: const Text(
                  'Turn this on if the photo shows dishes for multiple people.',
                ),
              ),
              if (_isSharedMeal) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _peopleCountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'People sharing the meal',
                    hintText: 'Example: 4',
                  ),
                  onChanged: (_) {
                    if (_userPortionWasEdited) {
                      setState(() {});
                      return;
                    }
                    setState(() {
                      _syncUserPortionWithPeopleCount();
                    });
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  'How much did you personally eat?',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: const Color(0xFF7A5A45),
                      ),
                ),
                Slider(
                  value: _userPortionPercent.toDouble(),
                  min: 10,
                  max: 100,
                  divisions: 18,
                  label: '$_userPortionPercent%',
                  onChanged: _isAnalyzing
                      ? null
                      : (value) {
                          setState(() {
                            _userPortionPercent = value.round();
                            _userPortionWasEdited = true;
                          });
                        },
                ),
                Text(
                  _portionLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF6E6257),
                      ),
                ),
              ],
            ],
            if (_mealType == MealType.drink) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _drinkVolumeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Drink volume (mL)',
                  hintText: 'Example: 350',
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final amount in const [50, 100, 150, 200, 250])
                    ChoiceChip(
                      label: Text('$amount mL'),
                      selected: _drinkVolumeController.text.trim() == '$amount',
                      onSelected: (_) {
                        setState(() {
                          _drinkVolumeController.text = '$amount';
                        });
                      },
                    ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFFAF6F1),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFEEE3D7)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Estimated calories',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: const Color(0xFF7A5A45),
                              ),
                        ),
                      ),
                      if (_isAnalyzing)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF2E8DD),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _imageSources.isNotEmpty
                                    ? 'Updating...'
                                    : 'Estimating...',
                                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                      color: const Color(0xFF8E6F5C),
                                    ),
                              ),
                            ],
                          ),
                        )
                      else if (canEstimateFromCurrentInput)
                        InkWell(
                          onTap: _estimateFromSummary,
                          borderRadius: BorderRadius.circular(999),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.auto_awesome_outlined,
                                  size: 14,
                                  color: _isAnalyzing
                                      ? const Color(0xFFB9ADA2)
                                      : const Color(0xFF8E6F5C),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Estimate',
                                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                        color: _isAnalyzing
                                            ? const Color(0xFFB9ADA2)
                                            : const Color(0xFF8E6F5C),
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_isAnalyzing)
                    Text(
                      estimationStatusText,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF7A5A45),
                          ),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _aiSuggestedCalories > 0
                              ? '$displayedCalories kcal'
                              : _imageSources.isNotEmpty
                                  ? 'Waiting for Mira'
                                  : 'No estimate yet',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF5F4C40),
                              ),
                        ),
                        if (_aiSuggestedCalories > 0 && _isSharedMeal) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Whole table: $_aiSuggestedCalories kcal • Your share: $displayedCalories kcal',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF7A5A45),
                                ),
                          ),
                        ],
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (_debugLastAiResult.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F7FB),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFD6E2EE)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mira debug',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _debugLastAiResult,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],
            Text(
              'How did you feel?',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            _StarRatingInput(
              rating: _feelingRating,
              onChanged: (rating) {
                setState(() {
                  _feelingRating = rating;
                  if (_feelingController.text.trim().isEmpty ||
                      _feelingController.text.trim() == _feelingLabel(_feelingRating)) {
                    _feelingController.text = _feelingLabel(rating);
                  }
                });
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _feelingController,
              decoration: const InputDecoration(
                labelText: 'Feeling note',
                hintText: 'Example: Too full, satisfied, light, sleepy',
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isAnalyzing ? null : _save,
                child: Text(_isEditing ? 'Save changes' : 'Save meal'),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatMealTime(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '${value.day}/${value.month}/${value.year} $hour:$minute $suffix';
  }

  String _feelingLabel(int rating) {
    switch (rating) {
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
        return 'Okay';
    }
  }

  String _friendlyAnalysisError(Object error) {
    final message = error.toString().toLowerCase();

    if (message.contains('401') || message.contains('403')) {
      return 'Mira could not start because the OpenAI key was rejected.';
    }

    if (message.contains('429')) {
      return 'Mira is currently busy. Please wait a moment and try again.';
    }

    if (message.contains('500') ||
        message.contains('502') ||
        message.contains('503') ||
        message.contains('504')) {
      return 'Mira is temporarily unavailable. Please try again shortly.';
    }

    if (message.contains('socket') ||
        message.contains('network') ||
        message.contains('connection') ||
        message.contains('clientexception')) {
      return 'Could not reach Mira. Please check your connection and try again.';
    }

    if (message.contains('output_text') || message.contains('parse')) {
      return 'Mira returned an unexpected result. Please try again with clearer meal photos.';
    }

    return 'Mira could not finish this meal estimate. Please try again.';
  }

  bool _sameItems(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }

    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }

    return true;
  }

  String? _buildAiUserContext({required bool includeSummary}) {
    final parts = <String>[];
    final summary = _summaryController.text.trim();
    final drinkVolumeMl = int.tryParse(_drinkVolumeController.text.trim()) ?? 0;

    if (includeSummary && summary.isNotEmpty) {
      parts.add(summary);
    }

    if (_mealType == MealType.drink && drinkVolumeMl > 0) {
      parts.add('Drink volume: $drinkVolumeMl mL');
    }

    if (_isSharedMeal && _mealType != MealType.drink) {
      parts.add(
        'Shared meal for about $_sharedMealPeopleCount people. My portion was about $_userPortionPercent percent of the full meal.',
      );
    }

    if (parts.isEmpty) {
      return null;
    }

    return parts.join('. ');
  }

  void _applyDetectedDrinkDetails(MealAnalysisSuggestion suggestion) {
    final detectedType = suggestion.detectedMealType;
    if (detectedType == MealType.drink) {
      _mealType = MealType.drink;
      final estimatedVolume = suggestion.estimatedDrinkVolumeMl ?? 0;
      if (estimatedVolume > 0 && _drinkVolumeController.text.trim().isEmpty) {
        _drinkVolumeController.text = '$estimatedVolume';
      }
      return;
    }

    if (_mealType == MealType.drink && suggestion.estimatedDrinkVolumeMl == null) {
      return;
    }

    if (detectedType != null && _imageSources.isNotEmpty) {
      _mealType = detectedType;
    }
  }

  String _buildDebugSummary(MealAnalysisSuggestion suggestion) {
    final usage = suggestion.debug;
    final lines = <String>[
      'Summary: ${suggestion.summary}',
      'Calories: ${suggestion.estimatedCalories}',
      'Review: ${suggestion.review}',
      if (suggestion.detectedMealType != null)
        'Detected type: ${suggestion.detectedMealType!.label}',
      if ((suggestion.estimatedDrinkVolumeMl ?? 0) > 0)
        'Estimated drink volume: ${suggestion.estimatedDrinkVolumeMl} mL',
      if (_isSharedMeal) 'Your portion: $_displayedCalories kcal ($_userPortionPercent%)',
    ];

    if (usage != null) {
      lines.add('Images: ${usage.imageCount}');
      lines.add('Response time: ${usage.responseTimeMs} ms');
      lines.add(
        'Tokens: input ${usage.inputTokens?.toString() ?? '-'}, '
        'output ${usage.outputTokens?.toString() ?? '-'}, '
        'total ${usage.totalTokens?.toString() ?? '-'}',
      );
    }

    return lines.join('\n');
  }

  MealType _defaultMealTypeFor(DateTime value) {
    final hour = value.hour;
    if (hour < 10) {
      return MealType.breakfast;
    }
    if (hour < 15) {
      return MealType.lunch;
    }
    if (hour < 21) {
      return MealType.dinner;
    }
    return MealType.snack;
  }

  String _quickEntryLabel(MealEntry entry) {
    final summary = entry.displaySummary.trim();
    if (entry.mealType == MealType.drink && entry.drinkVolumeMl > 0) {
      return '$summary • ${entry.drinkVolumeMl} mL';
    }
    return summary;
  }

  int get _sharedMealPeopleCount {
    if (!_isSharedMeal) {
      return 1;
    }
    final parsed = int.tryParse(_peopleCountController.text.trim()) ?? 1;
    return parsed < 2 ? 2 : parsed;
  }

  int get _displayedCalories {
    if (!_isSharedMeal) {
      return _aiSuggestedCalories;
    }
    return ((_aiSuggestedCalories * _userPortionPercent) / 100).round();
  }

  String get _portionLabel {
    if (_userPortionPercent <= 25) {
      return 'A light share';
    }
    if (_userPortionPercent <= 50) {
      return 'About half a normal plate';
    }
    if (_userPortionPercent <= 75) {
      return 'A generous share';
    }
    return 'Most of the meal';
  }

  void _syncUserPortionWithPeopleCount() {
    if (!_isSharedMeal || _userPortionWasEdited) {
      return;
    }
    _userPortionPercent = (100 / _sharedMealPeopleCount).round().clamp(10, 100);
  }
}

sealed class _MealImageSource {
  Widget buildPreview();
  XFile asXFile();
}

class _ExistingImageSource extends _MealImageSource {
  _ExistingImageSource(this.path);

  final String path;

  @override
  Widget buildPreview() {
    return Image.file(
      MealRepository.fileFromStoredPath(path),
      width: 140,
      height: 120,
      cacheWidth: 420,
      cacheHeight: 360,
      filterQuality: FilterQuality.low,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: 140,
          height: 120,
          color: const Color(0xFFF1E7DE),
          alignment: Alignment.center,
          child: const Text('Image unavailable'),
        );
      },
    );
  }

  @override
  XFile asXFile() => XFile(path);
}

class _PickedImageSource extends _MealImageSource {
  _PickedImageSource(this.file);

  final XFile file;

  @override
  Widget buildPreview() {
    return Image.file(
      MealRepository.fileFromStoredPath(file.path),
      width: 140,
      height: 120,
      cacheWidth: 420,
      cacheHeight: 360,
      filterQuality: FilterQuality.low,
      fit: BoxFit.cover,
    );
  }

  @override
  XFile asXFile() => file;
}

class _StarRatingInput extends StatelessWidget {
  const _StarRatingInput({
    required this.rating,
    required this.onChanged,
  });

  final int rating;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(5, (index) {
        final star = index + 1;
        return IconButton(
          onPressed: () => onChanged(star),
          icon: Icon(
            star <= rating ? Icons.star_rounded : Icons.star_border_rounded,
            color: const Color(0xFFB85C38),
            size: 30,
          ),
        );
      }),
    );
  }
}

class _MealDraft {
  const _MealDraft({
    required this.mealType,
    required this.capturedAt,
    required this.feelingRating,
    required this.feelingNote,
    required this.drinkVolumeMl,
    required this.imageSources,
    required this.aiSuggestedSummary,
    required this.aiSuggestedCalories,
    required this.aiReview,
    required this.isSharedMeal,
    required this.sharedMealPeopleCount,
    required this.userPortionPercent,
    required this.summaryInput,
    required this.caloriesInput,
    required this.summaryWasEdited,
  });

  final MealType mealType;
  final DateTime capturedAt;
  final int feelingRating;
  final String feelingNote;
  final int drinkVolumeMl;
  final List<_MealImageSource> imageSources;
  final String aiSuggestedSummary;
  final int aiSuggestedCalories;
  final String aiReview;
  final bool isSharedMeal;
  final int sharedMealPeopleCount;
  final int userPortionPercent;
  final String summaryInput;
  final int caloriesInput;
  final bool summaryWasEdited;

  String get displaySummary => summaryInput;
  int get displayCalories => caloriesInput;
}

class _MealEditorSeed {
  const _MealEditorSeed({
    required this.mealType,
    required this.capturedAt,
    required this.summary,
    required this.feelingRating,
    required this.feelingNote,
    required this.drinkVolumeMl,
  });

  final MealType mealType;
  final DateTime capturedAt;
  final String summary;
  final int feelingRating;
  final String feelingNote;
  final int drinkVolumeMl;
}

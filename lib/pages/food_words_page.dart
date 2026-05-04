import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/food_word.dart';
import '../services/meal_repository.dart';

class FoodWordsPage extends StatefulWidget {
  const FoodWordsPage({
    super.key,
    required this.words,
    required this.onDeleteWord,
    this.initialOpenWordId,
  });

  final List<FoodWord> words;
  final Future<void> Function(FoodWord word) onDeleteWord;
  final String? initialOpenWordId;

  @override
  State<FoodWordsPage> createState() => _FoodWordsPageState();
}

class _FoodWordsPageState extends State<FoodWordsPage> {
  late List<FoodWord> _words = [...widget.words];

  @override
  void initState() {
    super.initState();
    if (widget.initialOpenWordId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          final initialWord =
              _words.firstWhere((w) => w.id == widget.initialOpenWordId);
          if (mounted) {
            _showWordDetails(context, initialWord);
          }
        } catch (_) {}
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sortedWords = [..._words]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          tooltip: 'Back',
        ),
        title: const Text('My food words'),
      ),
      body: sortedWords.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Save useful food and cooking words from your meals, and they will show up here.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              itemCount: sortedWords.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final word = sortedWords[index];
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE7D8CB)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    word.term,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF6E9DD),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    word.category,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF8A664F),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (word.definition.trim().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                word.definition,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: const Color(0xFF5F5148),
                                    ),
                              ),
                            ],
                            if (word.examples.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: () =>
                                    _showWordDetails(context, word),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(
                                  Icons.open_in_new_rounded,
                                  size: 16,
                                ),
                                label: const Text('View more'),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        onPressed: () async {
                          await widget.onDeleteWord(word);
                          if (!mounted) {
                            return;
                          }
                          setState(() {
                            _words = [
                              for (final current in _words)
                                if (current.id != word.id) current,
                            ];
                          });
                        },
                        icon: const Icon(Icons.delete_outline_rounded),
                        tooltip: 'Delete word',
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  void _showWordDetails(BuildContext context, FoodWord word) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _WordVisualCard(word: word),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    word.term,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6E9DD),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    word.category,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF8A664F),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 12),
            if ((word.pronunciation ?? '').trim().isNotEmpty ||
                (word.pronunciationAudioUrl ?? '').trim().isNotEmpty) ...[
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: [
                  if ((word.pronunciation ?? '').trim().isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F1EA),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFE7D8CB)),
                      ),
                      child: Text(
                        word.pronunciation!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF5F5148),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  if ((word.pronunciationAudioUrl ?? '').trim().isNotEmpty)
                    TextButton.icon(
                      onPressed: () => _playPronunciation(
                        context,
                        word.pronunciationAudioUrl!,
                      ),
                      icon: const Icon(Icons.volume_up_rounded, size: 18),
                      label: const Text('Hear pronunciation'),
                    ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            Text(
              word.definition,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF5F5148),
                    height: 1.4,
                  ),
            ),
            if (word.examples.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                'Examples',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              for (final example in word.examples) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Icon(
                        Icons.circle,
                        size: 7,
                        color: Color(0xFFB85C38),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        example,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF625449),
                              height: 1.35,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _playPronunciation(BuildContext context, String rawUrl) async {
    final url = rawUrl.trim();
    if (url.isEmpty) {
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open pronunciation audio.')),
      );
    }
  }
}

class _WordVisualCard extends StatelessWidget {
  const _WordVisualCard({required this.word});

  final FoodWord word;

  @override
  Widget build(BuildContext context) {
    final palette = _paletteFor(word);
    final sourceImagePath = word.sourceImagePath.trim();
    final hasSourceImage = sourceImagePath.isNotEmpty;
    return Container(
      width: double.infinity,
      height: 148,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: palette,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: hasSourceImage
            ? _buildSourceImage(sourceImagePath)
            : _buildFallbackArt(),
      ),
    );
  }

  Widget _buildSourceImage(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildFallbackArt(),
      );
    }

    return Image.file(
      MealRepository.fileFromStoredPath(path),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _buildFallbackArt(),
    );
  }

  Widget _buildFallbackArt() {
    return Stack(
      children: [
        Positioned(
          top: 12,
          right: 14,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
          ),
        ),
        Positioned(
          bottom: 18,
          left: 18,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
          ),
        ),
        Center(
          child: Text(
            _emojiFor(word),
            style: const TextStyle(fontSize: 58),
          ),
        ),
      ],
    );
  }

  List<Color> _paletteFor(FoodWord word) {
    if (word.category.toLowerCase() == 'cooking') {
      return const [Color(0xFFB85C38), Color(0xFF7A3A22)];
    }
    return const [Color(0xFF6DAA6A), Color(0xFF3C7A52)];
  }

  String _emojiFor(FoodWord word) {
    final hint = '${word.imageHint} ${word.term}'.toLowerCase();
    if (hint.contains('potato')) return '🥔';
    if (hint.contains('chicken')) return '🍗';
    if (hint.contains('beef')) return '🥩';
    if (hint.contains('pork')) return '🥓';
    if (hint.contains('fish')) return '🐟';
    if (hint.contains('egg')) return '🥚';
    if (hint.contains('bread')) return '🍞';
    if (hint.contains('salad')) return '🥗';
    if (hint.contains('vegetable')) return '🥬';
    if (hint.contains('fruit')) return '🍎';
    if (hint.contains('rice')) return '🍚';
    if (hint.contains('noodle')) return '🍜';
    if (hint.contains('soup') || hint.contains('broth')) return '🥣';
    if (hint.contains('tofu')) return '🧈';
    if (hint.contains('herb')) return '🌿';
    if (hint.contains('pickle')) return '🥒';
    if (hint.contains('grill') || hint.contains('roast')) return '🔥';
    if (hint.contains('steam')) return '♨️';
    if (hint.contains('bake')) return '🍞';
    if (hint.contains('wok') || hint.contains('fried')) return '🍳';
    return word.category.toLowerCase() == 'cooking' ? '👨‍🍳' : '🍲';
  }
}

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/meal_entry.dart';
import '../services/meal_analysis_service.dart';
import '../services/meal_repository.dart';

class MiraChatPage extends StatefulWidget {
  const MiraChatPage({
    super.key,
    required this.analysisService,
    required this.repository,
    required this.recentEntries,
    required this.dietGoalBrief,
  });

  final MealAnalysisService analysisService;
  final MealRepository repository;
  final List<MealEntry> recentEntries;
  final String dietGoalBrief;

  @override
  State<MiraChatPage> createState() => _MiraChatPageState();
}

class _MiraChatPageState extends State<MiraChatPage> {
  static const int _initialHistoryBatchSize = 12;
  static const int _olderHistoryBatchSize = 20;

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _seedMessages = const [
    _ChatMessage.coach(
      'I am Mira. Ask me about your meals, drinks, calories, or how your recent eating pattern lines up with your mission.',
    ),
  ];
  late List<_ChatMessage> _messages = [
    ..._seedMessages,
  ];
  bool _isLoadingHistory = true;
  bool _isLoadingOlder = false;
  bool _isSending = false;
  int _loadedSavedMessageCount = 0;
  int _totalSavedMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _loadSavedMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedMessages() async {
    final saved = await widget.repository.loadLocalMiraMessages(
      limit: _initialHistoryBatchSize,
    );
    if (!mounted) {
      return;
    }

    final restored = saved
        .map((item) => _ChatMessage.fromMap(_repairMessageMap(item)))
        .where((message) => message.text.trim().isNotEmpty)
        .toList();

    setState(() {
      _messages = restored.isEmpty ? [..._seedMessages] : restored;
      _loadedSavedMessageCount = restored.length;
      _totalSavedMessageCount = restored.length;
      _isLoadingHistory = false;
    });

    _scrollToBottom();

    final totalSaved = await widget.repository.loadLocalMiraMessages();
    if (!mounted) {
      return;
    }
    setState(() {
      _totalSavedMessageCount = totalSaved.length;
    });
  }

  Future<void> _persistMessages() {
    return widget.repository.saveMiraMessages(
      _messages.map((message) => message.toMap()).toList(),
    );
  }

  Future<void> _sendMessage([String? preset]) async {
    final message = (preset ?? _messageController.text).trim();
    if (message.isEmpty || _isSending || _isLoadingHistory) {
      return;
    }

    _messageController.clear();
    setState(() {
      _messages.add(_ChatMessage.user(message));
      _isSending = true;
    });
    await _persistMessages();
    _scrollToBottom();

    try {
      final reply = await widget.analysisService.chatWithCoach(
        message: message,
        recentEntries: widget.recentEntries,
        dietGoalBrief: widget.dietGoalBrief,
        conversationMessages: _recentConversationContext(),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _messages.add(_ChatMessage.coach(_repairMojibake(reply)));
        _isSending = false;
      });
      await _persistMessages();
      _scrollToBottom();
    } catch (error) {
      final message = error.toString().replaceFirst('Exception: ', '').trim();
      if (!mounted) {
        return;
      }

      setState(() {
        _messages.add(
          _ChatMessage.coach(
            message.isNotEmpty
                ? message
                : 'I could not reply right now. Please try again in a moment.',
          ),
        );
        _isSending = false;
      });
      await _persistMessages();
      _scrollToBottom();
    }
  }

  Map<String, dynamic> _repairMessageMap(Map<String, dynamic> item) {
    final repaired = Map<String, dynamic>.from(item);
    final text = repaired['text'];
    if (text is String) {
      repaired['text'] = _repairMojibake(text);
    }
    return repaired;
  }

  String _repairMojibake(String text) {
    if (!text.contains('â') && !text.contains('Ã') && !text.contains('Â')) {
      return text;
    }

    try {
      return utf8.decode(latin1.encode(text));
    } catch (_) {
      return text;
    }
  }

  Future<void> _clearConversation() async {
    setState(() {
      _messages = [..._seedMessages];
      _loadedSavedMessageCount = 0;
      _totalSavedMessageCount = 0;
    });
    await widget.repository.clearMiraMessages();
    await _persistMessages();
  }

  List<Map<String, dynamic>> _recentConversationContext() {
    if (_messages.length <= 1) {
      return const [];
    }

    final conversation = _messages.take(_messages.length - 1).toList();
    final start = math.max(0, conversation.length - 8);
    return conversation
        .sublist(start)
        .map((message) => message.toMap())
        .toList();
  }

  bool get _hasOlderMessages =>
      _loadedSavedMessageCount < _totalSavedMessageCount;

  Future<void> _loadOlderMessages() async {
    if (_isLoadingHistory || _isLoadingOlder || !_hasOlderMessages) {
      return;
    }

    setState(() {
      _isLoadingOlder = true;
    });

    final previousOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    final previousMaxExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;

    final older = await widget.repository.loadLocalMiraMessages(
      limit: _olderHistoryBatchSize,
      offsetFromEnd: _loadedSavedMessageCount,
    );
    if (!mounted) {
      return;
    }

    final restored = older
        .map((item) => _ChatMessage.fromMap(_repairMessageMap(item)))
        .where((message) => message.text.trim().isNotEmpty)
        .toList();

    if (restored.isEmpty) {
      setState(() {
        _isLoadingOlder = false;
        _loadedSavedMessageCount = _totalSavedMessageCount;
      });
      return;
    }

    setState(() {
      _messages = [...restored, ..._messages];
      _loadedSavedMessageCount += restored.length;
      _isLoadingOlder = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      final newMaxExtent = _scrollController.position.maxScrollExtent;
      final delta = newMaxExtent - previousMaxExtent;
      _scrollController.jumpTo(previousOffset + math.max(0, delta));
    });
  }

  Future<void> _confirmClearConversation() async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Mira chat?'),
          content: const Text(
            'This will delete your conversation with Mira.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep chat'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldClear == true) {
      await _clearConversation();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F1EA),
      appBar: AppBar(
        title: const Text('Chat with Mira'),
        actions: [
          IconButton(
            onPressed: _isSending || _isLoadingHistory
                ? null
                : _confirmClearConversation,
            tooltip: 'Clear chat',
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [Color(0xFF2F251F), Color(0xFF7A4B2F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Mira',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.dietGoalBrief.isNotEmpty
                            ? 'Mira keeps your goal in mind while reviewing meals and drinks.'
                            : 'Mira can review your recent meals, drinks, and how they felt.',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 54,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              scrollDirection: Axis.horizontal,
              children: [
                _PromptChip(
                  label: 'How am I doing this week?',
                  onTap: () => _sendMessage('How am I doing this week?'),
                ),
                _PromptChip(
                  label: 'Which meals felt best?',
                  onTap: () => _sendMessage('Which recent meals felt best?'),
                ),
                _PromptChip(
                  label: 'How is my hydration?',
                  onTap: () => _sendMessage('How is my hydration lately?'),
                ),
                _PromptChip(
                  label: 'What should I improve?',
                  onTap: () => _sendMessage('What should I improve next?'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoadingHistory
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadOlderMessages,
                    notificationPredicate: (notification) =>
                        notification.depth == 0,
                    child: ListView.separated(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: _messages.length +
                          (_isSending ? 1 : 0) +
                          (_hasOlderMessages ? 1 : 0),
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        if (_hasOlderMessages && index == 0) {
                          return _HistoryLoadHint(isLoading: _isLoadingOlder);
                        }

                        final messageIndex =
                            index - (_hasOlderMessages ? 1 : 0);
                        if (_isSending && messageIndex == _messages.length) {
                          return const _TypingBubble();
                        }
                        final message = _messages[messageIndex];
                        return Align(
                          alignment: message.isUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 320),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: message.isUser
                                  ? const Color(0xFF7A4B2F)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              message.text,
                              style: TextStyle(
                                color: message.isUser
                                    ? Colors.white
                                    : const Color(0xFF2F251F),
                                height: 1.4,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: const InputDecoration(
                        hintText: 'Ask Mira about your meals or habits...',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(20)),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed:
                        _isSending || _isLoadingHistory ? null : _sendMessage,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(54, 54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PromptChip extends StatelessWidget {
  const _PromptChip({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        onPressed: onTap,
        label: Text(label),
      ),
    );
  }
}

class _HistoryLoadHint extends StatelessWidget {
  const _HistoryLoadHint({
    required this.isLoading,
  });

  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: const Color(0xFF8E6F5C),
        );

    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading) ...[
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text('Loading earlier messages...', style: textStyle),
            ] else
              Text('Pull down to load earlier messages', style: textStyle),
          ],
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const _TypingDots(),
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final phase = (_controller.value - (index * 0.16)).clamp(0.0, 1.0);
            final opacity = 0.28 + ((1 - (phase - 0.5).abs() * 2) * 0.72);
            return Container(
              width: 8,
              height: 8,
              margin: EdgeInsets.only(right: index == 2 ? 0 : 6),
              decoration: BoxDecoration(
                color: const Color(0xFF8E6F5C).withValues(alpha: opacity),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

class _ChatMessage {
  const _ChatMessage({
    required this.text,
    required this.isUser,
  });

  const _ChatMessage.user(this.text) : isUser = true;

  const _ChatMessage.coach(this.text) : isUser = false;

  final String text;
  final bool isUser;

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'isUser': isUser,
    };
  }

  factory _ChatMessage.fromMap(Map<String, dynamic> map) {
    return _ChatMessage(
      text: map['text'] as String? ?? '',
      isUser: map['isUser'] as bool? ?? false,
    );
  }
}

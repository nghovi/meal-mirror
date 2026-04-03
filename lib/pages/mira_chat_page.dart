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
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late List<_ChatMessage> _messages = [
    _ChatMessage.coach(
      'I am Mira. Ask me about your meals, drinks, calories, or how your recent eating pattern lines up with your mission.',
    ),
  ];
  bool _isLoadingHistory = true;
  bool _isSending = false;

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
    final saved = await widget.repository.loadMiraMessages();
    if (!mounted) {
      return;
    }

    final restored = saved
        .map(_ChatMessage.fromMap)
        .where((message) => message.text.trim().isNotEmpty)
        .toList();

    setState(() {
      _messages = restored.isEmpty
          ? [
              _ChatMessage.coach(
                'I am Mira. Ask me about your meals, drinks, calories, or how your recent eating pattern lines up with your mission.',
              ),
            ]
          : restored;
      _isLoadingHistory = false;
    });

    _scrollToBottom();
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
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _messages.add(_ChatMessage.coach(reply));
        _isSending = false;
      });
      await _persistMessages();
      _scrollToBottom();
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _messages.add(
          _ChatMessage.coach(
            'I could not reply right now. Please try again in a moment.',
          ),
        );
        _isSending = false;
      });
      await _persistMessages();
      _scrollToBottom();
    }
  }

  Future<void> _clearConversation() async {
    setState(() {
      _messages = [
        _ChatMessage.coach(
          'I am Mira. Ask me about your meals, drinks, calories, or how your recent eating pattern lines up with your mission.',
        ),
      ];
    });
    await widget.repository.clearMiraMessages();
    await _persistMessages();
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
            onPressed: _isSending || _isLoadingHistory ? null : _clearConversation,
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
                            ? 'Your meal reflection coach is keeping your mission in mind.'
                            : 'Your meal reflection coach can review recent food, drinks, and feelings with you.',
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
                : ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: _messages.length + (_isSending ? 1 : 0),
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      if (_isSending && index == _messages.length) {
                        return const _TypingBubble();
                      }
                      final message = _messages[index];
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
                    onPressed: _isSending || _isLoadingHistory ? null : _sendMessage,
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
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
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

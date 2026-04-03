import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_model.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class ChatTab extends StatefulWidget {
  final String sessionId;

  const ChatTab({super.key, required this.sessionId});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;

  static const _storagePrefix = 'chat_history_';

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String get _storageKey => '$_storagePrefix${widget.sessionId}';

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null) {
      try {
        final list = json.decode(raw) as List<dynamic>;
        setState(() {
          _messages.addAll(
              list.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)));
        });
        _scrollToBottom();
      } catch (_) {}
    }
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _storageKey, json.encode(_messages.map((m) => m.toJson()).toList()));
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    try {
      await ApiService.clearChatHistory(widget.sessionId);
    } catch (_) {}
    setState(() => _messages.clear());
  }

  Future<void> _sendMessage() async {
    final question = _inputController.text.trim();
    if (question.isEmpty || _isSending) return;

    _inputController.clear();
    setState(() {
      _messages.add(ChatMessage(role: 'user', content: question));
      _isSending = true;
    });
    _scrollToBottom();

    try {
      final response =
          await ApiService.sendMessage(widget.sessionId, question);
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(
            role: 'assistant',
            content: response.answer,
            citations: response.citations,
            timing: response.timing,
          ));
          _isSending = false;
        });
        await _saveHistory();
        _scrollToBottom();
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(
              role: 'assistant',
              content: 'Error: ${e.message}'));
          _isSending = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(
              role: 'assistant',
              content: 'Connection error. Is the backend running?'));
          _isSending = false;
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_messages.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: _clearHistory,
                  icon: const Icon(Icons.delete_outline,
                      size: 14, color: AppTheme.textMuted),
                  label: const Text('Clear history',
                      style: TextStyle(
                          color: AppTheme.textMuted, fontSize: 12)),
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4)),
                ),
              ],
            ),
          ),
        Expanded(
          child: _messages.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length + (_isSending ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == _messages.length) return _buildTypingIndicator();
                    return _buildMessageBubble(_messages[i]);
                  },
                ),
        ),
        _buildInputBar(),
      ],
    );
  }

  Widget _buildEmptyState() {
    const suggestions = [
      'What decisions were made?',
      'What action items were assigned?',
      'Who is responsible for the launch?',
      'Summarise the key points.',
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.chat_bubble_outline,
              size: 48, color: AppTheme.textMuted),
          const SizedBox(height: 16),
          Text('Ask anything about this meeting',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('Responses include citations with speaker, timestamp, and excerpt.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ...suggestions.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () {
                    _inputController.text = s;
                    _sendMessage();
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.bgElevated,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lightbulb_outline,
                            size: 16, color: AppTheme.accentAmber),
                        const SizedBox(width: 10),
                        Text(s,
                            style: const TextStyle(
                                color: AppTheme.textSecondary, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    final isUser = msg.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppTheme.accent.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.hub_rounded,
                  size: 16, color: AppTheme.accent),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isUser
                        ? AppTheme.accent.withOpacity(0.15)
                        : AppTheme.bgCard,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(12),
                      topRight: const Radius.circular(12),
                      bottomLeft: Radius.circular(isUser ? 12 : 2),
                      bottomRight: Radius.circular(isUser ? 2 : 12),
                    ),
                    border: Border.all(
                        color: isUser
                            ? AppTheme.accent.withOpacity(0.3)
                            : AppTheme.border),
                  ),
                  child: Text(
                    msg.content,
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 14, height: 1.5),
                  ),
                ),
                if (!isUser && msg.citations.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...msg.citations.map((c) => _buildCitation(c)),
                ],
                if (!isUser && msg.timing != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${msg.timing!.elapsedSeconds.toStringAsFixed(1)}s · ${msg.timing!.backend}',
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildCitation(Citation c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: const Border(
          left: BorderSide(color: AppTheme.accentLight, width: 3),
          top: BorderSide(color: AppTheme.border),
          right: BorderSide(color: AppTheme.border),
          bottom: BorderSide(color: AppTheme.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline,
                  size: 12, color: AppTheme.textMuted),
              const SizedBox(width: 4),
              Text(c.speaker,
                  style: const TextStyle(
                      color: AppTheme.accentLight,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              if (c.timestamp.isNotEmpty) ...[
                const Icon(Icons.access_time,
                    size: 11, color: AppTheme.textMuted),
                const SizedBox(width: 3),
                Text(c.timestamp,
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 11)),
              ],
            ],
          ),
          if (c.excerpt.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '"${c.excerpt}"',
              style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.hub_rounded,
                size: 16, color: AppTheme.accent),
          ),
          const SizedBox(width: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              border: Border.all(color: AppTheme.border),
            ),
            child: const _TypingDots(),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              onSubmitted: (_) => _sendMessage(),
              enabled: !_isSending,
              decoration: const InputDecoration(
                hintText: 'Ask about the meeting…',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              textInputAction: TextInputAction.send,
              maxLines: 3,
              minLines: 1,
            ),
          ),
          const SizedBox(width: 10),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            child: _isSending
                ? const SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppTheme.accent)))
                : IconButton(
                    onPressed: _sendMessage,
                    icon: const Icon(Icons.send_rounded),
                    color: AppTheme.accent,
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.accent.withOpacity(0.15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
          ),
        ],
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
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final offset = (i * 0.33);
            final t = (_ctrl.value - offset).clamp(0.0, 1.0);
            final opacity = t < 0.5 ? t * 2 : (1 - t) * 2;
            return Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: AppTheme.textSecondary.withOpacity(0.3 + opacity * 0.7),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

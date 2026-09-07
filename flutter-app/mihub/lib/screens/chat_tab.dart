import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_model.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class ChatTab extends StatefulWidget {
  final String sessionId;
  final String docType; // "meeting" | "document" — adapts copy/suggestions

  const ChatTab({super.key, required this.sessionId, this.docType = 'meeting'});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;

  // "document" = grounded/strict answers only from the file (default).
  // "general"  = blend file content with the model's broader knowledge.
  String _answerMode = 'document';

  static const _storagePrefix = 'chat_history_';
  static const _modePrefix = 'chat_answer_mode_';

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadAnswerMode();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String get _storageKey => '$_storagePrefix${widget.sessionId}';
  String get _modeStorageKey => '$_modePrefix${widget.sessionId}';

  Future<void> _loadAnswerMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_modeStorageKey);
    if (saved == 'document' || saved == 'general') {
      if (mounted) setState(() => _answerMode = saved!);
    }
  }

  Future<void> _setAnswerMode(String mode) async {
    setState(() => _answerMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeStorageKey, mode);
    // Persist as the session's default too, so other clients pick it up.
    try {
      await ApiService.setChatMode(widget.sessionId, mode);
    } catch (_) {
      // Non-fatal — the per-message mode override still applies locally.
    }
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null) {
      try {
        final list = json.decode(raw) as List<dynamic>;
        setState(() {
          _messages.addAll(list
              .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)));
        });
        _scrollToBottom();
      } catch (_) {}
    }
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _storageKey,
        json.encode(_messages.map((m) => m.toJson()).toList()));
  }

  Future<void> _clearHistory() async {
    final t = AppTheme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: t.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Clear conversation?',
            style: TextStyle(color: t.textPrimary, fontSize: 16)),
        content: Text(
            'This clears the conversation locally and on the server.',
            style: TextStyle(color: t.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: t.accentRed),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Clear server-side history first
    bool serverCleared = false;
    try {
      await ApiService.clearChatHistory(widget.sessionId);
      serverCleared = true;
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Server error: ${e.message}. Local history cleared.'),
          backgroundColor: t.accentAmber,
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Could not reach server. Local history cleared.'),
          backgroundColor: t.accentAmber,
        ));
      }
    }

    // Always clear local storage and state
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    if (mounted) {
      setState(() => _messages.clear());
      if (serverCleared) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Conversation cleared.'),
          backgroundColor: t.accentGreen,
        ));
      }
    }
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
      final response = await ApiService.sendMessage(
        widget.sessionId,
        question,
        mode: _answerMode,
      );
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
              role: 'assistant', content: 'Error: ${e.message}'));
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
        if (_messages.isNotEmpty) _buildClearBar(),
        Expanded(
          child: _messages.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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

  Widget _buildClearBar() {
    final t = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('${_messages.length ~/ 2} exchanges',
              style: TextStyle(color: t.textMuted, fontSize: 11)),
          Row(
            children: [
              _buildAnswerModeToggle(t),
              const SizedBox(width: 6),
              TextButton.icon(
                onPressed: _clearHistory,
                icon: Icon(Icons.delete_outline, size: 13, color: t.textMuted),
                label: Text('Clear',
                    style: TextStyle(color: t.textMuted, fontSize: 12)),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Small pill toggle: "Grounded" (strict, document-only) vs "General"
  /// (blends the file with the model's broader knowledge).
  Widget _buildAnswerModeToggle(AppThemeTokens t) {
    Widget pill(String label, String value) {
      final active = _answerMode == value;
      return GestureDetector(
        onTap: () => _setAnswerMode(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active ? t.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? t.onAccent : t.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: t.bgElevated,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: t.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          pill('🎯 Grounded', 'document'),
          pill('🌐 General', 'general'),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final t = AppTheme.of(context);
    final isDocument = widget.docType == 'document';
    final suggestions = isDocument
        ? const [
            ('What are the key points?', Icons.list_alt_outlined),
            ('How should I prepare for this?', Icons.checklist_rounded),
            ('What are the requirements?', Icons.rule_outlined),
            ('Summarise this document.', Icons.summarize_outlined),
          ]
        : const [
            ('What decisions were made?', Icons.check_circle_outline),
            ('What action items were assigned?', Icons.task_alt_outlined),
            ('Who is responsible for the launch?', Icons.person_outline),
            ('Summarise the key points.', Icons.summarize_outlined),
          ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: t.accentGlow,
              shape: BoxShape.circle,
              border: Border.all(color: t.borderGlow),
            ),
            child: Icon(Icons.chat_bubble_outline, size: 32, color: t.accent),
          ),
          const SizedBox(height: 20),
          Text(isDocument ? 'Ask about this document' : 'Ask about this meeting',
              style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 18)),
          const SizedBox(height: 8),
          Text(
              isDocument
                  ? 'Grounded mode cites the document; switch to General for advice that goes beyond it.'
                  : 'Responses include citations with speaker, timestamp, and excerpt.',
              style: TextStyle(
                  color: t.textSecondary, fontSize: 13, height: 1.5),
              textAlign: TextAlign.center),
          const SizedBox(height: 28),
          ...suggestions.map(((String text, IconData icon) s) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GestureDetector(
                  onTap: () {
                    _inputController.text = s.$1;
                    _sendMessage();
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: t.bgElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: t.border),
                    ),
                    child: Row(
                      children: [
                        Icon(s.$2,
                            size: 16, color: t.accent.withOpacity(0.7)),
                        const SizedBox(width: 12),
                        Text(s.$1,
                            style: TextStyle(
                                color: t.textSecondary, fontSize: 13)),
                        const Spacer(),
                        Icon(Icons.arrow_forward_rounded,
                            size: 14, color: t.textMuted),
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
    final t = AppTheme.of(context);
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
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [t.accentGlow, t.bgElevated],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                border: Border.all(color: t.borderGlow),
              ),
              child: Icon(Icons.hub_rounded, size: 15, color: t.accent),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isUser ? t.accentGlow : t.bgCard,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isUser ? 16 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 16),
                    ),
                    border: Border.all(
                        color: isUser ? t.borderGlow : t.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        msg.content,
                        style: TextStyle(
                            color: t.textPrimary, fontSize: 14, height: 1.55),
                      ),
                      if (!isUser && msg.timing != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${msg.timing!.elapsedSeconds.toStringAsFixed(1)}s · ${msg.timing!.backend}',
                          style: TextStyle(
                              color: t.textMuted.withOpacity(0.7),
                              fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!isUser && msg.citations.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ...msg.citations.map((c) => _buildCitation(c, t)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCitation(Citation c, AppThemeTokens t) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.fromLTRB(13, 11, 11, 11),
            decoration: BoxDecoration(
              color: t.bgDeep,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: t.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.person_outline, size: 11, color: t.textMuted),
                    const SizedBox(width: 4),
                    Text(c.speaker,
                        style: TextStyle(
                            color: t.accentLight,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (c.timestamp.isNotEmpty) ...[
                      Icon(Icons.access_time_outlined,
                          size: 11, color: t.textMuted),
                      const SizedBox(width: 3),
                      Text(c.timestamp,
                          style:
                              TextStyle(color: t.textMuted, fontSize: 11)),
                    ],
                  ],
                ),
                if (c.filename != null && c.filename!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.description_outlined,
                          size: 11, color: t.textMuted),
                      const SizedBox(width: 4),
                      Text(c.filename!,
                          style: TextStyle(color: t.textMuted, fontSize: 11)),
                    ],
                  ),
                ],
                if (c.excerpt.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    '"${c.excerpt}"',
                    style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        height: 1.4),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 6,
            child: Container(width: 2, color: t.accent),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    final t = AppTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [t.accentGlow, t.bgElevated],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              border: Border.all(color: t.borderGlow),
            ),
            child: Icon(Icons.hub_rounded, size: 15, color: t.accent),
          ),
          const SizedBox(width: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: t.bgCard,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
              ),
              border: Border.all(color: t.border),
            ),
            child: const _TypingDots(),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    final t = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: t.bgCard,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              onSubmitted: (_) => _sendMessage(),
              enabled: !_isSending,
              decoration: InputDecoration(
                hintText: widget.docType == 'document'
                    ? 'Ask about the document…'
                    : 'Ask about the meeting…',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
              ),
              textInputAction: TextInputAction.send,
              maxLines: 4,
              minLines: 1,
            ),
          ),
          const SizedBox(width: 10),
          _isSending
              ? Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: t.accentGlow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: t.accent),
                    ),
                  ),
                )
              : GestureDetector(
                  onTap: _sendMessage,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: t.accent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.send_rounded,
                        color: t.onAccent, size: 20),
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
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final offset = i * 0.28;
            final v = ((_ctrl.value - offset) % 1.0).clamp(0.0, 1.0);
            final opacity = v < 0.5 ? v * 2 : (1 - v) * 2;
            final scale = 0.7 + opacity * 0.3;
            return Transform.scale(
              scale: scale,
              child: Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                decoration: BoxDecoration(
                  color: t.accent.withOpacity(0.3 + opacity * 0.7),
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// Cross-session chat screen — searches across multiple (or all) transcripts.
class MultiChatScreen extends StatefulWidget {
  /// All session IDs available in the store.
  final List<String> allSessionIds;

  /// Optional map of sessionId → filename for display labels.
  final Map<String, String> sessionFilenames;

  const MultiChatScreen({
    super.key,
    required this.allSessionIds,
    this.sessionFilenames = const {},
  });

  @override
  State<MultiChatScreen> createState() => _MultiChatScreenState();
}

class _MultiChatScreenState extends State<MultiChatScreen> {
  final List<_MultiChatMessage> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;

  // null = search ALL sessions
  Set<String>? _selectedIds;

  // "document" = grounded/strict (default); "general" = blend with the
  // model's broader knowledge when the files don't fully answer.
  String _answerMode = 'document';

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final question = _inputController.text.trim();
    if (question.isEmpty || _isSending) return;
    _inputController.clear();
    setState(() {
      _messages.add(_MultiChatMessage.user(question));
      _isSending = true;
    });
    _scrollToBottom();

    try {
      final ids = _selectedIds?.toList();
      final result = await ApiService.sendMultiChat(
        question,
        sessionIds: ids,
        mode: _answerMode,
      );
      if (mounted) {
        setState(() {
          _messages.add(_MultiChatMessage.assistant(result));
          _isSending = false;
        });
        _scrollToBottom();
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(_MultiChatMessage.error(e.message));
          _isSending = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _messages.add(_MultiChatMessage.error('Connection error.'));
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

  void _showSessionPicker(BuildContext context) {
    final t = AppTheme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: t.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _SessionPickerSheet(
        allIds: widget.allSessionIds,
        filenames: widget.sessionFilenames,
        selected: _selectedIds,
        onConfirm: (sel) => setState(() => _selectedIds = sel),
      ),
    );
  }

  /// Small pill toggle: "Grounded" (strict, files-only) vs "General" (blends
  /// files with the model's broader knowledge).
  Widget _buildAnswerModeToggle(AppThemeTokens t) {
    Widget pill(String label, String value) {
      final active = _answerMode == value;
      return GestureDetector(
        onTap: () => setState(() => _answerMode = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
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
          pill('🎯', 'document'),
          pill('🌐', 'general'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final scopeLabel = _selectedIds == null
        ? 'All sessions (${widget.allSessionIds.length})'
        : '${_selectedIds!.length} selected';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Cross-Session Chat',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            Text('Searching: $scopeLabel',
                style: TextStyle(
                    fontSize: 11, color: t.textSecondary, fontWeight: FontWeight.w400)),
          ],
        ),
        actions: [
          _buildAnswerModeToggle(t),
          const SizedBox(width: 6),
          IconButton(
            icon: Icon(Icons.tune_rounded, size: 20, color: t.textSecondary),
            onPressed: () => _showSessionPicker(context),
            tooltip: 'Select sessions',
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: t.border),
        ),
      ),
      body: Column(
        children: [
          // Scope banner
          _ScopeBanner(
            label: scopeLabel,
            sessionCount: _selectedIds?.length ?? widget.allSessionIds.length,
            onConfigure: () => _showSessionPicker(context),
            t: t,
          ),
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState(t)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    itemCount: _messages.length + (_isSending ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == _messages.length) return _buildTypingIndicator(t);
                      return _buildBubble(_messages[i], t);
                    },
                  ),
          ),
          _buildInputBar(t),
        ],
      ),
    );
  }

  Widget _buildEmptyState(AppThemeTokens t) {
    const suggestions = [
      ('What decisions were made across all meetings?', Icons.check_circle_outline),
      ('Who owns the most action items?', Icons.task_alt_outlined),
      ('What topics appeared in multiple meetings?', Icons.repeat_rounded),
      ('Summarise all meetings in one paragraph.', Icons.summarize_outlined),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: t.accentPurple.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(color: t.accentPurple.withOpacity(0.3)),
            ),
            child: Icon(Icons.hub_rounded, size: 32, color: t.accentPurple),
          ),
          const SizedBox(height: 20),
          Text('Ask across all transcripts',
              style: TextStyle(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 17)),
          const SizedBox(height: 8),
          Text(
              'Uses TF-IDF to find relevant segments across every meeting, then answers with citations.',
              style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.5),
              textAlign: TextAlign.center),
          const SizedBox(height: 28),
          ...suggestions.map(((String text, IconData icon) s) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GestureDetector(
                  onTap: () {
                    _inputController.text = s.$1;
                    _send();
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
                            size: 16, color: t.accentPurple.withOpacity(0.7)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Text(s.$1,
                                style: TextStyle(
                                    color: t.textSecondary, fontSize: 13))),
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

  Widget _buildBubble(_MultiChatMessage msg, AppThemeTokens t) {
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
                color: t.accentPurple.withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(color: t.accentPurple.withOpacity(0.3)),
              ),
              child: Icon(Icons.hub_rounded, size: 15, color: t.accentPurple),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isUser
                        ? t.accentGlow
                        : msg.isError
                            ? t.accentRed.withOpacity(0.08)
                            : t.bgCard,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isUser ? 16 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 16),
                    ),
                    border: Border.all(
                        color: isUser
                            ? t.borderGlow
                            : msg.isError
                                ? t.accentRed.withOpacity(0.3)
                                : t.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(msg.content,
                          style: TextStyle(
                              color: msg.isError ? t.accentRed : t.textPrimary,
                              fontSize: 14,
                              height: 1.55)),
                      if (!isUser && msg.sessionCount != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${msg.sessionCount} session${msg.sessionCount! > 1 ? 's' : ''} searched · ${msg.elapsedSeconds?.toStringAsFixed(1) ?? '—'}s · ${msg.backend ?? '—'}',
                          style:
                              TextStyle(color: t.textMuted, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ),
                // Citations
                if (msg.citations.isNotEmpty) ...[
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

  Widget _buildCitation(Map<String, dynamic> c, AppThemeTokens t) {
    final speaker = c['speaker']?.toString() ?? '';
    final excerpt = c['excerpt']?.toString() ?? '';
    final timestamp = c['timestamp']?.toString() ?? '';
    final filename = c['filename']?.toString() ?? '';
    final sessionId = c['session_id']?.toString() ?? '';

    final sessionLabel = filename.isNotEmpty
        ? filename
        : sessionId.isNotEmpty
            ? sessionId.substring(0, 8)
            : '';

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
                    if (sessionLabel.isNotEmpty) ...[
                      Icon(Icons.insert_drive_file_outlined,
                          size: 10, color: t.accentPurple),
                      const SizedBox(width: 3),
                      Text(sessionLabel,
                          style: TextStyle(
                              color: t.accentPurple,
                              fontSize: 10,
                              fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(width: 8),
                    ],
                    if (speaker.isNotEmpty) ...[
                      Icon(Icons.person_outline, size: 10, color: t.textMuted),
                      const SizedBox(width: 3),
                      Text(speaker,
                          style: TextStyle(
                              color: t.accentLight,
                              fontSize: 10,
                              fontWeight: FontWeight.w600)),
                    ],
                    const Spacer(),
                    if (timestamp.isNotEmpty) ...[
                      Icon(Icons.access_time_outlined,
                          size: 10, color: t.textMuted),
                      const SizedBox(width: 3),
                      Text(timestamp,
                          style:
                              TextStyle(color: t.textMuted, fontSize: 10)),
                    ],
                  ],
                ),
                if (excerpt.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text('"$excerpt"',
                      style: TextStyle(
                          color: t.textSecondary,
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          height: 1.4)),
                ],
              ],
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 6,
            child: Container(width: 2, color: t.accentPurple),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(AppThemeTokens t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: t.accentPurple.withOpacity(0.12),
              shape: BoxShape.circle,
              border: Border.all(color: t.accentPurple.withOpacity(0.3)),
            ),
            child: Icon(Icons.hub_rounded, size: 15, color: t.accentPurple),
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
            child: Text('Searching transcripts…',
                style: TextStyle(color: t.textMuted, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(AppThemeTokens t) {
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
              onSubmitted: (_) => _send(),
              enabled: !_isSending,
              decoration: const InputDecoration(
                hintText: 'Ask across all meetings…',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                    color: t.accentPurple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: t.accentPurple),
                    ),
                  ),
                )
              : GestureDetector(
                  onTap: _send,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: t.accentPurple,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.send_rounded, color: t.onAccent, size: 20),
                  ),
                ),
        ],
      ),
    );
  }
}

// ── Scope banner ──────────────────────────────────────────────────────────────

class _ScopeBanner extends StatelessWidget {
  final String label;
  final int sessionCount;
  final VoidCallback onConfigure;
  final AppThemeTokens t;

  const _ScopeBanner({
    required this.label,
    required this.sessionCount,
    required this.onConfigure,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: t.accentPurple.withOpacity(0.06),
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 13, color: t.accentPurple),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Scope: $label',
              style: TextStyle(
                  color: t.textSecondary, fontSize: 12, height: 1),
            ),
          ),
          GestureDetector(
            onTap: onConfigure,
            child: Text('Change',
                style: TextStyle(
                    color: t.accentPurple,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ── Session picker bottom sheet ───────────────────────────────────────────────

class _SessionPickerSheet extends StatefulWidget {
  final List<String> allIds;
  final Map<String, String> filenames;
  final Set<String>? selected;
  final ValueChanged<Set<String>?> onConfirm;

  const _SessionPickerSheet({
    required this.allIds,
    required this.filenames,
    required this.selected,
    required this.onConfirm,
  });

  @override
  State<_SessionPickerSheet> createState() => _SessionPickerSheetState();
}

class _SessionPickerSheetState extends State<_SessionPickerSheet> {
  late Set<String>? _current;

  @override
  void initState() {
    super.initState();
    _current = widget.selected == null ? null : Set.of(widget.selected!);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: t.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Text('Select Sessions to Search',
              style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Leave all unselected to search every session.',
              style: TextStyle(color: t.textSecondary, fontSize: 12)),
          const SizedBox(height: 16),
          // "All" option
          _PickerTile(
            label: 'All sessions (${widget.allIds.length})',
            subtitle: 'Default — searches every transcript',
            selected: _current == null,
            color: t.accentPurple,
            t: t,
            onTap: () => setState(() => _current = null),
          ),
          const SizedBox(height: 8),
          // Individual sessions
          ...widget.allIds.map((id) {
            final filename = widget.filenames[id] ?? id.substring(0, 8);
            final isSelected = _current?.contains(id) ?? false;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _PickerTile(
                label: filename,
                subtitle: id.substring(0, 8),
                selected: _current != null && isSelected,
                color: t.accent,
                t: t,
                onTap: () {
                  setState(() {
                    _current ??= {};
                    if (isSelected) {
                      _current!.remove(id);
                      if (_current!.isEmpty) _current = null;
                    } else {
                      _current!.add(id);
                    }
                  });
                },
              ),
            );
          }),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                widget.onConfirm(_current);
              },
              child: Text(_current == null
                  ? 'Search All Sessions'
                  : 'Search ${_current!.length} Session${_current!.length > 1 ? 's' : ''}'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool selected;
  final Color color;
  final AppThemeTokens t;
  final VoidCallback onTap;

  const _PickerTile({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.color,
    required this.t,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.1) : t.bgElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? color.withOpacity(0.4) : t.border,
              width: selected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 18,
              color: selected ? color : t.textMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: selected ? color : t.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  Text(subtitle,
                      style: TextStyle(
                          color: t.textMuted,
                          fontSize: 11,
                          fontFamily: 'monospace')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Message model ─────────────────────────────────────────────────────────────

class _MultiChatMessage {
  final String role; // 'user' | 'assistant'
  final String content;
  final bool isError;
  final List<Map<String, dynamic>> citations;
  final int? sessionCount;
  final double? elapsedSeconds;
  final String? backend;

  _MultiChatMessage._({
    required this.role,
    required this.content,
    this.isError = false,
    this.citations = const [],
    this.sessionCount,
    this.elapsedSeconds,
    this.backend,
  });

  factory _MultiChatMessage.user(String text) =>
      _MultiChatMessage._(role: 'user', content: text);

  factory _MultiChatMessage.assistant(Map<String, dynamic> data) {
    final timing = data['timing'] as Map<String, dynamic>?;
    return _MultiChatMessage._(
      role: 'assistant',
      content: data['answer']?.toString() ?? '',
      citations: List<Map<String, dynamic>>.from(data['citations'] ?? []),
      sessionCount: (data['sessions_searched'] as num?)?.toInt(),
      elapsedSeconds: (timing?['elapsed_seconds'] as num?)?.toDouble(),
      backend: timing?['backend']?.toString(),
    );
  }

  factory _MultiChatMessage.error(String msg) =>
      _MultiChatMessage._(role: 'assistant', content: msg, isError: true);
}

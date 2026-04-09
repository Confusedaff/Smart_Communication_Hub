import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class AnalyticsTab extends StatefulWidget {
  final String sessionId;

  const AnalyticsTab({super.key, required this.sessionId});

  @override
  State<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<AnalyticsTab> {
  Map<String, dynamic>? _data;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getAnalytics(widget.sessionId);
      if (mounted) setState(() => _data = data);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load analytics');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);

    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: t.accent));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: t.accentRed, size: 40),
              const SizedBox(height: 16),
              Text(_error!,
                  style: TextStyle(color: t.textSecondary, fontSize: 13),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final speakerCount = (_data?['speaker_count'] as num?)?.toInt() ?? 0;
    if (_data == null || speakerCount == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bar_chart_outlined, size: 48, color: t.textMuted),
            const SizedBox(height: 16),
            Text('No speaker data',
                style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15)),
            const SizedBox(height: 8),
            Text('Upload a transcript with speaker labels to see analytics.',
                style: TextStyle(color: t.textSecondary, fontSize: 13),
                textAlign: TextAlign.center),
          ],
        ),
      );
    }

    final speakers =
        (_data!['speakers'] as List? ?? []).cast<Map<String, dynamic>>();
    final totalWords = (_data!['total_words'] as num?)?.toInt() ?? 0;
    final totalSegments = (_data!['total_segments'] as num?)?.toInt() ?? 0;
    final mostTalkative = _data!['most_talkative']?.toString();
    final mostAssigned = _data!['most_assigned']?.toString();
    final mostDecisive = _data!['most_decisive']?.toString();
    final totalQuestions = speakers.fold<int>(
        0,
        (sum, sp) =>
            sum + (((sp['question_count'] as num?)?.toInt()) ?? 0));

    return RefreshIndicator(
      onRefresh: _load,
      color: t.accent,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stat cards
            Row(
              children: [
                _StatCard(
                    value: '$speakerCount',
                    label: 'Speakers',
                    color: t.accent,
                    icon: Icons.people_outline),
                const SizedBox(width: 10),
                _StatCard(
                    value: _compact(totalWords),
                    label: 'Words',
                    color: t.accent,
                    icon: Icons.text_fields_outlined),
                const SizedBox(width: 10),
                _StatCard(
                    value: '$totalSegments',
                    label: 'Segments',
                    color: t.textMuted,
                    icon: Icons.segment_outlined),
                const SizedBox(width: 10),
                _StatCard(
                    value: '$totalQuestions',
                    label: 'Questions',
                    color: t.textMuted,
                    icon: Icons.help_outline_rounded),
              ],
            ),

            // Highlight row
            if (mostTalkative != null ||
                mostAssigned != null ||
                mostDecisive != null) ...[
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (mostTalkative != null) ...[
                      _HighlightCard(
                          icon: '🎤',
                          label: 'Most Talkative',
                          value: mostTalkative,
                          color: t.accent),
                      const SizedBox(width: 10),
                    ],
                    if (mostAssigned != null) ...[
                      _HighlightCard(
                          icon: '✅',
                          label: 'Most Assigned',
                          value: mostAssigned,
                          color: t.accentGreen),
                      const SizedBox(width: 10),
                    ],
                    if (mostDecisive != null)
                      _HighlightCard(
                          icon: '⚡',
                          label: 'Most Decisive',
                          value: mostDecisive,
                          color: t.accentAmber),
                  ],
                ),
              ),
            ],

            // Talk share chart
            const SizedBox(height: 20),
            _SectionHeader(
                title: 'Talk Share',
                subtitle: '$totalWords words total',
                color: t.accent),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: t.bgCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: t.border),
              ),
              child: Column(
                children: speakers.asMap().entries.map((e) {
                  final sp = e.value;
                  final color = _speakerColor(e.key, t);
                  final pct =
                      (sp['talk_share_pct'] as num?)?.toDouble() ?? 0.0;
                  final words = (sp['word_count'] as num?)?.toInt() ?? 0;
                  final maxWords =
                      (speakers.first['word_count'] as num?)?.toInt() ?? 1;

                  final speakerName = sp['speaker']?.toString() ?? '';
                  return InkWell(
                    onTap: () => _openSentimentDrillDown(speakerName),
                    child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: BoxDecoration(
                      border: e.key < speakers.length - 1
                          ? Border(bottom: BorderSide(color: t.border))
                          : null,
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                speakerName.isNotEmpty ? speakerName : '—',
                                style: TextStyle(
                                    color: color,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                            Text('${pct.toStringAsFixed(1)}%',
                                style: TextStyle(
                                    color: t.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'monospace')),
                            const SizedBox(width: 10),
                            Text('${_compact(words)} words',
                                style: TextStyle(
                                    color: t.textMuted,
                                    fontSize: 11,
                                    fontFamily: 'monospace')),
                            const SizedBox(width: 6),
                            Icon(Icons.sentiment_satisfied_alt_outlined,
                                size: 13, color: t.textMuted),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: maxWords > 0 ? words / maxWords : 0,
                            backgroundColor: t.bgElevated,
                            valueColor: AlwaysStoppedAnimation(color),
                            minHeight: 5,
                          ),
                        ),
                      ],
                    ),
                    ),
                  );
                }).toList(),
              ),
            ),

            // Per-speaker breakdown table
            const SizedBox(height: 20),
            _SectionHeader(
                title: 'Per-Speaker Breakdown',
                subtitle: '',
                color: t.accent),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: t.bgCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: t.border),
              ),
              child: Column(
                children: [
                  // Header row
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      border:
                          Border(bottom: BorderSide(color: t.border)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                            child: _tableHeader('Speaker', t)),
                        _tableHeader('Share', t),
                        const SizedBox(width: 16),
                        _tableHeader('Q', t),
                        const SizedBox(width: 16),
                        _tableHeader('Actions', t),
                        const SizedBox(width: 16),
                        _tableHeader('Decisions', t),
                      ],
                    ),
                  ),
                  // Data rows
                  ...speakers.asMap().entries.map((e) {
                    final sp = e.value;
                    final color = _speakerColor(e.key, t);
                    final pct =
                        (sp['talk_share_pct'] as num?)?.toDouble() ?? 0;
                    final questions =
                        (sp['question_count'] as num?)?.toInt() ?? 0;
                    final actions =
                        (sp['action_items_assigned'] as num?)?.toInt() ?? 0;
                    final decisions =
                        (sp['decisions_made'] as num?)?.toInt() ?? 0;

                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        border: e.key < speakers.length - 1
                            ? Border(bottom: BorderSide(color: t.border))
                            : null,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              sp['speaker']?.toString() ?? '—',
                              style: TextStyle(
                                  color: color,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text('${pct.toStringAsFixed(1)}%',
                              style: TextStyle(
                                  color: t.textSecondary,
                                  fontSize: 12,
                                  fontFamily: 'monospace')),
                          const SizedBox(width: 16),
                          _MetricPill(value: questions, color: t.accent),
                          const SizedBox(width: 16),
                          _MetricPill(
                              value: actions, color: t.accentAmber),
                          const SizedBox(width: 16),
                          _MetricPill(
                              value: decisions, color: t.accentGreen),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openSentimentDrillDown(String speaker) {
    if (speaker.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _SentimentDrillDownScreen(
          sessionId: widget.sessionId,
          speaker: speaker,
        ),
      ),
    );
  }

  Widget _tableHeader(String text, AppThemeTokens t) {
    return Text(text,
        style: TextStyle(
            color: t.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5));
  }

  String _compact(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  Color _speakerColor(int index, AppThemeTokens t) {
    return t.speakerColor(index);
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final IconData icon;

  const _StatCard(
      {required this.value,
      required this.label,
      required this.color,
      required this.icon});

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 15, color: color.withOpacity(0.7)),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1)),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: t.textMuted, fontSize: 10, letterSpacing: 0.3)),
          ],
        ),
      ),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  final String icon;
  final String label;
  final String value;
  final Color color;

  const _HighlightCard(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(color: t.textMuted, fontSize: 10)),
              Text(value,
                  style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;

  const _SectionHeader(
      {required this.title, required this.subtitle, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 8),
        Text(title,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: 14)),
        const Spacer(),
        if (subtitle.isNotEmpty)
          Text(subtitle,
              style: TextStyle(color: t.textMuted, fontSize: 11)),
      ],
    );
  }
}

class _MetricPill extends StatelessWidget {
  final int value;
  final Color color;

  const _MetricPill({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final hasValue = value > 0;
    return Container(
      width: 32,
      padding: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: hasValue ? color.withOpacity(0.1) : t.bgElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: hasValue ? color.withOpacity(0.3) : t.border),
      ),
      alignment: Alignment.center,
      child: Text('$value',
          style: TextStyle(
              color: hasValue ? color : t.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace')),
    );
  }
}


// ═════════════════════════════════════════════════════════════════════════════
// Sentiment Drill-Down Screen
// ═════════════════════════════════════════════════════════════════════════════

class _SentimentDrillDownScreen extends StatefulWidget {
  final String sessionId;
  final String speaker;

  const _SentimentDrillDownScreen({
    required this.sessionId,
    required this.speaker,
  });

  @override
  State<_SentimentDrillDownScreen> createState() =>
      _SentimentDrillDownScreenState();
}

class _SentimentDrillDownScreenState
    extends State<_SentimentDrillDownScreen> {
  String? _sentimentFilter; // null = all
  List<Map<String, dynamic>> _segments = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getSpeakerSegments(
        widget.sessionId,
        widget.speaker,
        sentiment: _sentimentFilter,
      );
      if (mounted) {
        setState(() =>
            _segments = List<Map<String, dynamic>>.from(data['segments'] ?? []));
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Failed to load segments');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openSegmentContext(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _SegmentContextScreen(
          sessionId: widget.sessionId,
          targetIndex: index,
          speaker: widget.speaker,
        ),
      ),
    );
  }

  Color _sentimentColor(String sentiment, AppThemeTokens t) => switch (sentiment) {
        'positive' => t.accentGreen,
        'negative' => t.accentRed,
        _ => t.textMuted,
      };

  String _sentimentEmoji(String sentiment) => switch (sentiment) {
        'positive' => '😊',
        'negative' => '😟',
        _ => '😐',
      };

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.speaker,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const Text('Sentiment Drill-Down',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w400)),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: t.border),
        ),
      ),
      body: Column(
        children: [
          // Sentiment filter chips
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration:
                BoxDecoration(border: Border(bottom: BorderSide(color: t.border))),
            child: Row(
              children: [
                Text('Filter: ',
                    style: TextStyle(color: t.textMuted, fontSize: 12)),
                const SizedBox(width: 8),
                ...[null, 'positive', 'negative', 'neutral'].map((s) {
                  final label = s == null
                      ? 'All'
                      : s[0].toUpperCase() + s.substring(1);
                  final color = s == null
                      ? t.textSecondary
                      : _sentimentColor(s, t);
                  final selected = _sentimentFilter == s;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _sentimentFilter = s);
                        _load();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: selected
                              ? color.withOpacity(0.15)
                              : t.bgElevated,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: selected
                                  ? color.withOpacity(0.5)
                                  : t.border,
                              width: selected ? 1.5 : 1),
                        ),
                        child: Text(label,
                            style: TextStyle(
                                color: selected ? color : t.textMuted,
                                fontSize: 12,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w400)),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          // Segments
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: t.accent))
                : _error != null
                    ? Center(
                        child: Text(_error!,
                            style: TextStyle(color: t.textSecondary)))
                    : _segments.isEmpty
                        ? Center(
                            child: Text('No segments found',
                                style: TextStyle(color: t.textMuted)))
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _segments.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              final seg = _segments[i];
                              final sentiment =
                                  seg['sentiment']?.toString() ?? 'neutral';
                              final color = _sentimentColor(sentiment, t);
                              final index =
                                  (seg['index'] as num?)?.toInt() ?? 0;
                              return GestureDetector(
                                onTap: () => _openSegmentContext(index),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: t.bgCard,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: color.withOpacity(0.25)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(_sentimentEmoji(sentiment),
                                              style: const TextStyle(
                                                  fontSize: 14)),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color:
                                                  color.withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              border: Border.all(
                                                  color:
                                                      color.withOpacity(0.3)),
                                            ),
                                            child: Text(
                                              sentiment[0].toUpperCase() +
                                                  sentiment.substring(1),
                                              style: TextStyle(
                                                  color: color,
                                                  fontSize: 11,
                                                  fontWeight:
                                                      FontWeight.w600),
                                            ),
                                          ),
                                          const Spacer(),
                                          if (seg['timestamp'] != null) ...[
                                            Icon(
                                                Icons.access_time_outlined,
                                                size: 11,
                                                color: t.textMuted),
                                            const SizedBox(width: 3),
                                            Text(
                                                seg['timestamp'].toString(),
                                                style: TextStyle(
                                                    color: t.textMuted,
                                                    fontSize: 11)),
                                            const SizedBox(width: 8),
                                          ],
                                          Icon(Icons.open_in_new_rounded,
                                              size: 13, color: t.textMuted),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        seg['text']?.toString() ?? '',
                                        style: TextStyle(
                                            color: t.textPrimary,
                                            fontSize: 14,
                                            height: 1.5),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

// ── Segment context jump-to screen ────────────────────────────────────────────

class _SegmentContextScreen extends StatefulWidget {
  final String sessionId;
  final int targetIndex;
  final String speaker;

  const _SegmentContextScreen({
    required this.sessionId,
    required this.targetIndex,
    required this.speaker,
  });

  @override
  State<_SegmentContextScreen> createState() => _SegmentContextScreenState();
}

class _SegmentContextScreenState extends State<_SegmentContextScreen> {
  Map<String, dynamic>? _data;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getSegmentContext(
          widget.sessionId, widget.targetIndex);
      if (mounted) setState(() => _data = data);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Failed to load context');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final contextSegs = _data != null
        ? List<Map<String, dynamic>>.from(_data!['context'] ?? [])
        : <Map<String, dynamic>>[];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Segment #${widget.targetIndex}',
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            Text('${widget.speaker} · with context',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: t.textSecondary)),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: t.border),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: t.accent))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, color: t.accentRed, size: 36),
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: TextStyle(color: t.textSecondary)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                  children: [
                    // Info note
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: t.accent.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: t.accent.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 13, color: t.accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Showing 2 segments before and after the selected one.',
                              style: TextStyle(
                                  color: t.textSecondary, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...contextSegs.map((seg) {
                      final isTarget = seg['is_target'] == true;
                      final spk = seg['speaker']?.toString() ?? '';
                      final txt = seg['text']?.toString() ?? '';
                      final ts = seg['timestamp']?.toString() ?? '';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color:
                                isTarget ? t.accentGlow : t.bgCard,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: isTarget
                                    ? t.borderGlow
                                    : t.border,
                                width: isTarget ? 1.5 : 1),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (isTarget)
                                    Container(
                                      margin: const EdgeInsets.only(right: 8),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: t.accent.withOpacity(0.15),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: Text('TARGET',
                                          style: TextStyle(
                                              color: t.accent,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.5)),
                                    ),
                                  if (spk.isNotEmpty)
                                    Text(spk,
                                        style: TextStyle(
                                            color: isTarget
                                                ? t.accentLight
                                                : t.textSecondary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600)),
                                  const Spacer(),
                                  if (ts.isNotEmpty)
                                    Text(ts,
                                        style: TextStyle(
                                            color: t.textMuted,
                                            fontSize: 11)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(txt,
                                  style: TextStyle(
                                      color: isTarget
                                          ? t.textPrimary
                                          : t.textSecondary,
                                      fontSize: 14,
                                      height: 1.5,
                                      fontWeight: isTarget
                                          ? FontWeight.w500
                                          : FontWeight.w400)),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
    );
  }
}

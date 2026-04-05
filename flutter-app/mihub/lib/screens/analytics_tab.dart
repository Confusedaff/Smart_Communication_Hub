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

                  return Container(
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
                                sp['speaker']?.toString() ?? '—',
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

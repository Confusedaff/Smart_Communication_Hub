import 'package:flutter/material.dart';
import '../models/extraction_model.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class ExtractionTab extends StatefulWidget {
  final String sessionId;
  final String engine;

  const ExtractionTab({
    super.key,
    required this.sessionId,
    required this.engine,
  });

  @override
  State<ExtractionTab> createState() => _ExtractionTabState();
}

class _ExtractionTabState extends State<ExtractionTab> {
  ExtractionModel? _extraction;
  bool _isLoading = false;
  String? _error;
  // ignore: unused_field
  Map<String, dynamic>? _rawJson;

  @override
  void initState() {
    super.initState();
    _runExtraction();
  }

  @override
  void didUpdateWidget(ExtractionTab old) {
    super.didUpdateWidget(old);
    if (widget.engine != old.engine) _runExtraction();
  }

  Future<void> _runExtraction() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _rawJson = null;
    });
    try {
      final result = await ApiService.extractWithRaw(
          widget.sessionId, engine: widget.engine);
      if (mounted) {
        setState(() {
          _extraction = result.$1;
          _rawJson = result.$2;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Connection error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _buildLoading();
    if (_error != null) return _buildError();
    if (_extraction == null) return const SizedBox();
    return _buildResults();
  }

  Widget _buildLoading() {
    final t = AppTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: t.accentGlow,
              shape: BoxShape.circle,
              border: Border.all(color: t.borderGlow),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: CircularProgressIndicator(
                  color: t.accent, strokeWidth: 2.5),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Running extraction…',
            style: TextStyle(
                color: t.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 15),
          ),
          const SizedBox(height: 6),
          Text(
            widget.engine == 'llm'
                ? 'This may take up to 90s with Ollama.'
                : 'Running NLP pipeline…',
            style: TextStyle(color: t.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    final t = AppTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: t.accentRed.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.error_outline, color: t.accentRed, size: 32),
            ),
            const SizedBox(height: 20),
            Text('Extraction failed',
                style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 16)),
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(color: t.textSecondary, fontSize: 13),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _runExtraction,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    final t = AppTheme.of(context);
    final ex = _extraction!;
    return RefreshIndicator(
      onRefresh: _runExtraction,
      color: t.accent,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatsRow(ex, t),
            const SizedBox(height: 20),
            if (ex.summary.isNotEmpty) ...[
              _buildSummaryCard(ex.summary, t),
              const SizedBox(height: 20),
            ],
            _buildSection(
              title: 'Decisions',
              count: ex.decisions.length,
              color: t.accent,
              children: ex.decisions.isEmpty
                  ? [_emptyState('No decisions found', t)]
                  : ex.decisions.map((d) => _decisionCard(d, t)).toList(),
            ),
            const SizedBox(height: 20),
            _buildSection(
              title: 'Action Items',
              count: ex.actionItems.length,
              color: t.accentGreen,
              children: ex.actionItems.isEmpty
                  ? [_emptyState('No action items found', t)]
                  : ex.actionItems.map((a) => _actionCard(a, t)).toList(),
            ),
            if (ex.timing != null) ...[
              const SizedBox(height: 16),
              _buildTimingCard(ex.timing!, t),
            ],
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: _runExtraction,
                icon: const Icon(Icons.refresh_rounded, size: 15),
                label: const Text('Re-extract'),
                style: TextButton.styleFrom(foregroundColor: t.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow(ExtractionModel ex, AppThemeTokens t) {
    return Row(
      children: [
        _statChip('${ex.decisions.length}', 'Decisions',
            t.accent, Icons.check_circle_outline, t),
        const SizedBox(width: 10),
        _statChip('${ex.actionItems.length}', 'Actions',
            t.accentGreen, Icons.task_alt_outlined, t),
        const SizedBox(width: 10),
        _statChip('${ex.uniqueOwners}', 'Owners',
            t.accentPurple, Icons.person_outline, t),
        const SizedBox(width: 10),
        _statChip('${ex.itemsWithDeadlines}', 'Deadlines',
            t.accentAmber, Icons.schedule_outlined, t),
      ],
    );
  }

  Widget _statChip(
      String value, String label, Color color, IconData icon, AppThemeTokens t) {
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
            Icon(icon, size: 16, color: color.withOpacity(0.7)),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 22,
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

  Widget _buildSummaryCard(String summary, AppThemeTokens t) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [t.accentGlow, t.bgCard],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.borderGlow),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_outlined, size: 15, color: t.accent),
              const SizedBox(width: 8),
              Text('Executive Summary',
                  style: TextStyle(
                      color: t.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 12),
          Text(summary,
              style: TextStyle(
                  color: t.textPrimary, fontSize: 14, height: 1.7)),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required int count,
    required Color color,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$count',
                  style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }

  Widget _emptyState(String msg, AppThemeTokens t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(msg,
          style: TextStyle(
              color: t.textMuted, fontStyle: FontStyle.italic)),
    );
  }

  Widget _decisionCard(DecisionItem d, AppThemeTokens t) {
    final displayText = d.decision.isNotEmpty
        ? d.decision
        : '(No decision text — check API field names)';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: t.accent.withOpacity(0.25)),
                ),
                child: Text('${d.id}',
                    style: TextStyle(
                        color: t.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  displayText,
                  style: TextStyle(
                    color: d.decision.isNotEmpty ? t.textPrimary : t.accentAmber,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    height: 1.55,
                  ),
                ),
              ),
            ],
          ),
          if (d.madeBy.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: t.bgElevated,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_outline, size: 11, color: t.textMuted),
                      const SizedBox(width: 4),
                      Text(d.madeBy,
                          style: TextStyle(
                              color: t.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ],
            ),
          ],
          if (d.evidence.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: t.bgDeep,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.border),
              ),
              child: Text(
                '"${d.evidence}"',
                style: TextStyle(
                    color: t.textMuted,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    height: 1.5),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actionCard(ActionItem a, AppThemeTokens t) {
    final displayText = a.task.isNotEmpty
        ? a.task
        : '(No task text — check API field names)';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.accentGreen.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: t.accentGreen.withOpacity(0.25)),
                ),
                child: Text('${a.id}',
                    style: TextStyle(
                        color: t.accentGreen,
                        fontSize: 11,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  displayText,
                  style: TextStyle(
                    color: a.task.isNotEmpty ? t.textPrimary : t.accentAmber,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    height: 1.55,
                  ),
                ),
              ),
            ],
          ),
          if (a.owner.isNotEmpty || a.deadline.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (a.owner.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: t.bgElevated,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_outline,
                            size: 11, color: t.textMuted),
                        const SizedBox(width: 4),
                        Text(a.owner,
                            style: TextStyle(
                                color: t.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                if (a.owner.isNotEmpty && a.deadline.isNotEmpty)
                  const SizedBox(width: 8),
                if (a.deadline.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: t.accentAmber.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: t.accentAmber.withOpacity(0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.schedule_outlined,
                            size: 11, color: t.accentAmber),
                        const SizedBox(width: 4),
                        Text(a.deadline,
                            style: TextStyle(
                                color: t.accentAmber,
                                fontSize: 11,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          if (a.evidence.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: t.bgDeep,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.border),
              ),
              child: Text(
                '"${a.evidence}"',
                style: TextStyle(
                    color: t.textMuted,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    height: 1.5),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimingCard(ExtractionTiming timing, AppThemeTokens t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: t.bgElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 13, color: t.textMuted),
          const SizedBox(width: 6),
          Text(
            '${timing.elapsedSeconds.toStringAsFixed(1)}s via ${timing.backend} (${timing.engine})',
            style: TextStyle(color: t.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
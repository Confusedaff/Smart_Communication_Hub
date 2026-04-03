import 'package:flutter/material.dart';
import '../models/extraction_model.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/status_badge.dart';

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
  String? _lastEngine;

  @override
  void initState() {
    super.initState();
    _runExtraction();
  }

  @override
  void didUpdateWidget(ExtractionTab old) {
    super.didUpdateWidget(old);
    if (widget.engine != old.engine) {
      _runExtraction();
    }
  }

  Future<void> _runExtraction() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result =
          await ApiService.extract(widget.sessionId, engine: widget.engine);
      if (mounted) {
        setState(() {
          _extraction = result;
          _lastEngine = widget.engine;
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppTheme.accent),
          const SizedBox(height: 20),
          Text(
            widget.engine == 'llm'
                ? 'Running AI extraction…\nThis may take up to 90s with Ollama.'
                : 'Running NLP extraction…',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppTheme.accentRed, size: 48),
            const SizedBox(height: 16),
            Text('Extraction failed',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_error!,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _runExtraction,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    final ex = _extraction!;
    return RefreshIndicator(
      onRefresh: _runExtraction,
      color: AppTheme.accent,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatsRow(ex),
            const SizedBox(height: 16),
            _buildSummaryCard(ex.summary),
            const SizedBox(height: 16),
            _buildDecisionsSection(ex.decisions),
            const SizedBox(height: 16),
            _buildActionItemsSection(ex.actionItems),
            const SizedBox(height: 16),
            if (ex.timing != null) _buildTimingCard(ex.timing!),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: _runExtraction,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Re-extract'),
                style: TextButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow(ExtractionModel ex) {
    return Row(
      children: [
        _statChip('${ex.decisions.length}', 'Decisions', AppTheme.accent),
        const SizedBox(width: 8),
        _statChip(
            '${ex.actionItems.length}', 'Actions', AppTheme.accentGreen),
        const SizedBox(width: 8),
        _statChip(
            '${ex.uniqueOwners}', 'Owners', AppTheme.accentAmber),
        const SizedBox(width: 8),
        _statChip(
            '${ex.itemsWithDeadlines}', 'Deadlines', AppTheme.accentRed),
      ],
    );
  }

  Widget _statChip(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
            Text(label,
                style: const TextStyle(
                    color: AppTheme.textMuted, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String summary) {
    if (summary.isEmpty) return const SizedBox();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.summarize_outlined,
                    size: 16, color: AppTheme.accent),
                SizedBox(width: 8),
                Text('Executive Summary',
                    style: TextStyle(
                        color: AppTheme.accent,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ],
            ),
            const SizedBox(height: 10),
            Text(summary,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    height: 1.6)),
          ],
        ),
      ),
    );
  }

  Widget _buildDecisionsSection(List<DecisionItem> decisions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Decisions', decisions.length, AppTheme.accent),
        const SizedBox(height: 8),
        if (decisions.isEmpty)
          _emptyState('No decisions found')
        else
          ...decisions.map((d) => _decisionCard(d)),
      ],
    );
  }

  Widget _buildActionItemsSection(List<ActionItem> actions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Action Items', actions.length, AppTheme.accentGreen),
        const SizedBox(height: 8),
        if (actions.isEmpty)
          _emptyState('No action items found')
        else
          ...actions.map((a) => _actionCard(a)),
      ],
    );
  }

  Widget _sectionHeader(String title, int count, Color color) {
    return Row(
      children: [
        Text(title,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('$count',
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _emptyState(String msg) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(msg,
          style: const TextStyle(
              color: AppTheme.textMuted, fontStyle: FontStyle.italic)),
    );
  }

  Widget _decisionCard(DecisionItem d) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('${d.id}',
                      style: const TextStyle(
                          color: AppTheme.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(d.decision,
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w500,
                          fontSize: 14)),
                ),
              ],
            ),
            if (d.madeBy.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.person_outline,
                      size: 13, color: AppTheme.textMuted),
                  const SizedBox(width: 4),
                  Text(d.madeBy,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12)),
                ],
              ),
            ],
            if (d.evidence.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.bgDeep,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Text(
                  '"${d.evidence}"',
                  style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      height: 1.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionCard(ActionItem a) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.accentGreen.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('${a.id}',
                      style: const TextStyle(
                          color: AppTheme.accentGreen,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(a.task,
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w500,
                          fontSize: 14)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (a.owner.isNotEmpty) ...[
                  const Icon(Icons.person_outline,
                      size: 13, color: AppTheme.textMuted),
                  const SizedBox(width: 4),
                  Text(a.owner,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12)),
                  const SizedBox(width: 12),
                ],
                if (a.deadline.isNotEmpty) ...[
                  const Icon(Icons.schedule_outlined,
                      size: 13, color: AppTheme.accentAmber),
                  const SizedBox(width: 4),
                  Text(a.deadline,
                      style: const TextStyle(
                          color: AppTheme.accentAmber, fontSize: 12)),
                ],
              ],
            ),
            if (a.evidence.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.bgDeep,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Text(
                  '"${a.evidence}"',
                  style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      height: 1.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTimingCard(ExtractionTiming timing) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, size: 14, color: AppTheme.textMuted),
          const SizedBox(width: 6),
          Text(
            '${timing.elapsedSeconds.toStringAsFixed(1)}s via ${timing.backend} (${timing.engine})',
            style: const TextStyle(
                color: AppTheme.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

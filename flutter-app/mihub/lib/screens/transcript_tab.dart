import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class TranscriptTab extends StatefulWidget {
  final String sessionId;

  const TranscriptTab({super.key, required this.sessionId});

  @override
  State<TranscriptTab> createState() => _TranscriptTabState();
}

class _TranscriptTabState extends State<TranscriptTab> {
  List<Map<String, dynamic>> _segments = [];
  List<String> _speakers = [];
  bool _isLoading = true;
  String? _error;
  bool _showPlainText = false;
  String _plainText = '';

  @override
  void initState() {
    super.initState();
    _loadTranscript();
  }

  Future<void> _loadTranscript() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getTranscript(widget.sessionId,
          format: 'segments');
      final segs =
          List<Map<String, dynamic>>.from(data['segments'] ?? []);
      final spks = List<String>.from(data['speakers'] ?? []);

      final plainData = await ApiService.getTranscript(widget.sessionId,
          format: 'plain');
      final plain = plainData['text'] as String? ?? '';

      if (mounted) {
        setState(() {
          _segments = segs;
          _speakers = spks;
          _plainText = plain;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load transcript');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.accent));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppTheme.accentRed.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.error_outline,
                    color: AppTheme.accentRed, size: 30),
              ),
              const SizedBox(height: 16),
              Text(_error!,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loadTranscript,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        _buildHeader(),
        if (_speakers.isNotEmpty && !_showPlainText)
          _buildSpeakerLegend(),
        Expanded(
          child: _showPlainText ? _buildPlainText() : _buildSegments(),
        ),
      ],
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.border))),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file_outlined,
              size: 13, color: AppTheme.textMuted),
          const SizedBox(width: 5),
          Text('${_segments.length} segments',
              style: const TextStyle(
                  color: AppTheme.textMuted, fontSize: 12)),
          const Spacer(),
          SegmentedButton<bool>(
            selected: {_showPlainText},
            onSelectionChanged: (s) =>
                setState(() => _showPlainText = s.first),
            segments: const [
              ButtonSegment(value: false, label: Text('Segments')),
              ButtonSegment(value: true, label: Text('Plain text')),
            ],
            style: SegmentedButton.styleFrom(
              backgroundColor: AppTheme.bgElevated,
              selectedBackgroundColor:
                  AppTheme.accent.withOpacity(0.15),
              foregroundColor: AppTheme.textSecondary,
              selectedForegroundColor: AppTheme.accent,
              textStyle: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500),
              side: const BorderSide(color: AppTheme.border),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Speaker legend (scrollable pill row) ───────────────────────────────────

  Widget _buildSpeakerLegend() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.border))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Wrap(
          spacing: 10,
          runSpacing: 6,
          children: _speakers.asMap().entries.map((e) {
            final color = AppTheme.speakerColor(e.key);
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(e.value,
                    style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Segment list ───────────────────────────────────────────────────────────

  Widget _buildSegments() {
    if (_segments.isEmpty) {
      return const Center(
        child: Text('No segments found',
            style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 13,
                fontStyle: FontStyle.italic)),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _segments.length,
      itemBuilder: (_, i) => _buildSegmentRow(_segments[i]),
    );
  }

  Widget _buildSegmentRow(Map<String, dynamic> seg) {
    final speaker = (seg['speaker'] ??
            seg['Speaker'] ??
            seg['name'] ??
            seg['author'] ??
            '') as String;
    final text = (seg['text'] ??
            seg['content'] ??
            seg['transcript'] ??
            seg['message'] ??
            seg['body'] ??
            '') as String;

    final speakerIdx = _speakers.indexOf(speaker);
    final color = speakerIdx >= 0
        ? AppTheme.speakerColor(speakerIdx)
        : AppTheme.textMuted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Speaker pill — transparent background, colored border + text
              // exactly matching screenshot 2
              if (speaker.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color, width: 1.5),
                  ),
                  child: Text(
                    speaker,
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              // Transcript text
              Text(
                text.isNotEmpty ? text : '(empty)',
                style: TextStyle(
                  color: text.isNotEmpty
                      ? AppTheme.textPrimary
                      : AppTheme.textMuted,
                  fontSize: 15,
                  height: 1.55,
                  fontStyle: text.isNotEmpty
                      ? FontStyle.normal
                      : FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        Container(height: 1, color: AppTheme.border),
      ],
    );
  }

  // ── Plain text ─────────────────────────────────────────────────────────────

  Widget _buildPlainText() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: SelectableText(
        _plainText,
        style: const TextStyle(
            color: AppTheme.textPrimary, fontSize: 14, height: 1.75),
      ),
    );
  }
}
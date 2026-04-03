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

      final plainData =
          await ApiService.getTranscript(widget.sessionId, format: 'plain');
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                color: AppTheme.accentRed, size: 40),
            const SizedBox(height: 12),
            Text(_error!,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: _loadTranscript, child: const Text('Retry')),
          ],
        ),
      );
    }
    return Column(
      children: [
        _buildControls(),
        if (_speakers.isNotEmpty && !_showPlainText) _buildSpeakerLegend(),
        Expanded(
          child: _showPlainText ? _buildPlainText() : _buildSegments(),
        ),
      ],
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.border))),
      child: Row(
        children: [
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
              ButtonSegment(value: true, label: Text('Plain')),
            ],
            style: SegmentedButton.styleFrom(
              backgroundColor: AppTheme.bgElevated,
              selectedBackgroundColor: AppTheme.accent.withOpacity(0.2),
              foregroundColor: AppTheme.textSecondary,
              selectedForegroundColor: AppTheme.accent,
              textStyle: const TextStyle(fontSize: 12),
              side: const BorderSide(color: AppTheme.border),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeakerLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.border))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Text('Speakers: ',
                style: TextStyle(
                    color: AppTheme.textMuted, fontSize: 12)),
            ..._speakers.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: AppTheme.speakerColor(e.key),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(e.value,
                          style: TextStyle(
                              color: AppTheme.speakerColor(e.key),
                              fontSize: 12,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildSegments() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _segments.length,
      itemBuilder: (_, i) {
        final seg = _segments[i];
        final speaker = seg['speaker'] as String? ?? '';
        final text = seg['text'] as String? ?? '';
        final timestamp = seg['timestamp'] as String? ?? '';
        final speakerIdx = _speakers.indexOf(speaker);
        final color = speakerIdx >= 0
            ? AppTheme.speakerColor(speakerIdx)
            : AppTheme.textMuted;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(10),
            border: Border(
              left: BorderSide(color: color, width: 3),
              top: const BorderSide(color: AppTheme.border),
              right: const BorderSide(color: AppTheme.border),
              bottom: const BorderSide(color: AppTheme.border),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (speaker.isNotEmpty) ...[
                    Text(speaker,
                        style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                    const Spacer(),
                  ],
                  if (timestamp.isNotEmpty)
                    Text(timestamp,
                        style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 11,
                            fontFamily: 'monospace')),
                ],
              ),
              if (speaker.isNotEmpty) const SizedBox(height: 4),
              Text(text,
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      height: 1.5)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlainText() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        _plainText,
        style: const TextStyle(
            color: AppTheme.textPrimary, fontSize: 14, height: 1.7),
      ),
    );
  }
}

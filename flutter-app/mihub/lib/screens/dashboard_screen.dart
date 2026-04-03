import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../models/session_model.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/status_badge.dart';
import 'extraction_tab.dart';
import 'chat_tab.dart';
import 'transcript_tab.dart';

class DashboardScreen extends StatefulWidget {
  final SessionModel session;
  final VoidCallback onNewUpload;

  const DashboardScreen({
    super.key,
    required this.session,
    required this.onNewUpload,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _engine = 'llm';
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _exportCsv() async {
    setState(() => _isExporting = true);
    try {
      final bytes = await ApiService.exportCsv(widget.session.sessionId);
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/${widget.session.filename.replaceAll(RegExp(r'\.\w+$'), '')}_report.csv');
      await file.writeAsBytes(bytes);
      await OpenFilex.open(file.path);
    } on ApiException catch (e) {
      if (mounted) {
        _showError(e.message);
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportPdf() async {
    setState(() => _isExporting = true);
    try {
      final bytes = await ApiService.exportPdf(widget.session.sessionId);
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/${widget.session.filename.replaceAll(RegExp(r'\.\w+$'), '')}_report.pdf');
      await file.writeAsBytes(bytes);
      await OpenFilex.open(file.path);
    } on ApiException catch (e) {
      if (mounted) {
        _showError(e.message);
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppTheme.accentRed,
      ),
    );
  }

  void _showSessionInfo() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Session Info',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            _infoRow('Session ID', widget.session.sessionId),
            _infoRow('File', widget.session.filename),
            _infoRow('Segments', '${widget.session.segmentCount}'),
            _infoRow('Characters', '${widget.session.charCount}'),
            _infoRow('Speakers', widget.session.speakers.join(', ')),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(
                    color: AppTheme.textMuted, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meeting Intelligence Hub'),
        actions: [
          // Engine toggle
          _EngineToggle(
            value: _engine,
            onChanged: (v) => setState(() => _engine = v),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.info_outline, size: 20),
            onPressed: _showSessionInfo,
            tooltip: 'Session info',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.bolt_rounded, size: 18), text: 'Extract'),
            Tab(icon: Icon(Icons.chat_bubble_outline, size: 18), text: 'Chat'),
            Tab(icon: Icon(Icons.article_outlined, size: 18), text: 'Transcript'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildSessionBanner(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                ExtractionTab(
                  sessionId: widget.session.sessionId,
                  engine: _engine,
                ),
                ChatTab(
                  sessionId: widget.session.sessionId,
                ),
                TranscriptTab(
                  sessionId: widget.session.sessionId,
                ),
              ],
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildSessionBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppTheme.bgElevated,
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file_outlined,
              size: 16, color: AppTheme.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.session.filename,
              style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          StatusBadge(
              label: '${widget.session.segmentCount} segments',
              color: AppTheme.textMuted),
          if (widget.session.speakers.isNotEmpty) ...[
            const SizedBox(width: 6),
            StatusBadge(
                label: '${widget.session.speakers.length} speakers',
                color: AppTheme.accent),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _isExporting ? null : _exportCsv,
              icon: _isExporting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.accentLight))
                  : const Icon(Icons.download_rounded, size: 16),
              label: const Text('CSV'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _isExporting ? null : _exportPdf,
              icon: _isExporting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.accentLight))
                  : const Icon(Icons.picture_as_pdf_outlined, size: 16),
              label: const Text('PDF'),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: widget.onNewUpload,
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('New'),
          ),
        ],
      ),
    );
  }
}

class _EngineToggle extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _EngineToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(value == 'llm' ? 'nlp' : 'llm'),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.bgElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.borderBright),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value == 'llm' ? Icons.psychology : Icons.memory,
              size: 14,
              color: value == 'llm' ? AppTheme.accent : AppTheme.accentGreen,
            ),
            const SizedBox(width: 4),
            Text(
              value == 'llm' ? 'LLM' : 'NLP',
              style: TextStyle(
                color:
                    value == 'llm' ? AppTheme.accent : AppTheme.accentGreen,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

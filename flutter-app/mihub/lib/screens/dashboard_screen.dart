import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../models/session_model.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
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

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  String _engine = 'llm';
  bool _isExporting = false;

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
      if (mounted) _showError(e.message);
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
      if (mounted) _showError(e.message);
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.accentRed),
    );
  }

  void _onNavTap(int index) {
    if (index == 3) {
      widget.onNewUpload();
    } else {
      setState(() => _selectedIndex = index);
    }
  }

  void _showExportSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(),
            const SizedBox(height: 20),
            Text('Export Report', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text('Download your meeting analysis',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),
            _exportTile(
              icon: Icons.table_chart_outlined,
              iconColor: AppTheme.accentGreen,
              label: 'Export as CSV',
              subtitle: 'Spreadsheet with decisions & actions',
              onTap: () {
                Navigator.pop(context);
                _exportCsv();
              },
            ),
            const SizedBox(height: 12),
            _exportTile(
              icon: Icons.picture_as_pdf_outlined,
              iconColor: AppTheme.accentRed,
              label: 'Export as PDF',
              subtitle: 'Formatted report document',
              onTap: () {
                Navigator.pop(context);
                _exportPdf();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetHandle() {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: AppTheme.borderBright,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _exportTile({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppTheme.bgElevated,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: AppTheme.textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showSessionInfo() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: _sheetHandle()),
            const SizedBox(height: 20),
            Text('Session Details',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            _infoRow(Icons.fingerprint, 'Session ID',
                widget.session.sessionId),
            _infoRow(Icons.insert_drive_file_outlined, 'File',
                widget.session.filename),
            _infoRow(Icons.segment, 'Segments',
                '${widget.session.segmentCount}'),
            _infoRow(Icons.text_fields, 'Characters',
                '${widget.session.charCount}'),
            _infoRow(Icons.people_outline, 'Speakers',
                widget.session.speakers.join(', ')),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: AppTheme.textMuted),
          const SizedBox(width: 12),
          SizedBox(
            width: 88,
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
      appBar: _buildAppBar(),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          ExtractionTab(
              sessionId: widget.session.sessionId, engine: _engine),
          ChatTab(sessionId: widget.session.sessionId),
          TranscriptTab(sessionId: widget.session.sessionId),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Meeting Intelligence',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          Text(
            widget.session.filename,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w400,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: [
        _EngineToggle(
          value: _engine,
          onChanged: (v) => setState(() => _engine = v),
        ),
        const SizedBox(width: 4),
        _isExporting
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.accent),
                ),
              )
            : IconButton(
                icon: const Icon(Icons.ios_share_outlined, size: 20),
                onPressed: _showExportSheet,
                tooltip: 'Export',
              ),
        IconButton(
          icon: const Icon(Icons.info_outline, size: 20),
          onPressed: _showSessionInfo,
          tooltip: 'Session info',
        ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppTheme.border),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.border, width: 1)),
      ),
      child: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onNavTap,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.bolt_outlined),
            selectedIcon: Icon(Icons.bolt_rounded),
            label: 'Extract',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.article_outlined),
            selectedIcon: Icon(Icons.article_rounded),
            label: 'Transcript',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle_rounded),
            label: 'New',
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
    final isLlm = value == 'llm';
    return GestureDetector(
      onTap: () => onChanged(isLlm ? 'nlp' : 'llm'),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isLlm
              ? AppTheme.accentGlow
              : AppTheme.accentGreen.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isLlm
                ? AppTheme.borderGlow
                : AppTheme.accentGreen.withOpacity(0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isLlm ? Icons.psychology_outlined : Icons.memory_outlined,
              size: 13,
              color: isLlm ? AppTheme.accentLight : AppTheme.accentGreen,
            ),
            const SizedBox(width: 5),
            Text(
              isLlm ? 'LLM' : 'NLP',
              style: TextStyle(
                color: isLlm ? AppTheme.accentLight : AppTheme.accentGreen,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
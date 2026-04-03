import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../models/session_model.dart';
import '../theme/app_theme.dart';
import '../widgets/status_badge.dart';

class UploadScreen extends StatefulWidget {
  final Function(SessionModel) onUploadSuccess;

  const UploadScreen({super.key, required this.onUploadSuccess});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen>
    with SingleTickerProviderStateMixin {
  bool _isUploading = false;
  bool _isCheckingHealth = false;
  String? _errorMessage;
  String? _uploadStatus;
  bool _backendOnline = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  final TextEditingController _urlController =
      TextEditingController(text: ApiService.baseUrl);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _pulseAnim =
        Tween<double>(begin: 0.85, end: 1.0).animate(_pulseController);
    _checkHealth();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _checkHealth() async {
    setState(() => _isCheckingHealth = true);
    try {
      await ApiService.getHealth();
      if (mounted) setState(() => _backendOnline = true);
    } catch (_) {
      if (mounted) setState(() => _backendOnline = false);
    } finally {
      if (mounted) setState(() => _isCheckingHealth = false);
    }
  }

  Future<void> _pickAndUpload() async {
    setState(() {
      _errorMessage = null;
      _uploadStatus = null;
    });

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'vtt'],
    );

    if (result == null || result.files.isEmpty) return;

    final path = result.files.single.path;
    if (path == null) {
      setState(() => _errorMessage = 'Could not access the selected file.');
      return;
    }

    final ext = path.split('.').last.toLowerCase();
    if (ext != 'txt' && ext != 'vtt') {
      setState(() => _errorMessage = 'Only .txt and .vtt files are supported.');
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadStatus = 'Uploading transcript…';
    });

    try {
      final file = File(path);
      final session = await ApiService.uploadTranscript(file);
      if (mounted) {
        setState(() => _uploadStatus = 'Upload successful!');
        await Future.delayed(const Duration(milliseconds: 300));
        widget.onUploadSuccess(session);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _isUploading = false;
          _uploadStatus = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage =
              'Connection failed. Is the backend running at ${ApiService.baseUrl}?';
          _isUploading = false;
          _uploadStatus = null;
        });
      }
    }
  }

  void _saveUrl() {
    ApiService.setBaseUrl(_urlController.text.trim());
    _checkHealth();
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Backend URL updated to ${ApiService.baseUrl}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              _buildHeader(),
              const SizedBox(height: 32),
              _buildBackendCard(),
              const SizedBox(height: 24),
              _buildUploadCard(),
              const SizedBox(height: 24),
              _buildFormatGuide(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppTheme.accent.withOpacity(0.3), width: 1),
              ),
              child: const Icon(Icons.hub_rounded,
                  color: AppTheme.accent, size: 28),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Meeting Intelligence',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontSize: 22)),
                Text('Hub',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontSize: 22, color: AppTheme.accent)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Upload a meeting transcript to extract decisions, action items, and chat with your meeting data.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _buildBackendCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Backend',
                    style: Theme.of(context).textTheme.titleMedium),
                StatusBadge(
                  label: _isCheckingHealth
                      ? 'Checking…'
                      : (_backendOnline ? 'Online' : 'Offline'),
                  color: _isCheckingHealth
                      ? AppTheme.accentAmber
                      : (_backendOnline
                          ? AppTheme.accentGreen
                          : AppTheme.accentRed),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: AppTheme.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Backend URL',
                      labelStyle: TextStyle(color: AppTheme.textMuted),
                      hintText: 'http://10.0.2.2:8000',
                    ),
                    onSubmitted: (_) => _saveUrl(),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: _saveUrl,
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14)),
                  child: const Text('Set'),
                ),
                const SizedBox(width: 6),
                IconButton(
                  onPressed: _checkHealth,
                  icon: const Icon(Icons.refresh_rounded,
                      color: AppTheme.textSecondary),
                  tooltip: 'Re-check health',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '• Android emulator: http://10.0.2.2:8000\n'
              '• iOS simulator: http://localhost:8000\n'
              '• Physical device: http://<your-machine-IP>:8000',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(height: 1.8),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            GestureDetector(
              onTap: _isUploading ? null : _pickAndUpload,
              child: AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, __) => Transform.scale(
                  scale: _isUploading ? 1.0 : _pulseAnim.value,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    decoration: BoxDecoration(
                      color: AppTheme.bgElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isUploading
                            ? AppTheme.accent
                            : AppTheme.borderBright,
                        width: _isUploading ? 2 : 1,
                        strokeAlign: BorderSide.strokeAlignInside,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isUploading)
                          const CircularProgressIndicator(
                              color: AppTheme.accent)
                        else
                          const Icon(Icons.upload_file_rounded,
                              size: 48, color: AppTheme.accent),
                        const SizedBox(height: 16),
                        Text(
                          _isUploading
                              ? (_uploadStatus ?? 'Uploading…')
                              : 'Tap to select a transcript',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                  color: _isUploading
                                      ? AppTheme.accentLight
                                      : AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 6),
                        if (!_isUploading)
                          Text('.txt or .vtt files',
                              style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.accentRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppTheme.accentRed.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: AppTheme.accentRed, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_errorMessage!,
                          style: const TextStyle(
                              color: AppTheme.accentRed, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ],
            if (!_isUploading) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _backendOnline ? _pickAndUpload : null,
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Upload Transcript'),
                ),
              ),
              if (!_backendOnline)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Backend must be online to upload.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppTheme.accentAmber),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFormatGuide() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.description_outlined,
                    size: 18, color: AppTheme.textSecondary),
                const SizedBox(width: 8),
                Text('Transcript Format Guide',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 14),
            _formatSection(
              '.txt — Plain text',
              'Alice: We need to finalize the Q3 budget by Friday.\nBob: Agreed. I\'ll send the numbers by Thursday.',
            ),
            const SizedBox(height: 12),
            _formatSection(
              '.vtt — WebVTT',
              'WEBVTT\n\n00:00:01.000 --> 00:00:04.000\nAlice: We need to finalize the Q3 budget.\n\n00:00:05.000 --> 00:00:08.000\n<v Bob>I\'ll send the numbers by Thursday.</v>',
            ),
          ],
        ),
      ),
    );
  }

  Widget _formatSection(String title, String code) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.bgDeep,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.border),
          ),
          child: Text(
            code,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: AppTheme.accentLight,
              height: 1.6,
            ),
          ),
        ),
      ],
    );
  }
}

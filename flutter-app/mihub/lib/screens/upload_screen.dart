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
        Tween<double>(begin: 0.97, end: 1.0).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
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
      setState(
          () => _errorMessage = 'Only .txt and .vtt files are supported.');
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
      SnackBar(
          content:
              Text('Backend URL updated to ${ApiService.baseUrl}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),
              _buildHeader(),
              const SizedBox(height: 32),
              _buildUploadCard(),
              const SizedBox(height: 20),
              _buildBackendCard(),
              const SizedBox(height: 32),
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
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.accent.withOpacity(0.3),
                    AppTheme.accentPurple.withOpacity(0.2),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppTheme.accent.withOpacity(0.3), width: 1),
              ),
              child: const Icon(Icons.hub_rounded,
                  color: AppTheme.accent, size: 26),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                        letterSpacing: -0.5),
                    children: [
                      TextSpan(text: 'Meeting '),
                      TextSpan(
                          text: 'Intelligence',
                          style: TextStyle(color: AppTheme.accent)),
                    ],
                  ),
                ),
                const Text('Hub',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                        letterSpacing: -0.5)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          'Upload a meeting transcript to extract decisions, action items, and chat with your meeting data.',
          style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
              height: 1.6),
        ),
      ],
    );
  }

  Widget _buildUploadCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _isUploading ? null : _pickAndUpload,
          child: AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Transform.scale(
              scale: _isUploading ? 1.0 : _pulseAnim.value,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 48),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _isUploading
                        ? [
                            AppTheme.accentGlow,
                            AppTheme.bgElevated,
                          ]
                        : [
                            AppTheme.bgElevated,
                            AppTheme.bgCard,
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isUploading
                        ? AppTheme.borderGlow
                        : AppTheme.borderBright,
                    width: _isUploading ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isUploading)
                      const CircularProgressIndicator(
                          color: AppTheme.accent, strokeWidth: 2.5)
                    else
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withOpacity(0.1),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AppTheme.accent.withOpacity(0.2)),
                        ),
                        child: const Icon(Icons.upload_file_rounded,
                            size: 36, color: AppTheme.accent),
                      ),
                    const SizedBox(height: 18),
                    Text(
                      _isUploading
                          ? (_uploadStatus ?? 'Uploading…')
                          : 'Tap to select a transcript',
                      style: TextStyle(
                          color: _isUploading
                              ? AppTheme.accentLight
                              : AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    if (!_isUploading)
                      const Text('.txt  ·  .vtt',
                          style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 12,
                              letterSpacing: 1)),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.accentRed.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppTheme.accentRed.withOpacity(0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline,
                    color: AppTheme.accentRed, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_errorMessage!,
                      style: const TextStyle(
                          color: AppTheme.accentRed, fontSize: 13,height: 1.4)),
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
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: const Text('Upload Transcript'),
            ),
          ),
          if (!_backendOnline && !_isCheckingHealth)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 14, color: AppTheme.accentAmber),
                  const SizedBox(width: 6),
                  Text(
                    'Backend must be online to upload',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppTheme.accentAmber, fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildBackendCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Backend Server',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
              Row(
                children: [
                  if (_isCheckingHealth)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.accent),
                    )
                  else
                    StatusBadge(
                      label: _backendOnline ? 'Online' : 'Offline',
                      color: _backendOnline
                          ? AppTheme.accentGreen
                          : AppTheme.accentRed,
                    ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _checkHealth,
                    child: const Icon(Icons.refresh_rounded,
                        size: 18, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
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
                    isDense: true,
                  ),
                  onSubmitted: (_) => _saveUrl(),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: _saveUrl,
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14)),
                child: const Text('Set'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _connectionHint('Emulator', 'http://10.0.2.2:8000'),
              _connectionHint('iOS Sim', 'http://localhost:8000'),
              _connectionHint('Device', 'http://<LAN-IP>:8000'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _connectionHint(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
            fontSize: 11, fontFamily: 'monospace', height: 1.8),
        children: [
          TextSpan(
              text: '$label  ',
              style: const TextStyle(color: AppTheme.textMuted)),
          TextSpan(
              text: value,
              style: const TextStyle(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}
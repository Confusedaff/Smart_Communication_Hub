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
  int _reconnectAttempts = 0;
  bool _isReconnecting = false;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectInterval = Duration(seconds: 2);

  // Mode switcher — how the uploaded file should be interpreted and answered.
  // "auto" (default) classifies meeting-vs-document automatically.
  String _docType = 'auto'; // 'auto' | 'meeting' | 'document'
  String _chatMode = 'document'; // 'document' (grounded) | 'general' (blended)

  static const List<String> _acceptedExtensions = [
    'txt', 'vtt', 'pdf', 'docx', 'pptx', 'xlsx', 'xls',
  ];

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
    _pulseAnim = Tween<double>(begin: 0.97, end: 1.0).animate(CurvedAnimation(
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
      if (mounted) {
        setState(() {
          _backendOnline = true;
          _reconnectAttempts = 0;
          _isReconnecting = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _backendOnline = false);
    } finally {
      if (mounted) setState(() => _isCheckingHealth = false);
    }
  }

  /// Called after the user taps "Set" — updates the URL and starts
  /// auto-reconnect attempts until the backend responds or we give up.
  Future<void> _saveUrlAndReconnect() async {
    final newUrl = _urlController.text.trim();
    if (newUrl.isEmpty) return;

    ApiService.setBaseUrl(newUrl);
    FocusScope.of(context).unfocus();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Backend URL updated — trying to connect…')),
    );

    setState(() {
      _backendOnline = false;
      _reconnectAttempts = 0;
      _isReconnecting = true;
      _errorMessage = null;
    });

    await _autoReconnect();
  }

  Future<void> _autoReconnect() async {
    while (_reconnectAttempts < _maxReconnectAttempts) {
      if (!mounted) return;

      setState(() {
        _isCheckingHealth = true;
        _reconnectAttempts++;
      });

      try {
        await ApiService.getHealth();
        if (mounted) {
          setState(() {
            _backendOnline = true;
            _isReconnecting = false;
            _isCheckingHealth = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Connected successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
        return; // success — stop retrying
      } catch (_) {
        if (mounted) {
          setState(() {
            _backendOnline = false;
            _isCheckingHealth = false;
          });
        }
      }

      if (_reconnectAttempts < _maxReconnectAttempts) {
        await Future.delayed(_reconnectInterval);
      }
    }

    // All attempts exhausted
    if (mounted) {
      setState(() => _isReconnecting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not reach ${ApiService.baseUrl} after $_maxReconnectAttempts attempts.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickAndUpload() async {
    setState(() {
      _errorMessage = null;
      _uploadStatus = null;
    });

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _acceptedExtensions,
    );

    if (result == null || result.files.isEmpty) return;

    final path = result.files.single.path;
    if (path == null) {
      setState(() => _errorMessage = 'Could not access the selected file.');
      return;
    }

    final ext = path.split('.').last.toLowerCase();
    if (!_acceptedExtensions.contains(ext)) {
      setState(() => _errorMessage =
          'Unsupported file type. Accepted: ${_acceptedExtensions.map((e) => '.$e').join(', ')}');
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadStatus = 'Uploading file…';
    });

    try {
      final file = File(path);
      final session = await ApiService.uploadTranscript(
        file,
        docType: _docType,
        chatMode: _chatMode,
      );
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
              const SizedBox(height: 24),
              _buildModeSwitcher(),
              const SizedBox(height: 24),
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
    final t = AppTheme.of(context);
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
                    t.accent.withOpacity(0.3),
                    t.accentPurple.withOpacity(0.2),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: t.accent.withOpacity(0.3), width: 1),
              ),
              child: Icon(Icons.hub_rounded, color: t.accent, size: 26),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: t.textPrimary,
                        letterSpacing: -0.5),
                    children: [
                      const TextSpan(text: 'Meeting '),
                      TextSpan(
                          text: 'Intelligence',
                          style: TextStyle(color: t.accent)),
                    ],
                  ),
                ),
                Text('Hub',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: t.textPrimary,
                        letterSpacing: -0.5)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Upload a meeting transcript or any document — brochures, policies, reports — to extract insights and chat with your data.',
          style: TextStyle(
              color: t.textSecondary, fontSize: 14, height: 1.6),
        ),
      ],
    );
  }

  Widget _buildModeSwitcher() {
    final t = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Document type',
              style: TextStyle(
                  color: t.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _modePill(t, '🪄 Auto-detect', _docType == 'auto',
                  () => setState(() => _docType = 'auto')),
              _modePill(t, '🗣 Meeting transcript', _docType == 'meeting',
                  () => setState(() => _docType = 'meeting')),
              _modePill(t, '📄 General document', _docType == 'document',
                  () => setState(() => _docType = 'document')),
            ],
          ),
          const SizedBox(height: 16),
          Text('Chat style (changeable later)',
              style: TextStyle(
                  color: t.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _modePill(t, '🎯 Grounded', _chatMode == 'document',
                  () => setState(() => _chatMode = 'document')),
              _modePill(t, '🌐 General', _chatMode == 'general',
                  () => setState(() => _chatMode = 'general')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _modePill(
      AppThemeTokens t, String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? t.accent : t.bgElevated,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
              color: active ? t.accent : t.border, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? t.onAccent : t.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildUploadCard() {
    final t = AppTheme.of(context);
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
                        ? [t.accentGlow, t.bgElevated]
                        : [t.bgElevated, t.bgCard],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isUploading ? t.borderGlow : t.borderBright,
                    width: _isUploading ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isUploading)
                      CircularProgressIndicator(
                          color: t.accent, strokeWidth: 2.5)
                    else
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: t.accent.withOpacity(0.1),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: t.accent.withOpacity(0.2)),
                        ),
                        child: Icon(Icons.upload_file_rounded,
                            size: 36, color: t.accent),
                      ),
                    const SizedBox(height: 18),
                    Text(
                      _isUploading
                          ? (_uploadStatus ?? 'Uploading…')
                          : 'Tap to select a file',
                      style: TextStyle(
                          color: _isUploading ? t.accentLight : t.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    if (!_isUploading)
                      Text('.txt · .vtt · .pdf · .docx · .pptx · .xlsx',
                          style: TextStyle(
                              color: t.textMuted,
                              fontSize: 12,
                              letterSpacing: 0.5),
                          textAlign: TextAlign.center),
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
              color: t.accentRed.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.accentRed.withOpacity(0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: t.accentRed, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_errorMessage!,
                      style: TextStyle(
                          color: t.accentRed, fontSize: 13, height: 1.4)),
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
              label: const Text('Upload File'),
            ),
          ),
          if (!_backendOnline && !_isCheckingHealth)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 14, color: t.accentAmber),
                  const SizedBox(width: 6),
                  Text(
                    'Backend must be online to upload',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: t.accentAmber, fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildBackendCard() {
    final t = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Backend Server',
                  style: TextStyle(
                      color: t.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
              Row(
                children: [
                  if (_isCheckingHealth)
                    Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: t.accent),
                        ),
                        if (_isReconnecting) ...[
                          const SizedBox(width: 6),
                          Text(
                            '$_reconnectAttempts/$_maxReconnectAttempts',
                            style: TextStyle(
                                fontSize: 11,
                                color: t.textMuted),
                          ),
                        ],
                      ],
                    )
                  else
                    StatusBadge(
                      label: _backendOnline ? 'Online' : 'Offline',
                      color: _backendOnline ? t.accentGreen : t.accentRed,
                    ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _isReconnecting ? null : _checkHealth,
                    child: Icon(Icons.refresh_rounded,
                        size: 18,
                        color: _isReconnecting ? t.textMuted.withOpacity(0.4) : t.textMuted),
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
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: t.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Backend URL',
                    labelStyle: TextStyle(color: t.textMuted),
                    hintText: 'http://100.95.213.57:8000',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _saveUrlAndReconnect(),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: _isReconnecting ? null : _saveUrlAndReconnect,
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14)),
                child: Text(_isReconnecting ? 'Connecting…' : 'Set'),
              ),
            ],
          ),

          // Reconnect progress bar
          if (_isReconnecting) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _reconnectAttempts / _maxReconnectAttempts,
                backgroundColor: t.border,
                color: t.accent,
                minHeight: 3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Attempt $_reconnectAttempts of $_maxReconnectAttempts — retrying in ${_reconnectInterval.inSeconds}s…',
              style: TextStyle(fontSize: 11, color: t.textMuted),
            ),
          ],

          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _connectionHint(t, 'Render (cloud)', 'https://mihub-backend.onrender.com'),
              _connectionHint(t, 'Tailscale',  'http://100.95.213.57:8000'),
              _connectionHint(t, 'Emulator',   'http://10.0.2.2:8000'),
              _connectionHint(t, 'Device LAN', 'http://<LAN-IP>:8000'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _connectionHint(AppThemeTokens t, String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
            fontSize: 11, fontFamily: 'monospace', height: 1.8),
        children: [
          TextSpan(
              text: '$label  ', style: TextStyle(color: t.textMuted)),
          TextSpan(
              text: value, style: TextStyle(color: t.textSecondary)),
        ],
      ),
    );
  }
}
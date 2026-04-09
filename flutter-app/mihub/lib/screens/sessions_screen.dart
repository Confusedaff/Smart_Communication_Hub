import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../models/session_model.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/status_badge.dart';
import 'settings_screen.dart';

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1C1C1C)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;
    const cellSize = 80.0;
    for (double x = 0; x <= size.width; x += cellSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += cellSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}

class SessionsScreen extends StatefulWidget {
  final List<SessionModel> sessions;
  final Function(SessionModel) onOpen;
  final Function(SessionModel) onDelete;
  final Function(SessionModel) onUploadSuccess;
  final Function(List<SessionModel>) onSessionsRestored;
  final VoidCallback onOpenSettings;
  final VoidCallback? onOpenMultiChat;

  const SessionsScreen({
    super.key,
    required this.sessions,
    required this.onOpen,
    required this.onDelete,
    required this.onUploadSuccess,
    required this.onSessionsRestored,
    required this.onOpenSettings,
    this.onOpenMultiChat,
  });

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  // ── Upload state ──────────────────────────────────────────────────────────
  bool _isUploading = false;
  String? _uploadStatus;
  String? _errorMessage;

  // ── Backend / health state ────────────────────────────────────────────────
  bool _backendOnline = false;
  bool _isCheckingHealth = true; // true until first check completes
  bool _isReconnecting = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectInterval = Duration(seconds: 2);
  final TextEditingController _urlController =
      TextEditingController(text: 'http://100.95.213.57:8000');

  @override
  void initState() {
    super.initState();
    _checkHealth();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  // ── Health / reconnect ────────────────────────────────────────────────────

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
        // Restore sessions that the backend persisted — runs silently on every
        // cold start so the list is never empty after a restart.
        await _loadSessionsFromServer();
      }
    } catch (_) {
      if (mounted) setState(() => _backendOnline = false);
    } finally {
      if (mounted) setState(() => _isCheckingHealth = false);
    }
  }

  Future<void> _saveUrlAndReconnect() async {
    final newUrl = _urlController.text.trim();
    if (newUrl.isEmpty) return;
    ApiService.setBaseUrl(newUrl);
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Backend URL updated — trying to connect…')),
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
          await _loadSessionsFromServer();
        }
        return;
      } catch (_) {
        if (mounted) setState(() {
          _backendOnline = false;
          _isCheckingHealth = false;
        });
      }
      if (_reconnectAttempts < _maxReconnectAttempts) {
        await Future.delayed(_reconnectInterval);
      }
    }
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

  // ── Session restore ──────────────────────────────────────────────────────

  /// Fetches all sessions from the server and passes new ones to the parent
  /// via [onSessionsRestored] — NOT [onUploadSuccess].
  /// This is critical: onUploadSuccess also sets _activeSession which
  /// navigates to the dashboard, so we must never call it during restore.
  Future<void> _loadSessionsFromServer() async {
    try {
      final serverSessions = await ApiService.listSessions();
      if (!mounted) return;

      final existingIds = widget.sessions.map((s) => s.sessionId).toSet();
      final restored = <SessionModel>[];

      for (final raw in serverSessions) {
        final id = (raw['id'] ?? raw['session_id'] ?? '') as String;
        if (id.isEmpty || existingIds.contains(id)) continue;

        try {
          final detail = await ApiService.getSessionDetail(id);
          restored.add(SessionModel.fromJson(detail));
        } catch (_) {
          // Detail fetch failed — add a partial model so it still shows up.
          restored.add(SessionModel(
            sessionId: id,
            filename: (raw['filename'] ?? 'Unknown') as String,
            segmentCount: 0,
            speakers: const [],
            charCount: 0,
          ));
        }
      }

      if (mounted && restored.isNotEmpty) {
        widget.onSessionsRestored(restored);
      }
    } catch (_) {
      // Silently ignore — list stays empty if server unreachable.
    }
  }

  // ── Upload ────────────────────────────────────────────────────────────────

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
        setState(() {
          _isUploading = false;
          _uploadStatus = null;
        });
        Navigator.pop(context); // close bottom sheet
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

  Future<void> _pickAndUploadBatch() async {
    setState(() {
      _errorMessage = null;
      _uploadStatus = null;
    });

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'vtt'],
      allowMultiple: true,
    );

    if (result == null || result.files.isEmpty) return;

    final paths = result.files
        .map((f) => f.path)
        .whereType<String>()
        .where((p) {
          final ext = p.split('.').last.toLowerCase();
          return ext == 'txt' || ext == 'vtt';
        })
        .toList();

    if (paths.isEmpty) {
      setState(() => _errorMessage = 'No valid .txt or .vtt files selected.');
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadStatus =
          'Uploading ${paths.length} file${paths.length > 1 ? 's' : ''}…';
    });

    try {
      final files = paths.map((p) => File(p)).toList();
      final results = await ApiService.uploadBatch(files);

      int successCount = 0;
      final errors = <String>[];

      for (final r in results) {
        if (r.containsKey('session_id') && r['session_id'] != null) {
          successCount++;
          try {
            final detail =
                await ApiService.getSessionDetail(r['session_id'] as String);
            if (mounted) widget.onUploadSuccess(SessionModel.fromJson(detail));
          } catch (_) {
            if (mounted) {
              widget.onUploadSuccess(SessionModel(
                sessionId: r['session_id'] as String,
                filename: r['filename']?.toString() ?? 'Unknown',
                segmentCount: (r['segment_count'] as num?)?.toInt() ?? 0,
                speakers: List<String>.from(r['speakers'] ?? []),
                charCount: 0,
              ));
            }
          }
        } else if (r.containsKey('error')) {
          errors.add('${r['filename']}: ${r['error']}');
        }
      }

      if (mounted) {
        Navigator.pop(context);
        setState(() {
          _isUploading = false;
          _uploadStatus = null;
          if (errors.isNotEmpty) {
            _errorMessage =
                '$successCount uploaded.\nFailed:\n${errors.join('\n')}';
          }
        });
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
          _errorMessage = 'Batch upload failed. Is the backend running?';
          _isUploading = false;
          _uploadStatus = null;
        });
      }
    }
  }


  // ── Sheets ────────────────────────────────────────────────────────────────

  void _openUploadSheet() {
    setState(() {
      _errorMessage = null;
      _uploadStatus = null;
      _isUploading = false;
    });
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => _UploadSheet(
          parent: this,
          onClose: () => Navigator.pop(context),
        ),
      ),
    );
  }


  void _confirmDelete(SessionModel session) {
    final t = AppTheme.of(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: t.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete session?',
            style: TextStyle(color: t.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(
          'This will permanently remove "${session.filename}" from the server.',
          style: TextStyle(color: t.textSecondary, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: t.textMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onDelete(session);
            },
            child: Text('Delete', style: TextStyle(color: t.accentRed, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0D0D),
        extendBodyBehindAppBar: true,
        body: Stack(
          children: [
            // Grid background
            Positioned.fill(child: CustomPaint(painter: _GridPainter())),

            // Main content
            SafeArea(
              child: widget.sessions.isEmpty
                  ? _buildEmptyState(t)
                  : _buildSessionList(t),
            ),

            // Multi-chat FAB — bottom left (only when 2+ sessions)
            if (widget.onOpenMultiChat != null)
              SafeArea(
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24, left: 16),
                    child: FloatingActionButton.extended(
                      heroTag: 'multi_chat_fab',
                      onPressed: widget.onOpenMultiChat,
                      backgroundColor: const Color(0xFFA78BFA).withOpacity(0.15),
                      foregroundColor: const Color(0xFFA78BFA),
                      elevation: 2,
                      icon: const Icon(Icons.hub_outlined, size: 20),
                      label: const Text(
                        'Multi-Chat',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ),

            // Floating settings icon — top right
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12, right: 16),
                  child: GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => SettingsScreen(
                                sessionIds: widget.sessions
                                    .map((s) => s.sessionId)
                                    .toList(),
                              )),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: t.bgCard,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: t.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child:
                          Icon(Icons.settings_rounded, size: 20, color: t.textMuted),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: _buildFab(t),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      ),
    );
  }

  Widget _buildFab(AppThemeTokens t) {
    return FloatingActionButton.extended(
      heroTag: 'upload_fab',
      onPressed: _backendOnline ? _openUploadSheet : null,
      backgroundColor: _backendOnline ? t.accent : t.bgElevated,
      foregroundColor: _backendOnline ? Colors.black : t.textMuted,
      elevation: 4,
      icon: _isCheckingHealth
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: t.textMuted),
            )
          : const Icon(Icons.add_rounded, size: 22),
      label: Text(
        _isCheckingHealth
            ? 'Checking…'
            : _backendOnline
                ? 'New Transcript'
                : 'Backend Offline',
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    );
  }

  Widget _buildEmptyState(AppThemeTokens t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo / icon area
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    t.accent.withOpacity(0.25),
                    t.accentPurple.withOpacity(0.15),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: t.accent.withOpacity(0.3)),
              ),
              child: Icon(Icons.hub_rounded, color: t.accent, size: 48),
            ),
            const SizedBox(height: 28),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: t.textPrimary,
                    letterSpacing: -0.5,
                    height: 1.2),
                children: [
                  const TextSpan(text: 'Meeting\n'),
                  TextSpan(
                      text: 'Intelligence',
                      style: TextStyle(color: t.accent)),
                  const TextSpan(text: ' Hub'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Upload a transcript to extract decisions, action items, and chat with your meeting data.',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.textSecondary, fontSize: 14, height: 1.6),
            ),
            const SizedBox(height: 32),
            if (!_backendOnline && !_isCheckingHealth)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 14, color: t.accentAmber),
                    const SizedBox(width: 6),
                    Text('Backend offline — tap ⚙ to configure',
                        style: TextStyle(color: t.accentAmber, fontSize: 12)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionList(AppThemeTokens t) {
    return CustomScrollView(
      slivers: [
        // Header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        t.accent.withOpacity(0.3),
                        t.accentPurple.withOpacity(0.2),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.accent.withOpacity(0.3)),
                  ),
                  child: Icon(Icons.hub_rounded, color: t.accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: t.textPrimary,
                              letterSpacing: -0.3),
                          children: [
                            const TextSpan(text: 'Meeting '),
                            TextSpan(
                                text: 'Intelligence',
                                style: TextStyle(color: t.accent)),
                            const TextSpan(text: ' Hub'),
                          ],
                        ),
                      ),
                      Text(
                        '${widget.sessions.length} transcript${widget.sessions.length == 1 ? '' : 's'}',
                        style: TextStyle(color: t.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),

              ],
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 16)),

        // Session cards
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => _SessionCard(
                session: widget.sessions[i],
                onOpen: () => widget.onOpen(widget.sessions[i]),
                onDelete: () => _confirmDelete(widget.sessions[i]),
              ),
              childCount: widget.sessions.length,
            ),
          ),
        ),
      ],
    );
  }

  // ── Backend card (reused in settings sheet) ───────────────────────────────

  // ignore: unused_element
  Widget _buildBackendCard(AppThemeTokens t) {
    return Column(
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
                  Row(children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: t.accent),
                    ),
                    if (_isReconnecting) ...[
                      const SizedBox(width: 6),
                      Text('$_reconnectAttempts/$_maxReconnectAttempts',
                          style:
                              TextStyle(fontSize: 11, color: t.textMuted)),
                    ],
                  ])
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
                      color: _isReconnecting
                          ? t.textMuted.withOpacity(0.4)
                          : t.textMuted),
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
                    fontFamily: 'monospace', fontSize: 13, color: t.textPrimary),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
              child: Text(_isReconnecting ? 'Connecting…' : 'Set'),
            ),
          ],
        ),
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
            'Attempt $_reconnectAttempts of $_maxReconnectAttempts — retrying…',
            style: TextStyle(fontSize: 11, color: t.textMuted),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            _hint(t, 'Tailscale', 'http://100.95.213.57:8000'),
            _hint(t, 'Emulator', 'http://10.0.2.2:8000'),
            _hint(t, 'Device LAN', 'http://<LAN-IP>:8000'),
          ],
        ),
      ],
    );
  }

  Widget _hint(AppThemeTokens t, String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
            fontSize: 11, fontFamily: 'monospace', height: 1.8),
        children: [
          TextSpan(text: '$label  ', style: TextStyle(color: t.textMuted)),
          TextSpan(text: value, style: TextStyle(color: t.textSecondary)),
        ],
      ),
    );
  }
}

// ── Upload bottom sheet ───────────────────────────────────────────────────────

class _UploadSheet extends StatelessWidget {
  final _SessionsScreenState parent;
  final VoidCallback onClose;

  const _UploadSheet({required this.parent, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: t.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: t.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
                20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: t.accent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: t.accent.withOpacity(0.25)),
                      ),
                      child: Icon(Icons.upload_file_rounded,
                          color: t.accent, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Text('Upload Transcript',
                        style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 20),

                // Upload tap area
                GestureDetector(
                  onTap: parent._isUploading ? null : parent._pickAndUpload,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: parent._isUploading
                            ? [t.accentGlow, t.bgElevated]
                            : [t.bgElevated, t.bgCard],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: parent._isUploading
                            ? t.borderGlow
                            : t.borderBright,
                        width: parent._isUploading ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (parent._isUploading)
                          CircularProgressIndicator(
                              color: t.accent, strokeWidth: 2.5)
                        else
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: t.accent.withOpacity(0.1),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: t.accent.withOpacity(0.2)),
                            ),
                            child: Icon(Icons.upload_file_rounded,
                                size: 30, color: t.accent),
                          ),
                        const SizedBox(height: 14),
                        Text(
                          parent._isUploading
                              ? (parent._uploadStatus ?? 'Uploading…')
                              : 'Tap to select a transcript',
                          style: TextStyle(
                              color: parent._isUploading
                                  ? t.accentLight
                                  : t.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        if (!parent._isUploading)
                          Text('.txt  ·  .vtt',
                              style: TextStyle(
                                  color: t.textMuted,
                                  fontSize: 12,
                                  letterSpacing: 1)),
                      ],
                    ),
                  ),
                ),

                // Error message
                if (parent._errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: t.accentRed.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: t.accentRed.withOpacity(0.25)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline,
                            color: t.accentRed, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(parent._errorMessage!,
                              style: TextStyle(
                                  color: t.accentRed,
                                  fontSize: 12,
                                  height: 1.4)),
                        ),
                      ],
                    ),
                  ),
                ],

                if (!parent._isUploading) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: parent._backendOnline
                          ? parent._pickAndUpload
                          : null,
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      label: const Text('Upload Transcript'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: parent._backendOnline
                          ? parent._pickAndUploadBatch
                          : null,
                      icon: const Icon(Icons.folder_open_outlined, size: 18),
                      label: const Text('Batch Upload (multiple files)'),
                    ),
                  ),
                  if (!parent._backendOnline && !parent._isCheckingHealth)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 14, color: t.accentAmber),
                          const SizedBox(width: 6),
                          Text('Backend must be online to upload',
                              style: TextStyle(
                                  color: t.accentAmber, fontSize: 12)),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Session card ──────────────────────────────────────────────────────────────

class _SessionCard extends StatelessWidget {
  final SessionModel session;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _SessionCard({
    required this.session,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final ext = session.filename.split('.').last.toUpperCase();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey(session.sessionId),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) async {
          onDelete();
          return false; // we handle removal ourselves
        },
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: t.accentRed.withOpacity(0.15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.accentRed.withOpacity(0.3)),
          ),
          child: Icon(Icons.delete_outline_rounded,
              color: t.accentRed, size: 22),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: t.bgCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: t.border),
              ),
              child: Row(
                children: [
                  // File type badge
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: t.accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: t.accent.withOpacity(0.2)),
                    ),
                    child: Center(
                      child: Text(
                        ext,
                        style: TextStyle(
                          color: t.accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.filename,
                          style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _chip(t, Icons.segment,
                                '${session.segmentCount} segs'),
                            const SizedBox(width: 10),
                            if (session.speakers.isNotEmpty)
                              _chip(t, Icons.people_outline,
                                  '${session.speakers.length} speakers'),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Arrow
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right_rounded,
                      color: t.textMuted, size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(AppThemeTokens t, IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: t.textMuted),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(color: t.textMuted, fontSize: 11)),
      ],
    );
  }
}
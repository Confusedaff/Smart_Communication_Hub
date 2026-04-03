import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/status_badge.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _urlController =
      TextEditingController(text: ApiService.baseUrl);
  bool _isCheckingHealth = false;
  bool? _backendOnline;
  Map<String, dynamic>? _healthData;

  @override
  void initState() {
    super.initState();
    _checkHealth();
  }

  Future<void> _checkHealth() async {
    setState(() {
      _isCheckingHealth = true;
      _healthData = null;
    });
    try {
      final data = await ApiService.getHealth();
      if (mounted) {
        setState(() {
          _backendOnline = true;
          _healthData = data;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _backendOnline = false);
    } finally {
      if (mounted) setState(() => _isCheckingHealth = false);
    }
  }

  void _saveUrl() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    ApiService.setBaseUrl(url);
    _checkHealth();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Backend URL updated to $url')),
    );
  }

  Future<void> _clearAllHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear All Chat History',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        content: const Text(
            'This will clear all locally cached chat history.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentRed),
              child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      final keys =
          prefs.getKeys().where((k) => k.startsWith('chat_history_'));
      for (final k in keys) {
        await prefs.remove(k);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All chat history cleared.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel('Backend'),
            _buildBackendCard(),
            const SizedBox(height: 28),
            _sectionLabel('Storage'),
            _buildStorageCard(),
            const SizedBox(height: 28),
            _sectionLabel('About'),
            _buildAboutCard(),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 2),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2),
      ),
    );
  }

  Widget _buildBackendCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Server Status',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13)),
                _isCheckingHealth
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.accent))
                    : StatusBadge(
                        label: _backendOnline == null
                            ? '—'
                            : (_backendOnline! ? 'Online' : 'Offline'),
                        color: _backendOnline == null
                            ? AppTheme.textMuted
                            : (_backendOnline!
                                ? AppTheme.accentGreen
                                : AppTheme.accentRed),
                      ),
              ],
            ),
          ),
          if (_healthData != null) ...[
            Container(height: 1, color: AppTheme.border),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  _infoRow(
                      'Version', _healthData!['version']?.toString() ?? '—'),
                  _infoRow('Extractor',
                      _healthData!['extractor_engine']?.toString() ?? '—'),
                  _infoRow('Sessions',
                      _healthData!['active_sessions']?.toString() ?? '—'),
                ],
              ),
            ),
          ],
          Container(height: 1, color: AppTheme.border),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _urlController,
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Backend URL',
                    hintText: 'http://10.0.2.2:8000',
                  ),
                  onSubmitted: (_) => _saveUrl(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                          onPressed: _saveUrl,
                          child: const Text('Save URL')),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: _checkHealth,
                      icon: const Icon(Icons.refresh_rounded, size: 15),
                      label: const Text('Test'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.bgElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    children: [
                      _hintRow('Android emulator',
                          'http://10.0.2.2:8000'),
                      _hintRow(
                          'iOS simulator', 'http://localhost:8000'),
                      _hintRow('Physical device',
                          'http://<LAN-IP>:8000'),
                      _hintRow('AWS/deployed',
                          'https://your-domain.com'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hintRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                    fontFamily: 'monospace')),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: _clearAllHistory,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.accentRed.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.delete_sweep_outlined,
                      color: AppTheme.accentRed, size: 20),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Clear All Chat History',
                          style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w500,
                              fontSize: 14)),
                      SizedBox(height: 2),
                      Text(
                          'Remove all locally cached conversation history',
                          style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: AppTheme.textMuted, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAboutCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          _infoRow('App', 'Meeting Intelligence Hub'),
          _infoRow('Version', '1.0.0'),
          _infoRow('Backend', 'FastAPI + Groq/Ollama'),
          _infoRow('Repo',
              'github.com/Confusedaff/Smart_Communication_Hub'),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(label,
                style: const TextStyle(
                    color: AppTheme.textMuted, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }
}
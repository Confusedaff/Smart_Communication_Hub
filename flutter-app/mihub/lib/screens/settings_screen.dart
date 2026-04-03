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
        title: const Text('Clear All Chat History'),
        content: const Text(
            'This will clear all locally cached chat history. Are you sure?',
            style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppTheme.accentRed),
              child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('chat_history_'));
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
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Backend Configuration'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                                    strokeWidth: 2,
                                    color: AppTheme.accent))
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
                    if (_healthData != null) ...[
                      const SizedBox(height: 8),
                      _infoRow('Version',
                          _healthData!['version']?.toString() ?? '—'),
                      _infoRow('Extractor',
                          _healthData!['extractor_engine']?.toString() ?? '—'),
                      _infoRow('Sessions',
                          _healthData!['active_sessions']?.toString() ?? '—'),
                    ],
                    const SizedBox(height: 14),
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
                    const SizedBox(height: 10),
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
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('Test'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text('Connection tips:',
                        style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(height: 6),
                    const Text(
                      '• Android emulator: http://10.0.2.2:8000\n'
                      '• iOS simulator: http://localhost:8000\n'
                      '• Physical device: http://<LAN-IP>:8000\n'
                      '• AWS/deployed: https://your-domain.com',
                      style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                          height: 1.8,
                          fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            _sectionTitle('Storage'),
            Card(
              child: ListTile(
                leading: const Icon(Icons.delete_sweep_outlined,
                    color: AppTheme.accentRed),
                title: const Text('Clear All Chat History'),
                subtitle: const Text(
                    'Remove all locally cached conversation history',
                    style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.chevron_right,
                    color: AppTheme.textMuted),
                onTap: _clearAllHistory,
              ),
            ),
            const SizedBox(height: 24),
            _sectionTitle('About'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoRow('App', 'Meeting Intelligence Hub'),
                    _infoRow('Version', '1.0.0'),
                    _infoRow('Backend', 'FastAPI + Groq/Ollama'),
                    _infoRow('Repo', 'github.com/Confusedaff/Smart_Communication_Hub'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
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

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(
                    color: AppTheme.textMuted, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

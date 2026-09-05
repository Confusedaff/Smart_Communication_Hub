import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_notifier.dart';
import '../widgets/status_badge.dart';

class SettingsScreen extends StatefulWidget {
  /// Pass the currently known session IDs so we can clear their chat history
  /// without needing an extra network call to list sessions.
  final List<String> sessionIds;

  /// Called after the user confirms logout, so main.dart can flip back to
  /// the login screen and drop all in-memory session state.
  final VoidCallback? onLoggedOut;

  const SettingsScreen({super.key, this.sessionIds = const [], this.onLoggedOut});

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

  bool _isClearingHistory = false;

  Future<void> _clearAllHistory() async {
    final t = AppTheme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: t.bgCard,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Clear All Chat History',
            style: TextStyle(color: t.textPrimary, fontSize: 16)),
        content: Text(
            'This will clear chat history for all sessions on the server.',
            style: TextStyle(color: t.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style:
                  ElevatedButton.styleFrom(backgroundColor: t.accentRed),
              child: const Text('Clear')),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isClearingHistory = true);

    try {
      // Always fetch the live session list from the server so we don't miss
      // sessions that were created after this screen was opened, or sessions
      // that weren't passed in via widget.sessionIds.
      final fetched = await ApiService.listSessions();
      final ids = fetched
          .map((s) => (s['id'] ?? s['session_id'] ?? '') as String)
          .where((id) => id.isNotEmpty)
          .toList();

      if (ids.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No sessions found to clear.')),
          );
        }
        return;
      }

      int cleared = 0;
      int failed = 0;
      for (final id in ids) {
        try {
          await ApiService.clearChatHistory(id);
          cleared++;
        } catch (_) {
          // Session may already have empty history or be unavailable — continue
          failed++;
        }
      }

      if (mounted) {
        final msg = failed == 0
            ? 'Chat history cleared for $cleared session${cleared == 1 ? '' : 's'}.'
            : 'Cleared $cleared session${cleared == 1 ? '' : 's'}, $failed could not be reached.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to clear history: $e'),
            backgroundColor: t.accentRed,
          ),
        );
      }
    } finally {
      // Always reset the loading state, even if we returned early above
      if (mounted) setState(() => _isClearingHistory = false);
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
            _sectionLabel('Account'),
            _buildAccountCard(),
            const SizedBox(height: 28),
            _sectionLabel('Appearance'),
            _buildThemeCard(),
            const SizedBox(height: 28),
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
    final t = AppTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 2),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
            color: t.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2),
      ),
    );
  }

  // ── Account card ───────────────────────────────────────────────────────────

  Future<void> _confirmLogout() async {
    final t = AppTheme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: t.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Log Out', style: TextStyle(color: t.textPrimary, fontSize: 16)),
        content: Text(
          "You'll need to sign in again to access your meeting history.",
          style: TextStyle(color: t.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: t.accentRed),
              child: const Text('Log Out')),
        ],
      ),
    );

    if (confirmed != true) return;

    await AuthService.logout();
    if (!mounted) return;

    // Pop back to the app shell first, then flip main.dart's auth state so
    // the login screen replaces everything (including this settings screen).
    Navigator.of(context).popUntil((route) => route.isFirst);
    widget.onLoggedOut?.call();
  }

  Widget _buildAccountCard() {
    final t = AppTheme.of(context);
    final user = AuthService.currentUser;

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
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: t.accent.withOpacity(0.15),
                child: Text(
                  (user?.displayName?.isNotEmpty == true
                          ? user!.displayName![0]
                          : (user?.email.isNotEmpty == true ? user!.email[0] : '?'))
                      .toUpperCase(),
                  style: TextStyle(
                      color: t.accent, fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.displayName?.isNotEmpty == true
                          ? user!.displayName!
                          : (user?.email ?? 'Signed in'),
                      style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                    ),
                    if (user?.displayName?.isNotEmpty == true)
                      Text(user!.email,
                          style: TextStyle(color: t.textMuted, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _confirmLogout,
              icon: Icon(Icons.logout, size: 18, color: t.accentRed),
              label: Text('Log Out', style: TextStyle(color: t.accentRed)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: t.accentRed.withOpacity(0.4)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Theme picker ───────────────────────────────────────────────────────────

  Widget _buildThemeCard() {
    final t = AppTheme.of(context);
    final notifier = context.watch<ThemeNotifier>();
    final current = notifier.mode;

    // Use the actual token values for the preview swatches — they will always
    // show the correct colours regardless of which theme is active.
    final blueTokens = AppThemeTokens.blue;
    final greenTokens = AppThemeTokens.green;

    return Container(
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'App Theme',
            style: TextStyle(
                color: t.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ThemeOption(
                  label: 'Terminal Green',
                  description: 'Mint green dark',
                  accentColor: greenTokens.accent,
                  bgColor: greenTokens.bgDeep,
                  cardColor: greenTokens.bgCard,
                  isSelected: current == AppThemeMode.green,
                  onTap: () => notifier.setMode(AppThemeMode.green),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ThemeOption(
                  label: 'Ocean Blue',
                  description: 'Original dark blue',
                  accentColor: blueTokens.accent,
                  bgColor: blueTokens.bgDeep,
                  cardColor: blueTokens.bgCard,
                  isSelected: current == AppThemeMode.blue,
                  onTap: () => notifier.setMode(AppThemeMode.blue),
                ),
              ),
            ],
          ),
          if (current == AppThemeMode.green) ...[
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: t.accentGlow,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.accent.withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 13, color: t.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Restart the app if some screens haven\'t updated yet.',
                      style: TextStyle(
                          color: t.accent, fontSize: 11, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Backend card ───────────────────────────────────────────────────────────

  Widget _buildBackendCard() {
    final t = AppTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Server Status',
                    style: TextStyle(color: t.textSecondary, fontSize: 13)),
                _isCheckingHealth
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: t.accent))
                    : StatusBadge(
                        label: _backendOnline == null
                            ? '—'
                            : (_backendOnline! ? 'Online' : 'Offline'),
                        color: _backendOnline == null
                            ? t.textMuted
                            : (_backendOnline! ? t.accentGreen : t.accentRed),
                      ),
              ],
            ),
          ),
          if (_healthData != null) ...[
            Container(height: 1, color: t.border),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  _infoRow('Version',
                      _healthData!['version']?.toString() ?? '—'),
                  _infoRow('Extractor',
                      _healthData!['extractor_engine']?.toString() ?? '—'),
                  _infoRow('Sessions',
                      _healthData!['active_sessions']?.toString() ?? '—'),
                ],
              ),
            ),
          ],
          Container(height: 1, color: t.border),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _urlController,
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: t.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Backend URL',
                    hintText: 'https://mihub-backend.onrender.com',
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
                    color: t.bgElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: t.border),
                  ),
                  child: Column(
                    children: [
                      _hintRow('Render (deployed)', 'https://mihub-backend.onrender.com'),
                      _hintRow('Tailscale', 'http://100.95.213.57:8000'),
                      _hintRow('iOS simulator', 'http://localhost:8000'),
                      _hintRow('Physical device', 'http://<LAN-IP>:8000'),
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
    final t = AppTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: TextStyle(
                    color: t.textMuted,
                    fontSize: 11,
                    fontFamily: 'monospace')),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 11,
                    fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  // ── Storage card ───────────────────────────────────────────────────────────

  Widget _buildStorageCard() {
    final t = AppTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: _isClearingHistory ? null : _clearAllHistory,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: t.accentRed.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _isClearingHistory
                      ? Padding(
                          padding: const EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: t.accentRed),
                        )
                      : Icon(Icons.delete_sweep_outlined,
                          color: t.accentRed, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Clear All Chat History',
                          style: TextStyle(
                              color: _isClearingHistory
                                  ? t.textMuted
                                  : t.textPrimary,
                              fontWeight: FontWeight.w500,
                              fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(
                          _isClearingHistory
                              ? 'Clearing…'
                              : 'Remove conversation history from all sessions',
                          style: TextStyle(
                              color: t.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                if (!_isClearingHistory)
                  Icon(Icons.chevron_right, color: t.textMuted, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── About card ─────────────────────────────────────────────────────────────

  Widget _buildAboutCard() {
    final t = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          _infoRow('App', 'Meeting Intelligence Hub'),
          _infoRow('Version', '1.0.0'),
          _infoRow('Backend', 'FastAPI + Groq/Ollama'),
          _infoRow('Repo', 'github.com/Confusedaff/Smart_Communication_Hub'),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    final t = AppTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(label,
                style: TextStyle(color: t.textMuted, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 12,
                    fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ThemeOption — visual theme swatch card
// The preview uses its own accentColor/bgColor/cardColor props (which are the
// actual token values for that specific theme), so it always shows the correct
// preview colours regardless of which theme is currently active.
// ─────────────────────────────────────────────────────────────────────────────
class _ThemeOption extends StatelessWidget {
  final String label;
  final String description;
  final Color accentColor;
  final Color bgColor;
  final Color cardColor;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.label,
    required this.description,
    required this.accentColor,
    required this.bgColor,
    required this.cardColor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: t.bgElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? accentColor : t.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mini preview — uses the swatch's own colours, not the active theme
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(11)),
              child: Container(
                height: 72,
                color: bgColor,
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 28,
                        color: cardColor,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 14,
                              height: 3,
                              margin: const EdgeInsets.symmetric(vertical: 2),
                              decoration: BoxDecoration(
                                color: accentColor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            ...List.generate(
                              3,
                              (_) => Container(
                                width: 14,
                                height: 2,
                                margin:
                                    const EdgeInsets.symmetric(vertical: 2),
                                decoration: BoxDecoration(
                                  color: accentColor.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 34,
                      top: 10,
                      right: 8,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 8,
                            width: 60,
                            decoration: BoxDecoration(
                              color: accentColor.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 6),
                          ...List.generate(
                            3,
                            (i) => Container(
                              height: 5,
                              width: [50.0, 70.0, 40.0][i],
                              margin: const EdgeInsets.only(bottom: 4),
                              decoration: BoxDecoration(
                                color:
                                    accentColor.withOpacity(0.15 + i * 0.05),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Label area
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style: TextStyle(
                                color: isSelected
                                    ? accentColor
                                    : t.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        Text(description,
                            style: TextStyle(
                                color: t.textMuted, fontSize: 10)),
                      ],
                    ),
                  ),
                  // Checkmark — uses onAccent from the swatch's own tokens
                  // so the tick colour always contrasts correctly with the
                  // swatch's accentColor (e.g. dark tick on green, white on blue).
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: isSelected ? accentColor : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? accentColor : t.borderBright,
                        width: 1.5,
                      ),
                    ),
                    child: isSelected
                        ? Icon(Icons.check,
                            size: 11,
                            color: accentColor == AppThemeTokens.green.accent
                                ? AppThemeTokens.green.onAccent
                                : AppThemeTokens.blue.onAccent)
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
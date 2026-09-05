import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'theme/theme_notifier.dart';
import 'models/session_model.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'screens/sessions_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/multi_chat_screen.dart';
import 'screens/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeNotifier(),
      child: const MeetingIntelligenceHubApp(),
    ),
  );
}

class MeetingIntelligenceHubApp extends StatelessWidget {
  const MeetingIntelligenceHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<ThemeNotifier>();

    final bgColor = notifier.tokens.bgDeep;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: bgColor,
    ));

    return AppTheme(
      mode: notifier.mode,
      tokens: notifier.tokens,
      child: MaterialApp(
        title: 'Meeting Intelligence Hub',
        theme: notifier.themeData,
        debugShowCheckedModeBanner: false,
        home: const _AuthGate(),
      ),
    );
  }
}

/// Shown first on every app launch. Tries to restore a previously saved
/// login session; if none exists (or it's been logged out), shows the
/// login/register screen. Only once authenticated does the real app
/// ([_AppShell]) mount — so no session data is ever fetched or shown
/// without a valid account behind it.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _checkingSession = true;
  bool _isLoggedIn = false;

  // Render's free tier spins the backend down after ~15 min idle, and the
  // next request then eats a ~30-60s cold start. Pinging /health every 5
  // minutes while the app is running keeps it warm. /health needs no auth,
  // so this runs for the app's whole lifetime — logged in or not — started
  // once here since _AuthGate is the one widget mounted the entire time.
  static const _pingInterval = Duration(minutes: 5);
  Timer? _keepAliveTimer;

  @override
  void initState() {
    super.initState();
    _restore();
    _pingBackend(); // warm it immediately on launch too
    _keepAliveTimer = Timer.periodic(_pingInterval, (_) => _pingBackend());
  }

  @override
  void dispose() {
    _keepAliveTimer?.cancel();
    super.dispose();
  }

  Future<void> _pingBackend() async {
    try {
      await ApiService.getHealth();
    } catch (_) {
      // Backend may be asleep, unreachable, or the URL not yet configured —
      // safe to ignore; the next scheduled ping will retry.
    }
  }

  Future<void> _restore() async {
    final restored = await AuthService.restoreSession();
    if (mounted) {
      setState(() {
        _isLoggedIn = restored;
        _checkingSession = false;
      });
    }
  }

  void _onAuthenticated() {
    setState(() => _isLoggedIn = true);
  }

  void _onLoggedOut() {
    setState(() => _isLoggedIn = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingSession) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isLoggedIn) {
      return LoginScreen(onAuthenticated: _onAuthenticated);
    }

    return _AppShell(onLoggedOut: _onLoggedOut);
  }
}

class _AppShell extends StatefulWidget {
  final VoidCallback onLoggedOut;

  const _AppShell({required this.onLoggedOut});

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  final List<SessionModel> _sessions = [];
  SessionModel? _activeSession;
  bool _handlingAuthExpiry = false;

  @override
  void initState() {
    super.initState();
    // Global safety net: if ANY request from ANY screen (dashboard tabs,
    // chat, action items, multi-chat, settings — not just the sessions
    // list) comes back 401 because the token expired or was invalidated,
    // this fires and routes back to login. Without this, a token expiring
    // while the user is a few screens deep (e.g. mid-chat) would just show
    // that one screen a generic error with no way back to a working state.
    ApiService.onUnauthorized = _onAuthExpired;
  }

  @override
  void dispose() {
    // Avoid a stale callback firing into a disposed widget after this
    // shell is torn down (e.g. right after we ourselves trigger logout).
    if (ApiService.onUnauthorized == _onAuthExpired) {
      ApiService.onUnauthorized = null;
    }
    super.dispose();
  }

  void _onUploadSuccess(SessionModel session) {
    setState(() {
      _sessions.removeWhere((s) => s.sessionId == session.sessionId);
      _sessions.insert(0, session);
      _activeSession = session; // navigates to dashboard for real new uploads
    });
  }

  /// Called on startup to restore persisted sessions — adds them to the list
  /// WITHOUT setting _activeSession, so no navigation happens.
  void _onSessionsRestored(List<SessionModel> sessions) {
    setState(() {
      for (final s in sessions) {
        if (!_sessions.any((e) => e.sessionId == s.sessionId)) {
          _sessions.add(s);
        }
      }
    });
  }

  void _onOpen(SessionModel session) {
    setState(() => _activeSession = session);
  }

  void _onClose() {
    setState(() => _activeSession = null);
  }

  Future<void> _onDelete(SessionModel session) async {
    setState(() {
      _sessions.removeWhere((s) => s.sessionId == session.sessionId);
      if (_activeSession?.sessionId == session.sessionId) {
        _activeSession = null;
      }
    });
    try {
      await ApiService.deleteSession(session.sessionId);
    } catch (_) {}
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => SettingsScreen(
                sessionIds: _sessions.map((s) => s.sessionId).toList(),
                onLoggedOut: widget.onLoggedOut,
              )),
    );
  }

  void _openMultiChat() {
    if (_sessions.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MultiChatScreen(
          allSessionIds: _sessions.map((s) => s.sessionId).toList(),
          sessionFilenames: {for (final s in _sessions) s.sessionId: s.filename},
        ),
      ),
    );
  }

  /// Called when any request — from ANY screen — comes back 401. The token
  /// expired or was invalidated server-side (e.g. the server restarted
  /// without a fixed JWT_SECRET). Logs out locally, pops back to the root
  /// so no stale authenticated screens are left on the navigation stack,
  /// and hands control back to _AuthGate to show the login screen.
  Future<void> _onAuthExpired() async {
    if (_handlingAuthExpiry) return; // avoid double-firing from a burst of 401s
    _handlingAuthExpiry = true;
    await AuthService.logout();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    widget.onLoggedOut();
    _handlingAuthExpiry = false;
  }

  @override
  Widget build(BuildContext context) {
    if (_activeSession != null) {
      return DashboardScreen(
        session: _activeSession!,
        allSessions: _sessions,
        onNewUpload: _onClose,
        onBack: _onClose,
      );
    }

    return SessionsScreen(
      sessions: _sessions,
      onOpen: _onOpen,
      onDelete: _onDelete,
      onUploadSuccess: _onUploadSuccess,
      onSessionsRestored: _onSessionsRestored,
      onOpenSettings: _openSettings,
      onOpenMultiChat: _sessions.length > 1 ? _openMultiChat : null,
      onAuthExpired: _onAuthExpired,
    );
  }
}
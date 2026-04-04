import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'theme/theme_notifier.dart';
import 'models/session_model.dart';
import 'services/api_service.dart';
import 'screens/sessions_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/settings_screen.dart';

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
        home: const _AppShell(),
      ),
    );
  }
}

class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  final List<SessionModel> _sessions = [];
  SessionModel? _activeSession;

  void _onUploadSuccess(SessionModel session) {
    setState(() {
      _sessions.removeWhere((s) => s.sessionId == session.sessionId);
      _sessions.insert(0, session);
      _activeSession = session;
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
              )),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_activeSession != null) {
      return DashboardScreen(
        session: _activeSession!,
        onNewUpload: _onClose,
        onBack: _onClose,
      );
    }

    return SessionsScreen(
      sessions: _sessions,
      onOpen: _onOpen,
      onDelete: _onDelete,
      onUploadSuccess: _onUploadSuccess,
      onOpenSettings: _openSettings,
    );
  }
}
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'models/session_model.dart';
import 'screens/upload_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppTheme.bgDeep,
  ));
  runApp(const MeetingIntelligenceHubApp());
}

class MeetingIntelligenceHubApp extends StatelessWidget {
  const MeetingIntelligenceHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meeting Intelligence Hub',
      theme: AppTheme.theme,
      debugShowCheckedModeBanner: false,
      home: const _AppShell(),
    );
  }
}

class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  SessionModel? _activeSession;

  void _onUploadSuccess(SessionModel session) {
    setState(() => _activeSession = session);
  }

  void _onNewUpload() {
    setState(() => _activeSession = null);
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_activeSession != null) {
      return DashboardScreen(
        session: _activeSession!,
        onNewUpload: _onNewUpload,
      );
    }
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: UploadScreen(onUploadSuccess: _onUploadSuccess),
    );
  }
}

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/auth_model.dart';
import 'api_service.dart';

/// Handles registration, login, logout, and persistence of the JWT access
/// token issued by the backend. The token is stored locally (via
/// shared_preferences) so the user stays logged in across app restarts,
/// and is attached by [ApiService] to every authenticated request.
class AuthService {
  static const _tokenKey = 'auth_token';
  static const _userIdKey = 'auth_user_id';
  static const _userEmailKey = 'auth_user_email';
  static const _userNameKey = 'auth_user_display_name';

  static String? _cachedToken;
  static AuthUser? _cachedUser;

  static String? get token => _cachedToken;
  static AuthUser? get currentUser => _cachedUser;
  static bool get isLoggedIn => _cachedToken != null;

  /// Call once on app startup to restore a previously saved session.
  static Future<bool> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token == null || token.isEmpty) return false;

    _cachedToken = token;
    ApiService.setAuthToken(token);

    final id = prefs.getString(_userIdKey);
    final email = prefs.getString(_userEmailKey);
    if (id != null && email != null) {
      _cachedUser = AuthUser(
        id: id,
        email: email,
        displayName: prefs.getString(_userNameKey),
      );
    }
    return true;
  }

  static Future<void> _persistSession(String token, AuthUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userIdKey, user.id);
    await prefs.setString(_userEmailKey, user.email);
    if (user.displayName != null) {
      await prefs.setString(_userNameKey, user.displayName!);
    } else {
      await prefs.remove(_userNameKey);
    }
    _cachedToken = token;
    _cachedUser = user;
    ApiService.setAuthToken(token);
  }

  /// Registers a new account and logs the user straight in.
  /// Throws [AuthException] with a user-facing message on failure.
  static Future<AuthUser> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final response = await http
        .post(
          Uri.parse('${ApiService.baseUrl}/auth/register'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'email': email,
            'password': password,
            if (displayName != null && displayName.trim().isNotEmpty)
              'display_name': displayName.trim(),
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 201) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      final user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
      await _persistSession(data['access_token'] as String, user);
      return user;
    }
    throw AuthException(_friendlyError(response));
  }

  /// Logs in with email + password.
  /// Throws [AuthException] with a user-facing message on failure.
  static Future<AuthUser> login({
    required String email,
    required String password,
  }) async {
    final response = await http
        .post(
          Uri.parse('${ApiService.baseUrl}/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'email': email, 'password': password}),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      final user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
      await _persistSession(data['access_token'] as String, user);
      return user;
    }
    throw AuthException(_friendlyError(response));
  }

  /// Clears the stored session. The user will need to log in again.
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_userEmailKey);
    await prefs.remove(_userNameKey);
    _cachedToken = null;
    _cachedUser = null;
    ApiService.setAuthToken(null);
  }

  static String _friendlyError(http.Response response) {
    try {
      final decoded = json.decode(response.body);
      final detail = decoded['detail'];
      if (detail is String) return detail;
      if (detail is List && detail.isNotEmpty) {
        // FastAPI/Pydantic validation error shape
        final first = detail.first;
        if (first is Map && first['msg'] != null) return first['msg'].toString();
      }
    } catch (_) {}
    switch (response.statusCode) {
      case 401:
        return 'Incorrect email or password.';
      case 409:
        return 'An account with this email already exists.';
      case 422:
        return 'Please check your email and password.';
      default:
        return 'Something went wrong (${response.statusCode}). Please try again.';
    }
  }
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}

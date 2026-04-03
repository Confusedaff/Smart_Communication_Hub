import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/session_model.dart';
import '../models/extraction_model.dart';
import '../models/chat_model.dart';

class ApiService {
  static String _baseUrl = 'http://10.0.2.2:8000'; // Android emulator default

  static void setBaseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  static String get baseUrl => _baseUrl;

  // ── Health ────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getHealth() async {
    final response = await http
        .get(Uri.parse('$_baseUrl/health'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw ApiException('Health check failed: ${response.statusCode}');
  }

  static Future<Map<String, dynamic>> getTimingStatus({String task = 'chat'}) async {
    final response = await http
        .get(Uri.parse('$_baseUrl/timing/status?task=$task'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw ApiException('Timing status failed: ${response.statusCode}');
  }

  // ── Upload ────────────────────────────────────────────────────────────────

  static Future<SessionModel> uploadTranscript(File file) async {
    final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/upload'));
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    final streamed = await request.send().timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode == 201) {
      return SessionModel.fromJson(json.decode(response.body));
    }
    final error = _parseError(response.body);
    throw ApiException('Upload failed: $error');
  }

  // ── Extraction ────────────────────────────────────────────────────────────

  static Future<ExtractionModel> extract(String sessionId,
      {String engine = 'llm'}) async {
    final response = await http
        .get(Uri.parse('$_baseUrl/sessions/$sessionId/extract?engine=$engine'))
        .timeout(const Duration(minutes: 3));
    if (response.statusCode == 200) {
      return ExtractionModel.fromJson(json.decode(response.body));
    }
    final error = _parseError(response.body);
    throw ApiException('Extraction failed: $error');
  }

  /// Returns both the parsed model AND the raw decoded JSON map.
  static Future<(ExtractionModel, Map<String, dynamic>)> extractWithRaw(
      String sessionId,
      {String engine = 'llm'}) async {
    final response = await http
        .get(Uri.parse('$_baseUrl/sessions/$sessionId/extract?engine=$engine'))
        .timeout(const Duration(minutes: 3));
    if (response.statusCode == 200) {
      final rawMap = json.decode(response.body) as Map<String, dynamic>;
      return (ExtractionModel.fromJson(rawMap), rawMap);
    }
    final error = _parseError(response.body);
    throw ApiException('Extraction failed: $error');
  }

  // ── Chat ──────────────────────────────────────────────────────────────────

  static Future<ChatResponse> sendMessage(
      String sessionId, String question) async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl/sessions/$sessionId/chat'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'question': question}),
        )
        .timeout(const Duration(minutes: 2));
    if (response.statusCode == 200) {
      return ChatResponse.fromJson(json.decode(response.body));
    }
    final error = _parseError(response.body);
    throw ApiException('Chat failed: $error');
  }

  static Future<List<Map<String, dynamic>>> getChatHistory(
      String sessionId) async {
    final response = await http
        .get(Uri.parse('$_baseUrl/sessions/$sessionId/chat/history'))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return List<Map<String, dynamic>>.from(data['history'] ?? []);
    }
    throw ApiException('Failed to get chat history');
  }

  static Future<void> clearChatHistory(String sessionId) async {
    await http
        .delete(Uri.parse('$_baseUrl/sessions/$sessionId/chat/history'))
        .timeout(const Duration(seconds: 10));
  }

  // ── Transcript ────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getTranscript(String sessionId,
      {String format = 'segments'}) async {
    final response = await http
        .get(Uri.parse(
            '$_baseUrl/sessions/$sessionId/transcript?format=$format'))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw ApiException('Failed to get transcript');
  }

  // ── Export ────────────────────────────────────────────────────────────────

  static Future<List<int>> exportCsv(String sessionId) async {
    final response = await http
        .get(Uri.parse('$_baseUrl/sessions/$sessionId/export/csv'))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 200) {
      return response.bodyBytes;
    }
    final error = _parseError(response.body);
    throw ApiException('CSV export failed: $error');
  }

  static Future<List<int>> exportPdf(String sessionId) async {
    final response = await http
        .get(Uri.parse('$_baseUrl/sessions/$sessionId/export/pdf'))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 200) {
      return response.bodyBytes;
    }
    final error = _parseError(response.body);
    throw ApiException('PDF export failed: $error');
  }

  // ── Sessions ──────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> listSessions() async {
    final response = await http
        .get(Uri.parse('$_baseUrl/sessions'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return List<Map<String, dynamic>>.from(data['sessions'] ?? []);
    }
    throw ApiException('Failed to list sessions');
  }

  static Future<void> deleteSession(String sessionId) async {
    await http
        .delete(Uri.parse('$_baseUrl/sessions/$sessionId'))
        .timeout(const Duration(seconds: 10));
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _parseError(String body) {
    try {
      final decoded = json.decode(body);
      return decoded['detail'] ?? decoded['message'] ?? body;
    } catch (_) {
      return body;
    }
  }
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}
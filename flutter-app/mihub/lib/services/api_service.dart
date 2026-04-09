import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/session_model.dart';
import '../models/extraction_model.dart';
import '../models/chat_model.dart';

class ApiService {
  static String _baseUrl = 'http://100.95.213.57:8000'; // Android emulator default

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
    final response = await http
        .delete(Uri.parse('$_baseUrl/sessions/$sessionId/chat/history'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      final error = _parseError(response.body);
      throw ApiException('Failed to clear chat history: $error');
    }
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

  /// Fetches the full detail for a single session.
  /// The /sessions/{id} endpoint returns segment_count, speakers, char_count
  /// and other fields needed to build a complete SessionModel.
  static Future<Map<String, dynamic>> getSessionDetail(String sessionId) async {
    final response = await http
        .get(Uri.parse('$_baseUrl/sessions/$sessionId'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw ApiException('Failed to get session detail: \${response.statusCode}');
  }

  // ── Analytics ─────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getAnalytics(String sessionId) async {
    final response = await http
        .get(Uri.parse('$_baseUrl/sessions/$sessionId/analytics'))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw ApiException('Failed to get analytics: \${response.statusCode}');
  }

  // ── Action Items ──────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getActionItems(String sessionId) async {
    final response = await http
        .get(Uri.parse('$_baseUrl/sessions/$sessionId/action-items'))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw ApiException('Failed to get action items: \${response.statusCode}');
  }

  static Future<void> updateActionItemStatus(
      String sessionId, int itemId, String status) async {
    final response = await http
        .patch(
          Uri.parse('$_baseUrl/sessions/$sessionId/action-items/$itemId/status'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'status': status}),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      // ignore: unused_local_variable
      final error = _parseError(response.body);
      throw ApiException('Failed to update status: \$error');
    }
  }

  static Future<Map<String, dynamic>> getDeadlineAlerts(
      String sessionId, {int warningDays = 3}) async {
    final response = await http
        .get(Uri.parse('$_baseUrl/sessions/$sessionId/action-items/alerts?warning_days=$warningDays'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw ApiException('Failed to get alerts: \${response.statusCode}');
  }

  static Future<void> deleteSession(String sessionId) async {
    await http
        .delete(Uri.parse('$_baseUrl/sessions/$sessionId'))
        .timeout(const Duration(seconds: 10));
  }

  // ── Batch Upload ──────────────────────────────────────────────────────────

  /// Upload multiple transcript files at once via POST /upload/batch.
  /// Returns a list of result maps — each has either 'session_id' (success)
  /// or 'error' (failure) plus the original 'filename'.
  static Future<List<Map<String, dynamic>>> uploadBatch(List<File> files) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('$_baseUrl/upload/batch'));
    for (final file in files) {
      request.files.add(await http.MultipartFile.fromPath('files', file.path));
    }
    final streamed =
        await request.send().timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode == 201) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(data['results'] ?? []);
    }
    final error = _parseError(response.body);
    throw ApiException('Batch upload failed: $error');
  }

  // ── Cross-session chat ────────────────────────────────────────────────────

  /// Cross-session chat — searches across multiple (or all) transcripts.
  /// [sessionIds] is optional; pass null to search all sessions.
  static Future<Map<String, dynamic>> sendMultiChat(
      String question, {List<String>? sessionIds}) async {
    final body = <String, dynamic>{'question': question};
    if (sessionIds != null && sessionIds.isNotEmpty) {
      body['session_ids'] = sessionIds;
    }
    final response = await http
        .post(
          Uri.parse('$_baseUrl/chat/multi'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(body),
        )
        .timeout(const Duration(minutes: 2));
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    final error = _parseError(response.body);
    throw ApiException('Multi-chat failed: $error');
  }

  // ── Sentiment click-through ───────────────────────────────────────────────

  /// Get segments for a speaker, optionally filtered/sorted by sentiment.
  /// [sentiment] can be 'positive', 'negative', 'neutral', or null.
  static Future<Map<String, dynamic>> getSpeakerSegments(
      String sessionId, String speaker,
      {String? sentiment}) async {
    final qs = sentiment != null ? '?sentiment=$sentiment' : '';
    final url = '$_baseUrl/sessions/$sessionId/transcript/speaker/'
        '${Uri.encodeComponent(speaker)}$qs';
    final response =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw ApiException('Failed to get speaker segments: ${response.statusCode}');
  }

  /// Get a single segment at [index] with 2 surrounding context segments.
  static Future<Map<String, dynamic>> getSegmentContext(
      String sessionId, int index) async {
    final response = await http
        .get(Uri.parse(
            '$_baseUrl/sessions/$sessionId/transcript/segment/$index'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw ApiException('Failed to get segment: ${response.statusCode}');
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
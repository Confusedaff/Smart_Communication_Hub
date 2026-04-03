class SessionModel {
  final String sessionId;
  final String filename;
  final int segmentCount;
  final List<String> speakers;
  final int charCount;

  SessionModel({
    required this.sessionId,
    required this.filename,
    required this.segmentCount,
    required this.speakers,
    required this.charCount,
  });

  factory SessionModel.fromJson(Map<String, dynamic> json) {
    return SessionModel(
      sessionId: json['session_id'] ?? '',
      filename: json['filename'] ?? '',
      segmentCount: json['segment_count'] ?? 0,
      speakers: List<String>.from(json['speakers'] ?? []),
      charCount: json['char_count'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'filename': filename,
        'segment_count': segmentCount,
        'speakers': speakers,
        'char_count': charCount,
      };
}

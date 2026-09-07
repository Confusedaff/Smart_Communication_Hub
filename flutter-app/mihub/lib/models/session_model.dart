class SessionModel {
  final String sessionId;
  final String filename;
  final int segmentCount;
  final List<String> speakers;
  final int charCount;
  final String docType;   // "meeting" | "document"
  final String chatMode;  // "document" | "general"
  final int tableCount;
  final int imageCount;

  SessionModel({
    required this.sessionId,
    required this.filename,
    required this.segmentCount,
    required this.speakers,
    required this.charCount,
    this.docType = 'meeting',
    this.chatMode = 'document',
    this.tableCount = 0,
    this.imageCount = 0,
  });

  factory SessionModel.fromJson(Map<String, dynamic> json) {
    return SessionModel(
      sessionId: json['session_id'] ?? '',
      filename: json['filename'] ?? '',
      segmentCount: json['segment_count'] ?? 0,
      speakers: List<String>.from(json['speakers'] ?? []),
      charCount: json['char_count'] ?? 0,
      docType: json['doc_type'] ?? 'meeting',
      chatMode: json['chat_mode'] ?? 'document',
      tableCount: json['table_count'] ?? 0,
      imageCount: json['image_count'] ?? 0,
    );
  }

  SessionModel copyWith({String? chatMode, String? docType}) => SessionModel(
        sessionId: sessionId,
        filename: filename,
        segmentCount: segmentCount,
        speakers: speakers,
        charCount: charCount,
        docType: docType ?? this.docType,
        chatMode: chatMode ?? this.chatMode,
        tableCount: tableCount,
        imageCount: imageCount,
      );

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'filename': filename,
        'segment_count': segmentCount,
        'speakers': speakers,
        'char_count': charCount,
        'doc_type': docType,
        'chat_mode': chatMode,
        'table_count': tableCount,
        'image_count': imageCount,
      };
}

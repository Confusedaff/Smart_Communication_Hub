class ChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  final List<Citation> citations;
  final ChatTiming? timing;
  final DateTime timestamp;

  ChatMessage({
    required this.role,
    required this.content,
    this.citations = const [],
    this.timing,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'citations': citations.map((c) => c.toJson()).toList(),
        'timing': timing?.toJson(),
        'timestamp': timestamp.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: json['role'] ?? 'user',
      content: json['content'] ?? '',
      citations: (json['citations'] as List<dynamic>? ?? [])
          .map((c) => Citation.fromJson(c))
          .toList(),
      timing: json['timing'] != null
          ? ChatTiming.fromJson(json['timing'])
          : null,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp']) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class ChatResponse {
  final String question;
  final String answer;
  final List<Citation> citations;
  final String sessionId;
  final ChatTiming? timing;
  final String? mode;

  ChatResponse({
    required this.question,
    required this.answer,
    required this.citations,
    required this.sessionId,
    this.timing,
    this.mode,
  });

  factory ChatResponse.fromJson(Map<String, dynamic> json) {
    return ChatResponse(
      question: json['question'] ?? '',
      answer: json['answer'] ?? '',
      citations: (json['citations'] as List<dynamic>? ?? [])
          .map((c) => Citation.fromJson(c))
          .toList(),
      sessionId: json['session_id'] ?? '',
      timing: json['timing'] != null
          ? ChatTiming.fromJson(json['timing'])
          : null,
      mode: json['mode'],
    );
  }
}

class Citation {
  final String speaker;
  final String excerpt;
  final String timestamp;
  final String? filename;

  Citation({
    required this.speaker,
    required this.excerpt,
    required this.timestamp,
    this.filename,
  });

  factory Citation.fromJson(Map<String, dynamic> json) {
    return Citation(
      speaker: json['speaker'] ?? '',
      excerpt: json['excerpt'] ?? '',
      timestamp: json['timestamp'] ?? '',
      filename: json['filename'],
    );
  }

  Map<String, dynamic> toJson() => {
        'speaker': speaker,
        'excerpt': excerpt,
        'timestamp': timestamp,
        if (filename != null) 'filename': filename,
      };
}

class ChatTiming {
  final double elapsedSeconds;
  final String backend;

  ChatTiming({required this.elapsedSeconds, required this.backend});

  factory ChatTiming.fromJson(Map<String, dynamic> json) {
    return ChatTiming(
      elapsedSeconds: (json['elapsed_seconds'] ?? 0).toDouble(),
      backend: json['backend'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'elapsed_seconds': elapsedSeconds,
        'backend': backend,
      };
}

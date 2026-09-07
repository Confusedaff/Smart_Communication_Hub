// lib/models/extraction_model.dart

class DecisionItem {
  final int id;
  final String decision;
  final String madeBy;
  final String evidence;

  const DecisionItem({
    required this.id,
    required this.decision,
    required this.madeBy,
    required this.evidence,
  });

  factory DecisionItem.fromJson(Map<String, dynamic> json, {int index = 0}) {
    // The evidence/quote field — extract first so we can fall back to it
    final evidence = _firstNonEmpty(json, const [
      'evidence', 'quote', 'context', 'source', 'excerpt', 'Evidence',
    ]);

    // Try every common field name for the decision text.
    // Final fallback: use evidence text (the actual quote) if everything else is empty.
    final decision = _firstNonEmpty(json, const [
      'decision', 'text', 'content', 'description', 'title', 'summary',
      'statement', 'body', 'Decision', 'decision_text', 'detail',
    ]).isNotEmpty
        ? _firstNonEmpty(json, const [
            'decision', 'text', 'content', 'description', 'title', 'summary',
            'statement', 'body', 'Decision', 'decision_text', 'detail',
          ])
        : evidence; // last resort: use the quoted text itself

    final madeBy = _firstNonEmpty(json, const [
      'made_by', 'madeBy', 'speaker', 'owner', 'author', 'person', 'by',
      'MadeBy', 'assigned_to', 'assignee',
    ]);

    return DecisionItem(
      id: (json['id'] as int?) ?? (json['index'] as int?) ?? index + 1,
      decision: decision,
      madeBy: madeBy,
      evidence: evidence,
    );
  }
}

class ActionItem {
  final int id;
  final String task;
  final String owner;
  final String deadline;
  final String evidence;

  const ActionItem({
    required this.id,
    required this.task,
    required this.owner,
    required this.deadline,
    required this.evidence,
  });

  factory ActionItem.fromJson(Map<String, dynamic> json, {int index = 0}) {
    // The evidence/quote field — extract first so we can fall back to it
    final evidence = _firstNonEmpty(json, const [
      'evidence', 'quote', 'context', 'source', 'excerpt', 'Evidence',
    ]);

    // Try every common field name for the task text.
    // Final fallback: use evidence text (the actual quote) — this fixes the
    // "(No task text — check API field names)" message when the backend
    // returns the task only as a quote/evidence field.
    final task = _firstNonEmpty(json, const [
      'task',
      'action',
      'action_item',
      'actionItem',
      'text',
      'content',
      'description',
      'title',
      'summary',
      'item',
      'body',
      'Task',
      'Action',
      'action_text',
      'task_text',
      'detail',
      'statement',
    ]).isNotEmpty
        ? _firstNonEmpty(json, const [
            'task', 'action', 'action_item', 'actionItem', 'text', 'content',
            'description', 'title', 'summary', 'item', 'body', 'Task', 'Action',
            'action_text', 'task_text', 'detail', 'statement',
          ])
        : evidence; // last resort: use the quoted text itself

    final owner = _firstNonEmpty(json, const [
      'owner', 'assignee', 'assigned_to', 'assignedTo', 'person',
      'responsible', 'speaker', 'by', 'Owner', 'who',
    ]);

    final deadline = _firstNonEmpty(json, const [
      'deadline', 'due', 'due_date', 'dueDate', 'date', 'by_when',
      'Deadline', 'when', 'time', 'by',
    ]);

    return ActionItem(
      id: (json['id'] as int?) ?? (json['index'] as int?) ?? index + 1,
      task: task,
      owner: owner,
      deadline: deadline,
      evidence: evidence,
    );
  }
}

class ExtractionTiming {
  final double elapsedSeconds;
  final String backend;
  final String engine;

  const ExtractionTiming({
    required this.elapsedSeconds,
    required this.backend,
    required this.engine,
  });

  factory ExtractionTiming.fromJson(Map<String, dynamic> json) {
    return ExtractionTiming(
      elapsedSeconds: ((json['elapsed_seconds'] ??
              json['elapsedSeconds'] ??
              json['elapsed'] ??
              json['duration'] ??
              0.0) as num)
          .toDouble(),
      backend: (json['backend'] ?? json['provider'] ?? '—').toString(),
      engine: (json['engine'] ?? json['mode'] ?? '—').toString(),
    );
  }
}

/// A single item in a general document's key-points / action-guidance /
/// open-questions lists — just a string, but wrapped so callers can extend
/// it later without changing call sites.
class DocSection {
  final String title;
  final String gist;

  const DocSection({required this.title, required this.gist});

  factory DocSection.fromJson(dynamic json) {
    if (json is String) return DocSection(title: json, gist: '');
    final map = Map<String, dynamic>.from(json as Map);
    return DocSection(
      title: (map['title'] ?? '').toString(),
      gist: (map['gist'] ?? '').toString(),
    );
  }
}

class ExtractionModel {
  final String summary;
  final List<DecisionItem> decisions;
  final List<ActionItem> actionItems;
  final ExtractionTiming? timing;

  // General-document fields (populated when doc_type == "document"; the
  // meeting fields above stay empty in that case, and vice versa).
  final String docKind; // "job_posting" | "policy" | "contract" | "report" | "brochure" | "guide" | "other"
  final List<String> keyPoints;
  final List<String> actionGuidance; // e.g. "how to prepare for this role"
  final List<DocSection> sections;
  final List<String> openQuestions;

  const ExtractionModel({
    required this.summary,
    required this.decisions,
    required this.actionItems,
    this.timing,
    this.docKind = 'other',
    this.keyPoints = const [],
    this.actionGuidance = const [],
    this.sections = const [],
    this.openQuestions = const [],
  });

  bool get isDocumentProfile => keyPoints.isNotEmpty ||
      actionGuidance.isNotEmpty ||
      sections.isNotEmpty ||
      openQuestions.isNotEmpty;

  int get uniqueOwners => actionItems
      .map((a) => a.owner)
      .where((o) => o.isNotEmpty)
      .toSet()
      .length;

  int get itemsWithDeadlines =>
      actionItems.where((a) => a.deadline.isNotEmpty).length;

  factory ExtractionModel.fromJson(Map<String, dynamic> json) {
    final summary = _firstNonEmpty(json, const [
      'summary', 'executive_summary', 'executiveSummary', 'overview',
      'synopsis', 'abstract',
    ]);

    final decisionsRaw = _firstList(json, const [
      'decisions', 'Decisions', 'decision_items', 'decisionItems',
    ]);
    final decisions = decisionsRaw
        .asMap()
        .entries
        .map((e) => DecisionItem.fromJson(
            Map<String, dynamic>.from(e.value as Map),
            index: e.key))
        .toList();

    final actionsRaw = _firstList(json, const [
      'action_items', 'actionItems', 'actions', 'tasks',
      'Action Items', 'ActionItems', 'todo', 'todos',
    ]);
    final actionItems = actionsRaw
        .asMap()
        .entries
        .map((e) => ActionItem.fromJson(
            Map<String, dynamic>.from(e.value as Map),
            index: e.key))
        .toList();

    final timingRaw = json['timing'] ?? json['meta'] ?? json['metadata'];
    final timing = timingRaw != null && timingRaw is Map
        ? ExtractionTiming.fromJson(Map<String, dynamic>.from(timingRaw))
        : null;

    final docKind = (json['doc_kind'] ?? 'other').toString();
    final keyPoints = List<dynamic>.from(json['key_points'] ?? const [])
        .map((e) => e.toString())
        .toList();
    final actionGuidance =
        List<dynamic>.from(json['action_guidance'] ?? const [])
            .map((e) => e.toString())
            .toList();
    final sections = List<dynamic>.from(json['sections'] ?? const [])
        .map((e) => DocSection.fromJson(e))
        .toList();
    final openQuestions =
        List<dynamic>.from(json['open_questions'] ?? const [])
            .map((e) => e.toString())
            .toList();

    return ExtractionModel(
      summary: summary,
      decisions: decisions,
      actionItems: actionItems,
      timing: timing,
      docKind: docKind,
      keyPoints: keyPoints,
      actionGuidance: actionGuidance,
      sections: sections,
      openQuestions: openQuestions,
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _firstNonEmpty(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final val = json[key];
    if (val != null && val.toString().trim().isNotEmpty) {
      return val.toString().trim();
    }
  }
  return '';
}

List<dynamic> _firstList(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final val = json[key];
    if (val is List && val.isNotEmpty) return val;
  }
  return [];
}
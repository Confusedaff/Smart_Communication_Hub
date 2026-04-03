class ExtractionModel {
  final String summary;
  final List<DecisionItem> decisions;
  final List<ActionItem> actionItems;
  final ExtractionTiming? timing;

  ExtractionModel({
    required this.summary,
    required this.decisions,
    required this.actionItems,
    this.timing,
  });

  factory ExtractionModel.fromJson(Map<String, dynamic> json) {
    return ExtractionModel(
      summary: json['summary'] ?? '',
      decisions: (json['decisions'] as List<dynamic>? ?? [])
          .map((e) => DecisionItem.fromJson(e))
          .toList(),
      actionItems: (json['action_items'] as List<dynamic>? ?? [])
          .map((e) => ActionItem.fromJson(e))
          .toList(),
      timing: json['timing'] != null
          ? ExtractionTiming.fromJson(json['timing'])
          : null,
    );
  }

  int get uniqueOwners {
    final owners = actionItems.map((a) => a.owner).where((o) => o.isNotEmpty).toSet();
    return owners.length;
  }

  int get itemsWithDeadlines {
    return actionItems.where((a) => a.deadline.isNotEmpty).length;
  }
}

class DecisionItem {
  final int id;
  final String decision;
  final String madeBy;
  final String evidence;

  DecisionItem({
    required this.id,
    required this.decision,
    required this.madeBy,
    required this.evidence,
  });

  factory DecisionItem.fromJson(Map<String, dynamic> json) {
    return DecisionItem(
      id: json['id'] ?? 0,
      decision: json['decision'] ?? '',
      madeBy: json['made_by'] ?? '',
      evidence: json['evidence'] ?? '',
    );
  }
}

class ActionItem {
  final int id;
  final String task;
  final String owner;
  final String deadline;
  final String evidence;

  ActionItem({
    required this.id,
    required this.task,
    required this.owner,
    required this.deadline,
    required this.evidence,
  });

  factory ActionItem.fromJson(Map<String, dynamic> json) {
    return ActionItem(
      id: json['id'] ?? 0,
      task: json['task'] ?? '',
      owner: json['owner'] ?? '',
      deadline: json['deadline'] ?? '',
      evidence: json['evidence'] ?? '',
    );
  }
}

class ExtractionTiming {
  final double elapsedSeconds;
  final String backend;
  final String engine;

  ExtractionTiming({
    required this.elapsedSeconds,
    required this.backend,
    required this.engine,
  });

  factory ExtractionTiming.fromJson(Map<String, dynamic> json) {
    return ExtractionTiming(
      elapsedSeconds: (json['elapsed_seconds'] ?? 0).toDouble(),
      backend: json['backend'] ?? '',
      engine: json['engine'] ?? '',
    );
  }
}

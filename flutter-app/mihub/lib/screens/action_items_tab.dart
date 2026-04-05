import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

// ── Status config ─────────────────────────────────────────────────────────────

enum ActionStatus { pending, inProgress, done, blocked }

extension ActionStatusExt on ActionStatus {
  String get key => switch (this) {
        ActionStatus.pending => 'pending',
        ActionStatus.inProgress => 'in_progress',
        ActionStatus.done => 'done',
        ActionStatus.blocked => 'blocked',
      };

  String get label => switch (this) {
        ActionStatus.pending => 'Pending',
        ActionStatus.inProgress => 'In Progress',
        ActionStatus.done => 'Done',
        ActionStatus.blocked => 'Blocked',
      };

  IconData get icon => switch (this) {
        ActionStatus.pending => Icons.radio_button_unchecked,
        ActionStatus.inProgress => Icons.timelapse_rounded,
        ActionStatus.done => Icons.check_circle_rounded,
        ActionStatus.blocked => Icons.block_rounded,
      };

  static ActionStatus fromKey(String key) => switch (key) {
        'in_progress' => ActionStatus.inProgress,
        'done' => ActionStatus.done,
        'blocked' => ActionStatus.blocked,
        _ => ActionStatus.pending,
      };
}

Color _statusColor(ActionStatus s, AppThemeTokens t) => switch (s) {
      ActionStatus.pending => t.textMuted,
      ActionStatus.inProgress => t.accent,
      ActionStatus.done => t.accentGreen,
      ActionStatus.blocked => t.accentRed,
    };

// ── Model ─────────────────────────────────────────────────────────────────────

class _ActionItem {
  final int id;
  final String what;
  final String who;
  final String byWhen;
  final String context;
  ActionStatus status;

  _ActionItem({
    required this.id,
    required this.what,
    required this.who,
    required this.byWhen,
    required this.context,
    required this.status,
  });

  factory _ActionItem.fromJson(Map<String, dynamic> json) {
    return _ActionItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      what: json['what']?.toString() ?? '',
      who: json['who']?.toString() ?? '',
      byWhen: json['by_when']?.toString() ?? '',
      context: json['context']?.toString() ?? '',
      status: ActionStatusExt.fromKey(json['status']?.toString() ?? 'pending'),
    );
  }
}

class _AlertItem {
  final int id;
  final String what;
  final String who;
  final String byWhen;
  final String urgency; // 'overdue' | 'due_soon'
  final int? daysFromNow;

  _AlertItem.fromJson(Map<String, dynamic> json)
      : id = (json['id'] as num?)?.toInt() ?? 0,
        what = json['what']?.toString() ?? '',
        who = json['who']?.toString() ?? '',
        byWhen = json['by_when']?.toString() ?? '',
        urgency = json['urgency']?.toString() ?? 'due_soon',
        daysFromNow = (json['days_from_now'] as num?)?.toInt();
}

// ── Tab widget ────────────────────────────────────────────────────────────────

class ActionItemsTab extends StatefulWidget {
  final String sessionId;
  final ValueChanged<int>? onAlertCount;

  const ActionItemsTab({
    super.key,
    required this.sessionId,
    this.onAlertCount,
  });

  @override
  State<ActionItemsTab> createState() => _ActionItemsTabState();
}

class _ActionItemsTabState extends State<ActionItemsTab> {
  List<_ActionItem> _items = [];
  List<_AlertItem> _alerts = [];
  bool _isLoading = true;

  // Always computed live from _items — never stale after status changes
  Map<String, int> get _totals => {
    'pending':     _items.where((i) => i.status == ActionStatus.pending).length,
    'in_progress': _items.where((i) => i.status == ActionStatus.inProgress).length,
    'done':        _items.where((i) => i.status == ActionStatus.done).length,
    'blocked':     _items.where((i) => i.status == ActionStatus.blocked).length,
  };
  String? _error;
  ActionStatus? _filter; // null = all
  int _warningDays = 3;
  int? _updatingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiService.getActionItems(widget.sessionId),
        ApiService.getDeadlineAlerts(widget.sessionId, warningDays: _warningDays),
      ]);

      // ignore: unnecessary_cast
      final itemsData = results[0] as Map<String, dynamic>;
      // ignore: unnecessary_cast
      final alertsData = results[1] as Map<String, dynamic>;

      final rawItems = (itemsData['action_items'] as List? ?? [])
          .cast<Map<String, dynamic>>();

      final rawAlerts = [
        ...(alertsData['overdue'] as List? ?? []).cast<Map<String, dynamic>>(),
        ...(alertsData['due_soon'] as List? ?? []).cast<Map<String, dynamic>>(),
      ];

      if (mounted) {
        setState(() {
          _items = rawItems.map(_ActionItem.fromJson).toList();
          _alerts = rawAlerts.map(_AlertItem.fromJson).toList();
        });
        widget.onAlertCount?.call(
            (alertsData['alert_count'] as num?)?.toInt() ?? 0);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load action items');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _changeStatus(int itemId, ActionStatus newStatus) async {
    setState(() => _updatingId = itemId);
    try {
      await ApiService.updateActionItemStatus(
          widget.sessionId, itemId, newStatus.key);
      if (mounted) {
        setState(() {
          final idx = _items.indexWhere((i) => i.id == itemId);
          if (idx != -1) _items[idx].status = newStatus;
        });
        
        // Refresh alerts silently
        ApiService.getDeadlineAlerts(widget.sessionId, warningDays: _warningDays)
            .then((d) {
          if (!mounted) return;
          final raw = [
            ...(d['overdue'] as List? ?? []).cast<Map<String, dynamic>>(),
            ...(d['due_soon'] as List? ?? []).cast<Map<String, dynamic>>(),
          ];
          setState(() => _alerts = raw.map(_AlertItem.fromJson).toList());
          widget.onAlertCount
              ?.call((d['alert_count'] as num?)?.toInt() ?? 0);
        }).catchError((_) {});
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _updatingId = null);
    }
  }

  List<_ActionItem> get _filtered {
    final base =
        _filter == null ? _items : _items.where((i) => i.status == _filter);
    // Deadline-first sort
    return base.toList()
      ..sort((a, b) {
        if (a.byWhen.isNotEmpty && b.byWhen.isEmpty) return -1;
        if (a.byWhen.isEmpty && b.byWhen.isNotEmpty) return 1;
        return 0;
      });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);

    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: t.accent));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: t.accentRed, size: 40),
              const SizedBox(height: 16),
              Text(_error!,
                  style: TextStyle(color: t.textSecondary, fontSize: 13),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.task_alt_outlined, size: 48, color: t.textMuted),
            const SizedBox(height: 16),
            Text('No action items',
                style: TextStyle(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15)),
            const SizedBox(height: 8),
            Text('Run extraction first to detect action items.',
                style: TextStyle(color: t.textSecondary, fontSize: 13),
                textAlign: TextAlign.center),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: t.accent,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // Alert banners
          if (_alerts.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  children: _alerts.map((a) => _AlertBanner(alert: a)).toList(),
                ),
              ),
            ),

          // Progress card
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _ProgressCard(items: _items, totals: _totals),
            ),
          ),

          // Filter chips + warning days
          SliverToBoxAdapter(
            child: _FilterRow(
              current: _filter,
              totals: _totals,
              total: _items.length,
              warningDays: _warningDays,
              onFilter: (f) => setState(() => _filter = f),
              onWarningDays: (d) {
                setState(() => _warningDays = d);
                _load();
              },
            ),
          ),

          // Items
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) {
                  final item = _filtered[i];
                  final alert =
                      _alerts.where((a) => a.id == item.id).firstOrNull;
                  return _ActionItemCard(
                    item: item,
                    alert: alert,
                    isUpdating: _updatingId == item.id,
                    onStatusChange: (s) => _changeStatus(item.id, s),
                  );
                },
                childCount: _filtered.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Alert banner ──────────────────────────────────────────────────────────────

class _AlertBanner extends StatelessWidget {
  final _AlertItem alert;
  const _AlertBanner({required this.alert});

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final isOverdue = alert.urgency == 'overdue';
    final color = isOverdue ? t.accentRed : t.accentAmber;
    final bg = isOverdue
        ? t.accentRed.withOpacity(0.08)
        : t.accentAmber.withOpacity(0.08);

    String dayLabel = '';
    if (alert.daysFromNow != null) {
      dayLabel = isOverdue
          ? ' · ${alert.daysFromNow!.abs()}d ago'
          : ' · ${alert.daysFromNow}d left';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Text(isOverdue ? '🚨' : '⏰', style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${isOverdue ? 'Overdue' : 'Due Soon'}$dayLabel',
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3),
                ),
                const SizedBox(height: 2),
                Text(alert.what,
                    style: TextStyle(color: t.textPrimary, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (alert.byWhen.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(alert.byWhen,
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }
}

// ── Progress card ─────────────────────────────────────────────────────────────

class _ProgressCard extends StatelessWidget {
  final List<_ActionItem> items;
  final Map<String, int> totals;
  const _ProgressCard({required this.items, required this.totals});

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final done = totals['done'] ?? 0;
    final total = items.length;
    final pct = total > 0 ? done / total : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Overall Progress',
                  style: TextStyle(
                      color: t.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5)),
              Text('$done / $total done',
                  style: TextStyle(
                      color: t.accentGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace')),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: t.bgElevated,
              valueColor: AlwaysStoppedAnimation(t.accentGreen),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 12),
          // 2×2 grid — avoids overflow on narrow screens
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: ActionStatus.values.map((s) {
              final color = _statusColor(s, t);
              final count = totals[s.key] ?? 0;
              return SizedBox(
                width: (MediaQuery.of(context).size.width - 32 - 32 - 12) / 2,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(s.icon, size: 12, color: color),
                    const SizedBox(width: 5),
                    Text(
                      '$count ${s.label}',
                      style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── Filter row ────────────────────────────────────────────────────────────────

class _FilterRow extends StatelessWidget {
  final ActionStatus? current;
  final Map<String, int> totals;
  final int total;
  final int warningDays;
  final ValueChanged<ActionStatus?> onFilter;
  final ValueChanged<int> onWarningDays;

  const _FilterRow({
    required this.current,
    required this.totals,
    required this.total,
    required this.warningDays,
    required this.onFilter,
    required this.onWarningDays,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          // "All" chip
          _Chip(
            label: 'All',
            count: total,
            selected: current == null,
            color: t.textSecondary,
            onTap: () => onFilter(null),
          ),
          const SizedBox(width: 8),
          // Status chips
          ...ActionStatus.values.map((s) {
            final color = _statusColor(s, t);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _Chip(
                label: s.label,
                count: totals[s.key] ?? 0,
                selected: current == s,
                color: color,
                onTap: () => onFilter(s),
              ),
            );
          }),
          // Warning days picker
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: t.bgElevated,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: t.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.notifications_outlined, size: 12, color: t.textMuted),
                const SizedBox(width: 5),
                Text('Alert ', style: TextStyle(color: t.textMuted, fontSize: 11)),
                DropdownButton<int>(
                  value: warningDays,
                  isDense: true,
                  underline: const SizedBox(),
                  dropdownColor: t.bgCard,
                  style: TextStyle(color: t.textSecondary, fontSize: 11),
                  items: [1, 2, 3, 5, 7, 14]
                      .map((d) => DropdownMenuItem(
                            value: d,
                            child: Text('${d}d'),
                          ))
                      .toList(),
                  onChanged: (v) => v != null ? onWarningDays(v) : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.count,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : t.bgElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? color : t.border, width: selected ? 1.5 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    color: selected ? color : t.textMuted,
                    fontSize: 12,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w400)),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: selected ? color.withOpacity(0.2) : t.bgCard,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('$count',
                  style: TextStyle(
                      color: selected ? color : t.textMuted,
                      fontSize: 10,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Action item card ──────────────────────────────────────────────────────────

class _ActionItemCard extends StatelessWidget {
  final _ActionItem item;
  final _AlertItem? alert;
  final bool isUpdating;
  final ValueChanged<ActionStatus> onStatusChange;

  const _ActionItemCard({
    required this.item,
    required this.alert,
    required this.isUpdating,
    required this.onStatusChange,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final isDone = item.status == ActionStatus.done;
    final statusColor = _statusColor(item.status, t);

    Color? deadlineColor;
    if (alert != null) {
      deadlineColor =
          alert!.urgency == 'overdue' ? t.accentRed : t.accentAmber;
    }

    return Opacity(
      opacity: isDone ? 0.6 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ID badge
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t.accentGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: t.accentGreen.withOpacity(0.25)),
                  ),
                  child: Text('${item.id}',
                      style: TextStyle(
                          color: t.accentGreen,
                          fontSize: 10,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.what.isNotEmpty ? item.what : '—',
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.5,
                      decoration: isDone ? TextDecoration.lineThrough : null,
                      decorationColor: t.textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Status button
                _StatusButton(
                  status: item.status,
                  isUpdating: isUpdating,
                  color: statusColor,
                  onChanged: onStatusChange,
                ),
              ],
            ),

            // Owner + Deadline row
            if (item.who.isNotEmpty || item.byWhen.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (item.who.isNotEmpty) ...[
                    Icon(Icons.person_outline, size: 12, color: t.textMuted),
                    const SizedBox(width: 4),
                    Text(item.who,
                        style: TextStyle(
                            color: t.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                  ],
                  if (item.who.isNotEmpty && item.byWhen.isNotEmpty)
                    const SizedBox(width: 12),
                  if (item.byWhen.isNotEmpty) ...[
                    Icon(Icons.schedule_outlined,
                        size: 12,
                        color: deadlineColor ?? t.accentAmber),
                    const SizedBox(width: 4),
                    Text(
                      '${alert?.urgency == 'overdue' ? '🚨 ' : alert?.urgency == 'due_soon' ? '⏰ ' : ''}${item.byWhen}',
                      style: TextStyle(
                          color: deadlineColor ?? t.accentAmber,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ],

            // Context quote
            if (item.context.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: t.bgDeep,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: t.border),
                ),
                child: Text(
                  '"${item.context}"',
                  style: TextStyle(
                      color: t.textMuted,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      height: 1.45),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Status button with dropdown ───────────────────────────────────────────────

class _StatusButton extends StatelessWidget {
  final ActionStatus status;
  final bool isUpdating;
  final Color color;
  final ValueChanged<ActionStatus> onChanged;

  const _StatusButton({
    required this.status,
    required this.isUpdating,
    required this.color,
    required this.onChanged,
  });

  void _showPicker(BuildContext context) {
    final t = AppTheme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: t.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: t.border, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            ...ActionStatus.values.map((s) {
              final sc = _statusColor(s, t);
              final isActive = s == status;
              return ListTile(
                leading: Icon(s.icon, color: sc, size: 20),
                title: Text(s.label,
                    style: TextStyle(
                        color: isActive ? sc : t.textPrimary,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                        fontSize: 14)),
                trailing: isActive
                    ? Icon(Icons.check_rounded, color: sc, size: 18)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  if (s != status) onChanged(s);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isUpdating ? null : () => _showPicker(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isUpdating)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: color),
              )
            else
              Icon(status.icon, size: 12, color: color),
            const SizedBox(width: 5),
            Text(status.label,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            if (!isUpdating) ...[
              const SizedBox(width: 3),
              Icon(Icons.expand_more_rounded, size: 12, color: color),
            ],
          ],
        ),
      ),
    );
  }
}
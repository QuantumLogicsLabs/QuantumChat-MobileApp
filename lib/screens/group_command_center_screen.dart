import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../state/chat_controller.dart';
import '../state/theme_controller.dart';
import '../theme/qc_theme.dart';
import '../utils/display_name.dart';
import '../utils/message_preview.dart';
import '../widgets/common.dart';

/// Group Command Center — website `GroupCommandCenter.jsx` parity.
///
/// Announcements / events / polls / files / pinned come from the loaded chat
/// history; tasks, links and notes live on the group (`commandCenter`) and are
/// writable by every member. Pops with a message id when the user taps an
/// item, so the thread can scroll to it.
class GroupCommandCenterScreen extends StatefulWidget {
  const GroupCommandCenterScreen({super.key, required this.groupId});

  final String groupId;

  @override
  State<GroupCommandCenterScreen> createState() => _GroupCommandCenterScreenState();
}

enum _CcSection { announcements, events, tasks, files, polls, important, members, links, notes }

extension on _CcSection {
  String get label => switch (this) {
        _CcSection.announcements => 'Announcements',
        _CcSection.events => 'Upcoming Events',
        _CcSection.tasks => 'Tasks',
        _CcSection.files => 'Shared Files',
        _CcSection.polls => 'Polls',
        _CcSection.important => 'Pinned Messages',
        _CcSection.members => 'Members',
        _CcSection.links => 'Important Links',
        _CcSection.notes => 'Group Notes',
      };

  IconData get icon => switch (this) {
        _CcSection.announcements => Icons.campaign_outlined,
        _CcSection.events => Icons.event_outlined,
        _CcSection.tasks => Icons.check_box_outlined,
        _CcSection.files => Icons.description_outlined,
        _CcSection.polls => Icons.bar_chart_rounded,
        _CcSection.important => Icons.push_pin_outlined,
        _CcSection.members => Icons.groups_outlined,
        _CcSection.links => Icons.link,
        _CcSection.notes => Icons.sticky_note_2_outlined,
      };
}

class _GroupCommandCenterScreenState extends State<GroupCommandCenterScreen> {
  _CcSection? _view;
  bool _busy = false;

  QcGroup? _group(ChatController chat) {
    for (final g in chat.groups) {
      if (g.id == widget.groupId) return g;
    }
    return chat.selected?.group;
  }

  Future<bool> _hub(Map<String, dynamic> payload) async {
    setState(() => _busy = true);
    try {
      await context.read<ChatController>().commandCenterAction(widget.groupId, payload);
      return true;
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return false;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatController>();
    final colors = context.watch<ThemeController>().colors;
    final group = _group(chat);
    if (group == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Command Center')),
        body: Center(child: Text('Group not found', style: TextStyle(color: colors.textMuted))),
      );
    }

    final inThisGroup = chat.selected?.id == group.id;
    final msgs = inThisGroup ? chat.messages : const <ChatMessage>[];
    final b = _Buckets.from(msgs, group.pinnedMessageIds.toSet());
    final hub = group.commandCenter;

    int count(_CcSection s) => switch (s) {
          _CcSection.announcements => b.announcements.length,
          _CcSection.events => b.events.length,
          _CcSection.tasks => hub.tasks.where((t) => !t.done).length,
          _CcSection.files => b.files.length,
          _CcSection.polls => b.polls.length,
          _CcSection.important => b.pinned.isNotEmpty ? b.pinned.length : group.pinnedMessageIds.length,
          _CcSection.members => group.members.length,
          _CcSection.links => hub.links.length,
          _CcSection.notes => hub.notes.length,
        };

    final view = _view;
    return PopScope(
      canPop: view == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _view = null);
      },
      child: Scaffold(
        backgroundColor: colors.body,
        appBar: AppBar(
          backgroundColor: colors.surface,
          leading: view == null
              ? null
              : IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() => _view = null),
                ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(view?.label ?? 'Command Center'),
              Text(
                group.name,
                style: TextStyle(color: colors.textMuted, fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          bottom: _busy
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(minHeight: 2, color: colors.accent),
                )
              : null,
        ),
        body: view == null
            ? _home(colors, count, hub, b)
            : _section(view, colors, chat, group, b),
      ),
    );
  }

  Widget _home(
    QcColors colors,
    int Function(_CcSection) count,
    GroupCommandCenterData hub,
    _Buckets b,
  ) {
    final nextEvent = b.events.isEmpty ? null : b.events.first;
    final openTasks = hub.tasks.where((t) => !t.done).length;
    final digest = <String>[
      if (b.announcements.isNotEmpty) '${b.announcements.length} announcement${b.announcements.length == 1 ? '' : 's'}',
      if (openTasks > 0) '$openTasks open task${openTasks == 1 ? '' : 's'}',
      if (nextEvent != null) 'next: ${nextEvent.eventData?.title ?? 'event'}',
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.accentMuted,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.accent.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Icon(Icons.dashboard_customize_outlined, color: colors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Quick digest', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      digest.isEmpty ? 'All caught up — nothing pending in this group.' : digest.join(' · '),
                      style: TextStyle(color: colors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.95,
          children: [
            for (final s in _CcSection.values)
              _Tile(section: s, count: count(s), colors: colors, onTap: () => setState(() => _view = s)),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Lists come from messages loaded in this chat. Tasks, links and notes are shared with every member.',
          style: TextStyle(color: colors.textMuted, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _section(_CcSection s, QcColors colors, ChatController chat, QcGroup group, _Buckets b) {
    switch (s) {
      case _CcSection.announcements:
        return _messageList(b.announcements, colors, 'No announcements yet. Admins can post one from the + menu in chat.');
      case _CcSection.events:
        return _messageList(
          b.events,
          colors,
          'No upcoming events. Create one from the + menu in chat.',
          meta: (m) {
            final when = _eventWhen(m);
            final where = m.eventData?.location ?? '';
            return [when == null ? 'Time TBD' : _fmt(when), if (where.isNotEmpty) where].join(' · ');
          },
        );
      case _CcSection.polls:
        return _messageList(b.polls, colors, 'No polls yet. Create one from the + menu in chat.');
      case _CcSection.files:
        return _messageList(b.files, colors, 'No shared files in this chat yet.');
      case _CcSection.important:
        return _messageList(b.pinned, colors, 'No pinned messages. Open a message menu and tap Pin.');
      case _CcSection.members:
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: group.members.length,
          separatorBuilder: (_, __) => Divider(height: 1, color: colors.border),
          itemBuilder: (_, i) {
            final m = group.members[i];
            final admin = group.isAdmin(m.id);
            return ListTile(
              leading: UserAvatar(name: getDisplayName(m), userId: m.id, hasAvatar: m.hasAvatar, size: 38),
              title: Row(
                children: [
                  Flexible(
                    child: Text(getDisplayName(m), overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.textPrimary)),
                  ),
                  if (admin) ...[
                    const SizedBox(width: 6),
                    _Badge(label: 'Admin', colors: colors),
                  ],
                ],
              ),
              subtitle: Text('@${m.username}', style: TextStyle(color: colors.textMuted, fontSize: 12)),
            );
          },
        );
      case _CcSection.tasks:
        return _TasksSection(group: group, colors: colors, chat: chat, busy: _busy, hub: _hub);
      case _CcSection.links:
        return _LinksSection(group: group, colors: colors, busy: _busy, hub: _hub);
      case _CcSection.notes:
        return _NotesSection(group: group, colors: colors, chat: chat, busy: _busy, hub: _hub);
    }
  }

  Widget _messageList(
    List<ChatMessage> items,
    QcColors colors,
    String empty, {
    String Function(ChatMessage)? meta,
  }) {
    if (items.isEmpty) return _Empty(text: empty, colors: colors);
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: colors.border),
      itemBuilder: (_, i) {
        final m = items[i];
        return ListTile(
          title: Text(
            _preview(m),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textPrimary),
          ),
          subtitle: Text(
            meta?.call(m) ?? formatMessageTime(m.createdAt),
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
          trailing: Icon(Icons.chevron_right, color: colors.textMuted),
          onTap: () => Navigator.pop(context, m.id),
        );
      },
    );
  }
}

String _preview(ChatMessage m) {
  if (m.isAnnouncement) return m.announcementBody?.isNotEmpty == true ? m.announcementBody! : 'Announcement';
  if (m.isPoll) return m.pollData?.question ?? 'Poll';
  if (m.isEvent) return m.eventData?.title ?? 'Event';
  if (m.attachment != null) return '📎 ${m.attachment!.filename}';
  final text = getMessagePreviewText(m.text);
  return text.isEmpty ? 'Message' : text;
}

DateTime? _eventWhen(ChatMessage m) {
  final raw = m.eventData?.when;
  return raw == null ? null : DateTime.tryParse(raw)?.toLocal();
}

String _fmt(DateTime t) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '${months[t.month - 1]} ${t.day}, $h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

class _Buckets {
  _Buckets(this.announcements, this.events, this.polls, this.files, this.pinned);

  final List<ChatMessage> announcements;
  final List<ChatMessage> events;
  final List<ChatMessage> polls;
  final List<ChatMessage> files;
  final List<ChatMessage> pinned;

  factory _Buckets.from(List<ChatMessage> messages, Set<String> pinnedIds) {
    final announcements = <ChatMessage>[];
    final events = <ChatMessage>[];
    final polls = <ChatMessage>[];
    final files = <ChatMessage>[];
    final pinned = <ChatMessage>[];
    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    for (final m in messages) {
      if (m.isAnnouncement) {
        announcements.add(m);
      } else if (m.isPoll) {
        polls.add(m);
      } else if (m.isEvent) {
        final when = _eventWhen(m);
        if (when == null || when.isAfter(cutoff)) events.add(m);
      } else if (m.attachment != null) {
        files.add(m);
      }
      if (pinnedIds.contains(m.id) || m.isPinned) pinned.add(m);
    }
    events.sort((a, b) => (_eventWhen(a) ?? DateTime(0)).compareTo(_eventWhen(b) ?? DateTime(0)));
    return _Buckets(
      announcements.reversed.toList(),
      events,
      polls.reversed.toList(),
      files.reversed.toList(),
      pinned.reversed.toList(),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.section, required this.count, required this.colors, required this.onTap});

  final _CcSection section;
  final int count;
  final QcColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: colors.accentMuted, borderRadius: BorderRadius.circular(12)),
                child: Icon(section.icon, color: colors.accent, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                section.label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600, height: 1.2),
              ),
              const SizedBox(height: 2),
              Text('$count', style: TextStyle(color: colors.textMuted, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.colors});

  final String label;
  final QcColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: colors.accentMuted, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: colors.accent, fontSize: 10, fontWeight: FontWeight.w800)),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text, required this.colors});

  final String text;
  final QcColors colors;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: colors.textMuted)),
      ),
    );
  }
}

typedef _HubFn = Future<bool> Function(Map<String, dynamic> payload);

class _TasksSection extends StatefulWidget {
  const _TasksSection({required this.group, required this.colors, required this.chat, required this.busy, required this.hub});

  final QcGroup group;
  final QcColors colors;
  final ChatController chat;
  final bool busy;
  final _HubFn hub;

  @override
  State<_TasksSection> createState() => _TasksSectionState();
}

class _TasksSectionState extends State<_TasksSection> {
  final _title = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final t = _title.text.trim();
    if (t.isEmpty) return;
    if (await widget.hub({'action': 'add', 'section': 'tasks', 'title': t})) _title.clear();
  }

  String? _memberName(String? id) {
    if (id == null) return null;
    for (final m in widget.group.members) {
      if (m.id == id) return getDisplayName(m);
    }
    return null;
  }

  Future<void> _assign(HubTask t) async {
    final colors = widget.colors;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: colors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.6),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: Icon(Icons.person_off_outlined, color: colors.textMuted),
                title: const Text('Unassigned'),
                onTap: () => Navigator.pop(ctx, ''),
              ),
              for (final m in widget.group.members)
                ListTile(
                  leading: UserAvatar(name: getDisplayName(m), userId: m.id, hasAvatar: m.hasAvatar, size: 32),
                  title: Text(getDisplayName(m)),
                  trailing: t.assigneeId == m.id ? Icon(Icons.check, color: colors.accent) : null,
                  onTap: () => Navigator.pop(ctx, m.id),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    await widget.hub({
      'action': 'update',
      'section': 'tasks',
      'itemId': t.id,
      'assigneeId': picked.isEmpty ? null : picked,
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final tasks = [...widget.group.commandCenter.tasks]..sort((a, b) => (a.done ? 1 : 0) - (b.done ? 1 : 0));
    return Column(
      children: [
        _AddRow(
          colors: colors,
          busy: widget.busy,
          onAdd: _add,
          child: TextField(
            controller: _title,
            maxLength: 200,
            enabled: !widget.busy,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _add(),
            decoration: const InputDecoration(hintText: 'Add a task…', counterText: ''),
          ),
        ),
        Expanded(
          child: tasks.isEmpty
              ? _Empty(text: 'No tasks yet. Add one above — everyone in the group can check it off.', colors: colors)
              : ListView.separated(
                  itemCount: tasks.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: colors.border),
                  itemBuilder: (_, i) {
                    final t = tasks[i];
                    final who = _memberName(t.assigneeId);
                    return ListTile(
                      leading: Checkbox(
                        value: t.done,
                        onChanged: widget.busy
                            ? null
                            : (v) => widget.hub({'action': 'toggle', 'section': 'tasks', 'itemId': t.id, 'done': v ?? false}),
                      ),
                      title: Text(
                        t.title,
                        style: TextStyle(
                          color: t.done ? colors.textMuted : colors.textPrimary,
                          decoration: t.done ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      subtitle: Text(
                        who == null ? 'Tap to assign' : 'Assigned to $who',
                        style: TextStyle(color: colors.textMuted, fontSize: 12),
                      ),
                      onTap: widget.busy ? null : () => _assign(t),
                      trailing: IconButton(
                        tooltip: 'Remove task',
                        icon: Icon(Icons.delete_outline, color: colors.textMuted),
                        onPressed: widget.busy
                            ? null
                            : () => widget.hub({'action': 'remove', 'section': 'tasks', 'itemId': t.id}),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _LinksSection extends StatefulWidget {
  const _LinksSection({required this.group, required this.colors, required this.busy, required this.hub});

  final QcGroup group;
  final QcColors colors;
  final bool busy;
  final _HubFn hub;

  @override
  State<_LinksSection> createState() => _LinksSectionState();
}

class _LinksSectionState extends State<_LinksSection> {
  final _title = TextEditingController();
  final _url = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    var url = _url.text.trim();
    if (url.isEmpty) return;
    if (!url.startsWith(RegExp(r'https?://', caseSensitive: false))) url = 'https://$url';
    final ok = await widget.hub({
      'action': 'add',
      'section': 'links',
      'title': _title.text.trim().isEmpty ? 'Link' : _title.text.trim(),
      'url': url,
    });
    if (ok) {
      _title.clear();
      _url.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final links = widget.group.commandCenter.links;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _title,
            maxLength: 120,
            enabled: !widget.busy,
            decoration: const InputDecoration(hintText: 'Title (optional)', counterText: ''),
          ),
        ),
        _AddRow(
          colors: colors,
          busy: widget.busy,
          onAdd: _add,
          child: TextField(
            controller: _url,
            enabled: !widget.busy,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _add(),
            decoration: const InputDecoration(hintText: 'https://…'),
          ),
        ),
        Expanded(
          child: links.isEmpty
              ? _Empty(text: 'No links saved. Pin docs, boards or meeting links here for the whole group.', colors: colors)
              : ListView.separated(
                  itemCount: links.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: colors.border),
                  itemBuilder: (_, i) {
                    final l = links[i];
                    return ListTile(
                      leading: Icon(Icons.link, color: colors.accent),
                      title: Text(l.title, style: TextStyle(color: colors.textPrimary)),
                      subtitle: Text(
                        l.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.textMuted, fontSize: 12),
                      ),
                      onTap: () {
                        final uri = Uri.tryParse(l.url);
                        if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
                      },
                      trailing: IconButton(
                        tooltip: 'Remove link',
                        icon: Icon(Icons.delete_outline, color: colors.textMuted),
                        onPressed: widget.busy
                            ? null
                            : () => widget.hub({'action': 'remove', 'section': 'links', 'itemId': l.id}),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _NotesSection extends StatelessWidget {
  const _NotesSection({required this.group, required this.colors, required this.chat, required this.busy, required this.hub});

  final QcGroup group;
  final QcColors colors;
  final ChatController chat;
  final bool busy;
  final _HubFn hub;

  Future<void> _edit(BuildContext context, [HubNote? note]) async {
    final title = TextEditingController(text: note?.title ?? '');
    final body = TextEditingController(text: note?.body ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(note == null ? 'New note' : 'Edit note', style: TextStyle(color: colors.textPrimary)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                maxLength: 120,
                decoration: const InputDecoration(hintText: 'Title (optional)', counterText: ''),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: body,
                autofocus: true,
                minLines: 4,
                maxLines: 10,
                maxLength: 5000,
                decoration: const InputDecoration(hintText: 'Write a note for the group…'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    final t = title.text.trim();
    final b = body.text.trim();
    title.dispose();
    body.dispose();
    if (ok != true || b.isEmpty) return;
    await hub({
      'action': note == null ? 'add' : 'update',
      'section': 'notes',
      if (note != null) 'itemId': note.id,
      'title': t,
      'body': b,
    });
  }

  @override
  Widget build(BuildContext context) {
    final notes = group.commandCenter.notes;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: busy ? null : () => _edit(context),
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        icon: const Icon(Icons.add),
        label: const Text('Note'),
      ),
      body: notes.isEmpty
          ? _Empty(text: 'No notes yet. Keep agendas, decisions or house rules here.', colors: colors)
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: notes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final n = notes[i];
                final by = n.updatedBy == null ? null : chat.displayName(n.updatedBy!);
                return Material(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: busy ? null : () => _edit(context, n),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: colors.border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (n.title.isNotEmpty)
                                  Text(n.title, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700)),
                                Text(n.body, style: TextStyle(color: colors.textSecondary, height: 1.35)),
                                if (by != null || n.updatedAt != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    [if (by != null) 'Edited by $by', if (n.updatedAt != null) _fmt(n.updatedAt!.toLocal())]
                                        .join(' · '),
                                    style: TextStyle(color: colors.textMuted, fontSize: 11),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete note',
                            icon: Icon(Icons.delete_outline, color: colors.textMuted),
                            onPressed: busy ? null : () => hub({'action': 'remove', 'section': 'notes', 'itemId': n.id}),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _AddRow extends StatelessWidget {
  const _AddRow({required this.colors, required this.busy, required this.onAdd, required this.child});

  final QcColors colors;
  final bool busy;
  final VoidCallback onAdd;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(child: child),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Add',
            onPressed: busy ? null : onAdd,
            style: IconButton.styleFrom(backgroundColor: colors.accent, foregroundColor: colors.onAccent),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

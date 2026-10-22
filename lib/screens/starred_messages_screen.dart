import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/chat_controller.dart';
import '../state/theme_controller.dart';
import '../theme/qc_theme.dart';
import '../utils/message_preview.dart';
import '../widgets/common.dart';

/// Starred (local) and Important (server-backed) messages — mirrors the website's
/// StarredMessagesModal with its Starred / Important tabs.
class StarredMessagesScreen extends StatefulWidget {
  const StarredMessagesScreen({super.key, this.initialTab = 0});

  /// 0 = Starred, 1 = Important.
  final int initialTab;

  @override
  State<StarredMessagesScreen> createState() => _StarredMessagesScreenState();
}

class _StarredMessagesScreenState extends State<StarredMessagesScreen> {
  List<ChatMessage>? _important;
  String? _importantError;

  @override
  void initState() {
    super.initState();
    _loadImportant();
  }

  Future<void> _loadImportant() async {
    setState(() => _importantError = null);
    try {
      final rows = await context.read<ChatController>().loadImportantMessages();
      if (mounted) setState(() => _important = rows);
    } catch (e) {
      if (mounted) {
        setState(() {
          _important = const [];
          _importantError = "Couldn't load Important messages";
        });
      }
    }
  }

  Future<void> _unmarkImportant(ChatMessage m) async {
    final chat = context.read<ChatController>();
    m.isImportant = true;
    final ok = await chat.toggleImportant(m);
    if (!mounted) return;
    if (ok) {
      // Keep the open thread's copy in sync too.
      for (final open in chat.messages) {
        if (open.id == m.id) open.isImportant = false;
      }
      setState(() => _important = _important?.where((x) => x.id != m.id).toList());
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(chat.threadError ?? 'Could not update Important')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatController>();
    final colors = context.watch<ThemeController>().colors;
    final starred = chat.messages.where((m) => m.isStarred).toList();

    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab.clamp(0, 1),
      child: Scaffold(
        backgroundColor: colors.body,
        appBar: AppBar(
          backgroundColor: colors.surface,
          title: const Text('Saved messages'),
          bottom: TabBar(
            labelColor: colors.accent,
            unselectedLabelColor: colors.textMuted,
            indicatorColor: colors.accent,
            tabs: const [
              Tab(icon: Icon(Icons.star_outline, size: 18), text: 'Starred'),
              Tab(icon: Icon(Icons.label_important_outline, size: 18), text: 'Important'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            starred.isEmpty
                ? _EmptyState(
                    colors: colors,
                    icon: Icons.star_border,
                    title: 'No starred messages',
                    hint: 'Long-press a message and tap Star to save it here.',
                  )
                : _MessageList(
                    messages: starred,
                    colors: colors,
                    chat: chat,
                    icon: Icons.star,
                    trailingTooltip: 'Unstar',
                    onRemove: (m) {
                      m.isStarred = false;
                      chat.notify();
                    },
                  ),
            _buildImportant(chat, colors),
          ],
        ),
      ),
    );
  }

  Widget _buildImportant(ChatController chat, QcColors colors) {
    final rows = _important;
    if (rows == null) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    if (_importantError != null) {
      return _EmptyState(
        colors: colors,
        icon: Icons.cloud_off_outlined,
        title: _importantError!,
        hint: 'Pull down to try again.',
        onRefresh: _loadImportant,
      );
    }
    if (rows.isEmpty) {
      return _EmptyState(
        colors: colors,
        icon: Icons.label_important_outline,
        title: 'No Important messages',
        hint: 'Long-press a message and tap Mark as Important. They sync across your devices.',
        onRefresh: _loadImportant,
      );
    }
    return RefreshIndicator(
      onRefresh: _loadImportant,
      child: _MessageList(
        messages: rows,
        colors: colors,
        chat: chat,
        icon: Icons.label_important,
        trailingTooltip: 'Remove from Important',
        onRemove: _unmarkImportant,
        showConversation: true,
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.messages,
    required this.colors,
    required this.chat,
    required this.icon,
    required this.trailingTooltip,
    required this.onRemove,
    this.showConversation = false,
  });

  final List<ChatMessage> messages;
  final QcColors colors;
  final ChatController chat;
  final IconData icon;
  final String trailingTooltip;
  final void Function(ChatMessage) onRemove;
  final bool showConversation;

  String _where(ChatMessage m) {
    if (m.groupId != null) {
      for (final g in chat.groups) {
        if (g.id == m.groupId) return g.name;
      }
      return 'Group';
    }
    final peerId = m.isMine(chat.me.id) ? m.to : m.from;
    return peerId == null ? '' : chat.displayName(peerId);
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: messages.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: colors.border),
      itemBuilder: (ctx, i) {
        final m = messages[i];
        final mine = m.isMine(chat.me.id);
        final preview = getMessagePreviewText(m.text, isMine: mine);
        final sender = mine ? 'You' : chat.displayName(m.from);
        final where = showConversation ? _where(m) : '';
        return ListTile(
          leading: Icon(icon, color: colors.accentCyan),
          title: Text(
            m.locked
                ? '🔒 Time capsule'
                : preview.isNotEmpty
                    ? preview
                    : (m.attachment != null ? '📎 ${m.attachment!.filename}' : 'Message'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textPrimary),
          ),
          subtitle: Text(
            [sender, if (where.isNotEmpty && where != sender) where, formatMessageTime(m.createdAt)].join('  •  '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
          trailing: IconButton(
            icon: Icon(icon, color: colors.accentCyan),
            tooltip: trailingTooltip,
            onPressed: () => onRemove(m),
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.colors,
    required this.icon,
    required this.title,
    required this.hint,
    this.onRefresh,
  });

  final QcColors colors;
  final IconData icon;
  final String title;
  final String hint;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final body = Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: colors.textMuted),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(color: colors.textMuted, fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              hint,
              style: TextStyle(color: colors.textMuted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
    if (onRefresh == null) return body;
    return RefreshIndicator(
      onRefresh: onRefresh!,
      child: LayoutBuilder(
        builder: (ctx, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(height: constraints.maxHeight, child: body),
        ),
      ),
    );
  }
}

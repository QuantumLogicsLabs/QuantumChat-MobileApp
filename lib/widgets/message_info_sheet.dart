import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../state/auth_controller.dart';
import '../theme/qc_theme.dart';
import 'common.dart';

void showMessageInfoSheet({
  required BuildContext context,
  required ChatMessage message,
  required QcColors colors,
  bool isGroup = false,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: colors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _MessageInfoBody(
      message: message,
      colors: colors,
      isGroup: isGroup,
      api: ctx.read<AuthController>().api,
    ),
  );
}

class _MessageInfoBody extends StatefulWidget {
  const _MessageInfoBody({
    required this.message,
    required this.colors,
    required this.isGroup,
    required this.api,
  });

  final ChatMessage message;
  final QcColors colors;
  final bool isGroup;
  final ApiClient api;

  @override
  State<_MessageInfoBody> createState() => _MessageInfoBodyState();
}

class _MessageInfoBodyState extends State<_MessageInfoBody> {
  bool loading = false;
  String? error;
  Map<String, dynamic>? info;

  @override
  void initState() {
    super.initState();
    if (widget.isGroup) _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await widget.api.getMessageInfo(widget.message.id);
      if (!mounted) return;
      setState(() => info = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final message = widget.message;
    final fmt = DateFormat('MMM d, yyyy  h:mm:ss a');
    final shortFmt = DateFormat('MMM d, h:mm a');

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: widget.isGroup ? MediaQuery.sizeOf(context).height * 0.55 : null,
          child: Column(
            mainAxisSize: widget.isGroup ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Message info',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              if (message.createdAt != null)
                _InfoRow(label: 'Sent', value: fmt.format(message.createdAt!.toLocal()), colors: colors),
              if (message.editedAt != null)
                _InfoRow(label: 'Edited', value: fmt.format(message.editedAt!.toLocal()), colors: colors),
              if (!widget.isGroup) ...[
                if (message.deliveredAt != null)
                  _InfoRow(label: 'Delivered', value: fmt.format(message.deliveredAt!.toLocal()), colors: colors),
                if (message.readAt != null)
                  _InfoRow(label: 'Read', value: fmt.format(message.readAt!.toLocal()), colors: colors),
                if (message.deliveredAt == null && message.readAt == null)
                  Text('Not delivered yet', style: TextStyle(color: colors.textMuted, fontSize: 13)),
              ] else ...[
                if (loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (error != null)
                  Text(error!, style: TextStyle(color: colors.error, fontSize: 13))
                else if (info != null)
                  Expanded(child: _GroupInfoLists(info: info!, colors: colors, fmt: shortFmt)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupInfoLists extends StatelessWidget {
  const _GroupInfoLists({required this.info, required this.colors, required this.fmt});

  final Map<String, dynamic> info;
  final QcColors colors;
  final DateFormat fmt;

  @override
  Widget build(BuildContext context) {
    final members = (info['members'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final read = members.where((m) => m['readAt'] != null).toList();
    final deliveredOnly = members
        .where((m) => m['readAt'] == null && m['deliveredAt'] != null)
        .toList();
    final pending = members
        .where((m) => m['readAt'] == null && m['deliveredAt'] == null)
        .toList();
    final readCount = info['readCount'] as int? ?? read.length;
    final deliveredCount = info['deliveredCount'] as int? ?? (read.length + deliveredOnly.length);
    final total = info['totalRecipients'] as int? ?? members.length;

    return ListView(
      shrinkWrap: true,
      children: [
        Text(
          'Read $readCount · Delivered $deliveredCount · of $total',
          style: TextStyle(color: colors.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        if (read.isNotEmpty) ...[
          _SectionLabel(label: 'Read', colors: colors),
          ...read.map((m) => _MemberRow(member: m, colors: colors, fmt: fmt, kind: _MemberKind.read)),
        ],
        if (deliveredOnly.isNotEmpty) ...[
          const SizedBox(height: 8),
          _SectionLabel(label: 'Delivered', colors: colors),
          ...deliveredOnly.map((m) => _MemberRow(member: m, colors: colors, fmt: fmt, kind: _MemberKind.delivered)),
        ],
        if (pending.isNotEmpty) ...[
          const SizedBox(height: 8),
          _SectionLabel(label: 'Not delivered', colors: colors),
          ...pending.map((m) => _MemberRow(member: m, colors: colors, fmt: fmt, kind: _MemberKind.pending)),
        ],
        if (members.isEmpty)
          Text('No delivery details yet', style: TextStyle(color: colors.textMuted, fontSize: 13)),
      ],
    );
  }
}

enum _MemberKind { read, delivered, pending }

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.colors});
  final String label;
  final QcColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: TextStyle(color: colors.accentCyan, fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.colors,
    required this.fmt,
    required this.kind,
  });

  final Map<String, dynamic> member;
  final QcColors colors;
  final DateFormat fmt;
  final _MemberKind kind;

  @override
  Widget build(BuildContext context) {
    final userId = '${member['userId'] ?? ''}';
    final displayName = (member['displayName'] as String?)?.trim();
    final username = member['username'] as String? ?? 'member';
    final title = (displayName != null && displayName.isNotEmpty) ? displayName : username;
    final hasAvatar = member['hasAvatar'] == true;
    DateTime? at;
    final raw = kind == _MemberKind.read
        ? member['readAt']
        : kind == _MemberKind.delivered
            ? member['deliveredAt']
            : null;
    if (raw is String) at = DateTime.tryParse(raw);

    String subtitle;
    IconData icon;
    Color iconColor;
    switch (kind) {
      case _MemberKind.read:
        subtitle = at != null ? fmt.format(at.toLocal()) : 'Read';
        icon = Icons.done_all;
        iconColor = colors.accentCyan;
      case _MemberKind.delivered:
        subtitle = at != null ? fmt.format(at.toLocal()) : 'Delivered';
        icon = Icons.done_all;
        iconColor = colors.textMuted;
      case _MemberKind.pending:
        subtitle = 'Not delivered yet';
        icon = Icons.done;
        iconColor = colors.textMuted;
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: UserAvatar(name: title, userId: userId, hasAvatar: hasAvatar, size: 36),
      title: Text(title, style: TextStyle(color: colors.textPrimary, fontSize: 14)),
      subtitle: Text(subtitle, style: TextStyle(color: colors.textMuted, fontSize: 12)),
      trailing: Icon(icon, size: 18, color: iconColor),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, required this.colors});
  final String label;
  final String value;
  final QcColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(color: colors.textMuted, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(value, style: TextStyle(color: colors.textPrimary, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

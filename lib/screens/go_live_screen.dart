import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/chat_controller.dart';
import '../state/live_controller.dart';
import '../state/theme_controller.dart';
import '../widgets/common.dart';
import 'live_stream_screen.dart';

/// Pre-stream setup: title and audience (privacy). Mirrors the website's
/// GoLiveModal; on-device recording is web-only for now.
class GoLiveScreen extends StatefulWidget {
  const GoLiveScreen({super.key});

  @override
  State<GoLiveScreen> createState() => _GoLiveScreenState();
}

class _GoLiveScreenState extends State<GoLiveScreen> {
  final _title = TextEditingController();
  String _audience = 'friends';
  String? _groupId;
  final Set<String> _picked = {};
  final Set<String> _hidden = {};
  bool _showHideFrom = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  bool get _canStart =>
      !_submitting &&
      (_audience == 'friends' ||
          (_audience == 'group' && _groupId != null) ||
          (_audience == 'custom' && _picked.isNotEmpty));

  Future<void> _start() async {
    if (!_canStart) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final statuses = await [Permission.camera, Permission.microphone].request();
    if (statuses.values.any((s) => !s.isGranted)) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Camera and microphone access is needed to go live.';
      });
      return;
    }
    final audience = <String, dynamic>{'type': _audience};
    if (_audience == 'group') audience['groupId'] = _groupId;
    if (_audience == 'custom') audience['userIds'] = _picked.toList();
    if (_audience != 'custom' && _hidden.isNotEmpty) audience['hiddenFrom'] = _hidden.toList();
    try {
      if (!mounted) return;
      await context.read<LiveController>().startBroadcast(title: _title.text.trim(), audience: audience);
      if (!mounted) return;
      await Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LiveStreamScreen()));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e is ApiException ? e.message : 'Could not start your live video.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeController>().colors;
    final chat = context.watch<ChatController>();
    final friends = chat.friends;
    final groups = chat.groups;
    final muted = TextStyle(color: colors.textMuted, fontSize: 12);

    Widget audienceOption(String id, String label, String hint, IconData icon, {bool enabled = true}) {
      final selected = _audience == id;
      return ListTile(
        enabled: enabled && !_submitting,
        onTap: () => setState(() => _audience = id),
        leading: Icon(icon, color: colors.textSecondary),
        title: Text(label, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600)),
        subtitle: Text(hint, style: muted),
        trailing: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: selected ? colors.accent : colors.textMuted,
        ),
        contentPadding: EdgeInsets.zero,
      );
    }

    return Scaffold(
      backgroundColor: colors.body,
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [Icon(Icons.sensors, size: 20), SizedBox(width: 8), Text('Go live')],
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _title,
              enabled: !_submitting,
              maxLength: liveTitleMax,
              style: TextStyle(color: colors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Title (optional)',
                hintText: "What's happening?",
              ),
              onChanged: (_) => setState(() {}),
            ),
            Text("The title is visible to QuantumChat's servers.", style: muted),
            const SizedBox(height: 20),
            Text('Who can watch', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700)),
            audienceOption('friends', 'Friends', 'All your friends can watch', Icons.people_outline),
            audienceOption(
              'group',
              'A group',
              groups.isEmpty ? 'You are not in any groups' : 'Members of one group',
              Icons.groups_outlined,
              enabled: groups.isNotEmpty,
            ),
            audienceOption('custom', 'Selected friends', 'Only the people you pick', Icons.how_to_reg_outlined),
            if (_audience == 'group')
              DropdownButtonFormField<String>(
                initialValue: _groupId,
                dropdownColor: colors.elevated,
                decoration: const InputDecoration(labelText: 'Group'),
                items: [
                  for (final g in groups)
                    DropdownMenuItem(value: g.id, child: Text(g.name, style: TextStyle(color: colors.textPrimary))),
                ],
                onChanged: _submitting ? null : (v) => setState(() => _groupId = v),
              ),
            if (_audience == 'custom')
              _PeoplePicker(
                people: friends,
                selected: _picked,
                emptyText: 'Add friends to pick a custom audience',
                onToggle: (id) => setState(() => _picked.contains(id) ? _picked.remove(id) : _picked.add(id)),
              ),
            if (_audience == 'friends' && friends.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _showHideFrom = !_showHideFrom),
                  icon: const Icon(Icons.lock_outline, size: 16),
                  label: Text(_hidden.isEmpty ? 'Hide from specific friends' : 'Hidden from ${_hidden.length}'),
                ),
              ),
              if (_showHideFrom)
                _PeoplePicker(
                  people: friends,
                  selected: _hidden,
                  onToggle: (id) => setState(() => _hidden.contains(id) ? _hidden.remove(id) : _hidden.add(id)),
                ),
            ],
            const SizedBox(height: 16),
            Text(
              'Video, comments and reactions go directly between devices, end-to-end encrypted. '
              'Your audience will be notified when you go live.',
              style: muted,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: colors.error)),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _canStart ? _start : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE53935),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: _submitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.sensors),
              label: Text(_submitting ? 'Starting…' : 'Go live'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Searchable multi-select friend list (audience picker / hide-from).
class _PeoplePicker extends StatefulWidget {
  const _PeoplePicker({
    required this.people,
    required this.selected,
    required this.onToggle,
    this.emptyText = 'No friends to show',
  });

  final List<QcUser> people;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final String emptyText;

  @override
  State<_PeoplePicker> createState() => _PeoplePickerState();
}

class _PeoplePickerState extends State<_PeoplePicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeController>().colors;
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.people
        : widget.people
            .where((p) => p.displayName.toLowerCase().contains(q) || p.username.toLowerCase().contains(q))
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          style: TextStyle(color: colors.textPrimary),
          decoration: const InputDecoration(hintText: 'Search friends…', prefixIcon: Icon(Icons.search)),
          onChanged: (v) => setState(() => _query = v),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: filtered.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(widget.emptyText, style: TextStyle(color: colors.textMuted)),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final p in filtered)
                      CheckboxListTile(
                        value: widget.selected.contains(p.id),
                        onChanged: (_) => widget.onToggle(p.id),
                        activeColor: colors.accent,
                        secondary: UserAvatar(name: p.displayName.isNotEmpty ? p.displayName : p.username, userId: p.id, hasAvatar: p.hasAvatar, size: 34),
                        title: Text(
                          p.displayName.isNotEmpty ? p.displayName : p.username,
                          style: TextStyle(color: colors.textPrimary),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

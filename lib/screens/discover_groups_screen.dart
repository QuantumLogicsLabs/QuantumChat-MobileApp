import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/auth_controller.dart';
import '../state/chat_controller.dart';
import '../state/theme_controller.dart';
import '../widgets/common.dart';
import 'thread_screen.dart';

class DiscoverGroupsScreen extends StatefulWidget {
  const DiscoverGroupsScreen({super.key});

  @override
  State<DiscoverGroupsScreen> createState() => _DiscoverGroupsScreenState();
}

class _DiscoverGroupsScreenState extends State<DiscoverGroupsScreen> {
  final search = TextEditingController();
  List<DiscoverGroup> items = [];
  bool loading = true;
  String? error;
  String? joiningId;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<void> _load([String q = '']) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final list = await context.read<AuthController>().api.discoverGroups(q: q);
      if (!mounted) return;
      setState(() => items = list);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _load(q.trim()));
  }

  Future<void> _joinOrRequest(DiscoverGroup g) async {
    if (joiningId != null) return;
    setState(() => joiningId = g.id);
    final api = context.read<AuthController>().api;
    final chat = context.read<ChatController>();
    try {
      if (g.requiresRequest) {
        await api.createJoinRequest(g.id);
        if (!mounted) return;
        setState(() {
          items = items
              .map((x) => x.id == g.id ? x.copyWith(joinRequestPending: true) : x)
              .toList();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Join request sent')),
        );
      } else {
        final group = await api.joinPublicGroup(g.id);
        await chat.refreshInbox();
        if (!mounted) return;
        final matches = chat.conversations.where((c) => c.id == group.id).toList();
        final conv = matches.isNotEmpty
            ? matches.first
            : Conversation(
                key: chat.storage.conversationKeyForGroup(group.id),
                type: ConversationType.group,
                id: group.id,
                title: group.name,
                subtitle: group.description,
                group: group,
              );
        await chat.open(conv);
        if (!mounted) return;
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ThreadScreen()),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => joiningId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeController>().colors;
    return Scaffold(
      backgroundColor: colors.body,
      appBar: AppBar(
        title: const Text('Discover groups'),
        backgroundColor: colors.surface,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: search,
              onChanged: _onSearch,
              decoration: InputDecoration(
                hintText: 'Search public groups',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: search.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          search.clear();
                          _load();
                        },
                        icon: const Icon(Icons.close, size: 18),
                      ),
              ),
            ),
          ),
          if (loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: error != null
                ? Center(child: Text(error!, style: TextStyle(color: colors.error)))
                : items.isEmpty && !loading
                    ? Center(
                        child: Text(
                          search.text.trim().isEmpty
                              ? 'No public groups to discover'
                              : 'No groups match your search',
                          style: TextStyle(color: colors.textMuted),
                        ),
                      )
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final g = items[i];
                          final busy = joiningId == g.id;
                          final pending = g.joinRequestPending;
                          String btnLabel;
                          if (pending) {
                            btnLabel = 'Pending';
                          } else if (g.requiresRequest) {
                            btnLabel = 'Request';
                          } else {
                            btnLabel = 'Join';
                          }
                          return ListTile(
                            leading: UserAvatar(
                              name: g.name,
                              userId: g.id,
                              hasAvatar: g.hasPhoto,
                              isGroup: true,
                            ),
                            title: Text(g.name, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w700)),
                            subtitle: Text(
                              [
                                if (g.description.isNotEmpty) g.description,
                                '${g.memberCount} members · ${g.requiresRequest ? 'Request' : 'Open'}',
                              ].join('\n'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: colors.textMuted, fontSize: 13),
                            ),
                            isThreeLine: g.description.isNotEmpty,
                            trailing: busy
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : TextButton(
                                    onPressed: pending ? null : () => _joinOrRequest(g),
                                    child: Text(btnLabel),
                                  ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

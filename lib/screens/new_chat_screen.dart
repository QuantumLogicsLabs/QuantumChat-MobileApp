import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/auth_controller.dart';
import '../state/chat_controller.dart';
import '../state/theme_controller.dart';
import '../widgets/common.dart';
import 'thread_screen.dart';
import 'user_profile_screen.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final query = TextEditingController();
  final contactQuery = TextEditingController();
  List<QcUser> results = [];
  bool loading = false;
  String? lookupStatus;
  Map<String, dynamic>? lookupHit;

  @override
  void initState() {
    super.initState();
    final chat = context.read<ChatController>();
    results = chat.discoverCandidates.isNotEmpty ? chat.discoverCandidates : chat.users;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDiscover();
    });
  }

  @override
  void dispose() {
    query.dispose();
    contactQuery.dispose();
    super.dispose();
  }

  Future<void> _loadDiscover({String q = ''}) async {
    setState(() => loading = true);
    final api = context.read<AuthController>().api;
    final chat = context.read<ChatController>();
    try {
      final users = await api.discoverUsers(q: q);
      if (!mounted) return;
      chat.discoverCandidates = users;
      setState(() => results = users);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _search(String q) async {
    await _loadDiscover(q: q.trim());
  }

  Future<void> _lookupContact() async {
    final raw = contactQuery.text.trim();
    if (raw.isEmpty) return;
    setState(() {
      loading = true;
      lookupStatus = null;
      lookupHit = null;
    });
    try {
      final api = context.read<AuthController>().api;
      final isEmail = raw.contains('@');
      final hit = await api.lookupContact(
        email: isEmail ? raw : null,
        phone: isEmail ? null : raw,
      );
      if (!mounted) return;
      setState(() {
        lookupHit = hit;
        lookupStatus = hit == null ? 'No matching contact found' : null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => lookupStatus = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _openUser(QcUser u) async {
    final chat = context.read<ChatController>();
    final conv = Conversation(
      key: chat.storage.conversationKeyForUser(u.id),
      type: ConversationType.dm,
      id: u.id,
      title: u.title,
      peer: u,
    );
    await chat.open(conv);
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ThreadScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeController>().colors;
    final chat = context.watch<ChatController>();
    return Scaffold(
      appBar: AppBar(title: const Text('New chat')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: query,
              onChanged: _search,
              decoration: const InputDecoration(
                hintText: 'Search by username',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: contactQuery,
                    decoration: const InputDecoration(
                      hintText: 'Find by email or phone',
                      prefixIcon: Icon(Icons.contact_mail_outlined),
                    ),
                    onSubmitted: (_) => _lookupContact(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _lookupContact,
                  icon: const Icon(Icons.search),
                  tooltip: 'Lookup contact',
                ),
              ],
            ),
          ),
          if (lookupStatus != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(lookupStatus!, style: TextStyle(color: colors.textMuted)),
            ),
          if (lookupHit != null)
            ListTile(
              leading: UserAvatar(
                name: '${lookupHit!['displayName'] ?? lookupHit!['username'] ?? 'User'}',
                userId: '${lookupHit!['id'] ?? lookupHit!['_id']}',
                hasAvatar: lookupHit!['hasAvatar'] == true,
              ),
              title: Text(
                '${lookupHit!['displayName'] ?? lookupHit!['username']}',
                style: TextStyle(color: colors.textPrimary),
              ),
              subtitle: Text(
                '@${lookupHit!['username'] ?? ''} · ${lookupHit!['requestStatus'] ?? 'none'}',
                style: TextStyle(color: colors.textMuted),
              ),
              trailing: IconButton(
                icon: Icon(Icons.person_add, color: colors.accent),
                onPressed: () async {
                  try {
                    await context.read<AuthController>().api.sendFriendRequest(
                          '${lookupHit!['id'] ?? lookupHit!['_id']}',
                        );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Friend request sent')),
                      );
                    }
                  } on ApiException catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                    }
                  }
                },
              ),
              onTap: () {
                final u = QcUser.fromJson(Map<String, dynamic>.from(lookupHit!));
                _openUser(u);
              },
            ),
          if (loading) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'People on QuantumChat',
                style: TextStyle(color: colors.accentCyan, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          Expanded(
            child: results.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 48),
                      Icon(Icons.people_outline, size: 48, color: colors.textMuted),
                      const SizedBox(height: 12),
                      Text(
                        'No members found',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.textSecondary),
                      ),
                    ],
                  )
                : ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, i) {
                      final u = results[i];
                      final isFriend = chat.isFriendId(u.id);
                      final isMe = u.id == chat.me.id;
                      final pending = u.requestStatus == 'pending_sent';
                      return ListTile(
                        leading: GestureDetector(
                          onTap: isMe
                              ? null
                              : () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => UserProfileScreen(userId: u.id)),
                                  ),
                          child: UserAvatar(name: u.title, userId: u.id, hasAvatar: u.hasAvatar),
                        ),
                        title: Text(u.title, style: TextStyle(color: colors.textPrimary)),
                        subtitle: Text('@${u.username}', style: TextStyle(color: colors.textMuted)),
                        trailing: isMe || isFriend
                            ? (isFriend
                                ? Icon(Icons.check_circle_outline, color: colors.success, size: 20)
                                : null)
                            : IconButton(
                                tooltip: pending ? 'Request sent' : 'Add friend',
                                icon: Icon(
                                  pending ? Icons.hourglass_top : Icons.person_add,
                                  color: colors.accent,
                                ),
                                onPressed: pending
                                    ? null
                                    : () async {
                                        try {
                                          await context.read<AuthController>().api.sendFriendRequest(u.id);
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Friend request sent')),
                                            );
                                          }
                                          await _loadDiscover(q: query.text.trim());
                                        } on ApiException catch (e) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text(e.message)),
                                            );
                                          }
                                        }
                                      },
                              ),
                        onTap: () => _openUser(u),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final name = TextEditingController();
  final selected = <String>{};
  bool busy = false;
  String visibility = 'private';
  String joinPolicy = 'open';

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatController>();
    final colors = context.watch<ThemeController>().colors;
    final byId = <String, QcUser>{
      for (final u in [...chat.friends, ...chat.users, ...chat.discoverCandidates])
        if (u.id != chat.me.id) u.id: u,
    };
    final memberPool = byId.values.toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    return Scaffold(
      appBar: AppBar(title: const Text('New group')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: name,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: 'Group name'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Visibility', style: TextStyle(color: colors.textSecondary, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'private', label: Text('Private'), icon: Icon(Icons.lock_outline, size: 16)),
                    ButtonSegment(value: 'public', label: Text('Public'), icon: Icon(Icons.public, size: 16)),
                  ],
                  selected: {visibility},
                  onSelectionChanged: (s) => setState(() => visibility = s.first),
                ),
                if (visibility == 'public') ...[
                  const SizedBox(height: 12),
                  Text('Join policy', style: TextStyle(color: colors.textSecondary, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'open', label: Text('Open')),
                      ButtonSegment(value: 'request', label: Text('Request')),
                    ],
                    selected: {joinPolicy},
                    onSelectionChanged: (s) => setState(() => joinPolicy = s.first),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Add members', style: TextStyle(color: colors.textSecondary, fontWeight: FontWeight.w600)),
            ),
          ),
          Expanded(
            child: memberPool.isEmpty
                ? Center(
                    child: Text(
                      'No members loaded yet. Pull to refresh on home or open People first.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.textMuted),
                    ),
                  )
                : ListView(
                    children: memberPool.map((u) {
                      final on = selected.contains(u.id);
                      return CheckboxListTile(
                        value: on,
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            selected.add(u.id);
                          } else {
                            selected.remove(u.id);
                          }
                        }),
                        title: Text(u.title, style: TextStyle(color: colors.textPrimary)),
                        secondary: UserAvatar(name: u.title, userId: u.id, hasAvatar: u.hasAvatar, size: 36),
                      );
                    }).toList(),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: QcPrimaryButton(
              label: busy ? 'Creating…' : 'Create group',
              loading: busy,
              onPressed: name.text.trim().isEmpty
                  ? null
                  : () async {
                      setState(() => busy = true);
                      final group = await chat.createGroup(
                        name.text.trim(),
                        selected.toList(),
                        visibility: visibility,
                        joinPolicy: visibility == 'public' ? joinPolicy : null,
                      );
                      if (group != null && context.mounted) {
                        final conv = Conversation(
                          key: chat.storage.conversationKeyForGroup(group.id),
                          type: ConversationType.group,
                          id: group.id,
                          title: group.name,
                          group: group,
                        );
                        await chat.open(conv);
                        if (context.mounted) {
                          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ThreadScreen()));
                        }
                      } else if (mounted) {
                        setState(() => busy = false);
                      }
                    },
            ),
          ),
        ],
      ),
    );
  }
}

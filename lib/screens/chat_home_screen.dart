import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/auth_controller.dart';
import '../state/chat_controller.dart';
import '../state/theme_controller.dart';
import '../theme/qc_theme.dart';
import '../widgets/common.dart';
import '../widgets/stories_rail.dart';
import '../widgets/theme_scene.dart';
import 'new_chat_screen.dart';
import 'join_group_screen.dart';
import 'discover_groups_screen.dart';
import 'activity_screen.dart';
import 'birthday_calendar_screen.dart';
import 'settings_screen.dart';
import 'thread_screen.dart';
import 'user_profile_screen.dart';

class ChatHomeScreen extends StatefulWidget {
  const ChatHomeScreen({super.key});

  @override
  State<ChatHomeScreen> createState() => _ChatHomeScreenState();
}

class _ChatHomeScreenState extends State<ChatHomeScreen> {
  final search = TextEditingController();
  /// Defer stories + inbox start so AppBar/title paint first (avoids black frame).
  bool _showStories = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ChatController>().start();
      // One more frame before mounting StoriesRail (image/decrypt heavy).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _showStories = true);
      });
    });
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _openQuantumAi(BuildContext context) async {
    final chat = context.read<ChatController>();
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Opening QuantumAI…'), duration: Duration(seconds: 1)),
      );
      await chat.openQuantumAiChat();
      if (!context.mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ThreadScreen()),
      );
      chat.closeThread();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatController>();
    final auth = context.watch<AuthController>();
    final theme = context.watch<ThemeController>();
    final colors = theme.colors;
    final scenic = theme.isFunTheme;
    // Website order — but when friend requests arrive, pull Friends right
    // after All and highlight it so the request is hard to miss.
    final hasFriendRequests = chat.incomingRequestCount > 0;
    final filters = hasFriendRequests
        ? <(String, String)>[
            ('all', 'All'),
            ('friends', 'Friends'),
            ('unread', 'Unread'),
            ('groups', 'Groups'),
            ('discover', 'Discover'),
            ('archived', 'Archived'),
          ]
        : <(String, String)>[
            ('all', 'All'),
            ('unread', 'Unread'),
            ('groups', 'Groups'),
            ('friends', 'Friends'),
            ('discover', 'Discover'),
            ('archived', 'Archived'),
          ];

    // Never use a transparent scaffold — on emulators that reads as a black
    // hole when ThemeScene / GPU composition lags behind the first paint.
    return Scaffold(
      backgroundColor: colors.body,
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        backgroundColor: scenic ? colors.surface.withValues(alpha: 0.92) : colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('QuantumChat'),
            Text(
              auth.user?.title ?? '',
              style: TextStyle(color: colors.textMuted, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'QuantumAI',
            onPressed: () => _openQuantumAi(context),
            icon: const Icon(Icons.auto_awesome),
          ),
          IconButton(
            tooltip: 'Activity',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ActivityScreen())),
            icon: const Icon(Icons.timeline_outlined),
          ),
          IconButton(
            tooltip: 'Birthdays',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BirthdayCalendarScreen())),
            icon: const Icon(Icons.cake_outlined),
          ),
          IconButton(
            tooltip: 'New chat',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewChatScreen())),
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
          IconButton(
            tooltip: 'Discover groups',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DiscoverGroupsScreen())),
            icon: const Icon(Icons.travel_explore_outlined),
          ),
          IconButton(
            tooltip: 'Join group',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const JoinGroupScreen())),
            icon: const Icon(Icons.link),
          ),
          IconButton(
            tooltip: 'New group',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateGroupScreen())),
            icon: const Icon(Icons.group_add_outlined),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openQuantumAi(context),
        icon: const Icon(Icons.auto_awesome),
        label: const Text('QuantumAI'),
      ),
      body: ThemeScene(
        themeId: theme.id,
        intensity: 0.55,
        animate: false,
        child: Column(
          children: [
          if (auth.user?.emailVerified == false)
            Material(
              color: colors.accentMuted,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Expanded(child: Text('Verify your email', style: TextStyle(color: colors.textPrimary))),
                    TextButton(
                      onPressed: () async {
                        try {
                          await auth.api.resendVerification();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Verification email sent')),
                            );
                          }
                        } catch (_) {}
                      },
                      child: const Text('Resend'),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: search,
              onChanged: (v) => chat.searchPeople(v),
              decoration: InputDecoration(
                hintText: chat.filter == 'discover'
                    ? 'Search public groups'
                    : chat.filter == 'friends'
                        ? 'Search friends'
                        : 'Search conversations',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: search.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          search.clear();
                          chat.searchPeople('');
                        },
                        icon: const Icon(Icons.close, size: 18),
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: filters.map((f) {
                final selected = chat.filter == f.$1 ||
                    (f.$1 == 'discover' && chat.filter == 'people');
                final requestCount = f.$1 == 'friends' ? chat.incomingRequestCount : 0;
                final hasRequests = requestCount > 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Badge(
                    isLabelVisible: hasRequests,
                    label: Text(
                      requestCount > 9 ? '9+' : '$requestCount',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
                    ),
                    backgroundColor: const Color(0xFFE11D48),
                    child: ChoiceChip(
                      avatar: hasRequests
                          ? Icon(
                              Icons.person_add_alt_1,
                              size: 16,
                              color: selected ? Colors.white : const Color(0xFFE11D48),
                            )
                          : null,
                      label: Text(f.$2),
                      selected: selected,
                      onSelected: (_) => chat.setFilter(f.$1),
                      selectedColor: hasRequests ? const Color(0xFFE11D48) : colors.accent,
                      labelStyle: TextStyle(
                        color: selected
                            ? (hasRequests ? Colors.white : colors.onAccent)
                            : hasRequests
                                ? const Color(0xFFE11D48)
                                : colors.textSecondary,
                        fontWeight: hasRequests ? FontWeight.w800 : FontWeight.w600,
                      ),
                      backgroundColor: hasRequests && !selected
                          ? const Color(0x33E11D48)
                          : colors.elevated,
                      side: BorderSide(
                        width: hasRequests ? 1.5 : 1,
                        color: hasRequests
                            ? const Color(0xFFE11D48)
                            : (selected ? colors.accent : colors.border),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          if (_showStories) const StoriesRail() else const SizedBox(height: 8),
          if (chat.inboxError != null && chat.inboxError!.isNotEmpty)
            Material(
              color: const Color(0x33E11D48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        chat.inboxError!,
                        style: TextStyle(color: colors.textPrimary, fontSize: 13),
                      ),
                    ),
                    TextButton(
                      onPressed: () => chat.refreshInbox(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          if ((chat.filter == 'friends' || chat.filter == 'all') && chat.friendRequests.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    'Friend requests',
                    style: TextStyle(color: colors.accentCyan, fontWeight: FontWeight.w800),
                  ),
                ),
                ...chat.friendRequests.map(
                  (r) => ListTile(
                    leading: UserAvatar(name: r.from.title, userId: r.from.id, hasAvatar: r.from.hasAvatar),
                    title: Text(
                      r.from.title.isNotEmpty ? r.from.title : '@${r.from.username}',
                      style: TextStyle(color: colors.textPrimary),
                    ),
                    subtitle: Text(
                      r.from.username.isNotEmpty ? '@${r.from.username}' : 'Incoming request',
                      style: TextStyle(color: colors.textMuted),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Accept',
                          onPressed: () => chat.acceptFriendRequest(r.id),
                          icon: Icon(Icons.check_circle, color: colors.success),
                        ),
                        IconButton(
                          tooltip: 'Decline',
                          onPressed: () => chat.declineFriendRequest(r.id),
                          icon: Icon(Icons.cancel, color: colors.error),
                        ),
                      ],
                    ),
                  ),
                ),
                Divider(color: colors.border.withValues(alpha: 0.5)),
              ],
            ),
          const SizedBox(height: 4),
          Expanded(
            child: chat.filter == 'discover' || chat.filter == 'people'
                ? _DiscoverGroupsPane(
                    colors: colors,
                    onJoined: () async {
                      await chat.refreshInbox();
                      chat.setFilter('all');
                    },
                  )
                : chat.loadingInbox && chat.conversations.isEmpty
                    ? const Center(
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: chat.refreshInbox,
                        child: chat.conversations.isEmpty
                            ? ListView(
                                children: [
                                  const SizedBox(height: 80),
                                  Icon(
                                    chat.filter == 'friends'
                                        ? Icons.people_outline
                                        : chat.filter == 'groups'
                                            ? Icons.groups_outlined
                                            : Icons.chat_bubble_outline,
                                    size: 48,
                                    color: colors.textMuted,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    chat.filter == 'friends'
                                        ? 'No friends yet — open All to find people'
                                        : chat.filter == 'unread'
                                            ? 'No unread chats'
                                            : chat.filter == 'groups'
                                                ? 'No groups yet'
                                                : chat.filter == 'archived'
                                                    ? 'No archived chats'
                                                    : 'No conversations yet',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: colors.textSecondary),
                                  ),
                                  if (chat.filter == 'friends') ...[
                                    const SizedBox(height: 16),
                                    Center(
                                      child: FilledButton.icon(
                                        onPressed: () => chat.setFilter('all'),
                                        icon: const Icon(Icons.people_alt_outlined),
                                        label: const Text('Browse people'),
                                      ),
                                    ),
                                  ],
                                ],
                              )
                            : ListView.separated(
                                itemCount: chat.conversations.length,
                                separatorBuilder: (_, __) => Divider(
                                  height: 1,
                                  color: colors.border.withValues(alpha: scenic ? 0.35 : 0.6),
                                ),
                                itemBuilder: (context, i) {
                                  final c = chat.conversations[i];
                                  final canAddFriend = !chat.isFriendId(c.id) &&
                                      !c.isSelfChat &&
                                      c.type == ConversationType.dm &&
                                      c.peer?.isQuantumAi != true &&
                                      (chat.filter == 'all' || chat.filter == 'friends') &&
                                      c.peer?.requestStatus != 'pending_sent';
                                  return Material(
                                    color: scenic ? colors.surface.withValues(alpha: 0.28) : Colors.transparent,
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                      leading: GestureDetector(
                                        onTap: c.type == ConversationType.dm && !c.isSelfChat
                                            ? () => Navigator.push(
                                                  context,
                                                  MaterialPageRoute(builder: (_) => UserProfileScreen(userId: c.id)),
                                                )
                                            : null,
                                        child: UserAvatar(
                                          name: c.title,
                                          userId: c.id,
                                          hasAvatar: c.peer?.hasAvatar == true || c.group?.hasPhoto == true,
                                          isGroup: c.type == ConversationType.group,
                                          online: c.online,
                                          size: 48,
                                        ),
                                      ),
                                      title: Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              c.title,
                                              style: TextStyle(
                                                color: colors.textPrimary,
                                                fontWeight: c.unread ? FontWeight.w800 : FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          if (c.peer?.isQuantumAi == true) ...[
                                            const SizedBox(width: 6),
                                            Icon(Icons.auto_awesome, size: 14, color: colors.accentCyan),
                                          ],
                                        ],
                                      ),
                                      subtitle: Text(
                                        c.peer?.isQuantumAi == true
                                            ? 'Your sealed AI companion'
                                            : (c.subtitle ??
                                                (c.online
                                                    ? 'online'
                                                    : formatLastSeen(c.peer?.lastLoginAt, online: c.online))),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: c.unread ? colors.accentCyan : colors.textMuted),
                                      ),
                                      trailing: canAddFriend
                                          ? IconButton(
                                              tooltip: c.peer?.requestStatus == 'pending_received'
                                                  ? 'Accept request'
                                                  : 'Add friend',
                                              icon: Icon(Icons.person_add_alt_1, color: colors.accent),
                                              onPressed: () async {
                                                try {
                                                  if (c.peer?.requestStatus == 'pending_received' &&
                                                      c.peer?.requestId != null) {
                                                    await chat.acceptFriendRequest(c.peer!.requestId!);
                                                  } else {
                                                    await auth.api.sendFriendRequest(c.id);
                                                    if (context.mounted) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        const SnackBar(content: Text('Friend request sent')),
                                                      );
                                                    }
                                                    await chat.refreshInbox();
                                                  }
                                                } on ApiException catch (e) {
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(content: Text(e.message)),
                                                    );
                                                  }
                                                }
                                              },
                                            )
                                          : c.unread
                                              ? Container(
                                                  width: 10,
                                                  height: 10,
                                                  decoration: BoxDecoration(
                                                    color: colors.accent,
                                                    shape: BoxShape.circle,
                                                  ),
                                                )
                                              : null,
                                      onTap: () {
                                        unawaited(chat.open(c));
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => const ThreadScreen()),
                                        ).then((_) {
                                          if (context.mounted) chat.closeThread();
                                        });
                                      },
                                    ),
                                  );
                                },
                              ),
                      ),
          ),
        ],
      ),
      ),
    );
  }
}

class _DiscoverGroupsPane extends StatelessWidget {
  const _DiscoverGroupsPane({required this.colors, required this.onJoined});

  final QcColors colors;
  final Future<void> Function() onJoined;

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatController>();
    final auth = context.watch<AuthController>();
    final items = chat.discoverGroups;

    if (chat.loadingDiscoverGroups && items.isEmpty) {
      return const Center(
        child: SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 3)),
      );
    }

    return RefreshIndicator(
      onRefresh: () => chat.refreshDiscoverGroups(q: ''),
      child: items.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 80),
                Icon(Icons.travel_explore_outlined, size: 48, color: colors.textMuted),
                const SizedBox(height: 12),
                Text(
                  'No public groups to discover',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textSecondary),
                ),
              ],
            )
          : ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: colors.border.withValues(alpha: 0.5)),
              itemBuilder: (context, i) {
                final g = items[i];
                final pending = g.joinRequestPending;
                final label = pending
                    ? 'Pending'
                    : g.requiresRequest
                        ? 'Request'
                        : 'Join';
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
                  trailing: TextButton(
                    onPressed: pending
                        ? null
                        : () async {
                            try {
                              if (g.requiresRequest) {
                                await auth.api.createJoinRequest(g.id);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Join request sent')),
                                  );
                                }
                                await chat.refreshDiscoverGroups();
                              } else {
                                final group = await auth.api.joinPublicGroup(g.id);
                                await onJoined();
                                if (!context.mounted) return;
                                final conv = Conversation(
                                  key: chat.storage.conversationKeyForGroup(group.id),
                                  type: ConversationType.group,
                                  id: group.id,
                                  title: group.name,
                                  subtitle: group.description,
                                  group: group,
                                );
                                unawaited(chat.open(conv));
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const ThreadScreen()),
                                );
                              }
                            } on ApiException catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(e.message)),
                                );
                              }
                            }
                          },
                    child: Text(label),
                  ),
                );
              },
            ),
    );
  }
}

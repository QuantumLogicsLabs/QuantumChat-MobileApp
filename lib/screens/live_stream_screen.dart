import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/live_controller.dart';
import '../widgets/common.dart';

/// Full-screen live video for both the host and a viewer. Pass [watchStreamId]
/// to join a stream; omit it right after [LiveController.startBroadcast].
class LiveStreamScreen extends StatefulWidget {
  const LiveStreamScreen({super.key, this.watchStreamId});

  final String? watchStreamId;

  @override
  State<LiveStreamScreen> createState() => _LiveStreamScreenState();
}

class _LiveStreamScreenState extends State<LiveStreamScreen> {
  final _renderer = RTCVideoRenderer();
  final _comment = TextEditingController();
  late final LiveController _live;
  MediaStream? _shown;
  Timer? _clock;
  bool _rendererReady = false;

  @override
  void initState() {
    super.initState();
    _live = context.read<LiveController>();
    _live.addListener(_syncRenderer);
    _renderer.initialize().then((_) {
      if (!mounted) return;
      setState(() => _rendererReady = true);
      _syncRenderer();
    });
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _live.session?.isLive == true) setState(() {});
    });
    final id = widget.watchStreamId;
    if (id != null) unawaited(_watch(id));
  }

  Future<void> _watch(String id) async {
    try {
      await _live.watch(id);
    } catch (e) {
      if (!mounted) return;
      final message = switch (e) {
        ApiException(status: 410) => 'This live video has ended',
        ApiException(status: 403) => "You can't watch this live video",
        ApiException(:final message) => message,
        _ => 'Could not join the live video',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      unawaited(_live.refreshStreams());
      Navigator.pop(context);
    }
  }

  void _syncRenderer() {
    if (!_rendererReady) return;
    final s = _live.session;
    final next = s?.isHost == true ? _live.localStream : _live.remoteStream;
    if (identical(next, _shown)) return;
    _shown = next;
    _renderer.srcObject = next;
  }

  @override
  void dispose() {
    _clock?.cancel();
    _live.removeListener(_syncRenderer);
    // Leaving the screen any way at all ends hosting / leaves the stream.
    unawaited(_live.leave());
    _renderer.srcObject = null;
    unawaited(_renderer.dispose());
    _comment.dispose();
    super.dispose();
  }

  Future<void> _confirmEnd() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End live video?'),
        content: const Text('Your viewers will be disconnected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep streaming')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('End')),
        ],
      ),
    );
    if (ok == true) await _live.endBroadcast();
  }

  void _send() {
    final text = _comment.text.trim();
    if (text.isEmpty) return;
    _live.postComment(text);
    _comment.clear();
  }

  Future<void> _showViewers() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      builder: (ctx) => Consumer<LiveController>(
        builder: (ctx, live, _) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  'Watching (${live.viewers.length})',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
              if (live.viewers.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No one is watching yet', style: TextStyle(color: Colors.white60)),
                ),
              for (final v in live.viewers)
                ListTile(
                  leading: UserAvatar(name: v.name, userId: v.id, size: 36),
                  title: Text(v.name, style: const TextStyle(color: Colors.white)),
                  trailing: TextButton(
                    onPressed: () => unawaited(live.removeViewer(v.id).catchError((_) {})),
                    child: const Text('Remove', style: TextStyle(color: Color(0xFFFF6B6B))),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final live = context.watch<LiveController>();
    final s = live.session;

    return PopScope(
      canPop: s == null || !s.isHost || !s.isLive,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmEnd());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: true,
        body: s == null
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : Stack(
                fit: StackFit.expand,
                children: [
                  if (_rendererReady)
                    RTCVideoView(
                      _renderer,
                      mirror: s.isHost,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  if (s.isHost && live.cameraOff) const _CenterNote(icon: Icons.videocam_off, text: 'Camera is off'),
                  if (!s.isHost && s.status != LiveStatus.ended) _ViewerConnectionNote(live: live),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x99000000), Color(0x00000000), Color(0x00000000), Color(0xB3000000)],
                        stops: [0, 0.2, 0.6, 1],
                      ),
                    ),
                  ),
                  _Reactions(reactions: live.reactions),
                  SafeArea(
                    child: Column(
                      children: [
                        _TopBar(
                          session: s,
                          viewerCount: live.viewerCount,
                          onViewers: s.isHost ? _showViewers : null,
                          onClose: () => s.isHost && s.isLive ? _confirmEnd() : Navigator.maybePop(context),
                        ),
                        const Spacer(),
                        if (s.status != LiveStatus.ended) ...[
                          _CommentList(comments: live.comments),
                          if (s.isHost) _HostControls(live: live, onEnd: _confirmEnd),
                          _CommentBar(
                            controller: _comment,
                            enabled: s.isLive && (s.isHost || s.allowComments),
                            hint: s.isHost || s.allowComments ? 'Comment…' : 'Comments are turned off',
                            onSend: _send,
                            onReact: live.sendReaction,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (s.status == LiveStatus.ended) _EndedCard(session: s, onClose: () => Navigator.maybePop(context)),
                ],
              ),
      ),
    );
  }
}

String _elapsed(DateTime since) {
  final d = DateTime.now().difference(since);
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$sec' : '$m:$sec';
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.session, required this.viewerCount, required this.onClose, this.onViewers});

  final LiveSession session;
  final int viewerCount;
  final VoidCallback onClose;
  final VoidCallback? onViewers;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final name = s.isHost ? 'You' : (s.hostName.isEmpty ? 'Live' : s.hostName);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
      child: Row(
        children: [
          if (!s.isHost && s.hostId.isNotEmpty) ...[
            UserAvatar(name: s.hostName, userId: s.hostId, hasAvatar: s.hostHasAvatar, size: 36),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                if (s.title.isNotEmpty)
                  Text(
                    s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
              ],
            ),
          ),
          if (s.isLive) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFFE53935), borderRadius: BorderRadius.circular(4)),
              child: Text(
                'LIVE ${_elapsed(s.startedAt)}',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              onTap: onViewers,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(4)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.visibility, color: Colors.white, size: 13),
                    const SizedBox(width: 4),
                    Text('$viewerCount', style: const TextStyle(color: Colors.white, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ],
          IconButton(onPressed: onClose, icon: const Icon(Icons.close, color: Colors.white)),
        ],
      ),
    );
  }
}

class _CenterNote extends StatelessWidget {
  const _CenterNote({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 40),
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(color: Colors.white70)),
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}

class _ViewerConnectionNote extends StatelessWidget {
  const _ViewerConnectionNote({required this.live});
  final LiveController live;

  @override
  Widget build(BuildContext context) {
    switch (live.connection) {
      case LiveConnection.connected:
      case LiveConnection.idle:
        return const SizedBox.shrink();
      case LiveConnection.failed:
        return _CenterNote(
          icon: Icons.wifi_off,
          text: "Couldn't connect to the live video",
          action: FilledButton(onPressed: live.reconnect, child: const Text('Try again')),
        );
      case LiveConnection.reconnecting:
      case LiveConnection.connecting:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 12),
              Text(
                live.connection == LiveConnection.reconnecting ? 'Reconnecting…' : 'Connecting…',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        );
    }
  }
}

class _CommentList extends StatelessWidget {
  const _CommentList({required this.comments});
  final List<LiveComment> comments;

  @override
  Widget build(BuildContext context) {
    final recent = comments.length > 40 ? comments.sublist(comments.length - 40) : comments;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.3),
      child: ListView.builder(
        reverse: true,
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: recent.length,
        itemBuilder: (_, i) {
          final c = recent[recent.length - 1 - i];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: c.isHost ? '${c.fromName} (host)  ' : '${c.fromName}  ',
                    style: TextStyle(
                      color: c.isHost ? const Color(0xFFFFB4A9) : Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(text: c.text, style: const TextStyle(color: Colors.white)),
                ],
              ),
              style: const TextStyle(fontSize: 13, shadows: [Shadow(blurRadius: 4)]),
            ),
          );
        },
      ),
    );
  }
}

class _HostControls extends StatelessWidget {
  const _HostControls({required this.live, required this.onEnd});
  final LiveController live;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final s = live.session!;
    Widget control(IconData icon, String tooltip, VoidCallback? onTap, {bool active = false}) {
      return IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        style: IconButton.styleFrom(backgroundColor: active ? Colors.white : Colors.black45),
        icon: Icon(icon, color: active ? Colors.black : Colors.white),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          control(live.muted ? Icons.mic_off : Icons.mic, live.muted ? 'Unmute' : 'Mute', live.toggleMute,
              active: live.muted),
          control(live.cameraOff ? Icons.videocam_off : Icons.videocam,
              live.cameraOff ? 'Turn camera on' : 'Turn camera off', live.toggleCamera,
              active: live.cameraOff),
          control(Icons.cameraswitch, 'Switch camera', () => unawaited(live.switchCamera())),
          control(s.allowComments ? Icons.chat_bubble_outline : Icons.speaker_notes_off,
              s.allowComments ? 'Turn comments off' : 'Turn comments on', () => live.setAllowComments(!s.allowComments),
              active: !s.allowComments),
          FilledButton(
            onPressed: s.isLive ? onEnd : null,
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE53935)),
            child: const Text('End'),
          ),
        ],
      ),
    );
  }
}

class _CommentBar extends StatelessWidget {
  const _CommentBar({
    required this.controller,
    required this.enabled,
    required this.hint,
    required this.onSend,
    required this.onReact,
  });

  final TextEditingController controller;
  final bool enabled;
  final String hint;
  final VoidCallback onSend;
  final ValueChanged<String> onReact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final emoji in liveReactions)
                InkWell(
                  onTap: () => onReact(emoji),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(padding: const EdgeInsets.all(6), child: Text(emoji, style: const TextStyle(fontSize: 24))),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  maxLength: liveCommentMax,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: const TextStyle(color: Colors.white60),
                    counterText: '',
                    filled: true,
                    fillColor: Colors.black45,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                  ),
                ),
              ),
              IconButton(
                onPressed: enabled ? onSend : null,
                icon: const Icon(Icons.send, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Emoji that float up the right-hand side and fade out.
class _Reactions extends StatelessWidget {
  const _Reactions({required this.reactions});
  final List<LiveReaction> reactions;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return IgnorePointer(
      child: Stack(
        children: [
          for (final r in reactions)
            TweenAnimationBuilder<double>(
              key: ValueKey(r.id),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 2400),
              builder: (_, t, child) => Positioned(
                right: 16 + r.x * 56,
                bottom: size.height * (0.25 + 0.45 * t),
                child: Opacity(opacity: (1 - t).clamp(0, 1), child: child),
              ),
              child: Text(r.emoji, style: const TextStyle(fontSize: 32)),
            ),
        ],
      ),
    );
  }
}

class _EndedCard extends StatelessWidget {
  const _EndedCard({required this.session, required this.onClose});
  final LiveSession session;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final summary = s.summary;
    final String heading;
    if (s.isHost) {
      heading = 'Your live video has ended';
    } else if (s.endReason == 'removed') {
      heading = 'The host removed you from this live video';
    } else {
      heading = 'This live video has ended';
    }
    String duration(Duration d) {
      final m = d.inMinutes;
      return m > 0 ? '${m}m ${d.inSeconds.remainder(60)}s' : '${d.inSeconds}s';
    }

    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sensors_off, color: Colors.white70, size: 44),
              const SizedBox(height: 12),
              Text(
                heading,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
              ),
              if (s.isHost && summary != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Duration ${duration(summary.duration)} · Peak viewers ${summary.peakViewers} · '
                  'Comments ${summary.commentCount}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(onPressed: onClose, child: const Text('Close')),
            ],
          ),
        ),
      ),
    );
  }
}

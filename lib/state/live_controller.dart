import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../api/qc_socket.dart';
import '../config.dart';
import '../crypto/key_storage.dart';
import '../crypto/qc_crypto.dart';
import '../models/models.dart';
import 'auth_controller.dart';

const liveReactions = ['❤️', '😂', '😮', '👏', '🔥', '😢'];
const liveCommentMax = 300;
const liveTitleMax = 100;

const _heartbeatEvery = Duration(seconds: 10);
const _viewerStatusEvery = Duration(seconds: 15);
const _directoryEvery = Duration(seconds: 30);
const _signalPollEvery = Duration(milliseconds: 900);
const _connectTimeout = Duration(seconds: 30);
const _peerDropGrace = Duration(seconds: 10);
const _reactionTtl = Duration(milliseconds: 2600);
const _maxSignalAge = Duration(seconds: 45);
const _maxComments = 200;
const _backlogComments = 30;
const _maxChannelMessage = 2000;
// Host-side flood control per viewer: the host is the only relay for
// comments, so it is also the only place that can throttle them.
const _rateWindow = Duration(seconds: 5);
const _commentBurst = 5;
const _reactionBurst = 12;

const _signalEvents = ['live:offer', 'live:answer', 'live:ice', 'live:leave', 'live:end'];
final _hexKey = RegExp(r'^[0-9a-f]{64}$', caseSensitive: false);

enum LiveRole { host, viewer }

/// joining → live → (ending →) ended
enum LiveStatus { joining, live, ending, ended }

/// idle · connecting · connected · reconnecting · failed (viewer link only)
enum LiveConnection { idle, connecting, connected, reconnecting, failed }

class LiveComment {
  const LiveComment({
    required this.id,
    required this.fromId,
    required this.fromName,
    required this.text,
    required this.at,
    this.isHost = false,
  });

  final String id;
  final String fromId;
  final String fromName;
  final bool isHost;
  final String text;
  final int at;

  Map<String, dynamic> toJson() => {
        'id': id,
        'from': {'id': fromId, 'name': fromName, if (isHost) 'isHost': true},
        'text': text,
        'at': at,
      };

  static LiveComment? fromJson(dynamic raw) {
    if (raw is! Map || raw['text'] is! String || raw['id'] == null) return null;
    final from = raw['from'] is Map ? raw['from'] as Map : const {};
    final text = raw['text'] as String;
    return LiveComment(
      id: raw['id'].toString(),
      fromId: from['id']?.toString() ?? '',
      fromName: from['name']?.toString() ?? 'Viewer',
      isHost: from['isHost'] == true,
      text: text.length > liveCommentMax ? text.substring(0, liveCommentMax) : text,
      at: (raw['at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class LiveReaction {
  const LiveReaction({required this.id, required this.emoji, required this.x});
  final String id;
  final String emoji;
  final double x;
}

class LiveViewer {
  const LiveViewer({required this.id, required this.name});
  final String id;
  final String name;
}

class LiveSummary {
  const LiveSummary({required this.peakViewers, required this.commentCount, required this.duration});
  final int peakViewers;
  final int commentCount;
  final Duration duration;
}

/// The stream the user is hosting or watching right now.
class LiveSession {
  LiveSession({
    required this.streamId,
    required this.role,
    required this.status,
    this.title = '',
    this.hostId = '',
    this.hostName = '',
    this.hostHasAvatar = false,
    this.audienceType = 'friends',
    this.groupName,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();

  final String streamId;
  final LiveRole role;
  LiveStatus status;
  String title;
  String hostId;
  String hostName;
  bool hostHasAvatar;
  String audienceType;
  String? groupName;
  DateTime startedAt;
  bool allowComments = true;
  /// host · removed · timeout — set once a viewer's stream ends.
  String? endReason;
  LiveSummary? summary;

  bool get isHost => role == LiveRole.host;
  bool get isLive => status == LiveStatus.live;
}

class _HostPeer {
  _HostPeer({required this.pc, required this.name, required this.keys});
  final RTCPeerConnection pc;
  RTCDataChannel? channel;
  String name;
  final List<String> keys;
  final List<DateTime> commentLog = [];
  final List<DateTime> reactionLog = [];
  Timer? dropTimer;
  bool connected = false;
  bool remoteSet = false;
  bool greeted = false;
}

class _ViewerLink {
  _ViewerLink({required this.hostId, required this.hostKeys});
  final String hostId;
  final List<String> hostKeys;
  RTCPeerConnection? pc;
  RTCDataChannel? channel;
  bool remoteSet = false;
}

bool _withinRate(List<DateTime> log, int burst) {
  final now = DateTime.now();
  log.removeWhere((t) => now.difference(t) > _rateWindow);
  if (log.length >= burst) return false;
  log.add(now);
  return true;
}

String _newId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32).toRadixString(36)}';

String _nameOf(QcUser? u) {
  final display = u?.displayName.trim() ?? '';
  if (display.isNotEmpty) return display;
  return u?.username ?? 'Someone';
}

/// Live streaming, ported from the website's `useLiveStream.js` and
/// wire-compatible with it, so web and mobile hosts/viewers mix freely.
///
/// Star topology: the host holds one RTCPeerConnection per viewer and sends
/// its camera/mic down each one; a viewer only connects to the host. Each
/// connection carries a `live` data channel and the host is the hub for
/// comments, reactions and the viewer count. None of that touches the server.
///
/// The server's part is admission: a viewer must POST /live/:id/join before
/// the relay will carry its `live:offer` to the host. Signaling is the same
/// X5 sealed-box envelope as calls, keyed by the stream id in `callId`, sent
/// over the socket when connected and otherwise via /call-signals.
class LiveController extends ChangeNotifier {
  LiveController({required this.auth, required this.storage, required this.socket}) {
    socket.on('live:started', _onDirectoryChanged);
    socket.on('live:invited', _onDirectoryChanged);
    socket.on('live:ended', _onServerEnded);
    socket.on('live:removed', _onServerRemoved);
  }

  final AuthController auth;
  final KeyStorage storage;
  final QcSocket socket;

  /// "Live now" for the stories rail (excludes nothing; UI filters own stream).
  List<LiveStreamInfo> streams = [];
  LiveSession? session;
  MediaStream? localStream;
  MediaStream? remoteStream;
  int viewerCount = 0;
  List<LiveViewer> viewers = [];
  List<LiveComment> comments = [];
  List<LiveReaction> reactions = [];
  bool muted = false;
  bool cameraOff = false;
  LiveConnection connection = LiveConnection.idle;

  final Map<String, _HostPeer> _peers = {};
  _ViewerLink? _link;
  final Map<String, List<Map<String, dynamic>>> _pendingIce = {};
  final Map<String, SocketEventHandler> _socketHandlers = {};
  Timer? _directoryTimer;
  Timer? _heartbeatTimer;
  Timer? _statusTimer;
  Timer? _connectTimer;
  Timer? _signalPollTimer;
  String? _signalCursor;
  bool _signalPollInFlight = false;
  final Set<String> _seenSignals = {};
  int _peak = 0;
  bool _disposed = false;

  String get _myId => auth.user?.id ?? '';

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ---- directory ("live now") ---------------------------------------------

  /// Starts the 30s "live now" refresh (idempotent). Called by the stories rail.
  void startDirectory() {
    if (_directoryTimer != null) return;
    unawaited(refreshStreams());
    _directoryTimer = Timer.periodic(_directoryEvery, (_) => unawaited(refreshStreams()));
  }

  Future<void> refreshStreams() async {
    if (auth.user == null) return;
    try {
      streams = await auth.api.listLive();
      _notify();
    } catch (e) {
      debugPrint('[live] list failed: $e');
    }
  }

  void _onDirectoryChanged(dynamic _) => unawaited(refreshStreams());

  // ---- signaling ------------------------------------------------------------

  Future<void> _sendSignal(String event, String to, List<String> keys, Map<String, dynamic> payload) async {
    final streamId = session?.streamId;
    if (streamId == null || keys.isEmpty) return;
    try {
      final envelope = sealMessage(jsonEncode(payload), pickRandom(keys)).toJson();
      if (socket.connected) {
        socket.emit(event, {'to': to, 'callId': streamId, 'envelope': envelope});
        return;
      }
      await auth.api.sendCallSignal(to: to, callId: streamId, event: event, envelope: envelope);
    } catch (e) {
      debugPrint('[live] send $event failed: $e');
    }
  }

  Future<Map<String, dynamic>?> _unseal(dynamic envelope) async {
    if (envelope is! Map) return null;
    try {
      final env = SealedEnvelope.fromJson(Map<String, dynamic>.from(envelope));
      if (env.targetPublicKey.isEmpty) return null;
      final secret = await storage.findSecretKeyForPublicKey(_myId, env.targetPublicKey);
      if (secret == null) return null;
      final text = unsealMessage(env, secret);
      if (text == null) return null;
      final body = jsonDecode(text);
      return body is Map ? Map<String, dynamic>.from(body) : null;
    } catch (_) {
      return null;
    }
  }

  void _attachSignaling() {
    for (final event in _signalEvents) {
      final handler = _socketHandlers.putIfAbsent(event, () => (dynamic data) => _onSignal(event, data));
      socket.on(event, handler);
    }
    // A peer on the REST fallback (serverless API) never reaches us over the
    // socket, and socket-relayed live signals are never stored, so polling
    // alongside the socket cannot double-deliver.
    _signalCursor = DateTime.now().subtract(_maxSignalAge).toUtc().toIso8601String();
    _seenSignals.clear();
    _signalPollTimer?.cancel();
    _signalPollTimer = Timer.periodic(_signalPollEvery, (_) => unawaited(_pollSignals()));
  }

  void _detachSignaling() {
    for (final entry in _socketHandlers.entries) {
      socket.off(entry.key, entry.value);
    }
    _signalPollTimer?.cancel();
    _signalPollTimer = null;
  }

  Future<void> _pollSignals() async {
    if (_signalPollInFlight || session == null) return;
    _signalPollInFlight = true;
    try {
      final data = await auth.api.pollCallSignals(after: _signalCursor);
      final cursor = data['cursor']?.toString();
      if (cursor != null && cursor.isNotEmpty) _signalCursor = cursor;
      for (final raw in (data['signals'] as List<dynamic>? ?? [])) {
        if (raw is! Map) continue;
        final id = raw['id']?.toString() ?? '';
        final event = raw['event']?.toString() ?? '';
        if (id.isEmpty || !_seenSignals.add(id) || !event.startsWith('live:')) continue;
        final createdAt = DateTime.tryParse(raw['createdAt']?.toString() ?? '');
        if (createdAt != null && DateTime.now().difference(createdAt) > _maxSignalAge) continue;
        await _onSignal(event, raw);
      }
      if (_seenSignals.length > 500) {
        final keep = _seenSignals.toList().sublist(_seenSignals.length - 250);
        _seenSignals
          ..clear()
          ..addAll(keep);
      }
    } catch (e) {
      debugPrint('[live] poll /call-signals failed: $e');
    } finally {
      _signalPollInFlight = false;
    }
  }

  Future<void> _onSignal(String event, dynamic data) async {
    if (data is! Map) return;
    final s = session;
    final callId = data['callId']?.toString();
    if (s == null || s.streamId != callId) return;
    if (s.status != LiveStatus.live && s.status != LiveStatus.joining) return;
    final from = data['from']?.toString() ?? '';
    final body = await _unseal(data['envelope']);
    if (body == null || from.isEmpty) return;

    switch (event) {
      case 'live:offer':
        if (s.isHost && body['type'] == 'offer' && body['sdp'] is Map) await _onOffer(from, body);
      case 'live:answer':
        if (!s.isHost && body['type'] == 'answer' && body['sdp'] is Map) await _onAnswer(from, body);
      case 'live:ice':
        if (body['type'] == 'ice' && body['candidate'] is Map) {
          await _onIce(from, Map<String, dynamic>.from(body['candidate'] as Map));
        }
      case 'live:leave':
        if (s.isHost && body['type'] == 'leave') await _dropPeer(from);
      case 'live:end':
        if (!s.isHost && from == _link?.hostId && body['type'] == 'end') _markViewerEnded('host');
    }
  }

  RTCSessionDescription _sdpFrom(dynamic raw) {
    final m = raw as Map;
    return RTCSessionDescription(m['sdp']?.toString(), m['type']?.toString());
  }

  Future<void> _flushIce(RTCPeerConnection pc, String peerId) async {
    final queued = _pendingIce.remove(peerId) ?? const [];
    for (final c in queued) {
      await pc.addCandidate(_candidateFrom(c)).catchError((_) {});
    }
  }

  RTCIceCandidate _candidateFrom(Map<String, dynamic> c) =>
      RTCIceCandidate(c['candidate']?.toString(), c['sdpMid']?.toString(), (c['sdpMLineIndex'] as num?)?.toInt());

  Future<void> _onOffer(String viewerId, Map<String, dynamic> body) async {
    final peer = await _createHostPeer(viewerId, body['viewer']);
    try {
      await peer.pc.setRemoteDescription(_sdpFrom(body['sdp']));
      peer.remoteSet = true;
      await _flushIce(peer.pc, viewerId);
      final answer = await peer.pc.createAnswer();
      await peer.pc.setLocalDescription(answer);
      await _sendSignal('live:answer', viewerId, peer.keys, {'type': 'answer', 'sdp': answer.toMap()});
    } catch (e) {
      debugPrint('[live] answer failed: $e');
      await _dropPeer(viewerId);
    }
  }

  Future<void> _onAnswer(String from, Map<String, dynamic> body) async {
    final link = _link;
    final pc = link?.pc;
    if (link == null || pc == null || from != link.hostId) return;
    if (await pc.getSignalingState() != RTCSignalingState.RTCSignalingStateHaveLocalOffer) return;
    try {
      await pc.setRemoteDescription(_sdpFrom(body['sdp']));
      link.remoteSet = true;
      await _flushIce(pc, link.hostId);
    } catch (_) {
      _setConnection(LiveConnection.failed);
    }
  }

  Future<void> _onIce(String from, Map<String, dynamic> candidate) async {
    final s = session!;
    RTCPeerConnection? pc;
    var ready = false;
    if (s.isHost) {
      final peer = _peers[from];
      pc = peer?.pc;
      ready = peer?.remoteSet == true;
    } else if (_link?.hostId == from) {
      pc = _link!.pc;
      ready = _link!.remoteSet;
    }
    if (pc == null || !ready) {
      _pendingIce.putIfAbsent(from, () => []).add(candidate);
      return;
    }
    await pc.addCandidate(_candidateFrom(candidate)).catchError((_) {});
  }

  void _onServerEnded(dynamic data) {
    unawaited(refreshStreams());
    final s = session;
    if (data is! Map || s == null || s.streamId != data['id']?.toString()) return;
    if (!s.isHost) {
      _markViewerEnded('host');
    } else if (s.isLive) {
      unawaited(endBroadcast());
    }
  }

  void _onServerRemoved(dynamic data) {
    final s = session;
    if (data is Map && s != null && !s.isHost && s.streamId == data['id']?.toString()) {
      _markViewerEnded('removed');
    }
  }

  // ---- data channel ---------------------------------------------------------

  void _sendJson(RTCDataChannel? channel, Map<String, dynamic> message) {
    if (channel?.state != RTCDataChannelState.RTCDataChannelOpen) return;
    channel!.send(RTCDataChannelMessage(jsonEncode(message))).catchError((_) {});
  }

  Map<String, dynamic>? _parseChannelMessage(RTCDataChannelMessage message) {
    if (message.isBinary || message.text.length > _maxChannelMessage) return null;
    try {
      final msg = jsonDecode(message.text);
      return msg is Map ? Map<String, dynamic>.from(msg) : null;
    } catch (_) {
      return null;
    }
  }

  void _addComment(LiveComment comment) {
    final next = [...comments, comment];
    comments = next.length > _maxComments ? next.sublist(next.length - _maxComments) : next;
    _notify();
  }

  void _showReaction(String emoji) {
    final reaction = LiveReaction(id: _newId('reaction'), emoji: emoji, x: Random().nextDouble());
    reactions = [...reactions.length > 30 ? reactions.sublist(reactions.length - 30) : reactions, reaction];
    _notify();
    Timer(_reactionTtl, () {
      reactions = reactions.where((r) => r.id != reaction.id).toList();
      _notify();
    });
  }

  // ---- host -----------------------------------------------------------------

  List<String> _openPeerIds() => _peers.entries
      .where((e) => e.value.channel?.state == RTCDataChannelState.RTCDataChannelOpen)
      .map((e) => e.key)
      .toList();

  void _broadcast(Map<String, dynamic> message, {String? except}) {
    for (final entry in _peers.entries) {
      if (entry.key == except) continue;
      _sendJson(entry.value.channel, message);
    }
  }

  void _publishMeta() {
    final s = session;
    if (s == null || !s.isHost) return;
    final open = _openPeerIds();
    _peak = max(_peak, open.length);
    viewerCount = open.length;
    viewers = open.map((id) => LiveViewer(id: id, name: _peers[id]?.name ?? 'Viewer')).toList();
    _broadcast({'t': 'meta', 'viewerCount': open.length, 'allowComments': s.allowComments, 'title': s.title});
    _notify();
  }

  Future<void> _dropPeer(String peerId, {bool publish = true, bool keepPendingIce = false}) async {
    final peer = _peers.remove(peerId);
    if (peer == null) return;
    peer.dropTimer?.cancel();
    if (!keepPendingIce) _pendingIce.remove(peerId);
    try {
      await peer.channel?.close();
      await peer.pc.close();
    } catch (_) {}
    if (publish) _publishMeta();
  }

  void _handleHostChannelMessage(String peerId, RTCDataChannelMessage raw) {
    final msg = _parseChannelMessage(raw);
    final peer = _peers[peerId];
    final s = session;
    if (msg == null || peer == null || s == null || !s.isHost) return;

    if (msg['t'] == 'comment') {
      if (!s.allowComments) return;
      var text = (msg['text']?.toString() ?? '').trim();
      if (text.length > liveCommentMax) text = text.substring(0, liveCommentMax);
      if (text.isEmpty || !_withinRate(peer.commentLog, _commentBurst)) return;
      final comment = LiveComment(
        id: _newId('comment'),
        fromId: peerId,
        fromName: peer.name,
        text: text,
        at: DateTime.now().millisecondsSinceEpoch,
      );
      _addComment(comment);
      _broadcast({'t': 'comment', ...comment.toJson()});
    } else if (msg['t'] == 'reaction') {
      final emoji = msg['emoji'];
      if (!liveReactions.contains(emoji) || !_withinRate(peer.reactionLog, _reactionBurst)) return;
      _showReaction(emoji as String);
      // The sender already showed its own reaction locally.
      _broadcast({'t': 'reaction', 'emoji': emoji}, except: peerId);
    }
  }

  Future<_HostPeer> _createHostPeer(String viewerId, dynamic viewerInfo) async {
    // A viewer re-offering replaces its old link; its fresh ICE may already be queued.
    if (_peers.containsKey(viewerId)) await _dropPeer(viewerId, publish: false, keepPendingIce: true);

    final info = viewerInfo is Map ? viewerInfo : const {};
    final keys = (info['publicKeys'] as List<dynamic>? ?? [])
        .map((k) => k.toString().toLowerCase())
        .where(_hexKey.hasMatch)
        .toList();
    var name = info['name']?.toString() ?? 'Viewer';
    if (name.length > 64) name = name.substring(0, 64);

    final pc = await createPeerConnection({'iceServers': AppConfig.iceServers, 'sdpSemantics': 'unified-plan'});
    final peer = _HostPeer(pc: pc, name: name, keys: keys);
    _peers[viewerId] = peer;

    final stream = localStream;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
      }
    }

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      unawaited(_sendSignal('live:ice', viewerId, peer.keys, {'type': 'ice', 'candidate': candidate.toMap()}));
    };
    pc.onDataChannel = (channel) {
      peer.channel = channel;
      void onOpen() {
        if (peer.greeted || _peers[viewerId] != peer) return;
        peer.greeted = true;
        final s = session;
        final backlog = comments.length > _backlogComments ? comments.sublist(comments.length - _backlogComments) : comments;
        _sendJson(channel, {
          't': 'hello',
          'comments': backlog.map((c) => c.toJson()).toList(),
          'allowComments': s?.allowComments ?? true,
          'title': s?.title ?? '',
        });
        _publishMeta();
      }

      channel.onMessage = (message) => _handleHostChannelMessage(viewerId, message);
      channel.onDataChannelState = (state) {
        if (state == RTCDataChannelState.RTCDataChannelOpen) {
          onOpen();
        } else if (state == RTCDataChannelState.RTCDataChannelClosed && _peers[viewerId] == peer) {
          unawaited(_dropPeer(viewerId));
        }
      };
      // Native may hand over a channel that is already open.
      if (channel.state == RTCDataChannelState.RTCDataChannelOpen) onOpen();
    };
    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        peer.connected = true;
        peer.dropTimer?.cancel();
        peer.dropTimer = null;
        return;
      }
      peer.connected = false;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        // Give a flaky network a moment; the viewer re-offers to recover.
        peer.dropTimer ??= Timer(_peerDropGrace, () {
          if (_peers[viewerId] == peer && !peer.connected) unawaited(_dropPeer(viewerId));
        });
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed && _peers[viewerId] == peer) {
        unawaited(_dropPeer(viewerId));
      }
    };
    return peer;
  }

  /// Opens the camera, registers the stream and starts accepting viewers.
  /// [audience] is the website's shape: `{type, groupId?, userIds?, hiddenFrom?}`.
  Future<void> startBroadcast({required String title, required Map<String, dynamic> audience}) async {
    if (session != null) throw StateError('You are already in a live stream');
    final media = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {
        'facingMode': 'user',
        'width': {'ideal': 1280},
        'height': {'ideal': 720},
      },
    });
    LiveStreamInfo created;
    try {
      created = await auth.api.startLive(title: title, audience: audience);
    } catch (_) {
      await _stopStream(media);
      rethrow;
    }

    localStream = media;
    comments = [];
    reactions = [];
    viewers = [];
    viewerCount = 0;
    muted = false;
    cameraOff = false;
    _peak = 0;
    session = LiveSession(
      streamId: created.id,
      role: LiveRole.host,
      status: LiveStatus.live,
      title: created.title,
      hostId: created.hostId,
      hostName: created.hostName,
      hostHasAvatar: created.hostHasAvatar,
      audienceType: created.audienceType,
      groupName: created.groupName,
      startedAt: created.startedAt,
    );
    _attachSignaling();
    _heartbeatTimer = Timer.periodic(_heartbeatEvery, (_) => unawaited(_heartbeat()));
    _notify();
  }

  Future<void> _heartbeat() async {
    final s = session;
    if (s == null || !s.isHost || !s.isLive) return;
    final connected = _peers.entries.where((e) => e.value.connected).map((e) => e.key).toList();
    try {
      final beat = await auth.api.heartbeatLive(s.streamId, connected);
      for (final v in (beat['viewers'] as List<dynamic>? ?? [])) {
        if (v is! Map) continue;
        final peer = _peers[v['id']?.toString()];
        if (peer == null) continue;
        final display = (v['displayName']?.toString() ?? '').trim();
        peer.name = display.isNotEmpty ? display : (v['username']?.toString() ?? peer.name);
      }
    } on ApiException catch (e) {
      // 410: ended elsewhere (e.g. another device went live and replaced it).
      if (e.status == 410 || e.status == 404) unawaited(endBroadcast());
    } catch (_) {}
  }

  Future<void> endBroadcast() async {
    final s = session;
    if (s == null || !s.isHost || s.status != LiveStatus.live) return;
    s.status = LiveStatus.ending;
    _notify();
    _clearTimers();

    _broadcast({'t': 'end'});
    // Sealed fallback for viewers whose data channel never opened. Must go
    // out before /end — the relay stops carrying live:* once it has ended.
    await Future.wait(_peers.entries.map((e) => _sendSignal('live:end', e.key, e.value.keys, {'type': 'end'})));
    unawaited(auth.api.endLive(s.streamId).catchError((_) {}));
    await _closeConnections();

    s
      ..status = LiveStatus.ended
      ..summary = LiveSummary(
        peakViewers: _peak,
        commentCount: comments.length,
        duration: DateTime.now().difference(s.startedAt),
      );
    _notify();
    unawaited(refreshStreams());
  }

  void postComment(String text) {
    final s = session;
    var clean = text.trim();
    if (clean.length > liveCommentMax) clean = clean.substring(0, liveCommentMax);
    if (clean.isEmpty || s == null || !s.isLive) return;
    if (s.isHost) {
      final comment = LiveComment(
        id: _newId('comment'),
        fromId: _myId,
        fromName: _nameOf(auth.user),
        isHost: true,
        text: clean,
        at: DateTime.now().millisecondsSinceEpoch,
      );
      _addComment(comment);
      _broadcast({'t': 'comment', ...comment.toJson()});
      return;
    }
    _sendJson(_link?.channel, {'t': 'comment', 'text': clean});
  }

  void sendReaction(String emoji) {
    final s = session;
    if (s == null || !s.isLive || !liveReactions.contains(emoji)) return;
    _showReaction(emoji);
    if (s.isHost) {
      _broadcast({'t': 'reaction', 'emoji': emoji});
    } else {
      _sendJson(_link?.channel, {'t': 'reaction', 'emoji': emoji});
    }
  }

  void setAllowComments(bool allow) {
    final s = session;
    if (s == null || !s.isHost) return;
    s.allowComments = allow;
    _publishMeta();
  }

  Future<void> removeViewer(String viewerId) async {
    final s = session;
    if (s == null || !s.isHost) return;
    _sendJson(_peers[viewerId]?.channel, {'t': 'removed'});
    await auth.api.removeLiveViewer(s.streamId, viewerId);
    await _dropPeer(viewerId);
  }

  void toggleMute() {
    final stream = localStream;
    if (stream == null) return;
    muted = !muted;
    for (final t in stream.getAudioTracks()) {
      t.enabled = !muted;
    }
    _notify();
  }

  /// Disabling (not removing) the track sends black frames, so viewers keep
  /// running without renegotiation.
  void toggleCamera() {
    final stream = localStream;
    if (stream == null) return;
    cameraOff = !cameraOff;
    for (final t in stream.getVideoTracks()) {
      t.enabled = !cameraOff;
    }
    _notify();
  }

  Future<void> switchCamera() async {
    final tracks = localStream?.getVideoTracks() ?? const [];
    if (tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks.first);
    } catch (e) {
      debugPrint('[live] switch camera failed: $e');
    }
  }

  // ---- viewer ---------------------------------------------------------------

  void _setConnection(LiveConnection next) {
    connection = next;
    _notify();
  }

  void _markViewerEnded(String reason) {
    final s = session;
    if (s == null || s.isHost || s.status == LiveStatus.ended) return;
    _clearTimers();
    unawaited(_closeConnections());
    s
      ..status = LiveStatus.ended
      ..endReason = reason;
    _notify();
    unawaited(refreshStreams());
  }

  void _handleViewerChannelMessage(RTCDataChannelMessage raw) {
    final msg = _parseChannelMessage(raw);
    final s = session;
    if (msg == null || s == null) return;
    switch (msg['t']) {
      case 'hello':
        final backlog = (msg['comments'] as List<dynamic>? ?? []).map(LiveComment.fromJson).whereType<LiveComment>().toList();
        comments = backlog.length > _backlogComments ? backlog.sublist(backlog.length - _backlogComments) : backlog;
        s.allowComments = msg['allowComments'] != false;
        if (msg['title'] is String) s.title = msg['title'] as String;
        _notify();
      case 'comment':
        final comment = LiveComment.fromJson(msg);
        if (comment != null) _addComment(comment);
      case 'reaction':
        if (liveReactions.contains(msg['emoji'])) _showReaction(msg['emoji'] as String);
      case 'meta':
        viewerCount = (msg['viewerCount'] as num?)?.toInt() ?? 0;
        s.allowComments = msg['allowComments'] != false;
        if (msg['title'] is String) s.title = msg['title'] as String;
        _notify();
      case 'end':
        _markViewerEnded('host');
      case 'removed':
        _markViewerEnded('removed');
    }
  }

  Future<void> _negotiateViewer() async {
    final s = session;
    final prev = _link;
    if (s == null || s.isHost || prev == null) return;
    try {
      await prev.channel?.close();
      await prev.pc?.close();
    } catch (_) {}
    _pendingIce.clear();
    remoteStream = null;
    _setConnection(LiveConnection.connecting);

    final link = _ViewerLink(hostId: prev.hostId, hostKeys: prev.hostKeys);
    _link = link;
    final pc = await createPeerConnection({'iceServers': AppConfig.iceServers, 'sdpSemantics': 'unified-plan'});
    link.pc = pc;
    await pc.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );
    await pc.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );
    final channel = await pc.createDataChannel('live', RTCDataChannelInit()..ordered = true);
    link.channel = channel;
    channel.onMessage = _handleViewerChannelMessage;

    pc.onTrack = (event) {
      if (_link != link) return;
      if (event.streams.isNotEmpty) {
        remoteStream = event.streams.first;
        _notify();
      }
    };
    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      unawaited(_sendSignal('live:ice', link.hostId, link.hostKeys, {'type': 'ice', 'candidate': candidate.toMap()}));
    };
    pc.onConnectionState = (state) {
      if (_link != link) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _connectTimer?.cancel();
        _setConnection(LiveConnection.connected);
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _setConnection(LiveConnection.failed);
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _setConnection(LiveConnection.reconnecting);
      }
    };

    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    final me = auth.user;
    await _sendSignal('live:offer', link.hostId, link.hostKeys, {
      'type': 'offer',
      'sdp': offer.toMap(),
      'viewer': {'name': _nameOf(me), 'publicKeys': me?.publicKeys ?? const []},
    });

    _connectTimer?.cancel();
    _connectTimer = Timer(_connectTimeout, () {
      if (_link == link && connection != LiveConnection.connected) _setConnection(LiveConnection.failed);
    });
  }

  /// Joins [streamId] as a viewer. Throws [ApiException] (403/410…) if refused.
  Future<void> watch(String streamId) async {
    final current = session;
    if (current != null) {
      if (current.streamId == streamId) return;
      throw StateError('Leave your current live stream first');
    }
    session = LiveSession(streamId: streamId, role: LiveRole.viewer, status: LiveStatus.joining);
    comments = [];
    reactions = [];
    connection = LiveConnection.connecting;
    _notify();

    Map<String, dynamic> joined;
    try {
      joined = await auth.api.joinLive(streamId);
    } catch (_) {
      await _resetAll();
      rethrow;
    }
    final info = LiveStreamInfo.fromJson(Map<String, dynamic>.from(joined['stream'] as Map));
    final hostKeys = (joined['hostPublicKeys'] as List<dynamic>? ?? []).map((k) => k.toString().toLowerCase()).toList();
    viewerCount = info.viewerCount;
    session = LiveSession(
      streamId: streamId,
      role: LiveRole.viewer,
      status: LiveStatus.live,
      title: info.title,
      hostId: info.hostId,
      hostName: info.hostName,
      hostHasAvatar: info.hostHasAvatar,
      audienceType: info.audienceType,
      groupName: info.groupName,
      startedAt: info.startedAt,
    );
    _link = _ViewerLink(hostId: info.hostId, hostKeys: hostKeys);
    _attachSignaling();

    _statusTimer = Timer.periodic(_viewerStatusEvery, (_) async {
      final s = session;
      if (s == null || s.isHost || !s.isLive) return;
      try {
        final latest = await auth.api.getLive(s.streamId);
        if (!latest.isLive) _markViewerEnded('host');
      } on ApiException catch (e) {
        if (e.status == 403) _markViewerEnded('removed');
        if (e.status == 404) _markViewerEnded('host');
      } catch (_) {}
    });

    await _negotiateViewer();
  }

  void reconnect() {
    _negotiateViewer().catchError((_) => _setConnection(LiveConnection.failed));
  }

  /// Leaves the current stream (or closes the ended screen). A host who is
  /// still live ends the broadcast.
  Future<void> leave() async {
    final s = session;
    if (s == null) return;
    if (s.isHost && s.isLive) {
      await endBroadcast();
    } else if (!s.isHost && s.isLive) {
      final link = _link;
      if (link != null) await _sendSignal('live:leave', link.hostId, link.hostKeys, {'type': 'leave'});
      unawaited(auth.api.leaveLive(s.streamId).catchError((_) {}));
    }
    await _resetAll();
  }

  // ---- teardown -------------------------------------------------------------

  void _clearTimers() {
    _heartbeatTimer?.cancel();
    _statusTimer?.cancel();
    _connectTimer?.cancel();
    _heartbeatTimer = null;
    _statusTimer = null;
    _connectTimer = null;
  }

  Future<void> _stopStream(MediaStream stream) async {
    for (final t in stream.getTracks()) {
      await t.stop();
    }
    await stream.dispose();
  }

  Future<void> _closeConnections() async {
    _detachSignaling();
    for (final peer in _peers.values) {
      peer.dropTimer?.cancel();
      try {
        await peer.channel?.close();
        await peer.pc.close();
      } catch (_) {}
    }
    _peers.clear();
    final link = _link;
    _link = null;
    if (link != null) {
      try {
        await link.channel?.close();
        await link.pc?.close();
      } catch (_) {}
    }
    _pendingIce.clear();
    final local = localStream;
    localStream = null;
    remoteStream = null;
    if (local != null) await _stopStream(local);
    _notify();
  }

  Future<void> _resetAll() async {
    _clearTimers();
    await _closeConnections();
    comments = [];
    reactions = [];
    viewers = [];
    viewerCount = 0;
    muted = false;
    cameraOff = false;
    connection = LiveConnection.idle;
    session = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _directoryTimer?.cancel();
    socket.off('live:started', _onDirectoryChanged);
    socket.off('live:invited', _onDirectoryChanged);
    socket.off('live:ended', _onServerEnded);
    socket.off('live:removed', _onServerRemoved);
    _clearTimers();
    unawaited(_closeConnections());
    super.dispose();
  }
}

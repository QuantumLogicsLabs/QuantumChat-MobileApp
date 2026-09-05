import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/qc_theme.dart';

/// Renders poll / event / announcement payloads in group threads.
class GroupMessageContent extends StatelessWidget {
  const GroupMessageContent({
    super.key,
    required this.message,
    required this.colors,
    required this.currentUserId,
    this.onVotePoll,
  });

  final ChatMessage message;
  final QcColors colors;
  final String currentUserId;
  final void Function(int optionIndex)? onVotePoll;

  @override
  Widget build(BuildContext context) {
    if (message.isAnnouncement) {
      return _AnnouncementCard(
        body: message.announcementBody ?? message.text ?? '',
        colors: colors,
      );
    }
    if (message.isEvent && message.eventData != null) {
      return _EventCard(data: message.eventData!, colors: colors);
    }
    if (message.isPoll && message.pollData != null) {
      return _PollCard(
        data: message.pollData!,
        votes: message.pollVotes,
        currentUserId: currentUserId,
        colors: colors,
        onVote: onVotePoll,
      );
    }
    return const SizedBox.shrink();
  }
}

class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.label, required this.colors});
  final String label;
  final QcColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colors.accentCyan.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.accentCyan,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.body, required this.colors});
  final String body;
  final QcColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.accentCyan.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.accentCyan.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _KindBadge(label: 'Announcement', colors: colors),
          Text(
            body,
            style: TextStyle(
              color: colors.textPrimary,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.data, required this.colors});
  final EventData data;
  final QcColors colors;

  String? _formatWhen(String? when) {
    if (when == null || when.isEmpty) return null;
    final dt = DateTime.tryParse(when);
    if (dt == null) return when;
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final mo = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final mi = local.minute.toString().padLeft(2, '0');
    return '$y-$mo-$d $h:$mi';
  }

  @override
  Widget build(BuildContext context) {
    final whenLabel = _formatWhen(data.when);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.overlay.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _KindBadge(label: 'Event', colors: colors),
          Text(
            data.title,
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          if (whenLabel != null) ...[
            const SizedBox(height: 6),
            Text('When: $whenLabel', style: TextStyle(color: colors.textSecondary, fontSize: 13)),
          ],
          if (data.location.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Where: ${data.location}', style: TextStyle(color: colors.textSecondary, fontSize: 13)),
          ],
          if (data.notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(data.notes, style: TextStyle(color: colors.textMuted, fontSize: 13, height: 1.3)),
          ],
        ],
      ),
    );
  }
}

class _PollCard extends StatelessWidget {
  const _PollCard({
    required this.data,
    required this.votes,
    required this.currentUserId,
    required this.colors,
    this.onVote,
  });

  final PollData data;
  final List<PollVote> votes;
  final String currentUserId;
  final QcColors colors;
  final void Function(int optionIndex)? onVote;

  @override
  Widget build(BuildContext context) {
    final total = votes.length;
    PollVote? myVote;
    for (final v in votes) {
      if (v.userId == currentUserId) {
        myVote = v;
        break;
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.overlay.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _KindBadge(label: 'Poll', colors: colors),
          Text(
            data.question,
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          ...List.generate(data.options.length, (idx) {
            final count = votes.where((v) => v.optionIndex == idx).length;
            final pct = total > 0 ? ((count / total) * 100).round() : 0;
            final selected = myVote?.optionIndex == idx;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onVote == null ? null : () => onVote!(idx),
                  borderRadius: BorderRadius.circular(8),
                  child: Ink(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? colors.accentCyan : colors.border.withValues(alpha: 0.7),
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: pct / 100,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.accentCyan.withValues(alpha: selected ? 0.28 : 0.14),
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  data.options[idx],
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                                  ),
                                ),
                              ),
                              Text(
                                '$count · $pct%',
                                style: TextStyle(color: colors.textMuted, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          Text(
            '$total vote${total == 1 ? '' : 's'}',
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/chat_controller.dart';
import '../state/theme_controller.dart';
import '../utils/birthday_utils.dart';
import '../widgets/common.dart';
import 'user_profile_screen.dart';

class BirthdayCalendarScreen extends StatefulWidget {
  const BirthdayCalendarScreen({super.key});

  @override
  State<BirthdayCalendarScreen> createState() => _BirthdayCalendarScreenState();
}

class _BirthdayCalendarScreenState extends State<BirthdayCalendarScreen> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeController>().colors;
    final chat = context.watch<ChatController>();
    final items = normalizeFriendBirthdays(chat.friends);
    final byDay = getBirthdaysByMonthDay(items, _month.month);
    final upcoming = items.where((i) => i.daysUntil <= 60).toList();
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final firstWeekday = DateTime(_month.year, _month.month, 1).weekday % 7; // Sun=0
    const monthNames = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Birthdays')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  '${monthNames[_month.month - 1]} ${_month.year}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w800, fontSize: 18),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: firstWeekday + daysInMonth,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemBuilder: (context, index) {
              if (index < firstWeekday) return const SizedBox.shrink();
              final day = index - firstWeekday + 1;
              final dayItems = byDay[day] ?? const <BirthdayItem>[];
              final has = dayItems.isNotEmpty;
              return Container(
                decoration: BoxDecoration(
                  color: has ? colors.accentMuted : colors.elevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: has ? colors.accent : colors.border),
                ),
                child: Center(
                  child: Text(
                    '$day',
                    style: TextStyle(
                      color: has ? colors.accent : colors.textSecondary,
                      fontWeight: has ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          Text(
            'Upcoming',
            style: TextStyle(color: colors.accentCyan, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (upcoming.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No visible friend birthdays yet. Friends can share their birthday in privacy settings.',
                style: TextStyle(color: colors.textMuted),
              ),
            )
          else
            ...upcoming.map(
              (item) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: UserAvatar(
                  name: item.displayName,
                  userId: item.friendId,
                  hasAvatar: item.hasAvatar,
                ),
                title: Text(item.displayName, style: TextStyle(color: colors.textPrimary)),
                subtitle: Text(
                  '${item.dateLabel} · ${formatBirthdayCountdown(item.daysUntil, item.nextOccurrence)}',
                  style: TextStyle(color: colors.textMuted),
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => UserProfileScreen(userId: item.friendId)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

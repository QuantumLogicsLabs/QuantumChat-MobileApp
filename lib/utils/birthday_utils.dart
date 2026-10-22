import '../models/models.dart';

class BirthdayMonthDay {
  const BirthdayMonthDay({required this.month, required this.day});
  final int month;
  final int day;
}

class BirthdayItem {
  const BirthdayItem({
    required this.friendId,
    required this.user,
    required this.displayName,
    required this.username,
    required this.hasAvatar,
    required this.month,
    required this.day,
    required this.nextOccurrence,
    required this.daysUntil,
    required this.isToday,
    required this.isTomorrow,
    required this.isThisWeek,
    required this.dateLabel,
  });

  final String friendId;
  final QcUser user;
  final String displayName;
  final String username;
  final bool hasAvatar;
  final int month;
  final int day;
  final DateTime nextOccurrence;
  final int daysUntil;
  final bool isToday;
  final bool isTomorrow;
  final bool isThisWeek;
  final String dateLabel;
}

bool isLeapYear(int year) => (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

BirthdayMonthDay? extractBirthMonthAndDay(DateTime? birthday, [String? raw]) {
  if (raw != null && raw.isNotEmpty) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
    if (match != null) {
      final month = int.parse(match.group(2)!);
      final day = int.parse(match.group(3)!);
      if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        return BirthdayMonthDay(month: month, day: day);
      }
    }
  }
  if (birthday == null) return null;
  return BirthdayMonthDay(month: birthday.toUtc().month, day: birthday.toUtc().day);
}

({DateTime nextDate, int daysUntil, bool isToday, bool isTomorrow, bool isThisWeek}) calculateNextBirthday(
  int month,
  int day, [
  DateTime? fromDate,
]) {
  final from = fromDate ?? DateTime.now();
  final currentYear = from.year;
  final todayAtMidnight = DateTime(currentYear, from.month, from.day);

  var targetDay = day;
  if (month == 2 && day == 29 && !isLeapYear(currentYear)) targetDay = 28;

  var candidate = DateTime(currentYear, month, targetDay);
  if (candidate.isBefore(todayAtMidnight)) {
    final nextYear = currentYear + 1;
    targetDay = day;
    if (month == 2 && day == 29 && !isLeapYear(nextYear)) targetDay = 28;
    candidate = DateTime(nextYear, month, targetDay);
  }

  final daysUntil = candidate.difference(todayAtMidnight).inDays;
  return (
    nextDate: candidate,
    daysUntil: daysUntil < 0 ? 0 : daysUntil,
    isToday: daysUntil == 0,
    isTomorrow: daysUntil == 1,
    isThisWeek: daysUntil >= 0 && daysUntil <= 7,
  );
}

String formatBirthdayCountdown(int daysUntil, DateTime targetDate) {
  if (daysUntil == 0) return 'Today';
  if (daysUntil == 1) return 'Tomorrow';
  if (daysUntil <= 7) return 'In $daysUntil days';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[targetDate.month - 1]} ${targetDate.day}';
}

String formatBirthdayDate(int month, int day) {
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return '${months[month - 1]} $day';
}

List<BirthdayItem> normalizeFriendBirthdays(List<QcUser> friends, [DateTime? fromDate]) {
  final from = fromDate ?? DateTime.now();
  final result = <BirthdayItem>[];
  final seen = <String>{};

  for (final friend in friends) {
    if (seen.contains(friend.id)) continue;
    seen.add(friend.id);
    if (friend.birthday == null || friend.birthdayLocked) continue;
    final parsed = extractBirthMonthAndDay(friend.birthday);
    if (parsed == null) continue;
    final next = calculateNextBirthday(parsed.month, parsed.day, from);
    result.add(
      BirthdayItem(
        friendId: friend.id,
        user: friend,
        displayName: friend.title,
        username: friend.username,
        hasAvatar: friend.hasAvatar,
        month: parsed.month,
        day: parsed.day,
        nextOccurrence: next.nextDate,
        daysUntil: next.daysUntil,
        isToday: next.isToday,
        isTomorrow: next.isTomorrow,
        isThisWeek: next.isThisWeek,
        dateLabel: formatBirthdayDate(parsed.month, parsed.day),
      ),
    );
  }

  result.sort((a, b) => a.daysUntil.compareTo(b.daysUntil));
  return result;
}

Map<int, List<BirthdayItem>> getBirthdaysByMonthDay(List<BirthdayItem> items, int targetMonth) {
  final map = <int, List<BirthdayItem>>{};
  for (final item in items) {
    if (item.month != targetMonth) continue;
    map.putIfAbsent(item.day, () => []).add(item);
  }
  return map;
}

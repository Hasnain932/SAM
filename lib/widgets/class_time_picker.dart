part of '../main.dart';

// Time picker limited to 6 AM - 6 PM.

// Time picker (6:00 AM to 6:00 PM only)
// Flutter's picker can't limit the range, so this is a small custom dialog:
// 6 AM to 6 PM, with only :00 at 6 PM.
Future<TimeOfDay?> pickClassTime(BuildContext context, TimeOfDay? initial) {
  int hour = (initial?.hour ?? 9).clamp(kPickerStartHour, kPickerEndHour).toInt();
  int minute = initial?.minute ?? 0;
  if (hour == kPickerEndHour) minute = 0;

  return showDialog<TimeOfDay>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        final maxMinute = hour == kPickerEndHour ? 0 : 59;
        return AlertDialog(
          title: const Text('Select class time'),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DropdownButton<int>(
                value: hour,
                items: [
                  for (int h = kPickerStartHour; h <= kPickerEndHour; h++)
                    DropdownMenuItem(
                      value: h,
                      child: Text(DateFormat('hh a').format(DateTime(2000, 1, 1, h))),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setS(() {
                    hour = v;
                    if (hour == kPickerEndHour) minute = 0;
                  });
                },
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(':', style: TextStyle(fontSize: 20)),
              ),
              DropdownButton<int>(
                value: minute > maxMinute ? 0 : minute,
                items: [
                  for (int m = 0; m <= maxMinute; m++)
                    DropdownMenuItem(
                      value: m,
                      child: Text(m.toString().padLeft(2, '0')),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setS(() => minute = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, TimeOfDay(hour: hour, minute: minute)),
              child: const Text('OK'),
            ),
          ],
        );
      },
    ),
  );
}

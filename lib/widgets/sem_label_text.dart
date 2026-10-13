part of '../main.dart';

// Shows a semester name.

// My subjects (subjects the teacher has claimed, with full context)
class SemLabelText extends StatelessWidget {
  final SemRef sem;
  final TextStyle? style;
  const SemLabelText({super.key, required this.sem, this.style});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
      future: safeGetDocOrNull(sem.doc),
      builder: (context, snap) {
        final l = (snap.data?.data()?['label'] ?? '').toString();
        return Text(l.isEmpty ? defaultSemesterLabel(sem.semester) : l,
            style: style);
      },
    );
  }
}

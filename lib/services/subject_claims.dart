part of '../main.dart';

// Teacher claims / unclaims a subject.

// Claim / unclaim a subject (teacher)
class ClaimException implements Exception {
  final String message;
  ClaimException(this.message);
}

Future<void> claimSubject(
    BuildContext context, SemRef sem, String subject) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Claim this subject?'),
      content: Text(
          "'$subject' will be assigned to you. No other teacher can claim it until you release it."),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Claim')),
      ],
    ),
  );
  if (confirm != true) return;
  if (!context.mounted) return;

  // Needs internet so the server can stop two teachers claiming the same subject.
  if ((await _netState()) != _Net.reachable) {
    if (context.mounted) {
      showSnack(context, 'An internet connection is required to claim a subject.');
    }
    return;
  }

  final subRef = sem.subjectDoc(subject);
  final claimRef =
      teacherClaimsRef(AppSession.teacherId).doc(sem.claimKey(subject));
  try {
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(subRef);
      if (!snap.exists) throw ClaimException('This subject no longer exists.');
      final cb = (snap.data()?['claimed_by'] ?? '').toString();
      if (cb.isNotEmpty && cb != AppSession.teacherId) {
        throw ClaimException(
            'This subject has already been claimed by ${(snap.data()?['claimed_by_name'] ?? 'another teacher').toString()}.');
      }
      tx.update(subRef, {
        'claimed_by': AppSession.teacherId,
        'claimed_by_name': AppSession.teacherName,
      });
      tx.set(claimRef, {
        'dept': sem.deptId,
        'section': sem.section,
        'semester': sem.semester,
        'subject': subject,
      });
    }).timeout(const Duration(seconds: 15));

    unawaited(LocalDb.setSubjectClaim(
        sem, subject, AppSession.teacherId, AppSession.teacherName));
    unawaited(LocalDb.upsertClaim(AppSession.teacherId, sem, subject));
    if (context.mounted) showSnack(context, "You claimed '$subject'");
  } on ClaimException catch (e) {
    if (context.mounted) showSnack(context, e.message);
  } catch (_) {
    if (context.mounted) {
      showSnack(context, 'Could not claim the subject. Please check your internet and try again.');
    }
  }
}

Future<void> unclaimSubject(
    BuildContext context, SemRef sem, String subject) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Leave this subject?'),
      content: Text(
          "'$subject' will become available to all teachers again. Existing attendance history will not be deleted."),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave',
                style: TextStyle(color: kAbsent))),
      ],
    ),
  );
  if (confirm != true) return;

  unawaited(sem.subjectDoc(subject).update({
    'claimed_by': FieldValue.delete(),
    'claimed_by_name': FieldValue.delete(),
  }).catchError((_) {}));
  unawaited(teacherClaimsRef(AppSession.teacherId)
      .doc(sem.claimKey(subject))
      .delete()
      .catchError((_) {}));
  unawaited(LocalDb.setSubjectClaim(sem, subject, '', ''));
  unawaited(LocalDb.deleteClaim(AppSession.teacherId, sem, subject));
  if (context.mounted) showSnack(context, "You left '$subject'");
}

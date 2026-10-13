part of '../main.dart';

// Pick a section.

// Sections screen: Department -> Section A / B / C / D
class SectionsScreen extends StatelessWidget {
  final String deptId;
  final String deptName;
  const SectionsScreen({super.key, required this.deptId, required this.deptName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(deptName)),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text('Choose a section',
                style: TextStyle(color: kMuted, fontSize: 14)),
          ),
          for (final sec in kSections)
            AppCard(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SemestersScreen(
                      deptId: deptId, deptName: deptName, section: sec),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: kAccent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(sec,
                        style: const TextStyle(
                            color: kAccent,
                            fontSize: 20,
                            fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text('Section $sec',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  const Icon(Icons.chevron_right, color: kMuted),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

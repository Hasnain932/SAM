part of '../../main.dart';

// First screen: Admin Login / Teacher Login.

// Welcome screen (Admin Login / Teacher Login)
// Brand on top, sign-in sheet at the bottom.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  Widget _feature(IconData icon, String label) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: kAccent, size: 24),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label,
                maxLines: 1,
                style: const TextStyle(color: kMuted, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    void openAdmin() => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
        );
    void openTeacher() => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TeacherAuthScreen()),
        );
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: CustomPaint(painter: _BrandRingsPainter()),
                  ),
                  Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // SAM logo: glass tile + graduation cap
                          Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              color: const Color(0x1FFFFFFF),
                              borderRadius: BorderRadius.circular(28),
                              border:
                                  Border.all(color: const Color(0x40FFFFFF)),
                            ),
                            child: const Icon(Icons.school_rounded,
                                color: Colors.white, size: 56),
                          ),
                          const SizedBox(height: 22),
                          const Text('SAM',
                              style: TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 12)),
                          const SizedBox(height: 10),
                          Text('SMART ATTENDANCE',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: kAccent.withValues(alpha: 0.95),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 5)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(24, 28, 24, 20 + bottomInset),
                decoration: const BoxDecoration(
                  color: kSurfaceHi,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Welcome back',
                        style: TextStyle(
                            fontSize: 28, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    const Text('Choose how you want to sign in',
                        style: TextStyle(color: kMuted, fontSize: 16)),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: openAdmin,
                        icon: const Icon(Icons.admin_panel_settings_outlined),
                        label: const Text('Admin Login',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: OutlinedButton.icon(
                        onPressed: openTeacher,
                        icon: const Icon(Icons.person_outline),
                        label: const Text('Teacher Login',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton(
                        onPressed: openTeacher,
                        child: Text.rich(
                          TextSpan(
                            text: 'New teacher? ',
                            style: const TextStyle(
                                color: kMuted, fontWeight: FontWeight.w400),
                            children: const [
                              TextSpan(
                                text: 'Create account',
                                style: TextStyle(
                                    color: kAccent,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _feature(Icons.bolt_outlined, 'Quick marking'),
                        _feature(Icons.description_outlined, 'Excel export'),
                        _feature(Icons.cloud_off_outlined, 'Works offline'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Faint concentric rings behind the brand on the welcome screen.
class _BrandRingsPainter extends CustomPainter {
  const _BrandRingsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.07);
    for (final r in const [120.0, 200.0, 280.0, 360.0]) {
      canvas.drawCircle(c, r, p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

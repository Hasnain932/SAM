part of '../main.dart';

// The gradient background behind each page.

// Paints the aurora gradient behind a page.
class AuroraBackground extends StatelessWidget {
  final Widget child;
  const AuroraBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: kAuroraGradient),
      child: child,
    );
  }
}

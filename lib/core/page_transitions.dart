part of '../main.dart';

// How pages slide / fade when you open them.

// Light page transition for the web (a plain fade).
class _WebFadeTransitions extends PageTransitionsBuilder {
  const _WebFadeTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(opacity: animation, child: child);
  }
}

// Each route paints its own gradient so the previous page doesn't show through.
class _AuroraTransitions extends PageTransitionsBuilder {
  final PageTransitionsBuilder inner;
  const _AuroraTransitions(this.inner);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return inner.buildTransitions<T>(
      route,
      context,
      animation,
      secondaryAnimation,
      AuroraBackground(child: child),
    );
  }
}

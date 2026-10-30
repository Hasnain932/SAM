part of 'main.dart';

// Theme: deep navy gradient, glass cards, blue glow buttons.
// Blue = present / selected, red = absent.
const Color kBgTop = Color(0xFF1B1166);
const Color kBgMid = Color(0xFF0B1240);
const Color kBgBottom = Color(0xFF08203A);
const Color kBg = kBgMid;
const Color kSurface = Color(0xFF111A4A); // solid navy: dialogs, menus
const Color kSurfaceHi = Color(0xFF1A2560);
const Color kGlass = Color(0x1AFFFFFF); // glass card fill (10% white)
const Color kGlassBorder = Color(0x803B6BF0); // glass card border (soft blue)
const Color kAccentLine = Color(0xFF3B6BF0); // outline of unselected chips
const Color kOutline = Color(0x33FFFFFF);
const Color kAccent = Color(0xFF14B8E6); // cyan blue: icons, highlights
const Color kOnAccent = Colors.white; // text on blue buttons
const Color kButton = Color(0xFF2563EB); // primary pill buttons
const Color kPresent = Color(0xFF14B8E6);
const Color kAccent2 = Color(0xFF2563EB); // royal blue
const Color kViolet = Color(0xFF8B7CF6);
const Color kAbsent = Color(0xFFFF8FA0);
const Color kMuted = Color(0xFFC3D1E7);
const Color kAbsent2 = Color(0xFFE5365F);
const Color kLabelBlue = Color(0xFF8FD8FF); // light blue for labels
// Soft, light glow (was strong: alpha AA, blur 10). Used on titles and labels.
const List<Shadow> kGlowText = [Shadow(color: Color(0x4014B8E6), blurRadius: 5)];
// Names of departments, sections, semesters and subjects: same soft glow.
const TextStyle kNameStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: Color(0xFFEAF6FF),
    shadows: kGlowText);
const TextStyle kLabelStyle = TextStyle(
    color: kLabelBlue, fontSize: 13, fontWeight: FontWeight.w600, shadows: kGlowText);
const LinearGradient kBlueGrad = LinearGradient(colors: [kAccent, kAccent2]);
// Diagonal gradient used on icon tiles (same as the department building boxes).
const LinearGradient kTileGrad = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [kAccent, kAccent2],
);
const LinearGradient kTileRedGrad = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFFF7A93), kAbsent2],
);
const LinearGradient kRedGrad =
    LinearGradient(colors: [Color(0xFFFF7A93), kAbsent2]);
// Card fill: soft blue gradient (same family as the P button).
const LinearGradient kCardGrad = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF1F3C9E), Color(0xFF0C5F95)],
);

const LinearGradient kAuroraGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [kBgTop, kBgMid, kBgBottom],
);

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

// Inner pages open instantly (no page animation, so no delay on tap).
class _NoTransitions extends PageTransitionsBuilder {
  const _NoTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}

// Soft fade used only for the Admin / Teacher login pages.
Route<T> _fadeRoute<T>(WidgetBuilder builder) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, _, _) => AuroraBackground(child: builder(context)),
    transitionsBuilder: (context, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    ),
  );
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

// ---- Small reusable widgets ----
// Gentle up/down float (professional, subtle).
class Floaty extends StatefulWidget {
  final Widget child;
  final double dy;
  final int ms;
  final double phase;
  const Floaty({
    super.key,
    required this.child,
    this.dy = 3,
    this.ms = 3400,
    this.phase = 0,
  });

  @override
  State<Floaty> createState() => _FloatyState();
}

class _FloatyState extends State<Floaty> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.ms),
  );

  @override
  void initState() {
    super.initState();
    _c.value = widget.phase.clamp(0.0, 1.0);
    _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(_c.value);
          return Transform.translate(
            offset: Offset(0, (t - 0.5) * 2 * widget.dy),
            child: child,
          );
        },
      ),
    );
  }
}

class AppCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;
  final double blur;
  final bool float; // soft floating + fade-in; off everywhere except where asked
  final Color? borderColor; // optional custom border (e.g. low attendance)
  final bool subtle; // plain dark fill instead of the blue gradient (long lists)
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(14),
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
    this.radius = 20,
    this.blur = 10,
    this.float = false,
    this.borderColor,
    this.subtle = false,
  });

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  static int _count = 0;
  late final double _phase = ((_count++) * 0.17) % 1.0; // wave pattern

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(widget.radius);
    final card = Material(
      color: widget.subtle ? const Color(0xFF16215F) : kGlass,
      child: InkWell(
        onTap: widget.onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: r,
            border: Border.all(color: widget.borderColor ?? kGlassBorder),
          ),
          padding: widget.padding,
          child: widget.child,
        ),
      ),
    );
    final body = Padding(
      padding: widget.margin,
      child: ClipRRect(
        borderRadius: r,
        // Web: no blur (a BackdropFilter per card is slow, and barely visible here).
        child: kIsWeb
            ? card
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur),
                child: card,
              ),
      ),
    );
    if (!widget.float || MediaQuery.of(context).disableAnimations) return body;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 14), child: child),
      ),
      child: Floaty(phase: _phase, dy: 2.5, child: body),
    );
  }
}

// Pill button with the blue (or red) gradient. filled = selected look.
class GradPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final LinearGradient gradient;
  final bool filled;
  final bool enabled;
  final bool expand;
  final double? height;
  final double radius;
  final double fontSize;
  const GradPill({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.gradient = kBlueGrad,
    this.filled = true,
    this.enabled = true,
    this.expand = false,
    this.height,
    this.radius = 999,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    final red = gradient == kRedGrad;
    final fg = filled ? Colors.white : (red ? kAbsent : kAccent);
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: fg, fontSize: fontSize, fontWeight: FontWeight.w700)),
        ),
      ],
    );
    final r = BorderRadius.circular(radius);
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: filled ? gradient : null,
          borderRadius: r,
          border: filled
              ? null
              : Border.all(color: red ? kAbsent : kAccentLine, width: 1.2),
          boxShadow: filled
              ? [
                  BoxShadow(
                    color: gradient.colors.last.withValues(alpha: 0.40),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: r,
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: 14, vertical: height == null ? 9 : 0),
              child: height != null ? Center(child: content) : content,
            ),
          ),
        ),
      ),
    );
  }
}

// Blue gradient pill button (login screens).
class GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.6 : 1,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [kAccent, kAccent2]),
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: kAccent.withValues(alpha: 0.40),
              blurRadius: 14,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(26),
            onTap: onPressed,
            child: Center(
              child: loading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          color: kOnAccent, strokeWidth: 2),
                    )
                  : Text(label,
                      style: const TextStyle(
                          color: kOnAccent,
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
            ),
          ),
        ),
      ),
    );
  }
}

// Labelled glass text field (login screens).
class AuthField extends StatelessWidget {
  final String label;
  final String hint;
  final IconData icon;
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final TextInputType? keyboardType;
  final TextCapitalization capitalization;
  const AuthField({
    super.key,
    required this.label,
    required this.hint,
    required this.icon,
    required this.controller,
    this.obscure = false,
    this.onToggleObscure,
    this.keyboardType,
    this.capitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(label.toUpperCase(),
              style: const TextStyle(
                  color: kMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3)),
        ),
        TextField(
          controller: controller,
          obscureText: obscure,
          autocorrect: false,
          keyboardType: keyboardType,
          textCapitalization: capitalization,
          decoration: InputDecoration(
            hintText: hint,
            fillColor: const Color(0x4D0A0F2E),
            prefixIcon: Icon(icon, color: kAccent, size: 20),
            suffixIcon: onToggleObscure == null
                ? null
                : IconButton(
                    onPressed: onToggleObscure,
                    icon: Icon(
                        obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: kMuted,
                        size: 20),
                  ),
          ),
        ),
      ],
    );
  }
}

// Shared look of the Admin / Teacher login pages.
class AuthShell extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;
  const AuthShell({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final content = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(
        children: [
          SizedBox(
            width: 148,
            height: 148,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 148,
                  height: 148,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      kAccent2.withValues(alpha: 0.30),
                      kAccent2.withValues(alpha: 0.08),
                    ]),
                    border: Border.all(
                        color: kAccent2.withValues(alpha: 0.35), width: 1),
                  ),
                ),
                Floaty(dy: 4, child: IconBadge(icon: icon, size: 80)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 29,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.3)),
          const SizedBox(height: 6),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: kMuted, fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 26),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: kGlass,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: kGlassBorder),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 18,
                    offset: Offset(0, 6)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
          const SizedBox(height: 22),
          const Text('SAM  ·  SMART ATTENDANCE',
              style: TextStyle(
                  color: kMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 3)),
        ],
      ),
    );
    // One-time soft fade + rise when the page opens (same feel as the main page).
    final animated = MediaQuery.of(context).disableAnimations
        ? content
        : TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            builder: (context, v, child) => Opacity(
              opacity: v,
              child: Transform.translate(
                  offset: Offset(0, (1 - v) * 18), child: child),
            ),
            child: content,
          );
    return Scaffold(
      appBar: AppBar(),
      body: Stack(
        children: [
          const Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: _BrandRingsPainter()),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
              child: animated,
            ),
          ),
        ],
      ),
    );
  }
}

// Round P / A button used on the attendance screen.
class AttendanceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback? onTap;
  const AttendanceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.55 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Duration.zero,
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: selected
                ? (color == kAbsent
                    ? kRedGrad
                    : (color == kPresent ? kBlueGrad : null))
                : null,
            color: selected && color != kPresent && color != kAbsent
                ? color
                : null,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: (color == kAbsent ? kAbsent2 : kAccent2)
                          .withValues(alpha: 0.42),
                      blurRadius: 9,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
            border: Border.all(
              color: selected
                  ? (color == kAbsent
                      ? kAbsent2
                      : (color == kPresent ? kAccent2 : color))
                  : kAccentLine,
              width: 1.2,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: selected ? kOnAccent : const Color(0xB3FFFFFF),
            ),
          ),
        ),
      ),
    );
  }
}

class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const IconBadge(
      {super.key, required this.icon, this.color = kAccent, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final big = size >= 60;
    final isAccent = color == kAccent;
    // Flat gradient tile with a white icon (same look as the HF avatar and the
    // bookmark button), no glow. Other colors (e.g. a taken subject) stay muted.
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: isAccent
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [kAccent, kAccent2],
              )
            : null,
        color: isAccent ? null : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(big ? size * 0.3 : 12),
        boxShadow: isAccent
            ? [
                BoxShadow(
                  color: kAccent2.withValues(alpha: big ? 0.42 : 0.32),
                  blurRadius: big ? 14 : 9,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Icon(icon,
          color: isAccent ? kOnAccent : color, size: size * 0.5),
    );
  }
}

// Small blue label chip (used in the permissions dialog).
class _PermChip extends StatelessWidget {
  final String text;
  const _PermChip(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: kAccent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        text,
        style: const TextStyle(
            color: kAccent, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

// Floating add button: same gradient rounded-square look as the icon tiles.
class GradFab extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  const GradFab({super.key, this.icon = Icons.add, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(18);
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        gradient: kTileGrad,
        borderRadius: r,
        boxShadow: [
          BoxShadow(
            color: kAccent2.withValues(alpha: 0.42),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: r,
          onTap: onPressed,
          child: Center(child: Icon(icon, color: Colors.white, size: 28)),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  // Optional button under the text (e.g. jump to marking attendance).
  final String? actionLabel;
  final VoidCallback? onAction;
  const EmptyState({
    super.key,
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: kMuted),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: kMuted, fontSize: 15)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.how_to_reg_outlined, size: 18),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// App bar action with a soft colored background, so similar icons
// (e.g. Import vs Export) are easy to tell apart.
class TintedIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onPressed;
  const TintedIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: IconButton(
        icon: Icon(icon, color: color),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}

// ---- Header card (dark rounded bar used on the redesigned screens) ----
// Square tile with an icon, used inside HeaderCard. Colors stay the app's own.
class HeaderTile extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color color;
  final bool tile; // false = plain icon without the tile background
  final bool dot; // small red dot (e.g. pending requests)
  const HeaderTile({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color = kAccent,
    this.tile = true,
    this.dot = false,
  });

  @override
  Widget build(BuildContext context) {
    final isBlue = color == kAccent;
    final isRed = color == kAbsent;
    final r = BorderRadius.circular(12);
    return Tooltip(
      message: tooltip,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Ink(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: tile && (isBlue || isRed)
                    ? (isRed ? kTileRedGrad : kTileGrad)
                    : null,
                color: tile && !(isBlue || isRed)
                    ? color.withValues(alpha: 0.18)
                    : null,
                borderRadius: r,
              ),
              child: InkWell(
                borderRadius: r,
                onTap: onTap,
                child: Center(
                    child: Icon(icon,
                        color: tile && (isBlue || isRed) ? Colors.white : color,
                        size: 20)),
              ),
            ),
            if (dot)
              Positioned(
                top: -3,
                right: -3,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: const BoxDecoration(
                    color: kAbsent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// One cell of the icon + label row under a HeaderCard title.
class HeaderAction {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const HeaderAction({required this.icon, required this.label, this.onTap});
}

class HeaderCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions; // small tiles on the right of the title
  final List<HeaderAction> tabs; // icon + label row under the title
  const HeaderCard({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.tabs = const [],
  });

  @override
  Widget build(BuildContext context) {
    final canBack = Navigator.of(context).canPop();
    final tileRow = <Widget>[];
    for (var i = 0; i < actions.length; i++) {
      if (i > 0) tileRow.add(const SizedBox(width: 6));
      tileRow.add(actions[i]);
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: kBgTop,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: kGlassBorder),
        boxShadow: [
          BoxShadow(
            color: kAccent2.withValues(alpha: 0.22),
            blurRadius: 14,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (canBack)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: InkResponse(
                    radius: 22,
                    onTap: () => Navigator.maybePop(context),
                    child: const Icon(Icons.arrow_back,
                        color: Colors.white, size: 24),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFEAF6FF),
                          shadows: kGlowText,
                        ),
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: kLabelBlue,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                  ],
                ),
              ),
              if (tileRow.isNotEmpty) ...[
                const SizedBox(width: 8),
                ...tileRow,
              ],
            ],
          ),
          if (tabs.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: const Color(0x14FFFFFF),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: kGlassBorder),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < tabs.length; i++) ...[
                    if (i > 0)
                      Container(width: 1, height: 34, color: kOutline),
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: tabs[i].onTap,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 9, horizontal: 2),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  gradient: kTileGrad,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(tabs[i].icon,
                                    color: Colors.white, size: 19),
                              ),
                              const SizedBox(height: 4),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  tabs[i].label,
                                  maxLines: 1,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      color: kLabelBlue),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Same header bar as the Departments screen, for the inner screens.
PreferredSizeWidget headerAppBar({
  required String title,
  String? subtitle,
  List<Widget> actions = const [],
}) {
  return AppBar(
    automaticallyImplyLeading: false,
    titleSpacing: 0,
    toolbarHeight: subtitle == null ? 84 : 102,
    title: HeaderCard(title: title, subtitle: subtitle, actions: actions),
  );
}

class InfoBanner extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  const InfoBanner(
      {super.key,
      required this.text,
      this.icon = Icons.info_outline,
      this.color = kAccent});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

void showSnack(BuildContext context, String msg, {Color? color}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: color),
  );
}

// Message that stays on screen until the user taps Dismiss.
// Replaces any snackbar already showing.
void showStickySnack(ScaffoldMessengerState messenger, String msg,
    {Color? color}) {
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(msg),
      backgroundColor: color,
      duration: const Duration(days: 1),
      action: SnackBarAction(
        label: 'Dismiss',
        textColor: Colors.white,
        onPressed: () => messenger.hideCurrentSnackBar(),
      ),
    ),
  );
}

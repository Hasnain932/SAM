part of '../main.dart';

// Small widgets reused on many screens.

// ---- Small reusable widgets ----
class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;
  final double blur;
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(14),
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
    this.radius = 20,
    this.blur = 10,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    final card = Material(
      color: kGlass,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: r,
            border: Border.all(color: kGlassBorder),
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
    return Padding(
      padding: margin,
      child: ClipRRect(
        borderRadius: r,
        // Web: no blur (a BackdropFilter per card is slow, and barely visible here).
        child: kIsWeb
            ? card
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: card,
              ),
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
          duration: const Duration(milliseconds: 160),
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? color : Colors.transparent,
            border: Border.all(
              color: selected ? color : const Color(0x4DFFFFFF),
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
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
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
    final fill = color == kAccent
        ? const Color(0x1AFFFFFF)
        : color.withValues(alpha: 0.18);
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
                color: tile ? fill : Colors.transparent,
                borderRadius: r,
              ),
              child: InkWell(
                borderRadius: r,
                onTap: onTap,
                child: Center(child: Icon(icon, color: color, size: 20)),
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
                          color: Colors.white,
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
                          color: kMuted,
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
                              Icon(tabs[i].icon, color: kAccent, size: 22),
                              const SizedBox(height: 4),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  tabs[i].label,
                                  maxLines: 1,
                                  style: const TextStyle(
                                      fontSize: 12.5, color: kMuted),
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

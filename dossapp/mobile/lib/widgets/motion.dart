import 'package:flutter/material.dart';

/// One motion language for the whole app.
///
/// Rules, borrowed from how iOS and the big banking apps move:
///  - short: nothing a person waits for runs longer than about 0.4 s
///    (Doherty Threshold)
///  - things arrive fast and settle slowly (a strong ease out), never bounce
///  - movement is small: a few points of travel plus a fade, so it reads as
///    "this appeared", not as decoration
///  - one thing moves at a time, and the direction means something
///    (forward goes one way, back goes the other)
///  - if the phone is set to reduce motion, everything just appears
class Motion {
  static const fast = Duration(milliseconds: 180);
  static const base = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 420);

  /// Arrives quickly, settles gently. The curve iOS uses for most things.
  static const enter = Cubic(0.2, 0.8, 0.2, 1.0);

  /// Leaves quickly, out of the way of what is coming.
  static const exit = Cubic(0.4, 0.0, 1.0, 1.0);

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static Duration of(BuildContext context, Duration d) =>
      reduced(context) ? Duration.zero : d;
}

/// Swaps one piece of content for another: the old one fades out first,
/// then the new one fades in while settling into place from slightly small.
/// Used for loading to loaded, for whole screens, and for anything that is
/// replaced rather than moved.
class FadeThrough extends StatelessWidget {
  /// Changes whenever the content is a different thing (not just new data).
  final Object stateKey;
  final Widget child;
  final Duration duration;
  final AlignmentGeometry alignment;

  const FadeThrough({
    super.key,
    required this.stateKey,
    required this.child,
    this.duration = Motion.base,
    this.alignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Motion.of(context, duration),
      // The old content is gone by a third of the way; no muddy cross-dissolve
      switchOutCurve: const Interval(0.65, 1.0, curve: Motion.exit),
      switchInCurve: const Interval(0.25, 1.0, curve: Motion.enter),
      layoutBuilder: (current, previous) => Stack(
        alignment: alignment,
        fit: StackFit.passthrough,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1.0).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(stateKey), child: child),
    );
  }
}

/// Plays once when it first appears: rises a few points while fading in.
/// [order] staggers a group so the eye is led down the page, one item after
/// another, without making anyone wait.
class Appear extends StatefulWidget {
  final Widget child;
  final int order;
  final double rise;
  final Duration duration;

  const Appear({
    super.key,
    required this.child,
    this.order = 0,
    this.rise = 14,
    this.duration = Motion.slow,
  });

  @override
  State<Appear> createState() => _AppearState();
}

class _AppearState extends State<Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _t =
      CurvedAnimation(parent: _c, curve: Motion.enter);

  @override
  void initState() {
    super.initState();
    // Capped: the tenth row must not arrive half a second late
    final wait = Duration(milliseconds: 45 * widget.order.clamp(0, 6));
    if (wait == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(wait, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return widget.child;
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(
          offset: Offset(0, widget.rise * (1 - _t.value)),
          child: child,
        ),
      ),
    );
  }
}

/// The body under a bottom bar. Tabs keep their state; the one that comes
/// forward fades in while sliding a few points from the side it lives on,
/// so left and right in the bar match left and right on screen.
class TabSwitcher extends StatefulWidget {
  final int index;
  final List<Widget> children;

  const TabSwitcher({super.key, required this.index, required this.children});

  @override
  State<TabSwitcher> createState() => _TabSwitcherState();
}

class _TabSwitcherState extends State<TabSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: Motion.base, value: 1);
  late final Animation<double> _t =
      CurvedAnimation(parent: _c, curve: Motion.enter);
  double _from = 0;

  @override
  void didUpdateWidget(TabSwitcher old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _from = widget.index > old.index ? 1 : -1;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stack = IndexedStack(index: widget.index, children: widget.children);
    if (Motion.reduced(context)) return stack;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return AnimatedBuilder(
      animation: _t,
      child: stack,
      builder: (context, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(
          offset: Offset((rtl ? -1 : 1) * _from * 16 * (1 - _t.value), 0),
          child: child,
        ),
      ),
    );
  }
}

/// The steps of a short flow (email, code, password). Going forward the new
/// step comes in from the end side, going back from the start side, and the
/// space it needs grows or shrinks smoothly instead of jumping.
class StepSwitcher extends StatefulWidget {
  final int step;
  final Widget child;

  const StepSwitcher({super.key, required this.step, required this.child});

  @override
  State<StepSwitcher> createState() => _StepSwitcherState();
}

class _StepSwitcherState extends State<StepSwitcher> {
  bool _forward = true;

  @override
  void didUpdateWidget(StepSwitcher old) {
    super.didUpdateWidget(old);
    if (old.step != widget.step) _forward = widget.step > old.step;
  }

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return widget.child;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final side = (_forward ? 1.0 : -1.0) * (rtl ? -1.0 : 1.0);
    return AnimatedSize(
      duration: Motion.base,
      curve: Motion.enter,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: Motion.base,
        switchOutCurve: const Interval(0.6, 1.0, curve: Motion.exit),
        switchInCurve: const Interval(0.2, 1.0, curve: Motion.enter),
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [...previous, if (current != null) current],
        ),
        transitionBuilder: (child, animation) {
          // Only the step coming in travels; the one leaving just fades
          final incoming = child.key == ValueKey(widget.step);
          return FadeTransition(
            opacity: animation,
            child: incoming
                ? AnimatedBuilder(
                    animation: animation,
                    child: child,
                    builder: (context, c) => Transform.translate(
                      offset: Offset(side * 28 * (1 - animation.value), 0),
                      child: c,
                    ),
                  )
                : child,
          );
        },
        child: KeyedSubtree(key: ValueKey(widget.step), child: widget.child),
      ),
    );
  }
}

/// A number that counts to its value instead of snapping to it. Text around
/// the digits ("100%", "7 of 7") is kept as written.
class CountUp extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const CountUp(this.text, {super.key, this.style});

  static final _digits = RegExp(r'\d+');

  @override
  Widget build(BuildContext context) {
    final match = _digits.firstMatch(text);
    final target = match == null ? null : int.tryParse(match.group(0)!);
    if (target == null || Motion.reduced(context)) {
      return Text(text, style: style);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: target.toDouble()),
      duration: const Duration(milliseconds: 650),
      curve: Motion.enter,
      builder: (context, value, _) => Text(
        text.replaceRange(match!.start, match.end, value.round().toString()),
        style: style,
      ),
    );
  }
}

/// A progress bar that fills to its value when it appears or changes.
class FillBar extends StatelessWidget {
  final double value;
  final Color color;
  final Color track;
  final double height;

  const FillBar({
    super.key,
    required this.value,
    required this.color,
    required this.track,
    this.height = 8,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: value.clamp(0.0, 1.0)),
        duration: Motion.of(context, const Duration(milliseconds: 700)),
        curve: Motion.enter,
        builder: (context, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: height,
          backgroundColor: track,
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    );
  }
}

/// Screens pushed on Android: the new page fades in while sliding a short
/// way from the end side. iPhone keeps its own slide and swipe back.
class SlideFadePageTransitionsBuilder extends PageTransitionsBuilder {
  const SlideFadePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final enter = CurvedAnimation(parent: animation, curve: Motion.enter, reverseCurve: Motion.exit);
    final leave = CurvedAnimation(parent: secondaryAnimation, curve: Motion.enter, reverseCurve: Motion.exit);
    return FadeTransition(
      opacity: enter,
      child: SlideTransition(
        position: Tween<Offset>(begin: Offset(rtl ? -0.08 : 0.08, 0), end: Offset.zero).animate(enter),
        // The page underneath steps back a little, like a card being covered
        child: SlideTransition(
          position: Tween<Offset>(begin: Offset.zero, end: Offset(rtl ? 0.04 : -0.04, 0)).animate(leave),
          child: child,
        ),
      ),
    );
  }
}

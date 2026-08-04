import 'package:flutter/material.dart';
import '../utils/theme.dart';

/// Wraps a child widget with a staggered slide-up + fade-in entrance animation.
class AnimatedListItem extends StatefulWidget {
  final int index;
  final Widget child;
  final Duration delay;
  final Duration duration;

  const AnimatedListItem({
    super.key,
    required this.index,
    required this.child,
    this.delay = AppAnimation.staggerDelay,
    this.duration = AppAnimation.slowDuration,
  });

  @override
  State<AnimatedListItem> createState() => _AnimatedListItemState();
}

class _AnimatedListItemState extends State<AnimatedListItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: AppAnimation.enterCurve,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: AppAnimation.enterCurve,
    ));

    Future.delayed(widget.delay * widget.index, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: widget.child,
      ),
    );
  }
}

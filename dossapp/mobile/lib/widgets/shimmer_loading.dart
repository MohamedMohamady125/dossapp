import 'package:flutter/material.dart';
import '../utils/theme.dart';

/// A shimmer loading placeholder that animates a gradient sweep.
class ShimmerLoading extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerLoading({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.borderRadius = 8,
  });

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2.0 * _controller.value, 0),
              end: Alignment(-0.5 + 2.0 * _controller.value, 0),
              colors: const [
                AppColors.surfaceVariant,
                AppColors.borderLight,
                AppColors.surfaceVariant,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A skeleton card that mimics a content card during loading.
class SkeletonCard extends StatelessWidget {
  final int lines;
  final bool hasAvatar;

  const SkeletonCard({super.key, this.lines = 3, this.hasAvatar = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasAvatar) ...[
            const ShimmerLoading(width: 48, height: 48, borderRadius: 14),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < lines; i++) ...[
                  ShimmerLoading(
                    height: i == 0 ? 18 : 14,
                    width: i == lines - 1 ? 120 : double.infinity,
                  ),
                  if (i < lines - 1) const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen skeleton loader with multiple cards.
class SkeletonList extends StatelessWidget {
  final int count;
  final bool hasAvatar;
  final EdgeInsets padding;

  const SkeletonList({
    super.key,
    this.count = 5,
    this.hasAvatar = false,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        children: List.generate(
          count,
          (i) => SkeletonCard(hasAvatar: hasAvatar, lines: i % 2 == 0 ? 3 : 2),
        ),
      ),
    );
  }
}

/// Hero stats skeleton for analytics-style headers.
class SkeletonHero extends StatelessWidget {
  const SkeletonHero({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 120, height: 14, decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          )),
          const SizedBox(height: 16),
          Row(
            children: List.generate(3, (_) => Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(width: 20, height: 20, decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  )),
                  const SizedBox(height: 6),
                  Container(width: 60, height: 20, decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  )),
                  const SizedBox(height: 4),
                  Container(width: 40, height: 10, decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  )),
                ],
              ),
            )),
          ),
        ],
      ),
    );
  }
}

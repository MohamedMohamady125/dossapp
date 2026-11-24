import 'package:flutter/material.dart';
import 'motion.dart';

/// A card or row that rises a few points and fades in the first time it is
/// shown. [index] staggers a list so items arrive one after another.
class AnimatedListItem extends StatelessWidget {
  final int index;
  final Widget child;

  const AnimatedListItem({super.key, required this.index, required this.child});

  @override
  Widget build(BuildContext context) => Appear(order: index, child: child);
}

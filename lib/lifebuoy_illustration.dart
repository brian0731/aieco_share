import 'package:flutter/material.dart';

class LifebuoyIllustration extends StatelessWidget {
  const LifebuoyIllustration({
    super.key,
    required this.scene,
    required this.color,
    this.height = 84,
    this.child,
  });

  final String scene;
  final Color color;
  final double height;
  final Widget? child;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: height, minWidth: double.infinity),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: color,
              child: Image.asset(
                'assets/images/lifebuoy/$scene.webp',
                fit: BoxFit.cover,
                excludeFromSemantics: true,
              ),
            ),
          ),
          if (child != null)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color, color.withValues(alpha: 0)],
                    stops: const [0, .39, .64],
                  ),
                ),
              ),
            ),
          child ?? SizedBox(height: height),
        ],
      ),
    ),
  );
}

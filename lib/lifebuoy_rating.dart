import 'package:flutter/material.dart';

class LifebuoyRatingDialog extends StatefulWidget {
  const LifebuoyRatingDialog({super.key});

  @override
  State<LifebuoyRatingDialog> createState() => _LifebuoyRatingDialogState();
}

class _LifebuoyRatingDialogState extends State<LifebuoyRatingDialog> {
  int stars = 0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('評價對方'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      content: Wrap(
        alignment: WrapAlignment.center,
        children: [
          for (var rating = 1; rating <= 5; rating++)
            Semantics(
              selected: stars == rating,
              child: IconButton(
                tooltip: '$rating 星',
                iconSize: 28,
                onPressed: () => setState(() => stars = rating),
                icon: Icon(
                  rating <= stars
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: rating <= stars
                      ? colors.primary
                      : colors.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: stars == 0 ? null : () => Navigator.pop(context, stars),
          child: const Text('送出評分'),
        ),
      ],
    );
  }
}

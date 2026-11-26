import 'package:flutter/material.dart';

bool matchesLifebuoySearch(String query, Iterable<Object?> values) {
  final text = query.trim().toLowerCase();
  if (text.isEmpty) return true;
  final searchable = values.whereType<String>().join(' ').toLowerCase();
  return text.split(RegExp(r'\s+')).every(searchable.contains);
}

class LifebuoySearchField extends StatelessWidget {
  const LifebuoySearchField({
    required this.controller,
    required this.label,
    required this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    textInputAction: TextInputAction.search,
    onChanged: (_) => onChanged(),
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: const Icon(Icons.search),
      isDense: true,
      suffixIcon: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => value.text.isEmpty
            ? const SizedBox.shrink()
            : IconButton(
                tooltip: '清除搜尋',
                icon: const Icon(Icons.clear),
                onPressed: () {
                  controller.clear();
                  onChanged();
                },
              ),
      ),
    ),
  );
}

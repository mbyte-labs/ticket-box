import 'package:flutter/material.dart';

class FilterButton extends StatelessWidget {
  final VoidCallback? onPress;
  final VoidCallback? onLongPress;
  final String text;
  final bool selected;

  const FilterButton({this.onPress, this.onLongPress, required this.text, required this.selected, super.key});

  @override
  Widget build(BuildContext context) {
    final btnText = Text(text);
    if (selected) {
      return OutlinedButton(onPressed: onPress, onLongPress: onLongPress, child: btnText);
    }

    return TextButton(onPressed: onPress, child: btnText);
  }
}

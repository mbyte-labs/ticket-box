import 'package:material_ui/material_ui.dart';

class CustomPillWidget extends StatelessWidget {
  final String displayText;
  final Color color;
  final double fontSize;

  const CustomPillWidget(this.displayText, this.color, {this.fontSize = 14, super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(15.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(5.0),
        child: Text(
          displayText,
          style: TextStyle(color: color, fontSize: fontSize),
        ),
      ),
    );
  }
}

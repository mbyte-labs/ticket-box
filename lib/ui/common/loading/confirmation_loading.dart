import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/screen_size_util.dart';

/// The widget shows the loading circle when submitting the data
///
/// Useful in the confirmation pop-ups
class ConfirmationLoadingWidget extends StatelessWidget {
  const ConfirmationLoadingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(height: ScreenSizeUtil.calculateSize(80)),
        const CircularProgressIndicator(),
        SizedBox(height: ScreenSizeUtil.calculateSize(50)),
      ],
    );
  }
}

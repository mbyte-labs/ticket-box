import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/theme/assets_path.dart';

class TicketBoxLogoWidget extends StatelessWidget {
  final double imageSize;
  final double topMargin;
  final double bottomMargin;

  const TicketBoxLogoWidget({this.imageSize = 3, this.topMargin = 15, this.bottomMargin = 0, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: ScreenSizeUtil.fromLTRB(0, topMargin, 0, bottomMargin),
      height: MediaQuery.of(context).size.height / imageSize,
      child: const Image(image: AssetImage(AssetsPath.ticketBoxLogo)),
    );
  }
}

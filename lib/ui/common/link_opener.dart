import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the external browser/app, falling back to a SnackBar when the
/// platform refuses it. Shared by the details link rows and the About page.
Future<void> openExternalLink(BuildContext context, String url) async {
  var opened = false;
  try {
    opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } on Exception {
    opened = false;
  }

  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the link')));
  }
}

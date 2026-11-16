import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/ui/routes.dart';

/// Opens the in-app Diagnostics log viewer, pushed so back returns to the caller.
///
/// Meant for error pages: the useful detail of a failure is usually only in the logs, and the
/// diagnostics route is deliberately reachable without being signed in.
class ViewLogsButton extends StatelessWidget {
  const ViewLogsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 250,
      child: OutlinedButton.icon(
        onPressed: () => context.pushNamed(Routes.diagnostics),
        icon: const Icon(Icons.bug_report_outlined, size: 18),
        label: const Text('View logs'),
      ),
    );
  }
}

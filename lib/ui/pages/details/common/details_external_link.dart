import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:material_ui/material_ui.dart';

part 'details_external_link.freezed.dart';

/// One entry of the tappable external-links row on the details pages.
/// [iconColor] is the source's brand tint; null renders in the neutral onSurfaceVariant.
@freezed
abstract class DetailsExternalLink with _$DetailsExternalLink {
  const factory DetailsExternalLink({required String label, required String url, required IconData icon, Color? iconColor}) =
      _DetailsExternalLink;
}

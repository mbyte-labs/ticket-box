/// Formats a byte count for display: `812 B`, `3.4 KB`, `12.0 MB`. Shared by the Diagnostics page
/// (chips, file header, share sheet) and the Settings artwork tile so they all agree.
String formatByteSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

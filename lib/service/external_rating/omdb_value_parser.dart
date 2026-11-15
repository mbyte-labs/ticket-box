/// OMDb returns every field as a string and uses the literal `"N/A"` for missing data;
/// vote counts come comma-grouped ("135,825"). These helpers normalise that to numbers,
/// mapping anything unparsable to null instead of throwing.
class OmdbValueParser {
  OmdbValueParser._();

  /// "8.2" → 8.2; "N/A", null, garbage → null.
  static double? parseRating(String? raw) {
    if (raw == null) {
      return null;
    }
    return double.tryParse(raw);
  }

  /// "135,825" → 135825; "N/A", null, garbage → null.
  static int? parseVotes(String? raw) {
    if (raw == null) {
      return null;
    }
    return int.tryParse(raw.replaceAll(',', ''));
  }
}

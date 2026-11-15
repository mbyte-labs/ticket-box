/// What a cast card already knows about the person it opens, handed to the person page as the
/// route's `extra` so the hero header can paint before the first TMDB request returns.
///
/// A paint-ahead hint only, never authoritative: the details response overwrites both fields, and
/// a page reached without them (a deep link, a stale `extra`) simply starts with a blank header, as
/// it always did. The headshot URL is built at the same profile quality the person page uses, so
/// the hero's image is a cache hit rather than a second download.
class PersonRouteArgs {
  final String? name;
  final String? photoUrl;

  const PersonRouteArgs({this.name, this.photoUrl});
}

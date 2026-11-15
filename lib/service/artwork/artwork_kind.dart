/// The kinds of artwork the library keeps on disk for a tracked movie or show.
///
/// The queue row stores [name]; the file name under the item's directory is fixed per kind (see
/// `ArtworkPaths`), so the kind and the item are all that identify a file.
enum ArtworkKind { poster, backdrop, seasonPoster, still, cast }

/// Where a details page stands. A tracked title always reaches [loaded] (from its stored
/// snapshot, even offline); [notFound] and [unreachable] can only happen for a title that is not
/// in the library and had to be fetched live.
enum DetailsLoadStatus { loading, loaded, notFound, unreachable }

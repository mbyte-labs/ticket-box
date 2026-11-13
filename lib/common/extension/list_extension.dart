import 'dart:math';

extension ListExtension<E> on List<E> {
  /// Splits the list into consecutive slices of at most [size] elements.
  ///
  /// Used to bound how much work runs at once: `for (final chunk in items.chunked(8)) await
  /// Future.wait(chunk.map(...))` keeps at most 8 requests in flight instead of bursting N of them.
  /// Returns an empty iterable for an empty list.
  Iterable<List<E>> chunked(int size) {
    if (size < 1) {
      throw ArgumentError.value(size, 'size', 'must be at least 1');
    }

    return Iterable.generate((length / size).ceil(), (index) => sublist(index * size, min((index + 1) * size, length)));
  }

  /// Adds only the elements that are not yet in the list
  void addAllUnique(Iterable<E> iterable) {
    for (var element in iterable) {
      if (!contains(element)) {
        add(element);
      }
    }
  }

  /// Adds an element to the list if it is unique
  void addUnique(E element) {
    if (!contains(element)) {
      add(element);
    }
  }
}

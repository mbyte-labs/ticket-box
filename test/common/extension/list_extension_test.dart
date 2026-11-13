import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/common/extension/list_extension.dart';

void main() {
  group('chunked', () {
    test('returns nothing for an empty list', () {
      expect(<int>[].chunked(8), isEmpty);
    });

    test('returns a single short chunk when the list is smaller than the size', () {
      expect([1].chunked(8), [
        [1],
      ]);
    });

    test('returns one full chunk on an exact multiple', () {
      expect(List.generate(8, (i) => i).chunked(8), [
        [0, 1, 2, 3, 4, 5, 6, 7],
      ]);
    });

    test('splits an uneven list without losing or duplicating elements', () {
      final source = List.generate(17, (i) => i);

      final chunks = source.chunked(8).toList();

      expect(chunks.map((chunk) => chunk.length), [8, 8, 1]);
      expect(chunks.expand((chunk) => chunk).toList(), source);
    });

    test('handles a size of one', () {
      expect([1, 2, 3].chunked(1), [
        [1],
        [2],
        [3],
      ]);
    });

    test('rejects a size below one', () {
      expect(() => [1, 2].chunked(0), throwsArgumentError);
      expect(() => [1, 2].chunked(-1), throwsArgumentError);
    });
  });
}

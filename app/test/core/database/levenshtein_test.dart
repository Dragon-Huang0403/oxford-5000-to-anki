import 'package:flutter_test/flutter_test.dart';
import 'package:deckionary/core/database/dictionary_search.dart';

void main() {
  group('levenshtein', () {
    test('identical strings → 0', () {
      expect(levenshtein('hello', 'hello'), 0);
    });

    test('empty vs non-empty → length of non-empty', () {
      expect(levenshtein('', 'abc'), 3);
      expect(levenshtein('xyz', ''), 3);
    });

    test('both empty → 0', () {
      expect(levenshtein('', ''), 0);
    });

    test('single substitution → 1', () {
      expect(levenshtein('cat', 'car'), 1);
    });

    test('single insertion → 1', () {
      expect(levenshtein('cat', 'cats'), 1);
    });

    test('single deletion → 1', () {
      expect(levenshtein('cats', 'cat'), 1);
    });

    test('completely different strings', () {
      expect(levenshtein('abc', 'xyz'), 3);
    });

    test('real-world typo: colour vs color', () {
      expect(levenshtein('colour', 'color'), 1);
    });

    test('real-world typo: recieve vs receive', () {
      expect(levenshtein('recieve', 'receive'), 2);
    });

    test('case-sensitive: Hello vs hello', () {
      expect(levenshtein('Hello', 'hello'), 1);
    });

    test('longer transposition-like: kitten vs sitting', () {
      expect(levenshtein('kitten', 'sitting'), 3);
    });
  });
}

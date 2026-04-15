import 'package:flutter_test/flutter_test.dart';
import 'test_helpers.dart';

void main() {
  test('createTestDictDb opens successfully and can query', () async {
    final db = createTestDictDb();
    // Verify we can query the headwords
    final words = await db.headwords;
    expect(words, isNotEmpty);
    expect(words.length, greaterThan(1000)); // should have ~76K entries
    await db.close();
  });

  test('createTestUserDb opens in-memory DB', () async {
    final db = createTestUserDb();
    // Verify we can do a basic query
    await db.warmUp();
    await db.close();
  });
}

import 'app_database.dart';

/// Data access for app settings
class SettingsDao {
  final UserDatabase _db;

  SettingsDao(this._db);

  Future<String?> get(String key) async {
    final row = await (_db.select(_db.settings)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> set(String key, String value) async {
    await _db.into(_db.settings).insertOnConflictUpdate(
      SettingsCompanion.insert(key: key, value: value),
    );
  }

  Future<String> getDialect() async => await get('audio_dialect') ?? 'us';
  Future<void> setDialect(String dialect) => set('audio_dialect', dialect);

  Future<bool> getAutoPronounce() async => (await get('auto_pronounce')) != 'false';
  Future<void> setAutoPronounce(bool enabled) => set('auto_pronounce', enabled.toString());

  Future<String> getThemeMode() async => await get('theme_mode') ?? 'system';
  Future<void> setThemeMode(String mode) => set('theme_mode', mode);
}

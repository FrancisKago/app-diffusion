import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/data/local/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test('getSetting returns null when key absent', () async {
    expect(await db.getSetting('foo'), isNull);
  });

  test('upsertSetting + getSetting round-trip', () async {
    await db.upsertSetting('first_run_battery_shown', '1');
    expect(await db.getSetting('first_run_battery_shown'), '1');
  });

  test('upsertSetting overwrites existing value', () async {
    await db.upsertSetting('k', 'a');
    await db.upsertSetting('k', 'b');
    expect(await db.getSetting('k'), 'b');
  });
}

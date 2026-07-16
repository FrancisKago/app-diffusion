import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player/data/file_hasher.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('file_hasher_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('empty file hashes to the SHA-256 empty digest', () async {
    final f = File('${tempDir.path}/empty.bin');
    await f.writeAsBytes(const []);
    expect(
      await FileHasher.sha256Hex(f.path),
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
  });

  test('known vector: "abc"', () async {
    final f = File('${tempDir.path}/abc.bin');
    await f.writeAsBytes('abc'.codeUnits);
    expect(
      await FileHasher.sha256Hex(f.path),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  test('multi-chunk file hashes identically to a one-shot hash', () async {
    // 1 MiB of repeating bytes — forces several 64 KiB stream chunks.
    final f = File('${tempDir.path}/big.bin');
    final bytes = List<int>.generate(1024 * 1024, (i) => i % 251);
    await f.writeAsBytes(bytes);
    expect(
      await FileHasher.sha256Hex(f.path),
      // Reference digest computed with `crypto`'s one-shot sha256.convert.
      await FileHasher.sha256HexOneShotForTest(bytes),
    );
  });
}

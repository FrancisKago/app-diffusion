import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

class FileHasher {
  /// SHA-256 of the file at [path], hex-encoded.
  ///
  /// Streams the file in chunks inside a background isolate: constant
  /// memory and zero jank, where the previous readAsBytes + one-shot
  /// convert loaded up to 100 MB in RAM and hashed it on the UI isolate
  /// (multi-second freeze during syncs).
  static Future<String> sha256Hex(String path) {
    return Isolate.run(() async {
      final digest = await sha256.bind(File(path).openRead()).first;
      return digest.toString();
    });
  }

  /// One-shot reference implementation, exposed for tests only.
  static Future<String> sha256HexOneShotForTest(List<int> bytes) async {
    return sha256.convert(bytes).toString();
  }
}

import 'dart:io';

import 'package:dio/dio.dart';

/// Downloads a remote URL to [target] with resume support.
///
/// Uses a `<target>.part` sibling file to accumulate bytes. Sends an
/// HTTP `Range: bytes=N-` header when a partial file already exists.
/// On full completion, renames `.part` to the final target.
///
/// On any error, the `.part` file is left in place — the next call will
/// resume from where it left off.
class MediaDownloader {
  MediaDownloader({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                // For streamed responses dio applies receiveTimeout between
                // data events, i.e. an inactivity timeout — a stalled
                // download aborts instead of hanging forever with the .part
                // file held open.
                receiveTimeout: const Duration(seconds: 30),
              ),
            );

  final Dio _dio;

  Future<void> downloadResumable({
    required String url,
    required File target,
  }) async {
    final partFile = File('${target.path}.part');
    final existingBytes =
        partFile.existsSync() ? await partFile.length() : 0;

    final headers = <String, dynamic>{
      'Accept': '*/*',
    };
    if (existingBytes > 0) {
      headers['Range'] = 'bytes=$existingBytes-';
    }

    final response = await _dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        headers: headers,
        followRedirects: true,
        // Don't throw on non-2xx so we can introspect (e.g. 416 Range Not Satisfiable
        // means our partial file is already complete).
        validateStatus: (s) => s != null && s < 500,
      ),
    );

    final status = response.statusCode ?? 0;

    // 416 Range Not Satisfiable : the .part file is at-or-past the resource
    // length on the server. Treat as "already complete" — rename .part if it
    // exists, otherwise just succeed silently.
    if (status == 416) {
      if (partFile.existsSync() && existingBytes > 0) {
        await partFile.rename(target.path);
      }
      return;
    }

    // 200 OK with a Range header means the server didn't honor the range
    // (some CDNs do this). Restart from scratch by truncating .part.
    if (status == 200 && existingBytes > 0) {
      await partFile.writeAsBytes(<int>[]);
    }

    // Make sure the .part file exists even if the stream is empty
    // (FileMode.append behavior is not guaranteed to create on all platforms).
    if (!partFile.existsSync()) {
      await partFile.create(recursive: true);
    }

    // Open .part in append mode so streamed bytes are written to the end.
    final raf = await partFile.open(mode: FileMode.append);
    try {
      await for (final chunk in response.data!.stream) {
        await raf.writeFrom(chunk);
      }
    } finally {
      await raf.close();
    }

    // Move .part to final target
    await partFile.rename(target.path);
  }
}

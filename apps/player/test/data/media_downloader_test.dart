import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:player/data/media_downloader.dart';

class _MockDio extends Mock implements Dio {}

class _FakeResponseBody extends Fake implements ResponseBody {
  _FakeResponseBody(List<List<int>> chunks)
      : stream = Stream.fromIterable(chunks.map(Uint8List.fromList));
  @override
  final Stream<Uint8List> stream;
}

void main() {
  setUpAll(() {
    registerFallbackValue(Options());
  });

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('media_downloader_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('downloadResumable downloads full file when no .part exists',
      () async {
    final dio = _MockDio();
    final target = File('${tempDir.path}/media.mp4');
    when(() => dio.get<ResponseBody>(any(), options: any(named: 'options')))
        .thenAnswer((_) async => Response<ResponseBody>(
              data: _FakeResponseBody([
                [1, 2, 3, 4],
                [5, 6, 7, 8],
              ]),
              requestOptions: RequestOptions(path: ''),
              statusCode: 200,
            ));

    final downloader = MediaDownloader(dio: dio);
    await downloader.downloadResumable(
      url: 'https://example/media.mp4',
      target: target,
    );

    expect(await target.readAsBytes(), [1, 2, 3, 4, 5, 6, 7, 8]);
    // .part file should be cleaned up
    expect(File('${target.path}.part').existsSync(), isFalse);
  });

  test('downloadResumable resumes from existing .part file', () async {
    final dio = _MockDio();
    final target = File('${tempDir.path}/media.mp4');
    final partFile = File('${target.path}.part');
    // Pre-existing partial : 4 bytes already downloaded
    await partFile.writeAsBytes([1, 2, 3, 4]);

    when(() => dio.get<ResponseBody>(any(), options: any(named: 'options')))
        .thenAnswer((invocation) async {
      final options = invocation.namedArguments[#options] as Options;
      // Verify Range header is set correctly
      expect(options.headers?['Range'], 'bytes=4-');
      // Server responds with 206 + remaining bytes
      return Response<ResponseBody>(
        data: _FakeResponseBody([
          [5, 6, 7, 8],
        ]),
        requestOptions: RequestOptions(path: ''),
        statusCode: 206,
      );
    });

    final downloader = MediaDownloader(dio: dio);
    await downloader.downloadResumable(
      url: 'https://example/media.mp4',
      target: target,
    );

    expect(await target.readAsBytes(), [1, 2, 3, 4, 5, 6, 7, 8]);
    expect(partFile.existsSync(), isFalse);
  });

  test('downloadResumable propagates DioException to caller', () async {
    final dio = _MockDio();
    final target = File('${tempDir.path}/media.mp4');
    when(() => dio.get<ResponseBody>(any(), options: any(named: 'options')))
        .thenThrow(DioException(
          requestOptions: RequestOptions(path: ''),
          message: 'connection lost',
        ));

    final downloader = MediaDownloader(dio: dio);
    expect(
      () => downloader.downloadResumable(
        url: 'https://example/media.mp4',
        target: target,
      ),
      throwsA(isA<DioException>()),
    );
  });

  test('downloadResumable returns empty file as success when stream is empty',
      () async {
    final dio = _MockDio();
    final target = File('${tempDir.path}/media.mp4');
    when(() => dio.get<ResponseBody>(any(), options: any(named: 'options')))
        .thenAnswer((_) async => Response<ResponseBody>(
              data: _FakeResponseBody(const []),
              requestOptions: RequestOptions(path: ''),
              statusCode: 200,
            ));

    final downloader = MediaDownloader(dio: dio);
    await downloader.downloadResumable(
      url: 'https://example/media.mp4',
      target: target,
    );

    expect(target.existsSync(), isTrue);
    expect(await target.length(), 0);
  });
}

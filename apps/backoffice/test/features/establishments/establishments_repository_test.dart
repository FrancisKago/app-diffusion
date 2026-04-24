import 'dart:async';

import 'package:backoffice/features/establishments/data/establishments_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockClient extends Mock implements SupabaseClient {}

class _MockBuilder extends Mock implements SupabaseQueryBuilder {}

class _MockFilterBuilder extends Mock
    implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {}

/// A fake transform builder that also behaves like a real Future by
/// delegating all Future member calls to an inner Future. This is needed
/// because `PostgrestTransformBuilder<T>` implements `Future<T>` and the
/// repository awaits the result of `.order(...)` directly.
class _FakeTransformBuilder extends Fake
    implements PostgrestTransformBuilder<List<Map<String, dynamic>>> {
  _FakeTransformBuilder(this._value);
  final List<Map<String, dynamic>> _value;
  Future<List<Map<String, dynamic>>> get _future => Future.value(_value);

  @override
  Future<R> then<R>(
    FutureOr<R> Function(List<Map<String, dynamic>>) onValue, {
    Function? onError,
  }) =>
      _future.then(onValue, onError: onError);

  @override
  Future<List<Map<String, dynamic>>> catchError(
    Function onError, {
    bool Function(Object error)? test,
  }) =>
      _future.catchError(onError, test: test);

  @override
  Future<List<Map<String, dynamic>>> whenComplete(
          FutureOr<void> Function() action) =>
      _future.whenComplete(action);

  @override
  Stream<List<Map<String, dynamic>>> asStream() => _future.asStream();

  @override
  Future<List<Map<String, dynamic>>> timeout(
    Duration timeLimit, {
    FutureOr<List<Map<String, dynamic>>> Function()? onTimeout,
  }) =>
      _future.timeout(timeLimit, onTimeout: onTimeout);
}

void main() {
  late _MockClient client;
  late EstablishmentsRepository repo;

  setUp(() {
    client = _MockClient();
    repo = EstablishmentsRepository(client);
  });

  test('list returns establishments ordered by name', () async {
    final builder = _MockBuilder();
    final select = _MockFilterBuilder();
    final ordered = _FakeTransformBuilder([
      {'id': 'e1', 'name': 'Alpha', 'timezone': 'UTC'},
      {'id': 'e2', 'name': 'Bravo', 'timezone': 'UTC'},
    ]);
    when(() => client.from('establishments')).thenAnswer((_) => builder);
    when(() => builder.select()).thenAnswer((_) => select);
    when(() => select.order('name')).thenAnswer((_) => ordered);

    final result = await repo.list();
    expect(result, hasLength(2));
    expect(result.first.name, 'Alpha');
  });
}

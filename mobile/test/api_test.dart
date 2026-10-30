import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:terrain_gn/api.dart';
import 'package:terrain_gn/session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  Future<Session> signedIn() async {
    final session = Session();
    await session.save({'accessToken': 'old', 'refreshToken': 'r1', 'user': {'id': 1}});
    return session;
  }

  test('concurrent 401s share a single refresh call', () async {
    var refreshes = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/refresh')) {
        refreshes++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return http.Response(jsonEncode({'accessToken': 'new', 'refreshToken': 'r2'}), 200);
      }
      final ok = request.headers['authorization'] == 'Bearer new';
      return http.Response(jsonEncode(ok ? {'ok': true} : {'code': 'TOKEN_INVALID'}), ok ? 200 : 401);
    });
    final api = Api(await signedIn(), client: client, baseUrl: 'http://api/v1');
    final results = await Future.wait([api.get('/me'), api.get('/me/parcels'), api.post('/parcels/1/contact')]);
    expect(results.every((r) => r['ok'] == true), isTrue);
    expect(refreshes, 1);
    expect(api.session.refreshToken, 'r2');
  });

  test('a rejected refresh signs the user out', () async {
    final client = MockClient((request) async => http.Response(jsonEncode({'code': request.url.path.endsWith('/auth/refresh') ? 'REFRESH_INVALID' : 'TOKEN_INVALID'}), 401));
    final api = Api(await signedIn(), client: client, baseUrl: 'http://api/v1');
    await expectLater(api.get('/me'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'TOKEN_INVALID')));
    expect(api.session.signedIn, isFalse);
  });

  test('retries a network failure only when the request is safe to repeat', () async {
    var calls = 0;
    final keys = <String?>{};
    final client = MockClient((request) async {
      calls++;
      keys.add(request.headers['idempotency-key']);
      if (calls.isOdd) throw http.ClientException('connection reset');
      return http.Response(jsonEncode({'id': 7}), 201);
    });
    final api = Api(Session(), client: client, baseUrl: 'http://api/v1', retryDelay: Duration.zero);
    expect((await api.post('/parcels', {'title': 'x'}, 'key-123'))['id'], 7);
    expect(keys, {'key-123'});

    calls = 0;
    await expectLater(api.post('/parcels/1/withdraw'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'NETWORK')));
    expect(calls, 1);
  });

  test('surfaces the API error code and body', () async {
    final client = MockClient((_) async => http.Response(jsonEncode({'code': 'PARCEL_OVERLAP', 'conflicts': [{'code': 'TGN-000001'}]}), 409));
    final api = Api(Session(), client: client, baseUrl: 'http://api/v1');
    await expectLater(
      api.post('/parcels', {}, 'k'),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 409).having((e) => (e.body['conflicts'] as List).length, 'conflicts', 1)),
    );
  });
}

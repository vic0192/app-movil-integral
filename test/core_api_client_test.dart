import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:biomedica_app/data/core_api_client.dart';
import 'package:biomedica_app/data/relational_account_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sends the saved bearer token to the configured API', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final authorization = Completer<String?>();
    server.listen((request) async {
      if (!authorization.isCompleted) {
        authorization.complete(
          request.headers.value(HttpHeaders.authorizationHeader),
        );
      }
      request.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'user': {'uid': 'patient-1'},
          }),
        );
      await request.response.close();
    });
    final tokenStore = _MemoryTokenStore()..token = 'stored-session-token';
    final client = CoreApiClient(
      baseUrl: 'http://${server.address.address}:${server.port}',
      tokenStore: tokenStore,
    );

    try {
      await client.get('/api/auth/me');

      expect(await authorization.future, 'Bearer stored-session-token');
    } finally {
      await server.close(force: true);
    }
  });

  test(
    'reads the current Supabase access token for each API request',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final authorizations = <String?>[];
      server.listen((request) async {
        authorizations.add(
          request.headers.value(HttpHeaders.authorizationHeader),
        );
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'reports': []}));
        await request.response.close();
      });
      var sessionToken = 'supabase-session-1';
      final client = CoreApiClient(
        baseUrl: 'http://${server.address.address}:${server.port}',
        accessTokenProvider: () async => sessionToken,
      );

      try {
        await client.get('/api/reports');
        sessionToken = 'supabase-session-2';
        await client.get('/api/reports');

        expect(authorizations, [
          'Bearer supabase-session-1',
          'Bearer supabase-session-2',
        ]);
      } finally {
        await server.close(force: true);
      }
    },
  );

  test(
    'restores the relational account profile from its saved session',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'user': {
                'uid': 'patient-1',
                'displayName': 'Ana Paciente',
                'email': 'ana@example.com',
                'role': 'patient',
                'assignedPatientUids': [],
              },
            }),
          );
        await request.response.close();
      });
      final tokenStore = _MemoryTokenStore()..token = 'saved-session';
      final repository = RelationalAccountRepository(
        api: CoreApiClient(
          baseUrl: 'http://${server.address.address}:${server.port}',
          tokenStore: tokenStore,
        ),
      );

      try {
        final profile = await repository.restoreSession();

        expect(profile?.uid, 'patient-1');
        expect(profile?.email, 'ana@example.com');
      } finally {
        await server.close(force: true);
      }
    },
  );

  test(
    'clears an expired session token when profile restore returns 401',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.unauthorized
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'message': 'La sesión venció.'}));
        await request.response.close();
      });
      final tokenStore = _MemoryTokenStore()..token = 'expired-session';
      final repository = RelationalAccountRepository(
        api: CoreApiClient(
          baseUrl: 'http://${server.address.address}:${server.port}',
          tokenStore: tokenStore,
        ),
      );

      try {
        await expectLater(
          repository.restoreSession(),
          throwsA(isA<AccountRepositoryException>()),
        );
        expect(tokenStore.token, isNull);
      } finally {
        await server.close(force: true);
      }
    },
  );

  test(
    'reports a missing API URL instead of falling back to another service',
    () {
      final client = CoreApiClient(
        tokenStore: _MemoryTokenStore(),
        baseUrl: '',
      );

      expect(
        () => client.get('/api/auth/me'),
        throwsA(
          isA<CoreApiException>().having(
            (error) => error.message,
            'message',
            contains('BIOMEDICA_CORE_API_URL'),
          ),
        ),
      );
    },
  );
}

class _MemoryTokenStore implements SessionTokenStore {
  String? token;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String value) async => token = value;

  @override
  Future<void> clearToken() async => token = null;
}

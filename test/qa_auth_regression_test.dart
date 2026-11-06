import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:coscircle/core/api/api_client.dart';
import 'package:coscircle/core/models/profile.dart';
import 'package:coscircle/core/repositories/auth_repository.dart';
import 'package:coscircle/core/repositories/event_repository.dart';
import 'package:coscircle/core/repositories/profile_repository.dart';
import 'package:coscircle/core/services/auth_state.dart';
import 'package:coscircle/core/services/oobe_service.dart';
import 'package:coscircle/features/profile/presentation/onboarding_profile_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final FutureOr<ResponseBody> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return await respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

const _photographer = UserProfile(
  id: 'A',
  nickname: 'Camera',
  profileRoles: ['photographer'],
  bio: 'Existing bio',
  regions: ['北部'],
  onboardingCompleted: true,
);

class _DelayedProfile extends InMemoryProfileRepository {
  final loaded = Completer<UserProfile?>();
  final saves = <UserProfile>[];
  Completer<UserProfile>? pendingSave;

  @override
  Future<UserProfile?> currentProfile() => loaded.future;

  @override
  Future<UserProfile> saveProfile(UserProfile profile) async {
    saves.add(profile);
    return pendingSave == null ? profile : await pendingSave!.future;
  }
}

class _Oobe extends OobeService {
  final completed = <String>[];

  @override
  Future<void> markCompleted(String userId) async => completed.add(userId);
}

class _DelayedPersistenceClient extends ApiClient {
  _DelayedPersistenceClient(HttpClientAdapter adapter)
    : super(baseUrl: 'https://api.test', adapter: adapter);
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> persistAuthToken(String? token) async {
    await super.persistAuthToken(token);
    if (token == 'A') {
      entered.complete();
      await release.future;
    }
  }
}

Future<void> _openOnboarding(
  WidgetTester tester,
  _DelayedProfile repository, {
  _Oobe? oobe,
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const OnboardingProfilePage()),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        profileRepositoryProvider.overrideWithValue(repository),
        if (oobe != null) oobeServiceProvider.overrideWithValue(oobe),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sessionExpired.value = false;
  });

  test('Q01 completed upload and save use the captured account', () async {
    final adapter = _Adapter(
      (request) => _json(
        request.path == '/uploads/image'
            ? {'url': 'https://images.test/a.png'}
            : _photographer.toJson(),
      ),
    );
    final client = ApiClient(baseUrl: 'https://api.test', adapter: adapter)
      ..setAuthToken('A');
    final operation = ApiProfileRepository(apiClient: client).beginOperation();
    addTearDown(operation.cancel);
    final url = await operation.uploadImage(
      bytes: Uint8List(1),
      mimeType: 'image/png',
    );
    await operation.saveProfile(_photographer.copyWith(avatarUrl: url));
    expect(adapter.requests.map((r) => r.path), ['/uploads/image', '/me']);
    expect(adapter.requests.map((r) => r.headers['Authorization']), [
      'Bearer A',
      'Bearer A',
    ]);
    expect(
      (adapter.requests.last.data as Map)['avatarUrl'],
      'https://images.test/a.png',
    );
  });

  for (final switchAccount in [true, false]) {
    test(
      'Q01 delayed upload cannot save after ${switchAccount ? 'account switch' : 'page cancellation'}',
      () async {
        final entered = Completer<void>();
        final upload = Completer<ResponseBody>();
        final adapter = _Adapter((request) {
          if (request.path == '/uploads/image') {
            entered.complete();
            return upload.future;
          }
          return _json(_photographer.toJson());
        });
        final client = ApiClient(baseUrl: 'https://api.test', adapter: adapter)
          ..setAuthToken('A');
        final operation = ApiProfileRepository(
          apiClient: client,
        ).beginOperation();
        final saving = () async {
          final url = await operation.uploadImage(
            bytes: Uint8List(1),
            mimeType: 'image/png',
          );
          await operation.saveProfile(_photographer.copyWith(avatarUrl: url));
        }();
        final rejected = expectLater(saving, throwsA(anything));
        await entered.future;
        if (switchAccount) {
          client.setAuthToken(null);
          client.setAuthToken('B');
        } else {
          operation.cancel();
        }
        upload.complete(_json({'url': 'https://images.test/a.png'}));
        await rejected;
        expect(adapter.requests.where((r) => r.method == 'PUT'), isEmpty);
        expect(adapter.requests.single.headers['Authorization'], 'Bearer A');
      },
    );
  }

  test('Q01 old 401 cannot expire a replacement account', () async {
    final entered = Completer<void>();
    final pending = Completer<ResponseBody>();
    final adapter = _Adapter((request) {
      if (request.path == '/old') {
        entered.complete();
        return pending.future;
      }
      return _json({});
    });
    final client = ApiClient(baseUrl: 'https://api.test', adapter: adapter);
    await client.persistAuthToken('A');
    final rejected = expectLater(
      client.get('/old'),
      throwsA(isA<DioException>()),
    );
    await entered.future;
    await client.persistAuthToken('B');
    pending.complete(_json({'error': 'unauthorized'}, 401));
    await rejected;
    await client.get('/new');
    expect(adapter.requests.last.headers['Authorization'], 'Bearer B');
    expect(
      (await SharedPreferences.getInstance()).getString('auth_token'),
      'B',
    );
    expect(sessionExpired.value, isFalse);
  });

  test(
    'Q01 stale event 401 cannot retry using or cancel the replacement session',
    () async {
      final entered = Completer<void>();
      final pending = Completer<ResponseBody>();
      final adapter = _Adapter((request) {
        entered.complete();
        return pending.future;
      });
      final client = ApiClient(baseUrl: 'https://api.test', adapter: adapter);
      await client.persistAuthToken('A');
      final rejected = expectLater(
        ApiEventRepository(apiClient: client).fetchEvents(),
        throwsA(isA<DioException>()),
      );
      await entered.future;
      await client.persistAuthToken('B');
      final sessionB = client.captureSession();
      pending.complete(_json({'error': 'unauthorized'}, 401));
      await rejected;
      expect(sessionB.isActive, isTrue);
      expect(adapter.requests, hasLength(1));
      expect(
        (await SharedPreferences.getInstance()).getString('auth_token'),
        'B',
      );
      sessionB.cancel();
    },
  );

  for (final replacement in <String?>['B', null]) {
    test(
      'Q01 login superseded during persistence cannot return a stale success ($replacement)',
      () async {
        final adapter = _Adapter(
          (_) => _json({'token': 'A', 'user': _photographer.toJson()}),
        );
        final client = _DelayedPersistenceClient(adapter);
        final rejected = expectLater(
          AuthRepository(
            apiClient: client,
          ).login(email: 'a@host.test', password: 'password'),
          throwsStateError,
        );
        await client.entered.future;
        await client.persistAuthToken(replacement);
        client.release.complete();
        await rejected;
        expect(
          (await SharedPreferences.getInstance()).getString('auth_token'),
          replacement,
        );
      },
    );
  }

  test('Q01 current 401 clears the token and expires the session', () async {
    final adapter = _Adapter((_) => _json({'error': 'unauthorized'}, 401));
    final client = ApiClient(baseUrl: 'https://api.test', adapter: adapter);
    await client.persistAuthToken('A');
    await expectLater(client.get('/me'), throwsA(isA<DioException>()));
    expect(
      (await SharedPreferences.getInstance()).getString('auth_token'),
      isNull,
    );
    expect(sessionExpired.value, isTrue);
    expect(() => client.captureSession(), throwsStateError);
  });

  test(
    'Q01 restoring a rejected bound session returns signed out, not a cancel failure',
    () async {
      final adapter = _Adapter((_) => _json({'error': 'unauthorized'}, 401));
      final client = ApiClient(baseUrl: 'https://api.test', adapter: adapter);
      await client.persistAuthToken('A');
      final otherOperation = client.captureSession();
      expect(await AuthRepository(apiClient: client).restoreToken(), isNull);
      expect(otherOperation.isActive, isFalse);
      expect(
        (await SharedPreferences.getInstance()).getString('auth_token'),
        isNull,
      );
      expect(sessionExpired.value, isTrue);
    },
  );

  test('Q01 queued token writes converge to the latest session', () async {
    final client = ApiClient(baseUrl: 'https://api.test');
    await Future.wait([
      client.persistAuthToken('A'),
      client.persistAuthToken(null),
      client.persistAuthToken('B'),
    ]);
    expect(
      (await SharedPreferences.getInstance()).getString('auth_token'),
      'B',
    );
    final operation = client.captureSession();
    expect(operation.isActive, isTrue);
    operation.cancel();
  });

  test('Q01 delayed logout cannot clear a newly logged in account', () async {
    final entered = Completer<void>();
    final pending = Completer<ResponseBody>();
    final adapter = _Adapter((request) {
      if (request.path == '/auth/logout') {
        entered.complete();
        return pending.future;
      }
      return _json({});
    });
    final client = ApiClient(baseUrl: 'https://api.test', adapter: adapter);
    await client.persistAuthToken('A');
    final logout = AuthRepository(apiClient: client).logout();
    await entered.future;
    await client.persistAuthToken('B');
    pending.complete(_json({}));
    await logout;
    await client.get('/me');
    expect(adapter.requests.last.headers['Authorization'], 'Bearer B');
    expect(
      (await SharedPreferences.getInstance()).getString('auth_token'),
      'B',
    );
  });

  test(
    'Q01 restoring while a token write is queued preserves the new account',
    () async {
      SharedPreferences.setMockInitialValues({'auth_token': 'A'});
      final adapter = _Adapter((_) => _json({}));
      final client = ApiClient(baseUrl: 'https://api.test', adapter: adapter);
      final saving = client.persistAuthToken('B');
      final restored = await AuthRepository(apiClient: client).restoreToken();
      await saving;
      expect(restored, 'B');
      expect(adapter.requests.single.headers['Authorization'], 'Bearer B');
      expect(
        (await SharedPreferences.getInstance()).getString('auth_token'),
        'B',
      );
    },
  );

  test('Q01 late login response cannot replace a newer session', () async {
    final entered = Completer<void>();
    final pending = Completer<ResponseBody>();
    final adapter = _Adapter((request) {
      if (request.path == '/auth/login') {
        entered.complete();
        return pending.future;
      }
      return _json({});
    });
    final client = ApiClient(baseUrl: 'https://api.test', adapter: adapter);
    final rejected = expectLater(
      AuthRepository(
        apiClient: client,
      ).login(email: 'a@host.test', password: 'password'),
      throwsStateError,
    );
    await entered.future;
    await client.persistAuthToken('B');
    pending.complete(_json({'token': 'A', 'user': _photographer.toJson()}));
    await rejected;
    await client.get('/me');
    expect(adapter.requests.last.headers['Authorization'], 'Bearer B');
    expect(
      (await SharedPreferences.getInstance()).getString('auth_token'),
      'B',
    );
  });

  test(
    'Q03 incorrect LINE binding password leaves the session usable',
    () async {
      final adapter = _Adapter(
        (request) => request.path.endsWith('/line')
            ? _json({'error': 'reauthentication_required'}, 403)
            : _json({}),
      );
      final client = ApiClient(baseUrl: 'https://api.test', adapter: adapter);
      await client.persistAuthToken('A');
      await expectLater(
        AuthRepository(
          apiClient: client,
        ).linkLine(accessToken: 'line-fixture', password: 'wrong'),
        throwsA(isA<DioException>()),
      );
      await client.get('/me');
      expect(adapter.requests.last.headers['Authorization'], 'Bearer A');
      expect(
        (await SharedPreferences.getInstance()).getString('auth_token'),
        'A',
      );
      expect(sessionExpired.value, isFalse);
    },
  );

  test('Q04 registration rejects unrecoverable email before sending', () async {
    final adapter = _Adapter((_) => _json({}));
    final repository = AuthRepository(
      apiClient: ApiClient(baseUrl: 'https://api.test', adapter: adapter),
    );
    await expectLater(
      repository.register(
        nickname: 'QA',
        email: 'qa@host',
        password: 'password',
      ),
      throwsArgumentError,
    );
    expect(adapter.requests, isEmpty);
    expect(
      normalizeRegistrationEmail(' QA+Tag@Host.Test '),
      'qa+tag@host.test',
    );
    expect(normalizeRegistrationEmail('${'a' * 182}@host.test'), isNull);
  });

  testWidgets(
    'Q06 skip waits for the existing profile and preserves its roles',
    (tester) async {
      final repository = _DelayedProfile();
      await _openOnboarding(tester, repository);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '略過'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('略過'));
      await tester.pump();
      expect(repository.saves, isEmpty);
      repository.loaded.complete(_photographer);
      await tester.pumpAndSettle();
      await tester.tap(find.text('略過'));
      await tester.pumpAndSettle();
      expect(repository.saves, hasLength(1));
      final saved = repository.saves.single;
      expect(saved.profileRoles, ['photographer']);
      expect(saved.nickname, 'Camera');
      expect(saved.bio, 'Existing bio');
      expect(saved.regions, ['北部']);
      expect(saved.onboardingCompleted, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Q06 failed profile load keeps skip disabled', (tester) async {
    final repository = _DelayedProfile();
    await _openOnboarding(tester, repository);
    repository.loaded.completeError(StateError('load failed'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '略過'))
          .onPressed,
      isNull,
    );
    expect(find.text('重新載入個人資料'), findsOneWidget);
    expect(repository.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Q06 disposed onboarding ignores a late profile load', (
    tester,
  ) async {
    final repository = _DelayedProfile();
    await _openOnboarding(tester, repository);
    await tester.pumpWidget(const SizedBox());
    repository.loaded.complete(_photographer);
    await tester.pumpAndSettle();
    expect(repository.saves, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Q01 disposed onboarding does not complete OOBE after a delayed save',
    (tester) async {
      final repository = _DelayedProfile()
        ..pendingSave = Completer<UserProfile>();
      final oobe = _Oobe();
      await _openOnboarding(tester, repository, oobe: oobe);
      repository.loaded.complete(_photographer);
      await tester.pumpAndSettle();
      await tester.tap(find.text('略過'));
      await tester.pump();
      expect(repository.saves, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      repository.pendingSave!.complete(_photographer);
      await tester.pumpAndSettle();
      expect(oobe.completed, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}

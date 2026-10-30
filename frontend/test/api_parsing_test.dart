import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laafi_ma/core/network/api_client.dart';
import 'package:laafi_ma/core/storage/json_store.dart';
import 'package:laafi_ma/core/storage/token_storage.dart';
import 'package:laafi_ma/features/assistant/data/assistant_models.dart';
import 'package:laafi_ma/features/assistant/data/assistant_repository.dart';
import 'package:laafi_ma/features/assistant/data/danger_detector.dart';
import 'package:laafi_ma/features/help/data/help_repository.dart';
import 'package:laafi_ma/features/learn/data/learn_repository.dart';
import 'package:laafi_ma/features/stats/stats_service.dart';

import 'helpers/fake_http.dart';

/// Exemple de réponse copié de docs/API.md (`POST /assistant/ask-text`).
const askExample = {
  'transcript': null,
  'question_fr': null,
  'matched': true,
  'confidence': 0.82,
  'entry': {
    'id': 'e1',
    'topic': 'grossesse',
    'question': 'Question canonique dans la langue demandée',
    'answer': 'Réponse validée dans la langue demandée',
    'audio_url': '/media/kb/e1.wav',
    'audio_kind': 'synthetic',
  },
  'danger': true,
  'danger_signs': [
    {'id': 'd1', 'label': 'Saignement pendant la grossesse', 'advice': 'Allez immédiatement au centre de santé.'},
  ],
  'fallback_message': null,
};

const dangerSignsExample = [
  {
    'id': 'd1',
    'label': 'Saignement pendant la grossesse',
    'advice': 'Allez immédiatement au centre de santé.',
    'keywords': ['saigne', 'saignement', 'sang'],
  },
  {
    'id': 'd2',
    'label': 'Fièvre',
    'advice': 'Consultez.',
    'keywords': ['fievre', 'corps chaud'],
  },
];

void main() {
  group('Assistant', () {
    test('ask-text : corps et analyse de la réponse', () async {
      final api = fakeApi((_) => jsonResponse(askExample));
      final repo = AssistantRepository(api.client.dio, MemoryJsonStore());
      final answer = await repo.askText('Je saigne', 'mos');
      final request = api.adapter.requests.single;
      expect(request.path, '/assistant/ask-text');
      expect(request.data, {'text': 'Je saigne', 'lang': 'mos'});
      expect(request.headers.containsKey('Authorization'), isFalse);
      expect(answer.matched, isTrue);
      expect(answer.confidence, 0.82);
      expect(answer.entry!.isSynthetic, isTrue);
      expect(answer.entry!.audioUrl, '/media/kb/e1.wav');
      expect(answer.danger, isTrue);
      expect(answer.dangerSigns.single.label, 'Saignement pendant la grossesse');
    });

    test('ask-text sans correspondance : message de repli', () async {
      final api = fakeApi(
        (_) => jsonResponse({
          'transcript': null,
          'question_fr': 'question',
          'matched': false,
          'confidence': 0.2,
          'entry': null,
          'danger': false,
          'danger_signs': [],
          'fallback_message': 'Demandez à votre agent de santé',
        }),
      );
      final answer = await AssistantRepository(api.client.dio, MemoryJsonStore()).askText('?', 'fr');
      expect(answer.entry, isNull);
      expect(answer.fallbackMessage, 'Demandez à votre agent de santé');
    });

    test('ask-voice : multipart audio + lang ; 503 -> message du serveur', () async {
      final api = fakeApi((_) => jsonResponse({'detail': 'Assistant vocal indisponible'}, status: 503));
      final repo = AssistantRepository(api.client.dio, MemoryJsonStore());
      await expectLater(
        repo.askVoice(Uint8List.fromList([1, 2]), 'q.wav', 'dyu'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 503)),
      );
      final form = api.adapter.requests.single.data as FormData;
      expect(form.fields.map((f) => '${f.key}=${f.value}'), ['lang=dyu']);
      expect(form.files.single.key, 'audio');
    });

    test('FAQ et signes de danger mis en cache pour hors connexion', () async {
      final api = fakeApi((request) {
        if (request.path == '/assistant/faq') {
          expect(request.queryParameters, {'lang': 'mos'});
          return jsonResponse({
            'version': '2026-10-29T10:00:00Z',
            'entries': [
              {
                'id': 'f1',
                'topic': 'grossesse',
                'question': 'Q ?',
                'answer': 'R.',
                'audio_url': null,
                'audio_kind': null,
                'is_danger_topic': true,
              },
            ],
          });
        }
        final lang = request.queryParameters['lang'];
        return jsonResponse([
          for (final s in dangerSignsExample) {...s, 'label': '${s['label']} ($lang)'},
        ]);
      });
      final cache = MemoryJsonStore();
      final repo = AssistantRepository(api.client.dio, cache);
      await repo.downloadForOffline('mos');
      expect(api.adapter.requests.map((r) => '${r.path}?${r.queryParameters['lang']}'), [
        '/assistant/faq?mos',
        '/assistant/danger-signs?fr',
        '/assistant/danger-signs?mos',
      ]);
      final faq = (await repo.cachedFaq('mos'))!.$1;
      expect(faq.entries.single.isDangerTopic, isTrue);
      final signs = await repo.offlineDangerSigns('mos');
      expect(signs.first.label, 'Saignement pendant la grossesse (mos)');
      expect(signs.first.keywords, ['saigne', 'saignement', 'sang']);
    });
  });

  group('Détection hors connexion', () {
    final signs = [for (final s in dangerSignsExample) DangerSign.fromJson(s)];

    test('mot-clé au début d\'un mot, sans accents ni majuscules', () {
      expect(detectDangerSigns('Je SAIGNE beaucoup', signs).map((s) => s.id), ['d1']);
      expect(detectDangerSigns('des saignements depuis hier', signs).map((s) => s.id), ['d1']);
      expect(detectDangerSigns("J'ai de la fièvre et le corps chaud", signs).map((s) => s.id), ['d2']);
      expect(detectDangerSigns('Je vais bien, merci', signs), isEmpty);
      // « sang » ne doit pas se déclencher au milieu d'un mot.
      expect(detectDangerSigns('elle est passante', signs), isEmpty);
    });
  });

  test('Annuaire : services actifs, « non confirmé » si verified_at nul, cache', () async {
    final api = fakeApi(
      (_) => jsonResponse([
        {
          'id': 's1',
          'name': 'Ligne verte',
          'category': 'hotline',
          'phone': '80 00 12 87',
          'city': null,
          'region': null,
          'address': null,
          'hours': null,
          'free_call': true,
          'languages': ['fr', 'mos', 'dyu'],
          'source_url': null,
          'verified_at': null,
          'active': true,
        },
        {
          'id': 's2',
          'name': 'Inactif',
          'category': 'health',
          'phone': '1',
          'free_call': false,
          'languages': [],
          'verified_at': '2026-10-01',
          'active': false,
        },
      ]),
    );
    final cache = MemoryJsonStore();
    final repo = HelpRepository(api.client.dio, cache);
    final services = await repo.fetchServices();
    expect(services.map((s) => s.id), ['s1']);
    expect(services.single.verified, isFalse);
    expect(services.single.freeCall, isTrue);
    final hotline = await repo.firstCached((s) => s.category == 'hotline' && s.freeCall);
    expect(hotline!.phone, '80 00 12 87');
    expect(await repo.firstCached((s) => s.category == 'health'), isNull);
  });

  test('Capsules : traductions, quiz, repli en français', () async {
    final api = fakeApi(
      (_) => jsonResponse([
        {
          'id': 'c2',
          'track': 'droits',
          'status': 'validated',
          'order': 2,
          'translations': {
            'fr': {'title': 'Titre 2', 'text': 'Texte', 'audio_url': null, 'audio_kind': null},
          },
          'quiz': [],
          'license': 'CC-BY-4.0',
          'validated_by': null,
          'validated_at': null,
        },
        {
          'id': 'c1',
          'track': 'bien_etre',
          'status': 'validated',
          'order': 1,
          'translations': {
            'fr': {'title': 'Titre', 'text': 'Texte', 'audio_url': '/media/capsules/c1.wav', 'audio_kind': 'human'},
            'mos': {'title': 'Zu-sobga', 'text': 'Gʋlsg', 'audio_url': null, 'audio_kind': null},
          },
          'quiz': [
            {
              'question': {'fr': 'Vrai ?'},
              'choices': [
                {'fr': 'Oui'},
                {'fr': 'Non'},
              ],
              'correct_index': 1,
            },
          ],
          'license': 'CC-BY-4.0',
          'validated_by': null,
          'validated_at': null,
        },
      ]),
    );
    final repo = LearnRepository(api.client.dio, MemoryJsonStore());
    final capsules = await repo.fetch('mos');
    expect(api.adapter.requests.single.queryParameters, {'lang': 'mos'});
    expect(capsules.map((c) => c.id), ['c1', 'c2']);
    expect(capsules.first.textIn('mos').title, 'Zu-sobga');
    expect(capsules.last.textIn('mos').title, 'Titre 2');
    expect(capsules.last.langShown('mos'), 'fr');
    final quiz = capsules.first.quiz.single;
    expect(quiz.questionIn('mos'), 'Vrai ?');
    expect(quiz.choiceIn(quiz.correctIndex, 'fr'), 'Non');
    expect((await repo.cached('mos'))!.$1, hasLength(2));
  });

  group('Statistiques anonymes', () {
    test('rien n\'est noté sans accord', () async {
      final api = fakeApi((_) => emptyResponse(202));
      final queue = MemoryJsonStore();
      final stats = StatsService(
        dio: api.client.dio,
        queue: queue,
        optedIn: () => false,
        lang: () => 'fr',
        districtId: () => null,
      );
      await stats.track(StatEvent.helpOpened);
      expect(await queue.list(StatsService.collection), isEmpty);
      expect(api.adapter.requests, isEmpty);
    });

    test('envoi par lots de 100, date seulement, aucun identifiant', () async {
      var offline = true;
      final api = fakeApi(
        (_) => offline
            ? throw DioException.connectionError(requestOptions: RequestOptions(), reason: 'x')
            : emptyResponse(202),
      );
      final queue = MemoryJsonStore();
      final stats = StatsService(
        dio: api.client.dio,
        queue: queue,
        optedIn: () => true,
        lang: () => 'dyu',
        districtId: () => 'd-1',
        clock: () => DateTime(2026, 10, 29, 23, 59),
      );
      for (var i = 0; i < 150; i++) {
        await stats.track(StatEvent.questionAsked);
      }
      // Tentative hors connexion : rien n'est perdu.
      expect(await stats.flush(), 0);
      expect(await queue.list(StatsService.collection), hasLength(150));

      offline = false;
      api.adapter.requests.clear();
      expect(await stats.flush(), 150);
      expect(api.adapter.requests, hasLength(2));
      final first = (api.adapter.requests.first.data as Map)['events'] as List;
      expect(first, hasLength(100));
      expect(first.first, {'type': 'question_asked', 'lang': 'dyu', 'district_id': 'd-1', 'occurred_on': '2026-10-29'});
      expect(await queue.list(StatsService.collection), isEmpty);
    });
  });

  test('Jetons : chaque requête porte SON jeton, jamais l\'autre', () async {
    final api = fakeApi((_) => jsonResponse({}));
    await api.tokens.saveToken(TokenKind.device, 'woman');
    await api.tokens.saveToken(TokenKind.staff, 'agent');
    await api.client.dio.get('/a', options: scoped(AuthScope.device));
    await api.client.dio.get('/b', options: scoped(AuthScope.staff));
    await api.client.dio.get('/c');
    expect(api.adapter.requests.map((r) => r.headers['Authorization']), ['Bearer woman', 'Bearer agent', null]);
  });

  test('Session agent expirée : jeton agent effacé, jeton de la femme gardé', () async {
    var expired = 0;
    final adapter = FakeAdapter((_) => jsonResponse({'detail': 'expired'}, status: 401));
    final dio = Dio(BaseOptions(baseUrl: 'http://api.test'))..httpClientAdapter = adapter;
    final tokens = fakeApi((_) => emptyResponse(200)).tokens;
    final client = ApiClient(tokens, dio: dio, onStaffUnauthorized: () => expired++);
    await tokens.saveToken(TokenKind.staff, 'agent');
    await tokens.saveToken(TokenKind.device, 'woman');
    await expectLater(client.dio.get('/agent/summary', options: scoped(AuthScope.staff)), throwsA(isA<DioException>()));
    expect(expired, 1);
    expect(await tokens.readToken(TokenKind.staff), isNull);
    expect(await tokens.readToken(TokenKind.device), 'woman');
  });
}

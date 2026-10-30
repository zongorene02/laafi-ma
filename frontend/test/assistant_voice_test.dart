// Assistant : confirmation de la question vocale (`/assistant/transcribe`),
// phrase d'aide secrète vérifiée SUR LE TÉLÉPHONE, « Avez-vous compris ? ».

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laafi_ma/core/providers.dart';
import 'package:laafi_ma/core/security/secret_phrase.dart';
import 'package:laafi_ma/core/security/session.dart';
import 'package:laafi_ma/core/settings/app_settings.dart';
import 'package:laafi_ma/core/storage/json_store.dart';
import 'package:laafi_ma/core/storage/secret_store.dart';
import 'package:laafi_ma/core/storage/vault.dart';
import 'package:laafi_ma/features/assistant/data/assistant_models.dart';
import 'package:laafi_ma/features/assistant/data/assistant_repository.dart';
import 'package:laafi_ma/features/assistant/presentation/assistant_controller.dart';
import 'package:laafi_ma/features/stats/stats_service.dart';

import 'helpers/fake_http.dart';

const _answer = {
  'transcript': null,
  'question_fr': null,
  'matched': true,
  'confidence': 0.9,
  'entry': {
    'id': 'e1',
    'topic': 'grossesse',
    'question': 'Question validée',
    'answer': 'Réponse validée',
    'audio_url': null,
    'audio_kind': null,
  },
  'danger': false,
  'danger_signs': [],
  'fallback_message': null,
};

class _Harness {
  _Harness({this.transcribeStatus = 200, this.transcript = 'M yãka pʋga zabre', this.lang = 'mos'});

  final int transcribeStatus;
  final String transcript;
  final String lang;
  final secrets = MemorySecretStore();
  final statsQueue = MemoryJsonStore();
  late final api = fakeApi((request) {
    switch (request.path) {
      case '/assistant/transcribe':
        return transcribeStatus == 200
            ? jsonResponse({'transcript': transcript, 'question_fr': 'J\'ai mal au ventre'})
            : jsonResponse({'detail': 'Not Found'}, status: transcribeStatus);
      case '/assistant/ask-text':
        return jsonResponse(_answer);
      case '/assistant/ask-voice':
        return jsonResponse({..._answer, 'transcript': transcript});
      default:
        // `/events` hors connexion : les événements restent dans la file.
        return emptyResponse(503);
    }
  });

  late final container = ProviderContainer(
    overrides: [
      secretStoreProvider.overrideWithValue(secrets),
      vaultProvider.overrideWithValue(
        VaultService(secrets, opener: (_, _) async => MemoryJsonStore(), deleter: (_) async {}),
      ),
      metaStoreProvider.overrideWithValue(MemoryJsonStore()),
      cacheStoreProvider.overrideWithValue(MemoryJsonStore()),
      initialSettingsProvider.overrideWithValue(AppSettings(onboarded: true, lang: lang)),
      apiClientProvider.overrideWithValue(api.client),
      statsServiceProvider.overrideWith(
        (ref) => StatsService(
          dio: api.client.dio,
          queue: statsQueue,
          optedIn: () => true,
          lang: () => lang,
          districtId: () => null,
        ),
      ),
    ],
  );

  AssistantController get controller => container.read(assistantControllerProvider.notifier);
  AssistantState get state => container.read(assistantControllerProvider);

  List<String> get paths => [for (final r in api.adapter.requests) r.path];
  List<String> get assistantPaths => paths.where((p) => p.startsWith('/assistant')).toList();

  Future<List<String>> events() async => [for (final e in await statsQueue.list(StatsService.collection)) e['type']];

  Future<void> open({ProfileKind kind = ProfileKind.real, int profile = 1, String? phrase}) async {
    if (phrase != null) await SecretPhraseStore(secrets).write(profile, phrase);
    await container.read(sessionProvider.notifier).unlock(kind, profile: profile);
    container.listen(assistantControllerProvider, (_, _) {});
  }
}

final _wav = Uint8List.fromList(List.filled(64, 0));

void main() {
  group('Question vocale confirmée', () {
    test('transcribe -> « Vous avez demandé » -> Oui -> ask-text dans la même langue', () async {
      final h = _Harness();
      await h.open();
      await h.controller.sendVoice(_wav);
      expect(h.state.status, AssistantStatus.confirming);
      expect(h.state.transcript, 'M yãka pʋga zabre');
      expect(h.assistantPaths, ['/assistant/transcribe']);

      await h.controller.confirmTranscript();
      expect(h.state.status, AssistantStatus.done);
      expect(h.state.question, 'M yãka pʋga zabre');
      expect(h.state.voice, isTrue);
      final ask = h.api.adapter.requests.firstWhere((r) => r.path == '/assistant/ask-text');
      expect(ask.data, {'text': 'M yãka pʋga zabre', 'lang': 'mos'});
      expect(await h.events(), containsAll([StatEvent.questionAsked, StatEvent.questionVoice]));
    });

    test('« Non, je répète » : retour au micro, rien d\'envoyé', () async {
      final h = _Harness();
      await h.open();
      await h.controller.sendVoice(_wav);
      h.controller.rejectTranscript();
      expect(h.state.status, AssistantStatus.idle);
      expect(h.assistantPaths, ['/assistant/transcribe']);
    });

    test('transcribe absent (404) : repli sur ask-voice', () async {
      final h = _Harness(transcribeStatus: 404);
      await h.open();
      await h.controller.sendVoice(_wav);
      expect(h.assistantPaths, ['/assistant/transcribe', '/assistant/ask-voice']);
      expect(h.state.status, AssistantStatus.done);
      expect(await h.events(), contains(StatEvent.questionVoice));
    });

    test('modèles absents (503) : message clair, pas de repli', () async {
      final h = _Harness(transcribeStatus: 503);
      await h.open();
      await h.controller.sendVoice(_wav);
      expect(h.state.status, AssistantStatus.error);
      expect(h.assistantPaths, ['/assistant/transcribe']);
    });

    test('question écrite : pas d\'événement question_voice', () async {
      final h = _Harness(lang: 'fr');
      await h.open();
      await h.controller.askText('J\'ai mal au ventre');
      final events = await h.events();
      expect(events, contains(StatEvent.questionAsked));
      expect(events, isNot(contains(StatEvent.questionVoice)));
    });
  });

  group('Phrase d\'aide secrète', () {
    test('tapée : RIEN n\'est envoyé, la page Aide s\'ouvre', () async {
      final h = _Harness(lang: 'fr');
      await h.open(phrase: 'Je prépare le tô ce soir');
      await h.controller.askText('je prepare le to ce soir.');
      expect(h.state.openHelp, isTrue);
      expect(h.state.answer, isNull);
      expect(h.assistantPaths, isEmpty);
      expect(await h.events(), isEmpty);
    });

    test('dite au micro : reconnue après transcribe, pas de ask-text', () async {
      final h = _Harness(transcript: 'je prépare le tô ce soir');
      await h.open(phrase: 'Je prépare le tô ce soir');
      await h.controller.sendVoice(_wav);
      expect(h.state.openHelp, isTrue);
      expect(h.state.transcript, isNull);
      expect(h.assistantPaths, ['/assistant/transcribe']);
    });

    test('reconnue aussi par la traduction française (question en mooré)', () async {
      final h = _Harness();
      await h.open(phrase: 'j\'ai mal au ventre');
      await h.controller.sendVoice(_wav);
      expect(h.state.openHelp, isTrue);
    });

    test('phrase du profil 2 : sans effet dans le profil 1', () async {
      final h = _Harness(lang: 'fr');
      await h.open(profile: 1);
      await SecretPhraseStore(h.secrets).write(2, 'Je prépare le tô ce soir');
      await h.controller.askText('Je prépare le tô ce soir');
      expect(h.state.openHelp, isFalse);
      expect(h.assistantPaths, ['/assistant/ask-text']);
    });

    test('profil leurre : pas de phrase d\'aide', () async {
      final h = _Harness(lang: 'fr');
      await SecretPhraseStore(h.secrets).write(1, 'Je prépare le tô ce soir');
      await h.open(kind: ProfileKind.decoy);
      await h.controller.askText('Je prépare le tô ce soir');
      expect(h.state.openHelp, isFalse);
    });
  });

  group('« Avez-vous compris ? »', () {
    test('une seule réponse comptée par réponse', () async {
      final h = _Harness(lang: 'fr');
      await h.open();
      await h.controller.askText('Question');
      await h.controller.markUnderstood(false);
      await h.controller.markUnderstood(true);
      expect(h.state.understood, isFalse);
      final events = await h.events();
      expect(events.where((e) => e == StatEvent.answerNotUnderstood), hasLength(1));
      expect(events, isNot(contains(StatEvent.answerUnderstood)));
    });

    test('rien à compter sans réponse affichée', () async {
      final h = _Harness(lang: 'fr');
      await h.open();
      await h.controller.markUnderstood(true);
      expect(await h.events(), isEmpty);
    });
  });

  group('Contrat d\'API', () {
    test('transcribe : multipart audio + lang, champs lus', () async {
      final api = fakeApi((_) => jsonResponse({'transcript': 'texte reconnu', 'question_fr': null}));
      final result = await AssistantRepository(api.client.dio, MemoryJsonStore()).transcribe(_wav, 'q.wav', 'fr');
      expect(result!.transcript, 'texte reconnu');
      expect(result.questionFr, isNull);
      final request = api.adapter.requests.single;
      expect(request.path, '/assistant/transcribe');
      final form = request.data as FormData;
      expect(form.fields.map((f) => '${f.key}=${f.value}'), ['lang=fr']);
      expect(form.files.single.key, 'audio');
    });

    test('transcribe 404 -> null ; 503 -> erreur', () async {
      final notFound = fakeApi((_) => jsonResponse({'detail': 'Not Found'}, status: 404));
      expect(await AssistantRepository(notFound.client.dio, MemoryJsonStore()).transcribe(_wav, 'q.wav', 'fr'), isNull);
      final down = fakeApi((_) => jsonResponse({'detail': 'Assistant vocal indisponible'}, status: 503));
      await expectLater(
        AssistantRepository(down.client.dio, MemoryJsonStore()).transcribe(_wav, 'q.wav', 'fr'),
        throwsA(anything),
      );
    });

    test('signes de danger : agent_questions / refer_when, gardés en cache', () async {
      final api = fakeApi(
        (request) => request.path == '/assistant/faq'
            ? jsonResponse({'version': null, 'entries': []})
            : jsonResponse([
                {
                  'id': 'd1',
                  'label': request.queryParameters['lang'] == 'mos' ? 'Zĩim' : 'Saignement',
                  'advice': 'Conseil',
                  'keywords': ['saigne'],
                  'agent_questions': ['Depuis quand ?', ' '],
                  'refer_when': request.queryParameters['lang'] == 'mos' ? null : 'Toujours',
                },
                {'id': 'd2', 'label': 'Fièvre', 'advice': 'A', 'keywords': [], 'agent_questions': [], 'refer_when': ''},
              ]),
      );
      final repo = AssistantRepository(api.client.dio, MemoryJsonStore());
      await repo.downloadForOffline('mos');
      final french = await repo.cachedDangerSigns('fr');
      expect(french.first.agentQuestions, ['Depuis quand ?']);
      expect(french.first.referWhen, 'Toujours');
      expect(french.first.hasDecisionAid, isTrue);
      expect(french.last.referWhen, isNull);
      expect(french.last.hasDecisionAid, isFalse);
      final merged = await repo.offlineDangerSigns('mos');
      expect(merged.first.label, 'Zĩim');
      expect(merged.first.agentQuestions, ['Depuis quand ?']);
      expect(DangerSign.fromJson(french.first.toJson()).referWhen, 'Toujours');
    });
  });
}

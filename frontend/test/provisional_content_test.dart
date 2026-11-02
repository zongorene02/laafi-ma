/// Contenu `provisional` (OMS, UNFPA, relu par aucune sage-femme) : lecture du
/// champ, conservation dans les caches, mention affichée et lue à voix haute,
/// repli sur le français des capsules.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laafi_ma/core/l10n/strings.dart';
import 'package:laafi_ma/core/storage/json_store.dart';
import 'package:laafi_ma/features/assistant/data/assistant_models.dart';
import 'package:laafi_ma/features/assistant/data/assistant_repository.dart';
import 'package:laafi_ma/features/assistant/presentation/assistant_screen.dart';
import 'package:laafi_ma/features/assistant/presentation/danger_banner.dart';
import 'package:laafi_ma/features/learn/data/learn_repository.dart';
import 'package:laafi_ma/shared/widgets/listen_button.dart';
import 'package:laafi_ma/shared/widgets/provisional_note.dart';

import 'helpers/fake_http.dart';

const _source = 'OMS, Malaria — https://www.who.int/';

Map<String, dynamic> _faqJson({bool? provisional, String? source}) => {
  'id': 'k1',
  'topic': 'grossesse',
  'question': 'Question ?',
  'answer': 'Réponse.',
  'audio_url': null,
  'audio_kind': null,
  'is_danger_topic': false,
  'provisional': ?provisional,
  'source': ?source,
};

Map<String, dynamic> _capsuleJson() => {
  'id': 'c1',
  'track': 'general',
  'order': 1,
  'translations': {
    'fr': {'title': 'Titre', 'text': 'Texte.', 'audio_url': '/media/fr.wav', 'audio_kind': 'synthetic'},
    'mos': {'title': '', 'text': '', 'audio_url': null, 'audio_kind': null},
    'dyu': {'title': '', 'text': '', 'audio_url': null, 'audio_kind': null},
  },
  'quiz': const [],
  'license': 'CC-BY-4.0',
  'provisional': true,
};

Widget _app(Widget child) => ProviderScope(
  child: MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  group('Lecture de `provisional` et `source`', () {
    test('valeurs par défaut pour les anciens caches', () {
      final answer = AnswerEntry.fromJson({'id': 'a', 'topic': 't'});
      expect(answer.provisional, isFalse);
      expect(answer.source, isNull);
      final faq = FaqEntry.fromJson(_faqJson());
      expect(faq.provisional, isFalse);
      expect(faq.source, isNull);
      expect(DangerSign.fromJson({'id': 'd'}).provisional, isFalse);
      expect(DangerSignHit.fromJson({'id': 'd'}).source, isNull);
      expect(Capsule.fromJson({'id': 'c'}).provisional, isFalse);
    });

    test('réponse de l\'assistant et signe détecté', () {
      final answer = AssistantAnswer.fromJson({
        'matched': true,
        'danger': true,
        'entry': {'id': 'a', 'topic': 't', 'provisional': true, 'source': _source},
        'danger_signs': [
          {'id': 'd', 'label': 'L', 'advice': 'A', 'provisional': true, 'source': _source},
        ],
      });
      expect(answer.entry!.provisional, isTrue);
      expect(answer.entry!.source, _source);
      expect(answer.dangerSigns.single.provisional, isTrue);
      expect(answer.dangerSigns.single.source, _source);
    });

    test('FAQ et signes gardent la mention dans le cache', () {
      final faq = FaqEntry.fromJson(FaqEntry.fromJson(_faqJson(provisional: true, source: _source)).toJson());
      expect(faq.provisional, isTrue);
      expect(faq.source, _source);

      final json = {'id': 'd', 'label': 'L', 'advice': 'A', 'provisional': true, 'source': _source};
      final sign = DangerSign.fromJson(DangerSign.fromJson(json).toJson());
      expect(sign.provisional, isTrue);
      expect(sign.toHit().provisional, isTrue);
      expect(sign.toHit().source, _source);
    });

    test('la fusion hors connexion garde la mention', () async {
      final api = fakeApi((request) {
        if (request.path == '/assistant/faq') return jsonResponse({'version': '1', 'entries': const []});
        return jsonResponse([
          {
            'id': 'd',
            'label': 'L',
            'advice': 'A',
            'keywords': ['sang'],
            'provisional': true,
            'source': _source,
          },
        ]);
      });
      final repo = AssistantRepository(api.client.dio, MemoryJsonStore());
      await repo.downloadForOffline('mos');
      final sign = (await repo.offlineDangerSigns('mos')).single;
      expect(sign.provisional, isTrue);
      expect(sign.source, _source);
    });
  });

  group('Capsules', () {
    test('une langue vide retombe sur le français', () {
      final capsule = Capsule.fromJson(_capsuleJson());
      expect(capsule.provisional, isTrue);
      expect(capsule.textIn('mos').title, 'Titre');
      expect(capsule.textIn('mos').audioUrl, '/media/fr.wav');
      expect(capsule.langShown('mos'), 'fr');
      expect(capsule.langShown('fr'), 'fr');
    });
  });

  group('Affichage', () {
    testWidgets('réponse sans audio : mention visible, lue, voix française', (tester) async {
      await tester.pumpWidget(_app(const AudioAnswerRow(text: 'Réponse.', lang: 'mos', provisional: true)));
      final button = tester.widget<ListenButton>(find.byType(ListenButton));
      expect(button.text, 'Réponse. ${S.provisionalNote}');
      expect(button.contentLang, 'fr');
    });

    testWidgets('réponse avec audio du serveur : la mention garde son bouton', (tester) async {
      await tester.pumpWidget(
        _app(
          const AudioAnswerRow(
            audioUrl: '/media/kb.wav',
            audioKind: 'synthetic',
            text: 'Réponse.',
            lang: 'fr',
            provisional: true,
          ),
        ),
      );
      expect(tester.widget<ListenButton>(find.byType(ListenButton)).text, S.provisionalNote);
    });

    testWidgets('contenu validé : ni mention ni changement de voix', (tester) async {
      await tester.pumpWidget(_app(const AudioAnswerRow(text: 'Réponse.', lang: 'mos')));
      final button = tester.widget<ListenButton>(find.byType(ListenButton));
      expect(button.text, 'Réponse.');
      expect(button.contentLang, 'mos');
    });

    testWidgets('FAQ : mention et source sous la réponse', (tester) async {
      final entry = FaqEntry.fromJson(_faqJson(provisional: true, source: _source));
      await tester.pumpWidget(_app(FaqTile(entry: entry, lang: 'fr')));
      await tester.tap(find.text('Question ?'));
      await tester.pumpAndSettle();
      expect(find.text(S.provisionalNote), findsOneWidget);
      expect(find.text(_source), findsOneWidget);
    });

    testWidgets('FAQ validée : aucune mention', (tester) async {
      await tester.pumpWidget(_app(FaqTile(entry: FaqEntry.fromJson(_faqJson()), lang: 'fr')));
      await tester.tap(find.text('Question ?'));
      await tester.pumpAndSettle();
      expect(find.byType(ProvisionalNote), findsNothing);
    });

    testWidgets('bandeau de danger : signes et appels d\'abord, mention en dernier', (tester) async {
      const sign = DangerSignHit(id: 'd', label: 'Saignement', advice: 'Allez au centre.', provisional: true);
      await tester.pumpWidget(_app(const DangerBanner(signs: [sign], contentLang: 'mos')));
      expect(find.text('Saignement'), findsOneWidget);
      expect(find.text(S.callHealthCenter), findsOneWidget);
      expect(find.text(S.provisionalNote), findsOneWidget);
      final callY = tester.getTopLeft(find.text(S.callHotline)).dy;
      expect(tester.getTopLeft(find.text(S.provisionalNote)).dy, greaterThan(callY));

      final button = tester.widget<ListenButton>(find.byType(ListenButton));
      expect(button.text, endsWith(S.provisionalNote));
      expect(button.text, startsWith(S.dangerTitle));
      expect(button.contentLang, 'fr');
    });

    testWidgets('bandeau de danger validé : aucune mention', (tester) async {
      const sign = DangerSignHit(id: 'd', label: 'Saignement', advice: 'Allez au centre.');
      await tester.pumpWidget(_app(const DangerBanner(signs: [sign], contentLang: 'mos')));
      expect(find.byType(ProvisionalNote), findsNothing);
      expect(tester.widget<ListenButton>(find.byType(ListenButton)).contentLang, 'mos');
    });
  });
}

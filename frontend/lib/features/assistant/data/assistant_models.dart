/// Modèles des réponses de l'assistant (docs/API.md, module 1).
class AnswerEntry {
  const AnswerEntry({
    required this.id,
    required this.topic,
    required this.question,
    required this.answer,
    this.audioUrl,
    this.audioKind,
    this.provisional = false,
    this.source,
  });

  factory AnswerEntry.fromJson(Map<String, dynamic> json) => AnswerEntry(
    id: json['id'] as String,
    topic: json['topic'] as String? ?? 'autre',
    question: json['question'] as String? ?? '',
    answer: json['answer'] as String? ?? '',
    audioUrl: json['audio_url'] as String?,
    audioKind: json['audio_kind'] as String?,
    provisional: json['provisional'] == true,
    source: json['source'] as String?,
  );

  final String id;
  final String topic;
  final String question;
  final String answer;
  final String? audioUrl;

  /// `human` ou `synthetic` : une voix de synthèse est toujours signalée.
  final String? audioKind;

  /// Contenu tiré d'une source publique, relu par aucune sage-femme.
  final bool provisional;
  final String? source;

  bool get isSynthetic => audioKind == 'synthetic';
}

class DangerSignHit {
  const DangerSignHit({
    required this.id,
    required this.label,
    required this.advice,
    this.provisional = false,
    this.source,
  });

  factory DangerSignHit.fromJson(Map<String, dynamic> json) => DangerSignHit(
    id: json['id'] as String,
    label: json['label'] as String? ?? '',
    advice: json['advice'] as String? ?? '',
    provisional: json['provisional'] == true,
    source: json['source'] as String?,
  );

  final String id;
  final String label;
  final String advice;
  final bool provisional;
  final String? source;
}

class AssistantAnswer {
  const AssistantAnswer({
    this.transcript,
    this.questionFr,
    required this.matched,
    this.confidence,
    this.entry,
    required this.danger,
    this.dangerSigns = const [],
    this.fallbackMessage,
  });

  factory AssistantAnswer.fromJson(Map<String, dynamic> json) => AssistantAnswer(
    transcript: json['transcript'] as String?,
    questionFr: json['question_fr'] as String?,
    matched: json['matched'] == true,
    confidence: (json['confidence'] as num?)?.toDouble(),
    entry: json['entry'] is Map ? AnswerEntry.fromJson((json['entry'] as Map).cast<String, dynamic>()) : null,
    danger: json['danger'] == true,
    dangerSigns: [
      for (final item in (json['danger_signs'] as List? ?? const []))
        DangerSignHit.fromJson((item as Map).cast<String, dynamic>()),
    ],
    fallbackMessage: json['fallback_message'] as String?,
  );

  final String? transcript;
  final String? questionFr;
  final bool matched;
  final double? confidence;
  final AnswerEntry? entry;
  final bool danger;
  final List<DangerSignHit> dangerSigns;
  final String? fallbackMessage;
}

/// `POST /assistant/transcribe` : ce que le serveur a compris, sans répondre.
class Transcription {
  const Transcription({required this.transcript, this.questionFr});

  factory Transcription.fromJson(Map<String, dynamic> json) =>
      Transcription(transcript: json['transcript'] as String? ?? '', questionFr: json['question_fr'] as String?);

  final String transcript;

  /// Traduction en français (`null` si la langue est déjà le français).
  final String? questionFr;
}

class FaqEntry {
  const FaqEntry({
    required this.id,
    required this.topic,
    required this.question,
    required this.answer,
    this.audioUrl,
    this.audioKind,
    this.isDangerTopic = false,
    this.provisional = false,
    this.source,
  });

  factory FaqEntry.fromJson(Map<String, dynamic> json) => FaqEntry(
    id: json['id'] as String,
    topic: json['topic'] as String? ?? 'autre',
    question: json['question'] as String? ?? '',
    answer: json['answer'] as String? ?? '',
    audioUrl: json['audio_url'] as String?,
    audioKind: json['audio_kind'] as String?,
    isDangerTopic: json['is_danger_topic'] == true,
    provisional: json['provisional'] == true,
    source: json['source'] as String?,
  );

  final String id;
  final String topic;
  final String question;
  final String answer;
  final String? audioUrl;
  final String? audioKind;
  final bool isDangerTopic;
  final bool provisional;
  final String? source;

  Map<String, dynamic> toJson() => {
    'id': id,
    'topic': topic,
    'question': question,
    'answer': answer,
    'audio_url': audioUrl,
    'audio_kind': audioKind,
    'is_danger_topic': isDangerTopic,
    'provisional': provisional,
    'source': source,
  };
}

class FaqBundle {
  const FaqBundle({required this.version, required this.entries});

  factory FaqBundle.fromJson(Map<String, dynamic> json) => FaqBundle(
    version: json['version']?.toString(),
    entries: [
      for (final item in (json['entries'] as List? ?? const []))
        FaqEntry.fromJson((item as Map).cast<String, dynamic>()),
    ],
  );

  final String? version;
  final List<FaqEntry> entries;

  Map<String, dynamic> toJson() => {'version': version, 'entries': entries.map((e) => e.toJson()).toList()};
}

/// Signe de danger avec ses mots-clés français, pour la détection hors
/// connexion (`GET /assistant/danger-signs`), et la fiche d'aide à la
/// décision de l'agent ([agentQuestions], [referWhen] : vides tant que la
/// sage-femme ne les a pas rédigés).
class DangerSign {
  const DangerSign({
    required this.id,
    required this.label,
    required this.advice,
    this.keywords = const [],
    this.agentQuestions = const [],
    this.referWhen,
    this.provisional = false,
    this.source,
  });

  factory DangerSign.fromJson(Map<String, dynamic> json) => DangerSign(
    id: json['id'] as String,
    label: json['label'] as String? ?? '',
    advice: json['advice'] as String? ?? '',
    keywords: [for (final k in (json['keywords'] as List? ?? const [])) k.toString()],
    agentQuestions: [
      for (final q in (json['agent_questions'] as List? ?? const []))
        if (q.toString().trim().isNotEmpty) q.toString(),
    ],
    referWhen: _nonBlank(json['refer_when']),
    provisional: json['provisional'] == true,
    source: json['source'] as String?,
  );

  final String id;
  final String label;
  final String advice;
  final List<String> keywords;
  final List<String> agentQuestions;
  final String? referWhen;
  final bool provisional;
  final String? source;

  /// La fiche d'aide à la décision a-t-elle été rédigée ?
  bool get hasDecisionAid => agentQuestions.isNotEmpty || referWhen != null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'advice': advice,
    'keywords': keywords,
    'agent_questions': agentQuestions,
    'refer_when': referWhen,
    'provisional': provisional,
    'source': source,
  };

  DangerSignHit toHit() =>
      DangerSignHit(id: id, label: label, advice: advice, provisional: provisional, source: source);
}

String? _nonBlank(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

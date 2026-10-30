import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum FieldKind { text, multiline, number, date, time, times, choice, toggle }

/// Un champ d'une rubrique du carnet.
class FieldSpec {
  const FieldSpec(
    this.key,
    this.label, {
    this.kind = FieldKind.text,
    this.choices = const [],
    this.required = false,
    this.hint,
    this.privateListen = false,
  });

  final String key;
  final String label;
  final FieldKind kind;

  /// (valeur stockée, libellé affiché) pour [FieldKind.choice].
  final List<(String, String)> choices;
  final bool required;
  final String? hint;

  /// Texte personnel lu UNIQUEMENT avec la voix du téléphone (jamais envoyé
  /// au serveur) : recommandations d'une consultation, par exemple.
  final bool privateListen;

  String display(Object? value) {
    if (value == null || (value is String && value.isEmpty) || (value is List && value.isEmpty)) return '';
    return switch (kind) {
      FieldKind.toggle => value == true ? 'Oui' : 'Non',
      FieldKind.choice =>
        choices.firstWhere((c) => c.$1 == value, orElse: () => (value.toString(), value.toString())).$2,
      FieldKind.times => (value as List).join(' · '),
      FieldKind.date => _frDate(value.toString()),
      _ => value.toString(),
    };
  }

  static String _frDate(String iso) {
    final parts = iso.split('-');
    return parts.length == 3 ? '${parts[2]}/${parts[1]}/${parts[0]}' : iso;
  }
}

typedef RecordHook = Future<void> Function(WidgetRef ref, Map<String, dynamic> record);

/// Événement statistique anonyme à compter après un enregistrement, selon la
/// version d'avant ([before], `null` pour un nouvel élément) et celle
/// d'après. `null` = rien à compter.
typedef RecordStatEvent = String? Function(Map<String, dynamic>? before, Map<String, dynamic> after);

/// Description d'une rubrique : l'écran de liste, la fiche et le formulaire
/// génériques en sont déduits (voir `record_screens.dart`).
class RecordSpec {
  const RecordSpec({
    required this.id,
    required this.collection,
    required this.title,
    required this.icon,
    required this.color,
    required this.listenText,
    required this.fields,
    required this.titleOf,
    this.subtitleOf,
    this.parentKey,
    this.maxItems,
    this.single = false,
    this.note,
    this.onSaved,
    this.onDeleted,
    this.remindable = false,
    this.statEventOf,
  });

  final String id;
  final String collection;
  final String title;
  final IconData icon;
  final Color color;
  final String listenText;
  final List<FieldSpec> fields;
  final String Function(Map<String, dynamic> record) titleOf;
  final String Function(Map<String, dynamic> record)? subtitleOf;

  /// Champ qui rattache l'élément à un parent (ex. `child_id` d'un vaccin).
  final String? parentKey;
  final int? maxItems;

  /// Un seul document (profil santé).
  final bool single;
  final String? note;
  final RecordHook? onSaved;
  final RecordHook? onDeleted;

  /// La rubrique programme des rappels (message « pas sur le web »).
  final bool remindable;

  /// Statistique anonyme liée à l'enregistrement (visite prénatale, vaccin).
  final RecordStatEvent? statEventOf;

  /// Texte lu par le bouton « Écouter » d'une ligne de la liste.
  String spokenSummary(Map<String, dynamic> record) {
    final subtitle = subtitleOf?.call(record);
    return subtitle == null || subtitle.isEmpty ? titleOf(record) : '${titleOf(record)}. $subtitle';
  }
}

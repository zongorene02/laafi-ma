import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../shared/data/listen_service.dart';

/// Rappels locaux (médicaments, rendez-vous, renouvellement de contraception).
///
/// Android uniquement : sur le web, toutes les méthodes ne font rien et
/// l'interface explique que les rappels ne sonnent pas dans un navigateur.
///
/// Le TEXTE des notifications est volontairement neutre (« Rappel ») : un
/// écran de verrouillage ne doit jamais afficher « pilule » ou « visite
/// prénatale » à la vue de tous.
class ReminderService {
  ReminderService([this._plugin]);

  FlutterLocalNotificationsPlugin? _plugin;
  bool _initialized = false;

  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Rappels',
      channelDescription: 'Rappels discrets',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      visibility: NotificationVisibility.secret,
    ),
  );

  Future<FlutterLocalNotificationsPlugin?> _ready() async {
    if (!supported) return null;
    final plugin = _plugin ??= FlutterLocalNotificationsPlugin();
    if (!_initialized) {
      await plugin.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      );
      _initialized = true;
    }
    return plugin;
  }

  Future<bool> requestPermission() async {
    final plugin = await _ready();
    final android = plugin?.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  /// Le Burkina Faso n'a pas d'heure d'été : on programme sur l'instant UTC
  /// correspondant à l'heure locale voulue, sans base de fuseaux horaires.
  tz.TZDateTime _toTz(DateTime local) => tz.TZDateTime.from(local.toUtc(), tz.UTC);

  Future<void> scheduleOnce(String key, DateTime when) async {
    final plugin = await _ready();
    if (plugin == null || when.isBefore(DateTime.now())) return;
    await plugin.zonedSchedule(
      id: stableIntId(key),
      title: 'Rappel',
      body: "Ouvrez l'application.",
      scheduledDate: _toTz(when),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> scheduleDaily(String key, int hour, int minute) async {
    final plugin = await _ready();
    if (plugin == null) return;
    final now = DateTime.now();
    var first = DateTime(now.year, now.month, now.day, hour, minute);
    if (first.isBefore(now)) first = first.add(const Duration(days: 1));
    await plugin.zonedSchedule(
      id: stableIntId(key),
      title: 'Rappel',
      body: "Ouvrez l'application.",
      scheduledDate: _toTz(first),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancel(String key) async {
    final plugin = await _ready();
    await plugin?.cancel(id: stableIntId(key));
  }

  Future<void> cancelAll() async {
    final plugin = await _ready();
    await plugin?.cancelAll();
  }
}

final reminderServiceProvider = Provider<ReminderService>((ref) => ReminderService());

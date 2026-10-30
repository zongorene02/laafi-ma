import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../../core/storage/cache.dart';
import '../../../core/storage/json_store.dart';

/// `HelpService` de docs/API.md.
class HelpService {
  const HelpService({
    required this.id,
    required this.name,
    required this.category,
    required this.phone,
    this.city,
    this.region,
    this.address,
    this.hours,
    this.freeCall = false,
    this.languages = const [],
    this.sourceUrl,
    this.verifiedAt,
    this.active = true,
  });

  factory HelpService.fromJson(Map<String, dynamic> json) => HelpService(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    category: json['category'] as String? ?? 'social',
    phone: json['phone'] as String? ?? '',
    city: json['city'] as String?,
    region: json['region'] as String?,
    address: json['address'] as String?,
    hours: json['hours'] as String?,
    freeCall: json['free_call'] == true,
    languages: [for (final l in (json['languages'] as List? ?? const [])) l.toString()],
    sourceUrl: json['source_url'] as String?,
    verifiedAt: json['verified_at'] as String?,
    active: json['active'] != false,
  );

  final String id;
  final String name;
  final String category;
  final String phone;
  final String? city;
  final String? region;
  final String? address;
  final String? hours;
  final bool freeCall;
  final List<String> languages;
  final String? sourceUrl;

  /// `null` = numéro pas encore confirmé : toujours affiché comme tel.
  final String? verifiedAt;
  final bool active;

  bool get verified => verifiedAt != null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'phone': phone,
    'city': city,
    'region': region,
    'address': address,
    'hours': hours,
    'free_call': freeCall,
    'languages': languages,
    'source_url': sourceUrl,
    'verified_at': verifiedAt,
    'active': active,
  };
}

const helpCategoryLabels = {
  'hotline': 'Numéro vert',
  'vbg_center': 'Centre d\'écoute VBG',
  'emergency': 'Urgences',
  'police': 'Police',
  'gendarmerie': 'Gendarmerie',
  'health': 'Santé',
  'social': 'Action sociale',
  'legal': 'Aide juridique',
  'psychosocial': 'Soutien psychologique',
};

class HelpRepository {
  HelpRepository(this._dio, this._cache);

  final Dio _dio;
  final JsonStore _cache;

  static const collection = 'help_services';

  /// Tout l'annuaire actif, mis en cache pour les appels hors connexion.
  Future<List<HelpService>> fetchServices({String? city, String? category}) async {
    try {
      final response = await _dio.get('/help/services', queryParameters: {'city': ?city, 'category': ?category});
      final services = [
        for (final item in response.data as List) HelpService.fromJson((item as Map).cast<String, dynamic>()),
      ].where((s) => s.active).toList();
      if (city == null && category == null) {
        await writeCache(_cache, collection, 'all', services.map((s) => s.toJson()).toList());
      }
      return services;
    } on DioException catch (e) {
      throw ApiClient.toApiException(e);
    }
  }

  Future<(List<HelpService>, DateTime)?> cachedServices() async {
    final entry = await readCache(_cache, collection, 'all');
    final data = entry?.data;
    if (data is! List) return null;
    return ([for (final item in data) HelpService.fromJson((item as Map).cast<String, dynamic>())], entry!.fetchedAt);
  }

  /// Réseau d'abord, cache en secours.
  Future<(List<HelpService>, bool fromCache)> load() async {
    try {
      return (await fetchServices(), false);
    } catch (e) {
      final cached = await cachedServices();
      if (cached != null) return (cached.$1, true);
      rethrow;
    }
  }

  /// Premier service EN CACHE d'une catégorie (bandeau de danger de
  /// l'assistant) : jamais de numéro inventé, `null` s'il n'y en a pas.
  Future<HelpService?> firstCached(bool Function(HelpService) test) async {
    final cached = await cachedServices();
    if (cached == null) return null;
    final matches = cached.$1.where(test).toList()..sort((a, b) => (b.verified ? 1 : 0) - (a.verified ? 1 : 0));
    return matches.isEmpty ? null : matches.first;
  }
}

final helpRepositoryProvider = Provider<HelpRepository>(
  (ref) => HelpRepository(ref.watch(dioProvider), ref.watch(cacheStoreProvider)),
);

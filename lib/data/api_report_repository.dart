import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user_profile.dart';
import '../models/health_report.dart';
import 'core_api_client.dart';
import 'report_repository.dart';
import 'supabase_config.dart';

export 'report_repository.dart';

class ApiReportRepository implements ReportRepository {
  ApiReportRepository({CoreApiClient? api, SupabaseClient? client})
    : _client = client,
      _api =
          api ??
          CoreApiClient(
            accessTokenProvider: _sessionTokenProvider(client),
            accessTokenRefresher: _forceRefreshSessionToken(client),
            requestTimeout: const Duration(seconds: 60),
          );

  final CoreApiClient _api;
  final SupabaseClient? _client;
  String? _ownerUid;
  AppRole? _role;

  SupabaseClient get _supabaseClient {
    final injectedClient = _client;
    if (injectedClient != null) return injectedClient;
    if (!SupabaseConfig.isConfigured) {
      throw const ReportStoreException(
        'Configura Supabase para consultar los reportes.',
      );
    }
    return Supabase.instance.client;
  }

  static Future<String?> Function() _sessionTokenProvider(
    SupabaseClient? client,
  ) {
    return () async {
      final activeClient =
          client ??
          (SupabaseConfig.isConfigured ? Supabase.instance.client : null);
      if (activeClient == null) {
        throw const CoreApiException(
          'No se encontró la sesión de Supabase. Inicia sesión nuevamente.',
          statusCode: 401,
        );
      }
      final session = activeClient.auth.currentSession;
      if (session == null) {
        throw const CoreApiException(
          'No hay una sesión de Supabase activa. Inicia sesión nuevamente.',
          statusCode: 401,
        );
      }
      final expiresAt = session.expiresAt;
      final refreshThreshold =
          DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60;
      if (expiresAt != null && expiresAt <= refreshThreshold) {
        try {
          final refreshed = await activeClient.auth.refreshSession();
          final accessToken = refreshed.session?.accessToken;
          if (accessToken == null || accessToken.isEmpty) {
            throw const CoreApiException(
              'No se pudo renovar tu sesión de Supabase. Inicia sesión nuevamente.',
              statusCode: 401,
            );
          }
          return accessToken;
        } on AuthException {
          throw CoreApiException(
              'Tu sesión expiró. Inicia sesión nuevamente.',
            statusCode: 401,
          );
        }
      }
      return session.accessToken;
    };
  }

  static Future<String?> Function() _forceRefreshSessionToken(
    SupabaseClient? client,
  ) {
    return () async {
      final activeClient =
          client ??
          (SupabaseConfig.isConfigured ? Supabase.instance.client : null);
      if (activeClient == null) return null;
      try {
        final refreshed = await activeClient.auth.refreshSession();
        return refreshed.session?.accessToken;
      } on AuthException {
        throw CoreApiException(
          'Tu sesión expiró. Inicia sesión nuevamente.',
          statusCode: 401,
        );
      }
    };
  }

  @override
  String? get ownerUid => _ownerUid;

  @override
  AppRole? get role => _role;

  @override
  Future<void> initialize() async {
    final user = _supabaseClient.auth.currentUser;
    if (user == null) {
      throw const ReportStoreException(
        'Inicia sesión con Supabase para consultar tus reportes.',
      );
    }
    final profile = await _supabaseClient
        .from('profiles')
        .select('role')
        .eq('id', user.id)
        .maybeSingle();
    if (profile == null || profile['role'] is! String) {
      throw const ReportStoreException(
        'No se encontró el perfil de esta cuenta en Supabase.',
      );
    }
    final roleName = profile['role'] as String;
    final role = AppRole.values.where((candidate) {
      return candidate.name == roleName;
    });
    if (role.isEmpty) {
      throw const ReportStoreException(
        'El perfil no tiene un rol válido en Supabase.',
      );
    }
    _ownerUid = user.id;
    _role = role.first;
  }

  @override
  Stream<List<HealthReport>> watchReports() {
    _requireOwner();
    return _api.events('/api/reports/stream').map(_decodeReports);
  }

  List<HealthReport> _decodeReports(Map<String, dynamic> response) {
    final items = response['reports'];
    if (items is! List) {
      throw const ReportStoreException(
        'La API devolvió una lista de reportes inválida.',
      );
    }
    return items
        .whereType<Map>()
        .map((item) => HealthReport.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false)
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
  }

  @override
  Future<String> createReport(
    HealthReportDraft draft, {
    String? documentId,
  }) async {
    if (_role != AppRole.patient) {
      throw const ReportStoreException(
        'Solo una cuenta de paciente puede crear un reporte.',
      );
    }
    _validateDraft(draft);
    final id = _validateId(documentId ?? draft.id);
    final reportId = id.isEmpty ? HealthReportDraft.generateId() : id;
    try {
      final response = await _api.post('/api/reports', {
        'id': reportId,
        ...draft.toApiJson(),
      });
      final report = response['report'];
      if (report is! Map || report['id'] is! String) {
        throw const ReportStoreException(
          'La API no devolvió el identificador del reporte.',
        );
      }
      return report['id'] as String;
    } on CoreApiException catch (error) {
      if (error.statusCode == 409) {
        throw DuplicateReportIdException(reportId);
      }
      throw _mapApiError(error);
    }
  }

  @override
  Future<void> updateReport(String id, HealthReportDraft draft) async {
    _requireWriteAccess();
    _validateDraft(draft);
    final normalizedId = _validateId(id);
    try {
      await _api.put('/api/reports/${Uri.encodeComponent(normalizedId)}', {
        ...draft.toApiJson(),
      });
    } on CoreApiException catch (error) {
      if (error.statusCode == 404) throw ReportNotFoundException(normalizedId);
      throw _mapApiError(error);
    }
  }

  @override
  Future<void> deleteReport(String id) async {
    _requireWriteAccess();
    final normalizedId = _validateId(id);
    try {
      await _api.request(
        'DELETE',
        '/api/reports/${Uri.encodeComponent(normalizedId)}',
      );
    } on CoreApiException catch (error) {
      if (error.statusCode == 404) throw ReportNotFoundException(normalizedId);
      throw _mapApiError(error);
    }
  }

  String _requireOwner() {
    final uid = _ownerUid;
    if (uid == null) {
      throw const ReportStoreException(
        'La sesión de BioMedica no está lista. Vuelve a iniciar sesión.',
      );
    }
    return uid;
  }

  void _requireWriteAccess() {
    if (_role == AppRole.doctor) {
      throw const ReportStoreException(
        'Los médicos pueden consultar reportes asignados, pero no modificarlos.',
      );
    }
    _requireOwner();
  }

  String _validateId(String value) {
    final normalized = value.trim();
    final error = HealthReportValidation.id(normalized);
    if (error != null) throw ReportStoreException(error);
    return normalized;
  }

  void _validateDraft(HealthReportDraft draft) {
    final errors = [
      HealthReportValidation.malestar(draft.malestar ?? draft.equipment),
      HealthReportValidation.otherMalestar(
        draft.otherMalestar,
        draft.malestar ?? draft.equipment,
      ),
      if (draft.onsetAt != null) HealthReportValidation.onsetAt(draft.onsetAt!),
      HealthReportValidation.description(draft.description),
      HealthReportValidation.priority(draft.priority),
    ];
    for (final error in errors) {
      if (error != null) throw ReportStoreException(error);
    }
  }

  ReportStoreException _mapApiError(CoreApiException error) =>
      switch (error.statusCode) {
        401 => const ReportStoreException(
          'Tu sesión expiró. Inicia sesión nuevamente.',
          code: 'unauthenticated',
        ),
        403 => const ReportStoreException(
          'No tienes permiso para realizar esta acción.',
          code: 'permission-denied',
        ),
        null => const ReportStoreException(
          'No se pudo conectar con el servicio de reportes. Inténtalo de nuevo.',
          code: 'unavailable',
        ),
        _ => const ReportStoreException(
          'No se pudo completar la operación de reportes. Inténtalo de nuevo.',
          code: 'api-error',
        ),
      };
}

import '../models/app_user_profile.dart';
import '../models/wearable_measurement.dart';
import 'core_api_client.dart';

abstract interface class MeasurementRepository {
  Future<void> initialize();

  Stream<List<WearableMeasurement>> watchMeasurements();

  Future<String> saveMeasurement(WearableMeasurementDraft measurement);
}

class RelationalMeasurementRepository implements MeasurementRepository {
  RelationalMeasurementRepository({CoreApiClient? api})
    : _api = api ?? CoreApiClient.instance;

  final CoreApiClient _api;
  AppRole? _role;

  @override
  Future<void> initialize() async {
    try {
      final response = await _api.get('/api/auth/me');
      final user = response['user'];
      if (user is! Map || user['role'] is! String) {
        throw const MeasurementStoreException(
          'La API no devolvió un perfil válido para mediciones.',
        );
      }
      _role = AppRole.values.firstWhere(
        (role) => role.name == user['role'],
        orElse: () => throw const MeasurementStoreException(
          'El perfil no tiene un rol válido.',
        ),
      );
    } on CoreApiException catch (error) {
      throw MeasurementStoreException(error.message);
    }
  }

  @override
  Stream<List<WearableMeasurement>> watchMeasurements() =>
      _api.poll(_fetchMeasurements);

  Future<List<WearableMeasurement>> _fetchMeasurements() async {
    try {
      final response = await _api.get('/api/measurements');
      final items = response['measurements'];
      if (items is! List) {
        throw const MeasurementStoreException(
          'La API devolvió una lista de mediciones inválida.',
        );
      }
      return items
          .whereType<Map>()
          .map(
            (item) =>
                WearableMeasurement.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false);
    } on CoreApiException catch (error) {
      throw MeasurementStoreException(error.message);
    }
  }

  @override
  Future<String> saveMeasurement(WearableMeasurementDraft measurement) async {
    final validationError = measurement.validate();
    if (validationError != null) {
      throw MeasurementStoreException(validationError);
    }
    if (_role != AppRole.patient) {
      throw const MeasurementStoreException(
        'Solo los pacientes pueden registrar sus mediciones.',
      );
    }
    try {
      final response = await _api.post(
        '/api/measurements',
        measurement.toJson(),
      );
      final data = response['measurement'];
      if (data is! Map || data['id'] is! String) {
        throw const MeasurementStoreException(
          'La API no devolvió el identificador de la medición.',
        );
      }
      return data['id'] as String;
    } on CoreApiException catch (error) {
      throw MeasurementStoreException(error.message);
    }
  }
}

class MeasurementStoreException implements Exception {
  const MeasurementStoreException(this.message);

  final String message;

  @override
  String toString() => message;
}
